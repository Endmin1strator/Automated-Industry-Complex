-- SmithingBrowser is a window of its own, opened from the Crafting tab, for
-- finding recipes. The left side is a searchable list of every recipe; the
-- one picked shows on the right with what one craft needs and what is
-- missing. Tapping a material pops up what it is crafted from when it is a
-- recipe itself. Recipes are added to Recipe Priority from here, which
-- replaced the Add Recipe dropdown.
return {
    Name = "SmithingBrowser",
    IsFeature = true,
    Dependencies = {"Runtime", "SaveConfig", "SmithingRecipes", "Floating"},

    Start = function(Context)
        local UI = Context.UI
        local UIRef = Context.UIRef
        local NotifyAction = Context.NotifyAction
        local Recipes = Context.SmithingRecipes
        local Floating = Context.Floating
        local UserInputService = Context.Services.UserInputService

        local New, Corner, Stroke, Padding, List = Floating.New, Floating.Corner, Floating.Stroke, Floating.Padding, Floating.List
        local Label, Button, ClearChildren, IsInside = Floating.Label, Floating.Button, Floating.ClearChildren, Floating.IsInside

        local MAX_STACK = Context.SaveConfig.ITEM_MAX_STACK
        local WINDOW_WIDTH = 580
        local WINDOW_HEIGHT = 400
        --// Share of the window the recipe list takes; the details get the rest.
        local LIST_WIDTH_SCALE = 0.46
        local ROW_HEIGHT = 34
        local POPUP_WIDTH = 240
        --// Inventory and skill are read again this often while open.
        local REFRESH_INTERVAL = 1

        local Browser = {
            Name = "SmithingBrowser",
            IsFeature = true,
            S = {
                Built = false,
                IsOpen = false,
                Selected = nil,
                --// Recipe name -> list row, kept between refreshes.
                Rows = {},
                --// Material name -> its row in the details, for the popup.
                MaterialRows = {},
                DetailSignature = nil,
                PopupFor = nil,
                PopupAnchor = nil,
                LastRefresh = 0,
            },
        }

        local S = Browser.S
        local Theme, Window, SearchBox, ListScroll, EmptyLabel, DetailScroll, Popup, PopupContent

        ------------------------------------------------------------------------
        --// What the inventory says about a recipe or a material
        ------------------------------------------------------------------------

        local function ReadInventory()
            return {
                Inventory = Recipes:GetInventory(),
                Reserves = Recipes:GetReserves(),
                Skill = Recipes:GetSkill(),
            }
        end

        local function Describe(Name, Stock)
            return Recipes:Describe({ Name = Name, Target = 0 }, Stock.Inventory, Stock.Reserves, Stock.Skill)
        end

        --// One material of one craft: Have counts the whole inventory, Usable
        --// what is left after Material Reserve, Missing what one craft lacks.
        local function DescribeMaterial(Material, Stock)
            local Have = Stock.Inventory[Material.Name] or 0
            local Keep = Stock.Reserves[Material.Name] or 0
            local Usable = math.max(0, Have - Keep)

            return {
                Have = Have,
                Keep = Keep,
                Usable = Usable,
                Missing = math.max(0, Material.Amount - Usable),
            }
        end

        local function GetRecipeList()
            return UIRef.RecipePriorityComponent
        end

        local function IsInPriority(Name)
            local RecipeList = GetRecipeList()
            return RecipeList ~= nil and table.find(RecipeList.Priority, Name) ~= nil
        end

        --// The status line of a recipe and its colour.
        local function DescribeStatus(State)
            if State.Locked then
                return "LOCKED", Theme.TextMuted
            elseif State.Craftable > 0 or not State.Short then
                return string.format("READY  x%d", State.Craftable), Theme.Cyan
            end

            return string.format("NEED %s %d/%d", State.Short.Name, State.Short.Have, State.Short.Need), Theme.Warning
        end

        local function Matches(Recipe, Query)
            if Query == "" or string.find(string.lower(Recipe.Name), Query, 1, true) then
                return true
            end

            --// Also finds what a material is used in.
            for _, Material in ipairs(Recipe.Materials) do
                if string.find(string.lower(Material.Name), Query, 1, true) then
                    return true
                end
            end

            return false
        end

        ------------------------------------------------------------------------
        --// Material popup
        ------------------------------------------------------------------------

        local function HidePopup()
            S.PopupFor = nil
            S.PopupAnchor = nil

            if Popup then
                Popup.Visible = false
            end
        end

        --// Beside the tapped row, flipped to its left when it would run off
        --// the screen, then pulled inside once its height is known.
        --// Deferred: a row just rebuilt has no position until layout runs.
        local function PlacePopup(Anchor)
            task.defer(function()
                if not Popup.Visible or S.PopupAnchor ~= Anchor or not Anchor.Parent then
                    return
                end

                local Screen = UI.ScreenGui.AbsoluteSize
                local Left = Anchor.AbsolutePosition.X + Anchor.AbsoluteSize.X + 6

                if Left + POPUP_WIDTH > Screen.X - Floating.SCREEN_MARGIN then
                    Left = Anchor.AbsolutePosition.X - POPUP_WIDTH - 6
                end

                Popup.Position = UDim2.fromOffset(Left, Anchor.AbsolutePosition.Y)
                UI._ClampToParent(Popup)
            end)
        end

        local function ShowPopup(MaterialName, Anchor)
            local Stock = ReadInventory()
            local Recipe = Recipes:Get(MaterialName)
            local Have = Stock.Inventory[MaterialName] or 0
            local Keep = Stock.Reserves[MaterialName] or 0

            ClearChildren(PopupContent)

            local Header = New("Frame", { Parent = PopupContent, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 1 })
            Label(Header, MaterialName, 13, { Size = UDim2.new(1, -24, 1, 0), TextColor3 = Theme.Cyan, Font = Enum.Font.GothamBold })

            local Close = Button(Header, "×", Theme.Danger, {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, 0, 0.5, 0),
                Size = UDim2.fromOffset(20, 18),
            })
            UI:_Connect(Close.Activated, HidePopup)

            local HaveText = string.format("HAVE  %d", Have)

            if Keep > 0 then
                HaveText ..= string.format("   (KEEP %d)", Keep)
            end

            Label(PopupContent, HaveText, 11, { TextColor3 = Theme.TextSecondary, LayoutOrder = 2 })

            if not Recipe then
                Label(PopupContent, "Not craftable: no smithing recipe makes it", 11, {
                    TextColor3 = Theme.TextMuted,
                    TextWrapped = true,
                    TextTruncate = Enum.TextTruncate.None,
                    AutomaticSize = Enum.AutomaticSize.Y,
                    LayoutOrder = 3,
                })
            else
                local Locked = Recipe.Skill > Stock.Skill

                Label(PopupContent, string.format("CRAFTED FROM  ·  SKILL %s", tostring(Recipe.Skill)), 11, {
                    TextColor3 = Locked and Theme.Danger or Theme.TextSecondary,
                    LayoutOrder = 3,
                })

                for Index, Material in ipairs(Recipe.Materials) do
                    local Info = DescribeMaterial(Material, Stock)

                    Label(PopupContent, string.format("  %s   %d / %d", Material.Name, Info.Usable, Material.Amount), 11, {
                        TextColor3 = Info.Missing > 0 and Theme.Warning or Theme.Text,
                        LayoutOrder = 3 + Index,
                    })
                end

                local Open = Button(PopupContent, "OPEN RECIPE", Theme.Cyan, { LayoutOrder = 100, Size = UDim2.new(1, 0, 0, 22) })

                UI:_Connect(Open.Activated, function()
                    Browser:Select(MaterialName)
                end)
            end

            S.PopupFor = MaterialName
            S.PopupAnchor = Anchor
            Popup.Visible = true
            PlacePopup(Anchor)
        end

        ------------------------------------------------------------------------
        --// Details of the selected recipe
        ------------------------------------------------------------------------

        local function GetDetailSignature(Recipe, Stock)
            local Parts = { Recipe.Name, tostring(Stock.Skill), tostring(Stock.Inventory[Recipe.Name] or 0), tostring(IsInPriority(Recipe.Name)) }

            for _, Material in ipairs(Recipe.Materials) do
                local Info = DescribeMaterial(Material, Stock)
                table.insert(Parts, Material.Name .. ":" .. Info.Have .. ":" .. Info.Keep)
            end

            return table.concat(Parts, "|")
        end

        local function AddMaterialRow(Material, Stock, Order)
            local Info = DescribeMaterial(Material, Stock)
            local Craftable = Recipes:Get(Material.Name) ~= nil

            local Row = New("TextButton", {
                Parent = DetailScroll,
                Size = UDim2.new(1, -6, 0, ROW_HEIGHT),
                BackgroundColor3 = Theme.Element,
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = true,
                LayoutOrder = Order,
            })

            Corner(Row, 4)
            Stroke(Row, Info.Missing > 0 and Theme.Warning or Theme.BorderDim, Info.Missing > 0 and 0.4 or 0.5)

            Label(Row, Material.Name .. (Craftable and "  ›" or ""), 12, {
                Position = UDim2.fromOffset(8, 3),
                Size = UDim2.new(1, -90, 0, 15),
            })

            Label(Row, string.format("%d / %d", Info.Usable, Material.Amount), 12, {
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -8, 0, 3),
                Size = UDim2.fromOffset(80, 15),
                TextXAlignment = Enum.TextXAlignment.Right,
                TextColor3 = Info.Missing > 0 and Theme.Warning or Theme.Cyan,
            })

            local Note = Info.Missing > 0 and string.format("MISSING %d", Info.Missing) or "OK"

            if Info.Keep > 0 then
                Note ..= string.format("   ·   HAVE %d, KEEP %d", Info.Have, Info.Keep)
            end

            Label(Row, Note, 10, {
                Position = UDim2.fromOffset(8, 18),
                Size = UDim2.new(1, -16, 0, 13),
                TextColor3 = Info.Missing > 0 and Theme.Warning or Theme.TextMuted,
            })

            UI:_Connect(Row.Activated, function()
                if S.PopupFor == Material.Name then
                    HidePopup()
                else
                    ShowPopup(Material.Name, Row)
                end
            end)

            S.MaterialRows[Material.Name] = Row
        end

        local function TogglePriority(Name)
            local RecipeList = GetRecipeList()

            if not RecipeList then
                return
            end

            if IsInPriority(Name) then
                RecipeList:Remove(Name)
                NotifyAction("AUTO SMITHING", "Removed " .. Name)
            elseif RecipeList:Add(Name, MAX_STACK) then
                NotifyAction("AUTO SMITHING", "Added " .. Name)
            end

            Browser:Refresh()
        end

        local function BuildDetail(Recipe, Stock)
            ClearChildren(DetailScroll)
            table.clear(S.MaterialRows)

            if not Recipe then
                Label(DetailScroll, "Pick a recipe from the list", 12, { TextColor3 = Theme.TextMuted, LayoutOrder = 1 })
                return
            end

            local State = Describe(Recipe.Name, Stock)
            local Status, StatusColor = DescribeStatus(State)

            Label(DetailScroll, Recipe.Name, 15, { TextColor3 = Theme.Cyan, Font = Enum.Font.GothamBold, LayoutOrder = 1 })
            Label(DetailScroll, string.format("SKILL  %s  ·  YOURS  %s", tostring(Recipe.Skill), tostring(Stock.Skill)), 11, {
                TextColor3 = State.Locked and Theme.Danger or Theme.TextSecondary,
                LayoutOrder = 2,
            })
            Label(DetailScroll, string.format("TYPE  %s  ·  HAVE  %d", Recipe.CraftType, State.Have), 11, {
                TextColor3 = Theme.TextSecondary,
                LayoutOrder = 3,
            })
            Label(DetailScroll, Status, 12, { TextColor3 = StatusColor, Font = Enum.Font.GothamBold, LayoutOrder = 4 })
            Label(DetailScroll, "MATERIALS PER CRAFT  (tap one to see how it is made)", 10, {
                TextColor3 = Theme.TextMuted,
                LayoutOrder = 5,
            })

            if #Recipe.Materials == 0 then
                Label(DetailScroll, "  none", 11, { TextColor3 = Theme.TextMuted, LayoutOrder = 6 })
            end

            for Index, Material in ipairs(Recipe.Materials) do
                AddMaterialRow(Material, Stock, 5 + Index)
            end

            local InPriority = IsInPriority(Recipe.Name)
            local Toggle = Button(DetailScroll, InPriority and "REMOVE FROM RECIPE PRIORITY" or "ADD TO RECIPE PRIORITY",
                InPriority and Theme.Danger or Theme.Cyan, { LayoutOrder = 1000 })

            UI:_Connect(Toggle.Activated, function()
                TogglePriority(Recipe.Name)
            end)
        end

        --// Rebuilt only when something it shows changed, so a refresh does
        --// not reset the scroll or drop an open popup.
        local function RefreshDetail(Stock)
            local Recipe = S.Selected and Recipes:Get(S.Selected)

            if S.Selected and not Recipe then
                S.Selected = nil
            end

            local Signature = Recipe and GetDetailSignature(Recipe, Stock) or ""

            if Signature == S.DetailSignature then
                return
            end

            S.DetailSignature = Signature
            BuildDetail(Recipe, Stock)

            --// The popup's row was replaced: follow the new one, or close.
            if S.PopupFor then
                local Anchor = S.MaterialRows[S.PopupFor]

                if Anchor then
                    ShowPopup(S.PopupFor, Anchor)
                else
                    HidePopup()
                end
            end
        end

        ------------------------------------------------------------------------
        --// Recipe list
        ------------------------------------------------------------------------

        local function CreateRow(Name)
            local Row = New("TextButton", {
                Parent = ListScroll,
                Size = UDim2.new(1, -6, 0, ROW_HEIGHT),
                BackgroundColor3 = Theme.Element,
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = true,
            })

            Corner(Row, 4)

            local Bar = New("Frame", {
                Parent = Row,
                Position = UDim2.fromOffset(0, 5),
                Size = UDim2.new(0, 3, 1, -10),
                BorderSizePixel = 0,
            })

            local NameLabel = Label(Row, Name, 12, { Position = UDim2.fromOffset(10, 3), Size = UDim2.new(1, -16, 0, 15) })
            local InfoLabel = Label(Row, "", 10, { Position = UDim2.fromOffset(10, 18), Size = UDim2.new(1, -16, 0, 13) })

            UI:_Connect(Row.Activated, function()
                Browser:Select(Name)
            end)

            return { Button = Row, Bar = Bar, NameLabel = NameLabel, InfoLabel = InfoLabel }
        end

        local function UpdateRow(Row, Recipe, Stock)
            local Status, Color = DescribeStatus(Describe(Recipe.Name, Stock))
            local Selected = S.Selected == Recipe.Name
            local Info = string.format("SKILL %s  ·  %s", tostring(Recipe.Skill), Status)

            if IsInPriority(Recipe.Name) then
                Info = "✓ " .. Info
            end

            Row.Bar.BackgroundColor3 = Color
            Row.InfoLabel.Text = Info
            Row.InfoLabel.TextColor3 = Color
            Row.NameLabel.TextColor3 = Selected and Theme.Cyan or Theme.Text
            Row.Button.BackgroundColor3 = Selected and Theme.PanelHover or Theme.Element
        end

        local function RefreshList(Stock)
            local Query = string.lower(SearchBox.Text or "")
            local All = Recipes:GetAll()
            local Seen = {}
            local Shown = 0

            for Index, Recipe in ipairs(All) do
                Seen[Recipe.Name] = true

                local Row = S.Rows[Recipe.Name]

                if not Row then
                    Row = CreateRow(Recipe.Name)
                    S.Rows[Recipe.Name] = Row
                end

                local Visible = Matches(Recipe, Query)
                Row.Button.Visible = Visible
                Row.Button.LayoutOrder = Index

                if Visible then
                    Shown += 1
                    UpdateRow(Row, Recipe, Stock)
                end
            end

            for Name, Row in pairs(S.Rows) do
                if not Seen[Name] then
                    Row.Button:Destroy()
                    S.Rows[Name] = nil
                end
            end

            EmptyLabel.Text = #All == 0 and "No recipes found" or "No recipes match"
            EmptyLabel.Visible = Shown == 0
        end

        ------------------------------------------------------------------------
        --// Window
        ------------------------------------------------------------------------

        local function Build()
            Theme = UI.Theme

            Window = Floating.CreateWindow({
                Title = "RECIPE BROWSER",
                Width = WINDOW_WIDTH,
                Height = WINDOW_HEIGHT,
                OnClose = function()
                    S.IsOpen = false
                    HidePopup()
                end,
            })

            SearchBox = New("TextBox", {
                Parent = Window.Body,
                Size = UDim2.new(1, 0, 0, 26),
                BackgroundColor3 = Theme.Element,
                BorderSizePixel = 0,
                Text = "",
                PlaceholderText = "search recipe or material...",
                PlaceholderColor3 = Theme.TextMuted,
                TextColor3 = Theme.Text,
                TextSize = 12,
                Font = Enum.Font.GothamMedium,
                TextXAlignment = Enum.TextXAlignment.Left,
                ClearTextOnFocus = false,
            })

            Corner(SearchBox, 4)
            Stroke(SearchBox, Theme.BorderDim, 0.3)
            New("UIPadding", { Parent = SearchBox, PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) })

            local Lists = New("Frame", {
                Parent = Window.Body,
                BackgroundTransparency = 1,
                Position = UDim2.fromOffset(0, 34),
                Size = UDim2.new(1, 0, 1, -34),
            })

            ListScroll = Floating.Scroller(Lists, UDim2.new(), UDim2.new(LIST_WIDTH_SCALE, -4, 1, 0), 4, 4)
            DetailScroll = Floating.Scroller(Lists, UDim2.new(LIST_WIDTH_SCALE, 4, 0, 0), UDim2.new(1 - LIST_WIDTH_SCALE, -4, 1, 0), 8, 6)

            EmptyLabel = Label(ListScroll, "No recipes match", 12, {
                TextColor3 = Theme.TextMuted,
                Visible = false,
                LayoutOrder = -1,
            })

            Popup = New("Frame", {
                Name = "SmithingBrowserPopup",
                Parent = UI.ScreenGui,
                Size = UDim2.fromOffset(POPUP_WIDTH, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundColor3 = Theme.Panel,
                BorderSizePixel = 0,
                Active = true,
                Visible = false,
                ZIndex = Floating.POPUP_Z,
            })

            Corner(Popup, 6)
            Stroke(Popup, Theme.Border)
            Padding(Popup, 8, 8)

            PopupContent = New("Frame", {
                Parent = Popup,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
            })

            List(PopupContent, 3)

            UI:_Connect(SearchBox:GetPropertyChangedSignal("Text"), function()
                RefreshList(ReadInventory())
            end)

            --// A tap anywhere but the popup or its row closes the popup.
            UI:_Connect(UserInputService.InputBegan, function(Input)
                if not Popup.Visible
                    or (Input.UserInputType ~= Enum.UserInputType.MouseButton1
                        and Input.UserInputType ~= Enum.UserInputType.Touch)
                then
                    return
                end

                local Position = Vector2.new(Input.Position.X, Input.Position.Y)

                if not IsInside(Popup, Position) and not IsInside(S.PopupAnchor, Position) then
                    HidePopup()
                end
            end)

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

            local Stock = ReadInventory()
            RefreshList(Stock)
            RefreshDetail(Stock)
        end

        function Browser:Select(Name)
            S.Selected = Name
            S.DetailSignature = nil
            HidePopup()
            Browser:Refresh()
        end

        function Browser:Open()
            if not Floating.Available() then
                return
            end

            if not S.Built then
                Build()
            end

            S.IsOpen = true
            S.DetailSignature = nil
            Window:Open()
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

        return Browser
    end,
}
