-- MobBrowser is the Mob Dictionary, a window of its own opened from the
-- Targeting section. It shows what the game's mob dictionary (MobDictionary)
-- says about every mob and boss, at a glance:
--
--   * The left side lists every mob, weakest to strongest by health,
--     narrowed by the search box and the ALL / MOBS / BOSSES / LIVE chips.
--     A thin bar under each row is its threat.
--   * The right side is the one picked: its kind, how many are alive in
--     this server, a threat meter, its health and speed in big numbers,
--     every number as a bar against the strongest mob, its other values as
--     tags, its status effect, and a button that adds it to Enemy Priority.
return {
    Name = "MobBrowser",
    IsFeature = true,
    Dependencies = {"Runtime", "Components", "Floating", "MobDictionary"},

    Start = function(Context)
        local UI = Context.UI
        local UIRef = Context.UIRef
        local AICUI = Context.AICUI
        local AICCombat = Context.AICCombat
        local AICProfile = Context.AICProfile
        local Floating = Context.Floating
        local Dictionary = Context.MobDictionary

        local New, Stroke = Floating.New, Floating.Stroke
        local Label, Button, ClearChildren = Floating.Label, Floating.Button, Floating.ClearChildren

        local WINDOW_WIDTH = 760
        local WINDOW_HEIGHT = 500
        local MIN_WIDTH = 580
        local MIN_HEIGHT = 380
        --// Share of the window the mob list takes; the detail gets the rest.
        local LIST_WIDTH_SCALE = 0.4
        local ROW_HEIGHT = 38
        local BAR_HEIGHT = 26
        local CHIP_HEIGHT = 22
        local TILE_HEIGHT = 54
        local STAT_BAR_HEIGHT = 30
        local THREAT_SEGMENTS = 5
        --// Live counts and priority marks are read again this often while open.
        local REFRESH_INTERVAL = 1

        local HEALTH_COLOR = Color3.fromRGB(96, 196, 120)
        local EXTREME_COLOR = Color3.fromRGB(255, 60, 60)
        local FILTERS = { "ALL", "MOBS", "BOSSES", "LIVE" }

        local Browser = {
            Name = "MobBrowser",
            IsFeature = true,
            S = {
                Built = false,
                IsOpen = false,
                Filter = "ALL",
                Selected = nil,
                --// Mob name -> list row, kept between refreshes.
                Rows = {},
                Chips = {},
                --// From MobDictionary:CountLive.
                Live = {},
                Entities = {},
                LastRefresh = 0,
                --// Detail labels updated in place on every refresh.
                LiveBadge = nil,
                PriorityButton = nil,
            },
        }

        local S = Browser.S
        local Theme, Window, SearchBox, RefreshButton, ChipBar, ListScroll, EmptyLabel, DetailScroll

        ------------------------------------------------------------------------
        --// Formatting
        ------------------------------------------------------------------------

        local function FormatNumber(Value)
            if Value == math.floor(Value) and math.abs(Value) < 1e15 then
                local Text = tostring(math.floor(math.abs(Value)))
                local Grouped = string.reverse((string.gsub(string.reverse(Text), "(%d%d%d)", "%1,")))
                Grouped = string.gsub(Grouped, "^,", "")
                return (Value < 0 and "-" or "") .. Grouped
            end

            local Text = string.format("%.2f", Value)
            return (string.gsub(string.gsub(Text, "0+$", ""), "%.$", ""))
        end

        local function FormatValue(Value)
            local Type = typeof(Value)

            if Type == "number" then
                return FormatNumber(Value)
            elseif Type == "boolean" then
                return Value and "YES" or "NO"
            elseif Type == "Instance" then
                return Value.Name
            elseif Value == nil or Value == "" then
                return "-"
            end

            return tostring(Value)
        end

        local THREAT_LEVELS = {
            { Name = "LOW", Color = function() return HEALTH_COLOR end },
            { Name = "MODERATE", Color = function() return Theme.Cyan end },
            { Name = "HIGH", Color = function() return Theme.Warning end },
            { Name = "SEVERE", Color = function() return Theme.Danger end },
            { Name = "EXTREME", Color = function() return EXTREME_COLOR end },
        }

        --// Filled segments (1..THREAT_SEGMENTS), level name and colour.
        local function DescribeThreat(Entry)
            local Filled = math.clamp(math.ceil(Dictionary.GetThreat(Entry) * THREAT_SEGMENTS), 1, THREAT_SEGMENTS)
            local Level = THREAT_LEVELS[Filled]
            return Filled, Level.Name, Level.Color()
        end

        local function GetStatColor(Stat)
            if Stat.Key == "Humanoid.MaxHealth" then
                return HEALTH_COLOR
            elseif Stat.Group == "Combat" then
                return Theme.Danger
            elseif Stat.Group == "Rewards" then
                return Theme.Cyan
            end

            return Theme.TextSecondary
        end

        local function GetKindColor(Entry)
            return Entry.Kind == "Boss" and Theme.Danger or Theme.Cyan
        end

        local function GetEntity(Name)
            return S.Entities[Name] or Name
        end

        local function IsInPriority(Name)
            return AICCombat.IsEntityInPriority ~= nil and AICCombat.IsEntityInPriority(GetEntity(Name))
        end

        ------------------------------------------------------------------------
        --// Small pieces
        ------------------------------------------------------------------------

        local function HorizontalList(Parent, Gap, Wraps)
            local Layout = New("UIListLayout", {
                Parent = Parent,
                FillDirection = Enum.FillDirection.Horizontal,
                SortOrder = Enum.SortOrder.LayoutOrder,
                VerticalAlignment = Enum.VerticalAlignment.Center,
                Padding = UDim.new(0, Gap),
            })

            --// Wraps is missing on older clients; tags then run on in one line.
            if Wraps then
                pcall(function()
                    Layout.Wraps = true
                end)
            end

            return Layout
        end

        local function Strip(Parent, Height, Order, Wraps)
            local Frame = New("Frame", {
                Parent = Parent,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, Height),
                AutomaticSize = Wraps and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
                LayoutOrder = Order,
            })

            HorizontalList(Frame, 4, Wraps)
            return Frame
        end

        local function Card(Parent, Order)
            local Frame = New("Frame", {
                Parent = Parent,
                BackgroundColor3 = Theme.Element,
                BackgroundTransparency = 0.1,
                BorderSizePixel = 0,
                Size = UDim2.new(1, -6, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                LayoutOrder = Order,
            })

            Stroke(Frame, Theme.BorderDim, 0.2)
            Floating.Padding(Frame, 10, 8)
            Floating.List(Frame, 6)
            return Frame
        end

        local function Heading(Parent, Text, Order)
            return Label(Parent, Text, 9, {
                TextColor3 = Theme.TextMuted,
                Font = Floating.Fonts.Bold,
                LayoutOrder = Order,
            })
        end

        local function Badge(Parent, Text, Color, Order)
            local Object = Label(Parent, Text, 9, {
                Size = UDim2.fromOffset(0, 18),
                AutomaticSize = Enum.AutomaticSize.X,
                BackgroundColor3 = Color,
                BackgroundTransparency = 0.82,
                TextColor3 = Color,
                Font = Floating.Fonts.Bold,
                TextXAlignment = Enum.TextXAlignment.Center,
                TextTruncate = Enum.TextTruncate.None,
                LayoutOrder = Order,
            })

            Stroke(Object, Color, 0.5)
            New("UIPadding", { Parent = Object, PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) })
            return Object
        end

        local function SetBadge(Object, Text, Color)
            Object.Text = Text
            Object.TextColor3 = Color
            Object.BackgroundColor3 = Color

            local BadgeStroke = Object:FindFirstChildOfClass("UIStroke")

            if BadgeStroke then
                BadgeStroke.Color = Color
            end
        end

        local function DescribeLive(Name)
            local Count = S.Live[Name] or 0

            if Count > 0 then
                return string.format("●  %d IN SERVER", Count), HEALTH_COLOR
            end

            return "○  NOT IN SERVER", Theme.TextMuted
        end

        ------------------------------------------------------------------------
        --// Detail
        ------------------------------------------------------------------------

        local function BuildThreatMeter(Parent, Entry, Order)
            local Filled, LevelName, Color = DescribeThreat(Entry)
            local Row = Strip(Parent, 16, Order)

            Label(Row, "THREAT", 9, {
                Size = UDim2.fromOffset(52, 16),
                TextColor3 = Theme.TextMuted,
                Font = Floating.Fonts.Bold,
                LayoutOrder = 0,
            })

            for Index = 1, THREAT_SEGMENTS do
                New("Frame", {
                    Parent = Row,
                    Size = UDim2.fromOffset(22, 8),
                    BackgroundColor3 = Index <= Filled and Color or Theme.Background,
                    BorderSizePixel = 0,
                    LayoutOrder = Index,
                })
            end

            Label(Row, "  " .. LevelName, 10, {
                Size = UDim2.fromOffset(90, 16),
                TextColor3 = Color,
                Font = Floating.Fonts.Bold,
                LayoutOrder = THREAT_SEGMENTS + 1,
            })
        end

        local function BuildHero(Entry)
            local Hero = Card(DetailScroll, 1)

            Label(Hero, string.upper(Entry.Name), 16, {
                Font = Floating.Fonts.Bold,
                TextColor3 = Theme.Text,
                LayoutOrder = 1,
            })

            local Badges = Strip(Hero, 18, 2)
            Badge(Badges, string.upper(Entry.Kind), GetKindColor(Entry), 1)

            local LiveText, LiveColor = DescribeLive(Entry.Name)
            S.LiveBadge = Badge(Badges, LiveText, LiveColor, 2)

            if Entry.Status then
                Badge(Badges, "☠  " .. string.upper(Entry.Status.Name), Theme.Warning, 3)
            end

            BuildThreatMeter(Hero, Entry, 3)
        end

        --// Health, speed and the first combat number in big type.
        local function PickTileStats(Entry)
            local Picked = {}

            for _, Key in ipairs({ "Humanoid.MaxHealth", "Humanoid.WalkSpeed" }) do
                for _, Stat in ipairs(Entry.Stats) do
                    if Stat.Key == Key then
                        table.insert(Picked, Stat)
                    end
                end
            end

            for _, Stat in ipairs(Entry.Stats) do
                if Stat.Numeric and Stat.Group == "Combat" then
                    table.insert(Picked, Stat)
                    break
                end
            end

            return Picked
        end

        local function BuildTiles(Entry)
            local Picked = PickTileStats(Entry)

            if #Picked == 0 then
                return
            end

            local Row = Strip(DetailScroll, TILE_HEIGHT, 2)
            Row.Size = UDim2.new(1, -6, 0, TILE_HEIGHT)

            for Index, Stat in ipairs(Picked) do
                local Color = GetStatColor(Stat)
                local _, Rank, Total = Dictionary.GetScale(Stat, Entry.Kind)
                local Tile = New("Frame", {
                    Parent = Row,
                    BackgroundColor3 = Theme.Element,
                    BackgroundTransparency = 0.1,
                    BorderSizePixel = 0,
                    Size = UDim2.new(1 / #Picked, -4, 1, 0),
                    LayoutOrder = Index,
                })

                Stroke(Tile, Theme.BorderDim, 0.2)

                New("Frame", {
                    Parent = Tile,
                    BackgroundColor3 = Color,
                    BorderSizePixel = 0,
                    Size = UDim2.new(1, 0, 0, 2),
                })

                Label(Tile, FormatNumber(Stat.Value), 18, {
                    Position = UDim2.fromOffset(10, 7),
                    Size = UDim2.new(1, -20, 0, 22),
                    Font = Floating.Fonts.Bold,
                    TextColor3 = Color,
                })

                Label(Tile, Stat.Label .. (Rank and string.format("  ·  #%d OF %d", Rank, Total) or ""), 8, {
                    Position = UDim2.fromOffset(10, 33),
                    Size = UDim2.new(1, -20, 0, 12),
                    TextColor3 = Theme.TextMuted,
                })
            end
        end

        local function BuildStatBar(Parent, Stat, Kind, Order)
            local Fraction, Rank, Total = Dictionary.GetScale(Stat, Kind)
            local Color = GetStatColor(Stat)
            local Holder = New("Frame", {
                Parent = Parent,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, STAT_BAR_HEIGHT),
                LayoutOrder = Order,
            })

            Label(Holder, Stat.Label, 9, {
                Size = UDim2.new(0.6, 0, 0, 14),
                TextColor3 = Theme.TextSecondary,
            })

            Label(Holder, FormatNumber(Stat.Value) .. (Rank and string.format("   #%d/%d", Rank, Total) or ""), 9, {
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.fromScale(1, 0),
                Size = UDim2.new(0.4, 0, 0, 14),
                TextColor3 = Theme.Text,
                Font = Floating.Fonts.Bold,
                TextXAlignment = Enum.TextXAlignment.Right,
            })

            local Track = New("Frame", {
                Parent = Holder,
                Position = UDim2.fromOffset(0, 18),
                Size = UDim2.new(1, 0, 0, 6),
                BackgroundColor3 = Theme.Background,
                BorderSizePixel = 0,
            })

            New("Frame", {
                Parent = Track,
                Size = UDim2.new(math.max(Fraction, 0.01), 0, 1, 0),
                BackgroundColor3 = Color,
                BorderSizePixel = 0,
            })
        end

        local GROUP_ORDER = { "Core", "Combat", "Rewards", "Other" }
        local GROUP_TITLES = { Core = "BODY", Combat = "COMBAT", Rewards = "REWARDS", Other = "OTHER" }

        --// Every number as a bar against the strongest of its kind, by group.
        local function BuildBars(Entry)
            local BarsCard = nil

            for _, Group in ipairs(GROUP_ORDER) do
                local Stats = {}

                for _, Stat in ipairs(Entry.Stats) do
                    if Stat.Numeric and Stat.Group == Group then
                        table.insert(Stats, Stat)
                    end
                end

                if #Stats > 0 then
                    if not BarsCard then
                        BarsCard = Card(DetailScroll, 3)
                        Heading(BarsCard, "COMPARED TO THE STRONGEST " .. string.upper(Entry.Kind), 0)
                    end

                    local Order = #BarsCard:GetChildren() * 100
                    Heading(BarsCard, GROUP_TITLES[Group], Order).TextColor3 = Theme.TextSecondary

                    for Index, Stat in ipairs(Stats) do
                        BuildStatBar(BarsCard, Stat, Entry.Kind, Order + Index)
                    end
                end
            end
        end

        local function AddTags(Parent, Pairs, Color, Order)
            local Flow = Strip(Parent, 0, Order, true)

            for Index, Pair in ipairs(Pairs) do
                Badge(Flow, Pair.Label .. "  " .. FormatValue(Pair.Value), Color, Index)
            end
        end

        --// Values that are not numbers, and the status effect.
        local function BuildTraits(Entry)
            local Traits = {}

            for _, Stat in ipairs(Entry.Stats) do
                if not Stat.Numeric then
                    table.insert(Traits, Stat)
                end
            end

            if #Traits > 0 then
                local TraitsCard = Card(DetailScroll, 4)
                Heading(TraitsCard, "TRAITS", 0)
                AddTags(TraitsCard, Traits, Theme.TextSecondary, 1)
            end

            if Entry.Status then
                local Status = Card(DetailScroll, 5)
                Heading(Status, "STATUS EFFECT", 0)

                Label(Status, "☠  " .. string.upper(Entry.Status.Name), 13, {
                    TextColor3 = Theme.Warning,
                    Font = Floating.Fonts.Bold,
                    LayoutOrder = 1,
                })

                if #Entry.Status.Props > 0 then
                    AddTags(Status, Entry.Status.Props, Theme.Warning, 2)
                end
            end
        end

        local function UpdatePriorityButton()
            local PriorityButton = S.PriorityButton

            if not PriorityButton or not S.Selected then
                return
            end

            local Added = IsInPriority(S.Selected)
            PriorityButton.Text = Added and "✓  IN ENEMY PRIORITY" or "+  ADD TO ENEMY PRIORITY"
            PriorityButton.TextColor3 = Added and HEALTH_COLOR or Theme.Cyan
        end

        local function BuildActions(Entry)
            local Row = Strip(DetailScroll, 28, 6)
            Row.Size = UDim2.new(1, -6, 0, 28)

            S.PriorityButton = Button(Row, "", Theme.Cyan, {
                Size = UDim2.new(0.62, -2, 1, 0),
                LayoutOrder = 1,
            })

            local CopyButton = Button(Row, "COPY NAME", Theme.TextMuted, {
                Size = UDim2.new(0.38, -2, 1, 0),
                LayoutOrder = 2,
            })

            S.PriorityButton.Activated:Connect(function()
                if IsInPriority(Entry.Name) then
                    return
                end

                if not AICProfile.S.ActiveProfileName then
                    Context.NotifyAction("Enemy Priority", "Load or create a profile first")
                    return
                end

                if AICUI.S.AddPriorityTarget then
                    AICUI.S.AddPriorityTarget(GetEntity(Entry.Name))
                end

                UpdatePriorityButton()
            end)

            CopyButton.Activated:Connect(function()
                local Copied = Floating.CopyText(GetEntity(Entry.Name))
                Context.NotifyAction("Mob Dictionary", Copied and "Name copied" or "No clipboard here")
            end)

            UpdatePriorityButton()
        end

        local function BuildDetail()
            ClearChildren(DetailScroll)
            S.LiveBadge = nil
            S.PriorityButton = nil

            local Entry = S.Selected and Dictionary:Get(S.Selected)

            if not Entry then
                local Message = "Pick a mob on the left"

                if Dictionary.S.Loading then
                    Message = "Loading the mob dictionary..."
                elseif Dictionary.S.Error then
                    Message = Dictionary.S.Error
                end

                Label(DetailScroll, Message, 10, {
                    TextColor3 = Dictionary.S.Error and Theme.Danger or Theme.TextMuted,
                    TextWrapped = true,
                    TextTruncate = Enum.TextTruncate.None,
                    AutomaticSize = Enum.AutomaticSize.Y,
                })
                return
            end

            BuildHero(Entry)
            BuildTiles(Entry)
            BuildBars(Entry)
            BuildTraits(Entry)
            BuildActions(Entry)
        end

        ------------------------------------------------------------------------
        --// List
        ------------------------------------------------------------------------

        local function IsShown(Entry, Query)
            if S.Filter == "MOBS" and Entry.Kind ~= "Mob" then
                return false
            elseif S.Filter == "BOSSES" and Entry.Kind ~= "Boss" then
                return false
            elseif S.Filter == "LIVE" and (S.Live[Entry.Name] or 0) == 0 then
                return false
            end

            return Query == "" or string.find(string.lower(Entry.Name), Query, 1, true) ~= nil
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

            New("Frame", {
                Parent = Row,
                Position = UDim2.fromOffset(0, 6),
                Size = UDim2.new(0, 2, 1, -12),
                BackgroundColor3 = GetKindColor(Entry),
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
                Size = UDim2.new(Filled / THREAT_SEGMENTS, -20 * Filled / THREAT_SEGMENTS, 0, 2),
                BackgroundColor3 = ThreatColor,
                BorderSizePixel = 0,
            })

            UI:_Connect(Row.Activated, function()
                Browser:Select(Entry.Name)
            end)

            return { Button = Row, NameLabel = NameLabel, InfoLabel = InfoLabel }
        end

        local function UpdateRow(Row, Entry)
            local Health = Dictionary.GetStat(Entry, "Humanoid.MaxHealth")
            local Parts = { string.upper(Entry.Kind) }

            if Health then
                table.insert(Parts, "HP " .. FormatNumber(Health))
            end

            local Count = S.Live[Entry.Name] or 0

            if Count > 0 then
                table.insert(Parts, string.format("● %d LIVE", Count))
            end

            if IsInPriority(Entry.Name) then
                table.insert(Parts, "✓ PRIORITY")
            end

            local Selected = S.Selected == Entry.Name
            Row.InfoLabel.Text = table.concat(Parts, "  ·  ")
            Row.InfoLabel.TextColor3 = Count > 0 and HEALTH_COLOR or Theme.TextMuted
            Row.NameLabel.TextColor3 = Selected and Theme.Cyan or Theme.Text
            Row.Button.BackgroundColor3 = Selected and Theme.PanelHover or Theme.Element
        end

        local function CountFilter(All, Filter)
            local Saved = S.Filter
            local Count = 0
            S.Filter = Filter

            for _, Entry in ipairs(All) do
                if IsShown(Entry, "") then
                    Count += 1
                end
            end

            S.Filter = Saved
            return Count
        end

        local function RefreshChips(All)
            for _, Filter in ipairs(FILTERS) do
                local Chip = S.Chips[Filter]
                local Active = S.Filter == Filter
                Chip.Text = string.format("%s  %d", Filter, CountFilter(All, Filter))
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

            RefreshButton = Button(Body, "↻  RELOAD", Theme.TextMuted, {
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, 0, 0, 0),
                Size = UDim2.fromOffset(86, BAR_HEIGHT),
            })

            ChipBar = New("Frame", {
                Parent = Body,
                Position = UDim2.fromOffset(0, BAR_HEIGHT + 6),
                Size = UDim2.new(1, 0, 0, CHIP_HEIGHT),
                BackgroundTransparency = 1,
            })

            HorizontalList(ChipBar, 4)

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

            UI:_Connect(RefreshButton.Activated, function()
                Browser:Reload()
            end)
        end

        local function Build()
            Theme = UI.Theme

            Window = Floating.CreateWindow({
                Title = "MOB DICTIONARY",
                Subtitle = "Every mob and boss  //  stats against the strongest  //  add to Enemy Priority",
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

            DetailScroll = Floating.Scroller(
                Lists,
                UDim2.new(LIST_WIDTH_SCALE, 4, 0, 0),
                UDim2.new(1 - LIST_WIDTH_SCALE, -4, 1, 0),
                8, 8, 8
            )

            S.Built = true
        end

        ------------------------------------------------------------------------
        --// API
        ------------------------------------------------------------------------

        local function RefreshLive()
            S.Live, S.Entities = Dictionary:CountLive()

            if S.LiveBadge and S.Selected then
                SetBadge(S.LiveBadge, DescribeLive(S.Selected))
            end

            UpdatePriorityButton()
        end

        function Browser:Refresh()
            if not S.IsOpen then
                return
            end

            S.LastRefresh = os.clock()
            RefreshLive()
            RefreshList()
        end

        function Browser:Select(Name)
            S.Selected = Name
            BuildDetail()
            Browser:Refresh()
        end

        --// The dictionary arrived (or failed): show it, keeping the pick.
        Dictionary.S.OnLoaded = function()
            if not S.Built then
                return
            end

            if S.Selected and not Dictionary:Get(S.Selected) then
                S.Selected = nil
            end

            if not S.Selected then
                local First = Dictionary:GetAll()[1]
                S.Selected = First and First.Name or nil
            end

            S.LastRefresh = os.clock()
            RefreshLive()
            RefreshList()
            BuildDetail()
        end

        function Browser:Reload()
            Dictionary:Load()

            if S.Built then
                RefreshList()
                BuildDetail()
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
                BuildDetail()
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
