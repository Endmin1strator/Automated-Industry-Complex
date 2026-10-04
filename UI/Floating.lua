-- Floating builds windows that sit outside the main UI (Recipe Browser,
-- Server Browser): a draggable frame with a title bar and a close button,
-- plus the small instance helpers they share, in the look of UI/Utils.
-- Colours come from the window library's theme at the time of each call.
return {
    Name = "Floating",
    Dependencies = {"Runtime"},

    Start = function(Context)
        local UI = Context.UI

        --// Kept free on every side of the screen.
        local SCREEN_MARGIN = 12
        --// Above the main window and the pinned items panel; popups above that.
        local WINDOW_Z = 60
        local POPUP_Z = 70
        local HEADER_HEIGHT = 32

        local Floating = {
            Name = "Floating",
            SCREEN_MARGIN = SCREEN_MARGIN,
            POPUP_Z = POPUP_Z,
        }

        function Floating.Available()
            return UI ~= nil and UI.ScreenGui ~= nil
        end

        function Floating.Theme()
            return UI.Theme
        end

        function Floating.New(ClassName, Properties)
            local Object = Instance.new(ClassName)

            for Property, Value in pairs(Properties or {}) do
                if Property ~= "Parent" then
                    Object[Property] = Value
                end
            end

            Object.Parent = Properties and Properties.Parent
            return Object
        end

        local New = Floating.New

        function Floating.Corner(Parent, Radius)
            return New("UICorner", { Parent = Parent, CornerRadius = UDim.new(0, Radius or 4) })
        end

        function Floating.Stroke(Parent, Color, Transparency)
            return New("UIStroke", {
                Parent = Parent,
                Color = Color,
                Transparency = Transparency or 0,
                ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            })
        end

        function Floating.Padding(Parent, X, Y)
            return New("UIPadding", {
                Parent = Parent,
                PaddingLeft = UDim.new(0, X),
                PaddingRight = UDim.new(0, X),
                PaddingTop = UDim.new(0, Y),
                PaddingBottom = UDim.new(0, Y),
            })
        end

        function Floating.List(Parent, Gap)
            return New("UIListLayout", {
                Parent = Parent,
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, Gap),
            })
        end

        local function Apply(Object, Properties)
            for Property, Value in pairs(Properties or {}) do
                Object[Property] = Value
            end

            return Object
        end

        function Floating.Label(Parent, Text, Size, Properties)
            return Apply(New("TextLabel", {
                Parent = Parent,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, Size + 4),
                Text = Text,
                TextColor3 = UI.Theme.Text,
                TextSize = Size,
                Font = Enum.Font.GothamMedium,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
            }), Properties)
        end

        function Floating.Button(Parent, Text, Color, Properties)
            local Object = New("TextButton", {
                Parent = Parent,
                Size = UDim2.new(1, 0, 0, 26),
                BackgroundColor3 = UI.Theme.Element,
                BorderSizePixel = 0,
                Text = Text,
                TextColor3 = Color or UI.Theme.Text,
                TextSize = 12,
                Font = Enum.Font.GothamBold,
                AutoButtonColor = true,
            })

            Floating.Corner(Object, 4)
            Floating.Stroke(Object, UI.Theme.BorderDim, 0.3)
            return Apply(Object, Properties)
        end

        function Floating.Scroller(Parent, Position, Size, PadX, PadY, Gap)
            local Scroll = New("ScrollingFrame", {
                Parent = Parent,
                Position = Position,
                Size = Size,
                BackgroundColor3 = UI.Theme.Panel,
                BorderSizePixel = 0,
                CanvasSize = UDim2.new(),
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollBarThickness = 4,
                ScrollBarImageColor3 = UI.Theme.Border,
                ScrollingDirection = Enum.ScrollingDirection.Y,
            })

            Floating.Corner(Scroll, 4)
            Floating.Padding(Scroll, PadX or 4, PadY or 4)
            Floating.List(Scroll, Gap or 3)
            return Scroll
        end

        function Floating.ClearChildren(Parent)
            for _, Child in ipairs(Parent:GetChildren()) do
                if Child:IsA("GuiObject") then
                    Child:Destroy()
                end
            end
        end

        function Floating.IsInside(Object, Position)
            if not Object or not Object.Parent or not Object.Visible then
                return false
            end

            local Min = Object.AbsolutePosition
            local Max = Min + Object.AbsoluteSize
            return Position.X >= Min.X and Position.X <= Max.X and Position.Y >= Min.Y and Position.Y <= Max.Y
        end

        --// Executor-only; false where there is no clipboard function (Studio).
        function Floating.CopyText(Text)
            local Copy = setclipboard or toclipboard

            if type(Copy) ~= "function" then
                return false
            end

            return pcall(Copy, Text)
        end

        --// A window of its own. Options: Title, Width, Height, OnClose.
        --// Content goes in Window.Body, the area under the title bar.
        function Floating.CreateWindow(Options)
            local Theme = UI.Theme
            local Window = { IsOpen = false }

            local Frame = New("Frame", {
                Name = Options.Title,
                Parent = UI.ScreenGui,
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromOffset(Options.Width, Options.Height),
                BackgroundColor3 = Theme.Background,
                BackgroundTransparency = 0.03,
                BorderSizePixel = 0,
                Active = true,
                Visible = false,
                ZIndex = WINDOW_Z,
            })

            Floating.Corner(Frame, 6)
            Floating.Stroke(Frame, Theme.BorderDim)

            local Header = New("Frame", {
                Parent = Frame,
                BackgroundColor3 = Theme.BackgroundLight,
                BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
                Active = true,
            })

            Floating.Corner(Header, 6)
            Floating.Label(Header, Options.Title, 13, {
                Position = UDim2.fromOffset(12, 0),
                Size = UDim2.new(1, -50, 1, 0),
                TextColor3 = Theme.Cyan,
                Font = Enum.Font.GothamBold,
            })

            local Close = Floating.Button(Header, "×", Theme.Danger, {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -8, 0.5, 0),
                Size = UDim2.fromOffset(22, 20),
            })

            Window.Frame = Frame
            Window.Body = New("Frame", {
                Parent = Frame,
                BackgroundTransparency = 1,
                Position = UDim2.fromOffset(10, HEADER_HEIGHT + 8),
                Size = UDim2.new(1, -20, 1, -(HEADER_HEIGHT + 18)),
            })

            UI:_MakeDraggable(Header, Frame, true)

            --// Fits a small screen, keeping the margin on every side.
            local function FitToScreen()
                local Screen = UI.ScreenGui.AbsoluteSize

                if Screen.X <= 0 or Screen.Y <= 0 then
                    return
                end

                Frame.Size = UDim2.fromOffset(
                    math.min(Options.Width, Screen.X - SCREEN_MARGIN * 2),
                    math.min(Options.Height, Screen.Y - SCREEN_MARGIN * 2)
                )

                task.defer(UI._ClampToParent, Frame)
            end

            function Window:Open()
                Window.IsOpen = true
                FitToScreen()
                Frame.Visible = true
            end

            function Window:Close()
                Window.IsOpen = false
                Frame.Visible = false

                if Options.OnClose then
                    Options.OnClose()
                end
            end

            UI:_Connect(Close.Activated, function()
                Window:Close()
            end)

            return Window
        end

        return Floating
    end,
}
