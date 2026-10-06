-- MobBrowser is the Mob Dictionary, a window of its own opened from the
-- Targeting section. It shows what the game's mob dictionary (MobDictionary)
-- says about every mob and boss, at a glance:
--
--   * The left side lists every mob, weakest to strongest by health,
--     narrowed by the search box and the ALL / MOBS / BOSSES / LIVE chips.
--     A thin bar under each row is its threat.
--   * The right side (MobDetail) is the one picked: kind, level, live count,
--     threat, big numbers, drops per kill with the player's Luck, every
--     number against the strongest of its kind, and Add to Enemy Priority.
return {
    Name = "MobBrowser",
    IsFeature = true,
    Dependencies = {"Runtime", "Components", "Floating", "MobDictionary", "MobDetail"},

    Start = function(Context)
        local UI = Context.UI
        local UIRef = Context.UIRef
        local Floating = Context.Floating
        local Dictionary = Context.MobDictionary
        local Detail = Context.MobDetail

        local New, Stroke = Floating.New, Floating.Stroke
        local Label, Button = Floating.Label, Floating.Button
        local FormatNumber, DescribeThreat = Detail.FormatNumber, Detail.DescribeThreat

        local WINDOW_WIDTH = 760
        local WINDOW_HEIGHT = 520
        local MIN_WIDTH = 580
        local MIN_HEIGHT = 380
        --// Share of the window the mob list takes; the detail gets the rest.
        local LIST_WIDTH_SCALE = 0.4
        local ROW_HEIGHT = 38
        local BAR_HEIGHT = 26
        local CHIP_HEIGHT = 22
        --// Live counts, drops, Luck and priority marks are read again this
        --// often while open.
        local REFRESH_INTERVAL = 1

        local FILTERS = { "ALL", "MOBS", "BOSSES", "LIVE" }

        local Browser = {
            Name = "MobBrowser",
            IsFeature = true,
            S = {
                Built = false,
                IsOpen = false,
                Filter = "ALL",
                --// Mob name -> list row, kept between refreshes.
                Rows = {},
                Chips = {},
                LastRefresh = 0,
            },
        }

        local S = Browser.S
        local Theme, Window, SearchBox, ListScroll, EmptyLabel

        ------------------------------------------------------------------------
        --// List
        ------------------------------------------------------------------------

        local function MatchesFilter(Entry, Filter)
            if Filter == "MOBS" then
                return Entry.Kind == "Mob"
            elseif Filter == "BOSSES" then
                return Entry.Kind == "Boss"
            elseif Filter == "LIVE" then
                return Dictionary:GetLive(Entry.Name) > 0
            end

            return true
        end

        local function IsShown(Entry, Query)
            return MatchesFilter(Entry, S.Filter)
                and (Query == "" or string.find(string.lower(Entry.Name), Query, 1, true) ~= nil)
        end

        local function CreateRow(Entry)
            local Row = New("TextButton", {
                Parent = ListScroll,
                Size = UDim2.new(1, -6, 0, ROW_HEIGHT),
                BackgroundColor3 = Theme.Element,
                BackgroundTransparency = 0.1,
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = false,
            })

            Floating.Hover(Row)

            local Filled, _, ThreatColor = DescribeThreat(Entry)
            local Share = Filled / Detail.THREAT_SEGMENTS

            New("Frame", {
                Parent = Row,
                Position = UDim2.fromOffset(0, 6),
                Size = UDim2.new(0, 2, 1, -12),
                BackgroundColor3 = Detail.GetKindColor(Entry),
                BorderSizePixel = 0,
            })

            local NameLabel = Label(Row, string.upper(Entry.Name), 10, {
                Position = UDim2.fromOffset(10, 5),
                Size = UDim2.new(1, -18, 0, 15),
                Font = Floating.Fonts.Bold,
            })

            local InfoLabel = Label(Row, "", 8, {
                Position = UDim2.fromOffset(10, 20),
                Size = UDim2.new(1, -18, 0, 12),
                TextColor3 = Theme.TextMuted,
            })

            --// Threat, as a thin bar along the bottom.
            New("Frame", {
                Parent = Row,
                Position = UDim2.new(0, 10, 1, -4),
                Size = UDim2.new(Share, -20 * Share, 0, 2),
                BackgroundColor3 = ThreatColor,
                BorderSizePixel = 0,
            })

            UI:_Connect(Row.Activated, function()
                Browser:Select(Entry.Name)
            end)

            return { Button = Row, NameLabel = NameLabel, InfoLabel = InfoLabel }
        end

        local function UpdateRow(Row, Entry)
            local Parts = { string.upper(Entry.Kind) }
            local Level = Dictionary.GetStat(Entry, "Config.LVL")
            local Health = Dictionary.GetStat(Entry, "Humanoid.MaxHealth")
            local Count = Dictionary:GetLive(Entry.Name)
            local Drops = Dictionary:GetDrops(Entry.Name)

            if type(Level) == "number" then
                table.insert(Parts, "LV " .. FormatNumber(Level))
            end

            if Health then
                table.insert(Parts, "HP " .. FormatNumber(Health))
            end

            if Drops and #Drops > 0 then
                table.insert(Parts, #Drops .. (#Drops == 1 and " DROP" or " DROPS"))
            end

            if Count > 0 then
                table.insert(Parts, string.format("● %d LIVE", Count))
            end

            if Detail.IsInPriority(Entry.Name) then
                table.insert(Parts, "✓")
            end

            local Selected = Detail:GetSelected() == Entry.Name
            Row.InfoLabel.Text = table.concat(Parts, "  ·  ")
            Row.InfoLabel.TextColor3 = Count > 0 and Detail.HEALTH_COLOR or Theme.TextMuted
            Row.NameLabel.TextColor3 = Selected and Theme.Cyan or Theme.Text
            Row.Button.BackgroundColor3 = Selected and Theme.PanelHover or Theme.Element
        end

        local function RefreshChips(All)
            for _, Filter in ipairs(FILTERS) do
                local Count = 0

                for _, Entry in ipairs(All) do
                    if MatchesFilter(Entry, Filter) then
                        Count += 1
                    end
                end

                local Chip = S.Chips[Filter]
                local Active = S.Filter == Filter
                Chip.Text = string.format("%s  %d", Filter, Count)
                Chip.TextColor3 = Active and Theme.Cyan or Theme.TextMuted
                Chip.BackgroundColor3 = Active and Theme.PanelHover or Theme.Element
            end
        end

        local function RefreshList()
            local Query = string.lower(SearchBox.Text or "")
            local All = Dictionary:GetAll()
            local Seen = {}
            local Shown = 0

            RefreshChips(All)

            for Index, Entry in ipairs(All) do
                Seen[Entry.Name] = true

                local Row = S.Rows[Entry.Name]

                if not Row then
                    Row = CreateRow(Entry)
                    S.Rows[Entry.Name] = Row
                end

                local Visible = IsShown(Entry, Query)
                Row.Button.Visible = Visible
                Row.Button.LayoutOrder = Index

                if Visible then
                    Shown += 1
                    UpdateRow(Row, Entry)
                end
            end

            for Name, Row in pairs(S.Rows) do
                if not Seen[Name] then
                    Row.Button:Destroy()
                    S.Rows[Name] = nil
                end
            end

            if Dictionary.S.Loading then
                EmptyLabel.Text = "Loading..."
            elseif #All == 0 then
                EmptyLabel.Text = Dictionary.S.Error and "Mob dictionary unavailable" or "No mobs found"
            else
                EmptyLabel.Text = "No mobs match the filters"
            end

            EmptyLabel.Visible = Shown == 0
        end

        ------------------------------------------------------------------------
        --// Window
        ------------------------------------------------------------------------

        local function BuildFilterBar(Body)
            SearchBox = New("TextBox", {
                Parent = Body,
                Size = UDim2.new(1, -94, 0, BAR_HEIGHT),
                BackgroundColor3 = Theme.Element,
                BorderSizePixel = 0,
                Text = "",
                PlaceholderText = "SEARCH MOB...",
                PlaceholderColor3 = Theme.TextMuted,
                TextColor3 = Theme.Text,
                TextSize = 10,
                Font = Floating.Fonts.Regular,
                TextXAlignment = Enum.TextXAlignment.Left,
                ClearTextOnFocus = false,
            })

            Floating.Hover(SearchBox, Stroke(SearchBox, Theme.BorderDim, 0.15))
            New("UIPadding", { Parent = SearchBox, PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) })

            local ReloadButton = Button(Body, "↻  RELOAD", Theme.TextMuted, {
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, 0, 0, 0),
                Size = UDim2.fromOffset(86, BAR_HEIGHT),
            })

            local ChipBar = New("Frame", {
                Parent = Body,
                Position = UDim2.fromOffset(0, BAR_HEIGHT + 6),
                Size = UDim2.new(1, 0, 0, CHIP_HEIGHT),
                BackgroundTransparency = 1,
            })

            New("UIListLayout", {
                Parent = ChipBar,
                FillDirection = Enum.FillDirection.Horizontal,
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 4),
            })

            for Index, Filter in ipairs(FILTERS) do
                local Chip = Button(ChipBar, Filter, Theme.TextMuted, {
                    Size = UDim2.fromOffset(0, CHIP_HEIGHT),
                    AutomaticSize = Enum.AutomaticSize.X,
                    TextSize = 9,
                    LayoutOrder = Index,
                })

                New("UIPadding", { Parent = Chip, PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) })

                UI:_Connect(Chip.Activated, function()
                    S.Filter = Filter
                    Browser:Refresh()
                end)

                S.Chips[Filter] = Chip
            end

            UI:_Connect(SearchBox:GetPropertyChangedSignal("Text"), function()
                RefreshList()
            end)

            UI:_Connect(ReloadButton.Activated, function()
                Browser:Reload()
            end)
        end

        local function Build()
            Theme = UI.Theme

            Window = Floating.CreateWindow({
                Title = "MOB DICTIONARY",
                Subtitle = "Every mob and boss  //  drops with your Luck  //  add to Enemy Priority",
                Width = WINDOW_WIDTH,
                Height = WINDOW_HEIGHT,
                MinWidth = MIN_WIDTH,
                MinHeight = MIN_HEIGHT,
                OnClose = function()
                    S.IsOpen = false
                end,
            })

            BuildFilterBar(Window.Body)

            local Top = BAR_HEIGHT + CHIP_HEIGHT + 14
            local Lists = New("Frame", {
                Parent = Window.Body,
                BackgroundTransparency = 1,
                Position = UDim2.fromOffset(0, Top),
                Size = UDim2.new(1, 0, 1, -Top),
            })

            ListScroll = Floating.Scroller(Lists, UDim2.new(), UDim2.new(LIST_WIDTH_SCALE, -4, 1, 0), 4, 4)
            EmptyLabel = Label(ListScroll, "", 10, {
                TextColor3 = Theme.TextMuted,
                Visible = false,
                LayoutOrder = -1,
            })

            Detail:Build(Floating.Scroller(
                Lists,
                UDim2.new(LIST_WIDTH_SCALE, 4, 0, 0),
                UDim2.new(1 - LIST_WIDTH_SCALE, -4, 1, 0),
                8, 8, 8
            ))

            S.Built = true
        end

        ------------------------------------------------------------------------
        --// API
        ------------------------------------------------------------------------

        function Browser:Refresh()
            if not S.IsOpen then
                return
            end

            S.LastRefresh = os.clock()
            Dictionary:ScanLive()
            RefreshList()
            Detail:Refresh()
        end

        function Browser:Select(Name)
            Detail:Select(Name)
            Browser:Refresh()
        end

        --// The dictionary arrived (or failed): show it, keeping the pick, or
        --// the first mob when there is none.
        Dictionary.S.OnLoaded = function()
            if not S.Built then
                return
            end

            local Selected = Detail:GetSelected()

            if not Selected or not Dictionary:Get(Selected) then
                local First = Dictionary:GetAll()[1]
                Selected = First and First.Name or nil
            end

            Detail:Select(Selected)
            Browser:Refresh()
        end

        function Browser:Reload()
            Dictionary:Load()

            if S.Built then
                RefreshList()
                Detail:Rebuild()
            end
        end

        function Browser:Open()
            if not Floating.Available() then
                return
            end

            if not S.Built then
                Build()
            end

            S.IsOpen = true
            Window:Open()

            if not Dictionary.S.Loaded and not Dictionary.S.Loading then
                Browser:Reload()
            else
                Detail:Rebuild()
            end

            Browser:Refresh()
        end

        function Browser:Close()
            if Window then
                Window:Close()
            end
        end

        function Browser:Toggle()
            if S.IsOpen then
                Browser:Close()
            else
                Browser:Open()
            end
        end

        function Browser:Update()
            if S.IsOpen and os.clock() - S.LastRefresh >= REFRESH_INTERVAL then
                Browser:Refresh()
            end
        end

        --// Below Enemy Priority and the target pickers, which Bootstrap adds.
        function Browser:BuildLateUI()
            if UIRef.TargetSection then
                UIRef.TargetSection:AddButton("Open Mob Dictionary", function()
                    Browser:Toggle()
                end)
            end
        end

        return Browser
    end,
}
