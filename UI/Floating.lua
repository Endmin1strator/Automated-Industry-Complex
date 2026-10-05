-- Floating builds windows that sit outside the main UI (Recipe Browser,
-- Server Browser): a draggable frame with a title bar and a close button,
-- plus the small instance helpers they share, in the look of UI/Utils.
-- Colours come from the window library's theme at the time of each call.
return {
    Name = "Floating",
    Dependencies = {"Runtime"},

    Start = function(Context)
        local UI = Context.UI
        local UserInputService = Context.Services.UserInputService

        --// Kept free on every side of the screen.
        local SCREEN_MARGIN = 12
        --// Above the main window and the pinned items panel; popups above that.
        local WINDOW_Z = 60
        local POPUP_Z = 70
        local HEADER_HEIGHT = 32
        --// Smallest a window can be resized to, unless it asks otherwise.
        local DEFAULT_MIN_WIDTH = 360
        local DEFAULT_MIN_HEIGHT = 240
        local RESIZE_GRIP_SIZE = 18

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

        --// A stand-in for a main window section, so the UI/Utils widgets
        --// (AddSlider, AddPriority...) can be used inside a floating window:
        --// they only need Holder, Components and Library. The holder grows
        --// with its content; Properties are applied to it.
        function Floating.Section(Parent, Properties)
            local Holder = New("Frame", {
                Parent = Parent,
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
            })

            Floating.List(Holder, 5)
            Apply(Holder, Properties)

            return setmetatable({
                Library = UI,
                Holder = Holder,
                Components = {},
            }, { __index = UI.SectionMethods })
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

        --// A window of its own. Options: Title, Width, Height (its starting
        --// size), MinWidth, MinHeight, OnClose, OnMinimize(Minimized).
        --// Content goes in Window.Body, the area under the title bar, and
        --// should size by scale so it follows a resize.
        --// The title bar drags it, "—" folds it to the title bar and back,
        --// and the corner grip resizes it. Size and fold are kept for the
        --// session, across closing and reopening.
        function Floating.CreateWindow(Options)
            local Theme = UI.Theme
            local MinSize = Vector2.new(Options.MinWidth or DEFAULT_MIN_WIDTH, Options.MinHeight or DEFAULT_MIN_HEIGHT)
            local Window = {
                IsOpen = false,
                Minimized = false,
                --// The unfolded size, as resized.
                Size = Vector2.new(Options.Width, Options.Height),
                Placed = false,
            }

            local Frame = New("Frame", {
                Name = Options.Title,
                Parent = UI.ScreenGui,
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
                Size = UDim2.new(1, -76, 1, 0),
                TextColor3 = Theme.Cyan,
                Font = Enum.Font.GothamBold,
            })

            local Close = Floating.Button(Header, "×", Theme.Danger, {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -8, 0.5, 0),
                Size = UDim2.fromOffset(22, 20),
            })

            local Minimize = Floating.Button(Header, "—", Theme.TextMuted, {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -34, 0.5, 0),
                Size = UDim2.fromOffset(22, 20),
            })

            Window.Frame = Frame
            Window.Body = New("Frame", {
                Parent = Frame,
                BackgroundTransparency = 1,
                Position = UDim2.fromOffset(10, HEADER_HEIGHT + 8),
                Size = UDim2.new(1, -20, 1, -(HEADER_HEIGHT + 18)),
            })

            local Grip = New("TextButton", {
                Parent = Frame,
                AnchorPoint = Vector2.new(1, 1),
                Position = UDim2.fromScale(1, 1),
                Size = UDim2.fromOffset(RESIZE_GRIP_SIZE, RESIZE_GRIP_SIZE),
                BackgroundTransparency = 1,
                Text = "◢",
                TextColor3 = Theme.TextMuted,
                TextSize = 12,
                Font = Enum.Font.GothamBold,
                AutoButtonColor = false,
                ZIndex = 2,
            })

            UI:_MakeDraggable(Header, Frame, true)

            --// Largest size that still fits on screen from where it stands.
            local function GetMaxSize()
                local Screen = UI.ScreenGui.AbsoluteSize

                return Vector2.new(
                    math.max(MinSize.X, Screen.X - Frame.AbsolutePosition.X - SCREEN_MARGIN),
                    math.max(MinSize.Y, Screen.Y - Frame.AbsolutePosition.Y - SCREEN_MARGIN)
                )
            end

            local function ApplySize()
                local Height = Window.Minimized and HEADER_HEIGHT or Window.Size.Y
                Frame.Size = UDim2.fromOffset(Window.Size.X, Height)
            end

            --// Centred the first time, and shrunk to fit a small screen.
            local function FitToScreen()
                local Screen = UI.ScreenGui.AbsoluteSize

                if Screen.X <= 0 or Screen.Y <= 0 then
                    return
                end

                local MaxWidth = Screen.X - SCREEN_MARGIN * 2
                local MaxHeight = Screen.Y - SCREEN_MARGIN * 2

                Window.Size = Vector2.new(
                    math.clamp(Window.Size.X, math.min(MinSize.X, MaxWidth), MaxWidth),
                    math.clamp(Window.Size.Y, math.min(MinSize.Y, MaxHeight), MaxHeight)
                )

                if not Window.Placed then
                    Window.Placed = true
                    Frame.Position = UDim2.fromOffset(
                        math.floor((Screen.X - Window.Size.X) * 0.5),
                        math.floor((Screen.Y - Window.Size.Y) * 0.5)
                    )
                end

                ApplySize()
                task.defer(UI._ClampToParent, Frame)
            end

            function Window:SetMinimized(Value)
                Window.Minimized = Value == true
                Window.Body.Visible = not Window.Minimized
                Grip.Visible = not Window.Minimized
                Minimize.Text = Window.Minimized and "+" or "—"
                ApplySize()

                if Options.OnMinimize then
                    Options.OnMinimize(Window.Minimized)
                end
            end

            UI:_Connect(Minimize.Activated, function()
                Window:SetMinimized(not Window.Minimized)
            end)

            --// Resized from the bottom-right grip; the top-left corner stays put.
            local Resizing, ResizeStart, StartSize = false, nil, nil

            UI:_Connect(Grip.InputBegan, function(Input)
                if Input.UserInputType == Enum.UserInputType.MouseButton1
                    or Input.UserInputType == Enum.UserInputType.Touch
                then
                    Resizing = true
                    ResizeStart = Vector2.new(Input.Position.X, Input.Position.Y)
                    StartSize = Window.Size
                end
            end)

            UI:_Connect(UserInputService.InputChanged, function(Input)
                if not Resizing
                    or (Input.UserInputType ~= Enum.UserInputType.MouseMovement
                        and Input.UserInputType ~= Enum.UserInputType.Touch)
                then
                    return
                end

                local Delta = Vector2.new(Input.Position.X, Input.Position.Y) - ResizeStart
                local MaxSize = GetMaxSize()

                Window.Size = Vector2.new(
                    math.clamp(StartSize.X + Delta.X, MinSize.X, MaxSize.X),
                    math.clamp(StartSize.Y + Delta.Y, MinSize.Y, MaxSize.Y)
                )

                ApplySize()
            end)

            UI:_Connect(UserInputService.InputEnded, function(Input)
                if Input.UserInputType == Enum.UserInputType.MouseButton1
                    or Input.UserInputType == Enum.UserInputType.Touch
                then
                    Resizing = false
                end
            end)

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
