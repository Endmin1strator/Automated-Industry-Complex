--!strict
--!optimize 2

local Players            = game:GetService("Players")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local RunService         = game:GetService("RunService")

local Player             = Players.LocalPlayer
local PlayerGui          = Player:WaitForChild("PlayerGui")

local Library = {}
Library.__index = Library

--//==============================================================
--// Theme
--//==============================================================

local Theme = {
    Background         = Color3.fromRGB(15, 18, 19),
    BackgroundLight    = Color3.fromRGB(23, 27, 28),

    Panel              = Color3.fromRGB(27, 32, 33),
    PanelLight         = Color3.fromRGB(34, 39, 40),
    PanelHover         = Color3.fromRGB(40, 46, 47),

    Element            = Color3.fromRGB(30, 35, 36),
    ElementHover       = Color3.fromRGB(39, 45, 46),

    Text               = Color3.fromRGB(232, 237, 235),
    TextSecondary      = Color3.fromRGB(171, 181, 179),
    TextMuted          = Color3.fromRGB(108, 119, 117),

    Cyan               = Color3.fromRGB(220, 205, 0),
    CyanDark           = Color3.fromRGB(150, 150, 150),
    CyanDim            = Color3.fromRGB(255, 255, 255),

    White              = Color3.fromRGB(242, 244, 242),

    Border             = Color3.fromRGB(79, 91, 91),
    BorderDim          = Color3.fromRGB(51, 61, 61),

    Danger             = Color3.fromRGB(218, 79, 79),
    Warning            = Color3.fromRGB(222, 181, 75),

    Black              = Color3.fromRGB(7, 9, 10),
}

--//==============================================================
--// Constants
--//==============================================================

local WINDOW_SIZE = Vector2.new(760, 480)
local TEXT_SCALE   = 1.4

local TWEEN_FAST   = TweenInfo.new(0.12, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local TWEEN_NORMAL = TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local TWEEN_SMOOTH = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

--//==============================================================
--// Utility
--//==============================================================

local function New(className: string, properties: {[string]: any}?): Instance
    local object = Instance.new(className)

    if properties then
        for property, value in pairs(properties) do
            object[property] = value
        end
    end

    return object
end

local function Tween(object: Instance, info: TweenInfo, properties: {[string]: any})
    local tween = TweenService:Create(object, info, properties)
    tween:Play()

    return tween
end

local function AddCorner(parent: Instance, radius: number?)
    local corner = New("UICorner", {
        CornerRadius = UDim.new(0, radius or 3),
    })

    corner.Parent = parent

    return corner
end

local function AddStroke(parent: Instance, color: Color3?, transparency: number?, thickness: number?)
    local stroke = New("UIStroke", {
        Color = color or Theme.Border,
        Transparency = transparency or 0,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })

    stroke.Parent = parent

    return stroke
end

local function AddPadding(parent: Instance, left: number?, right: number?, top: number?, bottom: number?)
    local padding = New("UIPadding", {
        PaddingLeft = UDim.new(0, left or 0),
        PaddingRight = UDim.new(0, right or 0),
        PaddingTop = UDim.new(0, top or 0),
        PaddingBottom = UDim.new(0, bottom or 0),
    })

    padding.Parent = parent

    return padding
end

local function AddGradient(parent: Instance, rotation: number?, transparency: NumberSequence?)
    local gradient = New("UIGradient", {
        Rotation = rotation or 0,
        Transparency = transparency,
    })

    gradient.Parent = parent

    return gradient
end

local function AddLine(parent: Instance, position: UDim2, size: UDim2, color: Color3?, transparency: number?)
    return New("Frame", {
        Parent = parent,
        BackgroundColor3 = color or Theme.Border,
        BackgroundTransparency = transparency or 0,
        BorderSizePixel = 0,
        Position = position,
        Size = size,
    })
end

local function AddText(
    parent: Instance,
    text: string,
    size: number,
    position: UDim2,
    dimensions: UDim2
)
    local label = New("TextLabel", {
        Parent = parent,

        BackgroundTransparency = 1,

        Position = position,
        Size = dimensions,

        Text = text,
        TextColor3 = Theme.Text,
        TextSize = math.round(size * TEXT_SCALE),

        Font = Enum.Font.GothamMedium,

        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,

        ClipsDescendants = true,
    })

    return label
end

--//==============================================================
--// Angular Decoration
--//==============================================================

local function AddAngularCorners(parent: Instance, color: Color3?)
    local holder = New("Frame", {
        Parent = parent,

        BackgroundTransparency = 1,

        Size = UDim2.fromScale(1, 1),

        ZIndex = parent.ZIndex + 2,

        ClipsDescendants = true,
    })

    local accent = color or Theme.Cyan

    -- Top left
    AddLine(
        holder,
        UDim2.fromOffset(0, 0),
        UDim2.fromOffset(28, 1),
        accent
    )

    AddLine(
        holder,
        UDim2.fromOffset(0, 0),
        UDim2.fromOffset(1, 18),
        accent
    )

    AddLine(
        holder,
        UDim2.fromOffset(0, 17),
        UDim2.fromOffset(8, 1),
        accent
    )

    -- Top right
    AddLine(
        holder,
        UDim2.new(1, -28, 0, 0),
        UDim2.fromOffset(28, 1),
        accent
    )

    AddLine(
        holder,
        UDim2.new(1, -1, 0, 0),
        UDim2.fromOffset(1, 18),
        accent
    )

    -- Bottom left
    AddLine(
        holder,
        UDim2.new(0, 0, 1, -1),
        UDim2.fromOffset(28, 1),
        accent
    )

    AddLine(
        holder,
        UDim2.new(0, 0, 1, -18),
        UDim2.fromOffset(1, 18),
        accent
    )

    -- Bottom right
    AddLine(
        holder,
        UDim2.new(1, -28, 1, -1),
        UDim2.fromOffset(28, 1),
        accent
    )

    AddLine(
        holder,
        UDim2.new(1, -1, 1, -18),
        UDim2.fromOffset(1, 18),
        accent
    )

    return holder
end

--//==============================================================
--// Connection Manager
--//==============================================================

function Library:_Connect(signal, callback)
    local connection = signal:Connect(callback)

    table.insert(self._connections, connection)

    return connection
end

--//==============================================================
--// Window
--//==============================================================

function Library.new(title: string?)
    local self = setmetatable({}, Library)

    self.Title             = title or "SYSTEM"
    self.Theme             = table.clone(Theme)

    self.Tabs              = {}
    self.Sections          = {}
    self.Components        = {}
    self._connections      = {}

    self.CurrentTab        = nil
    self.Visible           = true
    self.Destroyed         = false

    self._dropdowns        = {}
    self._notifications    = {}

    --==========================================================
    -- ScreenGui
    --==========================================================

    local screenGui = New("ScreenGui", {
        Name = "ENDFIELD_INDUSTRIES_UI",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 9999,
        Parent = PlayerGui,
    })

    self.ScreenGui = screenGui

    --==========================================================
    -- Scale
    --==========================================================

    local scale = New("UIScale", {
        Scale = 1,
        Parent = screenGui,
    })

    self.UIScale = scale

    -- Separate animation scale so open/close never modifies responsive scale.
    local windowScale = New("UIScale", {
        Scale = 1,
        Parent = nil,
    })

    self.WindowUIScale = windowScale

    --==========================================================
    -- Window
    --==========================================================

    local window = New("Frame", {
        Name = "Window",

        Parent = screenGui,

        AnchorPoint = Vector2.new(0.5, 0.5),

        Position = UDim2.fromScale(0.5, 0.5),

        Size = UDim2.fromOffset(
            WINDOW_SIZE.X,
            WINDOW_SIZE.Y
        ),

        BackgroundColor3 = self.Theme.Background,

        BorderSizePixel = 0,

        ClipsDescendants = true,

        ZIndex = 10,
    })

    windowScale.Parent = window
    self.Window = window

    AddStroke(window, self.Theme.Border, 0.15, 1)
    AddAngularCorners(window)

    --==========================================================
    -- Window Header
    --==========================================================

    local header = New("Frame", {
        Name = "Header",

        Parent = window,

        BackgroundColor3 = self.Theme.BackgroundLight,

        BackgroundTransparency = 0.05,

        BorderSizePixel = 0,

        Position = UDim2.fromOffset(0, 0),

        Size = UDim2.new(1, 0, 0, 58),

        ZIndex = 12,
    })

    self.Header = header

    -- Header bottom line
    AddLine(
        header,
        UDim2.new(0, 0, 1, -1),
        UDim2.new(1, 0, 0, 1),
        self.Theme.BorderDim
    )

    -- Logo mark
    local logo = New("TextLabel", {
        Parent = header,

        BackgroundTransparency = 1,

        Position = UDim2.fromOffset(18, 7),

        Size = UDim2.fromOffset(42, 42),

        Text = "◇",

        TextColor3 = self.Theme.Cyan,

        TextSize = 32,

        Font = Enum.Font.GothamBold,

        ZIndex = 14,
    })

    self.Logo = logo

    -- Title
    local titleLabel = AddText(
        header,
        self.Title:upper(),
        18,
        UDim2.fromOffset(66, 8),
        UDim2.fromOffset(330, 25)
    )

    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.ZIndex = 14

    self.TitleLabel = titleLabel

    -- Subtitle
    local subtitle = AddText(
        header,
        "CREATED BY ENDMIN1STRATOR // UTILITY SYSTEM  //  ONLINE",
        9,
        UDim2.fromOffset(67, 31),
        UDim2.fromOffset(330, 17)
    )

    subtitle.TextColor3 = self.Theme.TextMuted
    subtitle.Font = Enum.Font.GothamMedium
    subtitle.ZIndex = 14

    self.Subtitle = subtitle

    -- System status
    local status = AddText(
        header,
        "SYSTEM  //  01",
        9,
        UDim2.new(1, -260, 0, 10),
        UDim2.fromOffset(130, 18)
    )

    status.TextColor3 = self.Theme.TextMuted
    status.TextXAlignment = Enum.TextXAlignment.Right
    status.ZIndex = 14

    self.StatusLabel = status

    -- Cyan status dot
    local statusDot = New("Frame", {
        Parent = header,

        BackgroundColor3 = self.Theme.Cyan,

        BorderSizePixel = 0,

        Position = UDim2.new(1, -108, 0, 15),

        Size = UDim2.fromOffset(5, 5),

        ZIndex = 14,
    })

    self.StatusDot = statusDot

    -- Close
    local close = New("TextButton", {
        Name = "Close",

        Parent = header,

        BackgroundColor3 = self.Theme.Danger,

        BackgroundTransparency = 0.08,

        BorderSizePixel = 0,

        Position = UDim2.new(1, -45, 0, 10),

        Size = UDim2.fromOffset(34, 34),

        Text = "×",

        TextColor3 = self.Theme.White,

        TextSize = 25,

        Font = Enum.Font.GothamMedium,

        AutoButtonColor = false,

        ZIndex = 15,
    })

    self.CloseButton = close

    AddCorner(close, 2)

    self:_Connect(close.MouseEnter, function()
        Tween(close, TWEEN_FAST, {
            BackgroundColor3 = Color3.fromRGB(235, 91, 91),
        })
    end)

    self:_Connect(close.MouseLeave, function()
        Tween(close, TWEEN_FAST, {
            BackgroundColor3 = self.Theme.Danger,
        })
    end)

    self:_Connect(close.MouseButton1Click, function()
        self:SetVisible(false)
    end)

    --==========================================================
    -- Sidebar
    --==========================================================

    local sidebar = New("Frame", {
        Name = "Sidebar",

        Parent = window,

        BackgroundColor3 = self.Theme.Panel,

        BackgroundTransparency = 0.05,

        BorderSizePixel = 0,

        Position = UDim2.fromOffset(0, 58),

        Size = UDim2.new(0, 188, 1, -58),

        ZIndex = 11,
    })

    self.Sidebar = sidebar

    AddLine(
        sidebar,
        UDim2.new(1, -1, 0, 0),
        UDim2.fromOffset(1, 532),
        self.Theme.BorderDim
    )

    -- Sidebar header
    local navTitle = AddText(
        sidebar,
        "NAVIGATION",
        9,
        UDim2.fromOffset(20, 17),
        UDim2.new(1, -40, 0, 18)
    )

    navTitle.TextColor3 = self.Theme.TextMuted
    navTitle.Font = Enum.Font.GothamBold

    -- Tab container
    local tabContainer = New("Frame", {
        Name = "Tabs",

        Parent = sidebar,

        BackgroundTransparency = 1,

        Position = UDim2.fromOffset(10, 48),

        Size = UDim2.new(1, -20, 1, -120),

        ZIndex = 12,
    })

    self.TabContainer = tabContainer

    local tabLayout = New("UIListLayout", {
        Parent = tabContainer,

        FillDirection = Enum.FillDirection.Vertical,

        HorizontalAlignment = Enum.HorizontalAlignment.Center,

        SortOrder = Enum.SortOrder.LayoutOrder,

        Padding = UDim.new(0, 5),
    })

    -- Sidebar footer
    local footer = AddText(
        sidebar,
        "ENDMIN1STRATOR  //  UTILITY",
        8,
        UDim2.fromOffset(20, -44),
        UDim2.new(1, -40, 0, 18)
    )

    footer.AnchorPoint = Vector2.new(0, 1)
    footer.TextColor3 = self.Theme.TextMuted

    local version = AddText(
        sidebar,
        "SYSTEM BUILD  //  01",
        8,
        UDim2.fromOffset(20, -25),
        UDim2.new(1, -40, 0, 18)
    )

    version.AnchorPoint = Vector2.new(0, 1)
    version.TextColor3 = self.Theme.CyanDark

    --==========================================================
    -- Content
    --==========================================================

    local content = New("Frame", {
        Name = "Content",

        Parent = window,

        BackgroundTransparency = 1,

        Position = UDim2.fromOffset(188, 58),

        Size = UDim2.new(1, -188, 1, -58),

        ZIndex = 11,

        ClipsDescendants = true,
    })

    self.Content = content

    --==========================================================
    -- Overlay
    --==========================================================

    local overlay = New("Frame", {
        Name = "Overlay",

        Parent = screenGui,

        BackgroundTransparency = 1,

        Size = UDim2.fromScale(1, 1),

        ZIndex = 100,

        Active = false,
    })

    self.Overlay = overlay

    --==========================================================
    -- Reopen Button
    --==========================================================

    local reopen = New("TextButton", {
        Name = "Reopen",

        Parent = screenGui,

        AnchorPoint = Vector2.new(1, 1),

        Position = UDim2.new(1, -24, 1, -24),

        Size = UDim2.fromOffset(54, 54),

        BackgroundColor3 = self.Theme.Panel,

        BackgroundTransparency = 0.05,

        BorderSizePixel = 0,

        Text = "◇",

        TextColor3 = self.Theme.Cyan,

        TextSize = 26,

        Font = Enum.Font.GothamBold,

        AutoButtonColor = false,

        Visible = false,

        ZIndex = 200,
    })

    self.ReopenButton = reopen

    AddStroke(reopen, self.Theme.CyanDark, 0.1, 1)
    AddCorner(reopen, 2)

    self:_Connect(reopen.MouseEnter, function()
        Tween(reopen, TWEEN_FAST, {
            BackgroundColor3 = self.Theme.CyanDim,
        })
    end)

    self:_Connect(reopen.MouseLeave, function()
        Tween(reopen, TWEEN_FAST, {
            BackgroundColor3 = self.Theme.Panel,
        })
    end)

    self:_Connect(reopen.MouseButton1Click, function()
        self:SetVisible(true)
    end)

    --==========================================================
    -- Responsive
    --==========================================================

    self:_Connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), function()
        self:_UpdateScale()
    end)

    self:_UpdateScale()

    --==========================================================
    -- Drag
    --==========================================================

    self:_MakeDraggable(header, window)

    return self
end

--//==============================================================
--// Responsive Scale
--//==============================================================

function Library:_UpdateScale()
    if self.Destroyed then
        return
    end

    local camera = workspace.CurrentCamera

    if not camera then
        return
    end

    local viewport = camera.ViewportSize

    local scaleX = (viewport.X - 40) / WINDOW_SIZE.X
    local scaleY = (viewport.Y - 40) / WINDOW_SIZE.Y

    local scale = math.min(scaleX, scaleY)

    -- Mobile/portrait screens need a smaller window scale.
    -- Text has its own global multiplier above, so the UI can shrink
    -- without making the text disproportionately small.
    local minimumScale = viewport.X <= 700 and 0.42 or 0.55
    scale = math.clamp(scale, minimumScale, 1)

    self.UIScale.Scale = scale
end

--//==============================================================
--// Draggable
--//==============================================================

--// Pulls a GuiObject back inside its parent if any edge is past the parent's
--// bounds. Worked out from Position, AnchorPoint and AbsoluteSize rather than
--// AbsolutePosition, which can lag a frame behind a Position change.
local function ClampToParent(target: GuiObject)
    local parent = target.Parent

    if not parent or not parent:IsA("GuiBase2d") then
        return
    end

    local bounds = parent.AbsoluteSize
    local size = target.AbsoluteSize

    if bounds.X <= 0 or bounds.Y <= 0 then
        return
    end

    local position = target.Position
    local anchor = target.AnchorPoint
    local left = bounds.X * position.X.Scale + position.X.Offset - anchor.X * size.X
    local top = bounds.Y * position.Y.Scale + position.Y.Offset - anchor.Y * size.Y

    local clampedLeft = math.clamp(left, 0, math.max(0, bounds.X - size.X))
    local clampedTop = math.clamp(top, 0, math.max(0, bounds.Y - size.Y))

    if clampedLeft ~= left or clampedTop ~= top then
        target.Position = UDim2.new(
            position.X.Scale,
            position.X.Offset + (clampedLeft - left),
            position.Y.Scale,
            position.Y.Offset + (clampedTop - top)
        )
    end
end

Library._ClampToParent = ClampToParent

function Library:_MakeDraggable(handle: GuiObject, target: GuiObject, keepOnScreen: boolean?)
    local dragging = false
    local dragStart: Vector2
    local startPosition: UDim2

    self:_Connect(handle.InputBegan, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end

        dragging = true

        dragStart = input.Position
        startPosition = target.Position

        local changedConnection

        changedConnection = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false

                if changedConnection then
                    changedConnection:Disconnect()
                end
            end
        end)
    end)

    self:_Connect(UserInputService.InputChanged, function(input)
        if not dragging then
            return
        end

        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end

        local delta = input.Position - dragStart

        target.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )

        if keepOnScreen then
            ClampToParent(target)
        end
    end)
end

--//==============================================================
--// Set Visible
--//==============================================================

function Library:SetVisible(value: boolean)
    if self.Destroyed then
        return
    end

    if self.Visible == value then
        return
    end

    self.Visible = value

    local windowScale = self.WindowUIScale

    if value then
        self.ReopenButton.Visible = false
        self.Window.Visible = true

        -- Always start from the same animation scale.
        windowScale.Scale = 0.94

        Tween(windowScale, TWEEN_SMOOTH, {
            Scale = 1,
        })

        self:_FadeWindow(0)
    else
        self:_CloseDropdowns()

        Tween(windowScale, TWEEN_NORMAL, {
            Scale = 0.96,
        })

        task.delay(0.18, function()
            if self.Destroyed or self.Visible then
                return
            end

            self.Window.Visible = false
            self.ReopenButton.Visible = true
            windowScale.Scale = 1
        end)
    end
end

function Library:_FadeWindow(transparency: number)
    local objects = self.Window:GetDescendants()

    for _, object in ipairs(objects) do
        if object:IsA("TextLabel")
            or object:IsA("TextButton")
            or object:IsA("TextBox") then

            local targetTransparency = object.TextTransparency

            object.TextTransparency = 1

            Tween(object, TWEEN_SMOOTH, {
                TextTransparency = targetTransparency,
            })
        elseif object:IsA("ImageLabel")
            or object:IsA("ImageButton") then

            local targetTransparency = object.ImageTransparency

            object.ImageTransparency = 1

            Tween(object, TWEEN_SMOOTH, {
                ImageTransparency = targetTransparency,
            })
        end
    end
end

function Library:Toggle()
    self:SetVisible(not self.Visible)
end

--//==============================================================
--// Tab
--//==============================================================

local TabMethods = {}
TabMethods.__index = TabMethods

function Library:AddTab(name: string)
    local tab = setmetatable({}, TabMethods)

    tab.Library      = self
    tab.Name         = name
    tab.Sections     = {}
    tab._layoutOrder = #self.Tabs + 1

    --==========================================================
    -- Tab Button
    --==========================================================

    local button = New("TextButton", {
        Parent = self.TabContainer,

        BackgroundColor3 = self.Theme.Panel,

        BackgroundTransparency = 1,

        BorderSizePixel = 0,

        Size = UDim2.new(1, 0, 0, 46),

        Text = "",

        AutoButtonColor = false,

        LayoutOrder = tab._layoutOrder,

        ZIndex = 13,
    })

    tab.Button = button

    -- Active bar
    local activeBar = New("Frame", {
        Parent = button,

        BackgroundColor3 = self.Theme.Cyan,

        BorderSizePixel = 0,

        Position = UDim2.fromOffset(0, 0),

        Size = UDim2.fromOffset(3, 46),

        BackgroundTransparency = 1,

        ZIndex = 14,
    })

    tab.ActiveBar = activeBar

    -- Diamond
    local diamond = AddText(
        button,
        "◇",
        14,
        UDim2.fromOffset(14, 0),
        UDim2.fromOffset(25, 46)
    )

    diamond.TextColor3 = self.Theme.TextMuted
    diamond.ZIndex = 14

    tab.Diamond = diamond

    -- Name
    local label = AddText(
        button,
        name:upper(),
        11,
        UDim2.fromOffset(43, 0),
        UDim2.new(1, -70, 1, 0)
    )

    label.Font = Enum.Font.GothamBold
    label.TextColor3 = self.Theme.TextSecondary
    label.ZIndex = 14

    tab.Label = label

    -- Number
    local number = AddText(
        button,
        string.format("%02d", tab._layoutOrder),
        8,
        UDim2.new(1, -32, 0, 0),
        UDim2.fromOffset(24, 46)
    )

    number.TextColor3 = self.Theme.TextMuted
    number.TextXAlignment = Enum.TextXAlignment.Right
    number.ZIndex = 14

    tab.Number = number

    self:_Connect(button.MouseEnter, function()
        if self.CurrentTab ~= tab then
            Tween(button, TWEEN_FAST, {
                BackgroundColor3 = self.Theme.PanelHover,
                BackgroundTransparency = 0.65,
            })

            Tween(label, TWEEN_FAST, {
                TextColor3 = self.Theme.Text,
            })
        end
    end)

    self:_Connect(button.MouseLeave, function()
        if self.CurrentTab ~= tab then
            Tween(button, TWEEN_FAST, {
                BackgroundTransparency = 1,
            })

            Tween(label, TWEEN_FAST, {
                TextColor3 = self.Theme.TextSecondary,
            })
        end
    end)

    self:_Connect(button.MouseButton1Click, function()
        self:SelectTab(tab)
    end)

    -- Content page
    local page = New("ScrollingFrame", {
        Name = name,

        Parent = self.Content,

        BackgroundTransparency = 1,

        BorderSizePixel = 0,

        Position = UDim2.fromOffset(0, 0),

        Size = UDim2.fromScale(1, 1),

        ScrollBarThickness = 2,

        ScrollBarImageColor3 = self.Theme.CyanDark,

        CanvasSize = UDim2.fromOffset(0, 0),

        AutomaticCanvasSize = Enum.AutomaticSize.Y,

        Visible = false,

        ZIndex = 12,

        ClipsDescendants = true,
    })

    tab.Page = page

    AddPadding(page, 22, 22, 20, 30)

    local layout = New("UIListLayout", {
        Parent = page,

        FillDirection = Enum.FillDirection.Vertical,

        SortOrder = Enum.SortOrder.LayoutOrder,

        Padding = UDim.new(0, 14),
    })

    tab.Layout = layout

    table.insert(self.Tabs, tab)

    if not self.CurrentTab then
        self:SelectTab(tab)
    end

    return tab
end

function Library:SelectTab(tab)
    if self.Destroyed then
        return
    end

    if self.CurrentTab == tab then
        return
    end

    self:_CloseDropdowns()

    for _, current in ipairs(self.Tabs) do
        local selected = current == tab

        current.Page.Visible = selected

        if selected then
            current.Button.BackgroundColor3 = self.Theme.CyanDim
            current.Button.BackgroundTransparency = 0.65

            current.ActiveBar.BackgroundTransparency = 0

            current.Diamond.TextColor3 = self.Theme.Cyan
            current.Label.TextColor3 = self.Theme.White
            current.Number.TextColor3 = self.Theme.Cyan
        else
            current.Button.BackgroundTransparency = 1

            current.ActiveBar.BackgroundTransparency = 1

            current.Diamond.TextColor3 = self.Theme.TextMuted
            current.Label.TextColor3 = self.Theme.TextSecondary
            current.Number.TextColor3 = self.Theme.TextMuted
        end
    end

    self.CurrentTab = tab
end

--//==============================================================
--// Section
--//==============================================================

function TabMethods:AddSection(name: string)
    local section = {}

    section.Library = self.Library
    section.Tab = self
    section.Name = name
    section.Components = {}

    local frame = New("Frame", {
        Name = name,

        Parent = self.Page,

        BackgroundColor3 = self.Library.Theme.Panel,

        BackgroundTransparency = 0.12,

        BorderSizePixel = 0,

        Size = UDim2.new(1, 0, 0, 0),

        AutomaticSize = Enum.AutomaticSize.Y,

        LayoutOrder = #self.Sections + 1,

        ZIndex = 13,
    })

    section.Frame = frame

    AddStroke(
        frame,
        self.Library.Theme.BorderDim,
        0.1,
        1
    )

    AddAngularCorners(frame)

    --==========================================================
    -- Header
    --==========================================================

    local header = New("Frame", {
        Parent = frame,

        BackgroundTransparency = 1,

        Size = UDim2.new(1, 0, 0, 54),

        ZIndex = 14,
    })

    section.Header = header

    local icon = AddText(
        header,
        "◇",
        18,
        UDim2.fromOffset(16, 0),
        UDim2.fromOffset(30, 54)
    )

    icon.TextColor3 = self.Library.Theme.Cyan
    icon.Font = Enum.Font.GothamBold

    local title = AddText(
        header,
        name:upper(),
        12,
        UDim2.fromOffset(48, 7),
        UDim2.new(1, -70, 0, 22)
    )

    title.Font = Enum.Font.GothamBold

    local description = AddText(
        header,
        "CONFIGURATION / PARAMETERS",
        8,
        UDim2.fromOffset(49, 29),
        UDim2.new(1, -70, 0, 16)
    )

    description.TextColor3 = self.Library.Theme.TextMuted

    AddLine(
        header,
        UDim2.fromOffset(16, 53),
        UDim2.new(1, -32, 0, 1),
        self.Library.Theme.BorderDim
    )

    --==========================================================
    -- Components Holder
    --==========================================================

    local holder = New("Frame", {
        Parent = frame,

        BackgroundTransparency = 1,

        Position = UDim2.fromOffset(14, 60),

        Size = UDim2.new(1, -28, 0, 0),

        AutomaticSize = Enum.AutomaticSize.Y,

        ZIndex = 14,
    })

    section.Holder = holder

    local layout = New("UIListLayout", {
        Parent = holder,

        FillDirection = Enum.FillDirection.Vertical,

        SortOrder = Enum.SortOrder.LayoutOrder,

        Padding = UDim.new(0, 5),
    })

    table.insert(self.Sections, section)

    return setmetatable(section, {
        __index = Library.SectionMethods,
    })
end

Library.SectionMethods = {}

--//==============================================================
--// Label
--//==============================================================

function Library.SectionMethods:AddLabel(text: string)
    local label = AddText(
        self.Holder,
        text,
        10,
        UDim2.fromOffset(8, 0),
        UDim2.new(1, -16, 0, 28)
    )

    label.TextColor3 = self.Library.Theme.TextSecondary
    label.LayoutOrder = #self.Components + 1

    table.insert(self.Components, label)

    return label
end

--//==============================================================
--// Button
--//==============================================================

function Library.SectionMethods:AddButton(name: string, callback)
    local button = New("TextButton", {
        Parent = self.Holder,

        BackgroundColor3 = self.Library.Theme.Element,

        BackgroundTransparency = 0.1,

        BorderSizePixel = 0,

        Size = UDim2.new(1, 0, 0, 42),

        Text = "",

        AutoButtonColor = false,

        LayoutOrder = #self.Components + 1,

        ZIndex = 15,
    })

    AddStroke(
        button,
        self.Library.Theme.BorderDim,
        0.25,
        1
    )

    local diamond = AddText(
        button,
        "◇",
        13,
        UDim2.fromOffset(13, 0),
        UDim2.fromOffset(22, 42)
    )

    diamond.TextColor3 = self.Library.Theme.Cyan

    local label = AddText(
        button,
        name:upper(),
        10,
        UDim2.fromOffset(42, 0),
        UDim2.new(1, -60, 1, 0)
    )

    label.Font = Enum.Font.GothamBold

    local arrow = AddText(
        button,
        "›",
        18,
        UDim2.new(1, -34, 0, 0),
        UDim2.fromOffset(24, 42)
    )

    arrow.TextColor3 = self.Library.Theme.TextMuted
    arrow.TextXAlignment = Enum.TextXAlignment.Right

    self.Library:_Connect(button.MouseEnter, function()
        Tween(button, TWEEN_FAST, {
            BackgroundColor3 = self.Library.Theme.ElementHover,
        })

        Tween(diamond, TWEEN_FAST, {
            TextColor3 = self.Library.Theme.White,
        })

        Tween(arrow, TWEEN_FAST, {
            TextColor3 = self.Library.Theme.Cyan,
        })
    end)

    self.Library:_Connect(button.MouseLeave, function()
        Tween(button, TWEEN_FAST, {
            BackgroundColor3 = self.Library.Theme.Element,
        })

        Tween(diamond, TWEEN_FAST, {
            TextColor3 = self.Library.Theme.Cyan,
        })

        Tween(arrow, TWEEN_FAST, {
            TextColor3 = self.Library.Theme.TextMuted,
        })
    end)

    self.Library:_Connect(button.MouseButton1Click, function()
        if callback then
            callback()
        end
    end)

    table.insert(self.Components, button)

    return button
end

--//==============================================================
--// Toggle
--//==============================================================

function Library.SectionMethods:AddToggle(name: string, default: boolean?, callback)
    local component = {}
    component.Library = self.Library

    component.Value = default == true
    component.Callback = callback

    local button = New("TextButton", {
        Parent = self.Holder,

        BackgroundColor3 = self.Library.Theme.Element,

        BackgroundTransparency = 0.1,

        BorderSizePixel = 0,

        Size = UDim2.new(1, 0, 0, 42),

        Text = "",

        AutoButtonColor = false,

        LayoutOrder = #self.Components + 1,

        ZIndex = 15,
    })

    component.Frame = button

    local label = AddText(
        button,
        name:upper(),
        10,
        UDim2.fromOffset(13, 0),
        UDim2.new(1, -130, 1, 0)
    )

    label.Font = Enum.Font.GothamBold

    -- Toggle background
    local toggle = New("Frame", {
        Parent = button,

        BackgroundColor3 = self.Library.Theme.PanelLight,

        BorderSizePixel = 0,

        Position = UDim2.new(1, -68, 0, 11),

        Size = UDim2.fromOffset(42, 20),

        ZIndex = 16,
    })

    AddStroke(toggle, self.Library.Theme.Border, 0.15, 1)
    AddCorner(toggle, 30)

    local knob = New("Frame", {
        Parent = toggle,

        BackgroundColor3 = self.Library.Theme.TextMuted,

        BorderSizePixel = 0,

        Position = UDim2.fromOffset(3, 3),

        Size = UDim2.fromOffset(14, 14),

        ZIndex = 17,
    })

    AddCorner(knob, 30)

    local state = AddText(
        button,
        component.Value and "ON" or "OFF",
        8,
        UDim2.new(1, -116, 0, 0),
        UDim2.fromOffset(40, 42)
    )

    state.TextXAlignment = Enum.TextXAlignment.Right
    state.Font = Enum.Font.GothamBold

    function component:Set(value: boolean, fireCallback: boolean?)
        self.Value = value

        state.Text = value and "ON" or "OFF"

        if value then
            Tween(toggle, TWEEN_NORMAL, {
                BackgroundColor3 = self.Library.Theme.CyanDark,
            })

            Tween(knob, TWEEN_NORMAL, {
                Position = UDim2.new(1, -17, 0, 3),
                BackgroundColor3 = self.Library.Theme.Cyan,
            })

            Tween(state, TWEEN_NORMAL, {
                TextColor3 = self.Library.Theme.Cyan,
            })
        else
            Tween(toggle, TWEEN_NORMAL, {
                BackgroundColor3 = self.Library.Theme.PanelLight,
            })

            Tween(knob, TWEEN_NORMAL, {
                Position = UDim2.fromOffset(3, 3),
                BackgroundColor3 = self.Library.Theme.TextMuted,
            })

            Tween(state, TWEEN_NORMAL, {
                TextColor3 = self.Library.Theme.TextMuted,
            })
        end

        if fireCallback ~= false and self.Callback then
            self.Callback(value)
        end
    end

    function component:Get()
        return self.Value
    end

    self.Library:_Connect(button.MouseButton1Click, function()
        component:Set(not component.Value)
    end)

    self.Library:_Connect(button.MouseEnter, function()
        Tween(button, TWEEN_FAST, {
            BackgroundColor3 = self.Library.Theme.ElementHover,
        })
    end)

    self.Library:_Connect(button.MouseLeave, function()
        Tween(button, TWEEN_FAST, {
            BackgroundColor3 = self.Library.Theme.Element,
        })
    end)

    table.insert(self.Components, component)

    component:Set(component.Value, false)

    return component
end

--//==============================================================
--// Slider
--//==============================================================

function Library.SectionMethods:AddSlider(
    name: string,
    default: number,
    minimum: number,
    maximum: number,
    callback
)
    local component = {}
    component.Library = self.Library

    component.Value = math.clamp(default, minimum, maximum)
    component.Minimum = minimum
    component.Maximum = maximum
    component.Callback = callback

    local frame = New("Frame", {
        Parent = self.Holder,

        BackgroundColor3 = self.Library.Theme.Element,

        BackgroundTransparency = 0.1,

        BorderSizePixel = 0,

        Size = UDim2.new(1, 0, 0, 58),

        LayoutOrder = #self.Components + 1,

        ZIndex = 15,
    })

    component.Frame = frame

    local label = AddText(
        frame,
        name:upper(),
        9,
        UDim2.fromOffset(13, 5),
        UDim2.fromOffset(180, 20)
    )

    label.Font = Enum.Font.GothamBold

    local valueLabel = AddText(
        frame,
        tostring(component.Value),
        9,
        UDim2.new(1, -75, 5, 0),
        UDim2.fromOffset(60, 20)
    )

    valueLabel.AnchorPoint = Vector2.new(0, 0)
    valueLabel.Position = UDim2.new(1, -75, 0, 5)
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right
    valueLabel.TextColor3 = self.Library.Theme.Cyan
    valueLabel.Font = Enum.Font.GothamBold

    -- Track
    local track = New("Frame", {
        Parent = frame,

        BackgroundColor3 = self.Library.Theme.PanelLight,

        BorderSizePixel = 0,

        Position = UDim2.fromOffset(14, 34),

        Size = UDim2.new(1, -28, 0, 5),

        ZIndex = 16,
    })

    AddCorner(track, 2)

    local fill = New("Frame", {
        Parent = track,

        BackgroundColor3 = self.Library.Theme.Cyan,

        BorderSizePixel = 0,

        Size = UDim2.fromScale(0, 1),

        ZIndex = 17,
    })

    AddCorner(fill, 2)

    local knob = New("Frame", {
        Parent = track,

        BackgroundColor3 = self.Library.Theme.White,

        BorderSizePixel = 0,

        AnchorPoint = Vector2.new(0.5, 0.5),

        Position = UDim2.fromScale(0, 0.5),

        Size = UDim2.fromOffset(10, 10),

        ZIndex = 18,
    })

    AddCorner(knob, 2)

    local dragging = false

    local function UpdateFromX(x: number)
        local relative = math.clamp(
            (x - track.AbsolutePosition.X) / track.AbsoluteSize.X,
            0,
            1
        )

        local value = minimum + (maximum - minimum) * relative

        if math.floor(minimum) == minimum
            and math.floor(maximum) == maximum then
            value = math.round(value)
        else
            value = math.round(value * 100) / 100
        end

        component:Set(value)
    end

    function component:Set(value: number, fireCallback: boolean?)
        self.Value = math.clamp(value, self.Minimum, self.Maximum)

        local percent =
            (self.Value - self.Minimum)
            / (self.Maximum - self.Minimum)

        valueLabel.Text = tostring(self.Value)

        Tween(fill, TWEEN_FAST, {
            Size = UDim2.fromScale(percent, 1),
        })

        Tween(knob, TWEEN_FAST, {
            Position = UDim2.fromScale(percent, 0.5),
        })

        if fireCallback ~= false and self.Callback then
            self.Callback(self.Value)
        end
    end

    function component:Get()
        return self.Value
    end

    self.Library:_Connect(track.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then

            dragging = true
            UpdateFromX(input.Position.X)
        end
    end)

    self.Library:_Connect(UserInputService.InputChanged, function(input)
        if not dragging then
            return
        end

        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then

            UpdateFromX(input.Position.X)
        end
    end)

    self.Library:_Connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then

            dragging = false
        end
    end)

    table.insert(self.Components, component)

    component:Set(component.Value, false)

    return component
end

--//==============================================================
--// Textbox
--//==============================================================

function Library.SectionMethods:AddTextbox(name: string, default: string?, callback)
    local component = {}
    component.Library = self.Library

    component.Value = default or ""
    component.Callback = callback

    local frame = New("Frame", {
        Parent = self.Holder,

        BackgroundColor3 = self.Library.Theme.Element,

        BackgroundTransparency = 0.1,

        BorderSizePixel = 0,

        Size = UDim2.new(1, 0, 0, 42),

        LayoutOrder = #self.Components + 1,

        ZIndex = 15,
    })

    component.Frame = frame

    local label = AddText(
        frame,
        name:upper(),
        9,
        UDim2.fromOffset(13, 0),
        UDim2.fromOffset(170, 42)
    )

    label.Font = Enum.Font.GothamBold

    local box = New("TextBox", {
        Parent = frame,

        BackgroundColor3 = self.Library.Theme.PanelLight,

        BorderSizePixel = 0,

        Position = UDim2.new(1, -220, 0, 7),

        Size = UDim2.fromOffset(205, 28),

        Text = component.Value,

        PlaceholderText = "ENTER VALUE",

        PlaceholderColor3 = self.Library.Theme.TextMuted,

        TextColor3 = self.Library.Theme.Text,

        TextSize = 11,

        Font = Enum.Font.GothamMedium,

        ClearTextOnFocus = false,

        TextXAlignment = Enum.TextXAlignment.Left,

        ZIndex = 16,
    })

    AddPadding(box, 9, 9, 0, 0)
    AddStroke(box, self.Library.Theme.BorderDim, 0.15, 1)

    component.TextBox = box

    function component:Set(value: string, fireCallback: boolean?)
        self.Value = value
        box.Text = value

        if self.Callback and fireCallback ~= false then
            self.Callback(value)
        end
    end

    function component:Get()
        return self.Value
    end

    self.Library:_Connect(box.FocusLost, function()
        component:Set(box.Text)
    end)

    table.insert(self.Components, component)

    return component
end

--//==============================================================
--// Dropdown
--//==============================================================

function Library.SectionMethods:AddDropdown(
    name: string,
    options: {string},
    callback
)
    local component = {}
    component.Library = self.Library

    component.Options = options
    component.Value = options[1]
    component.Callback = callback
    component.IsOpen = false

    local frame = New("Frame", {
        Parent = self.Holder,

        BackgroundColor3 = self.Library.Theme.Element,

        BackgroundTransparency = 0.1,

        BorderSizePixel = 0,

        Size = UDim2.new(1, 0, 0, 48),

        LayoutOrder = #self.Components + 1,

        ZIndex = 15,
    })

    component.Frame = frame

    local label = AddText(
        frame,
        name:upper(),
        9,
        UDim2.fromOffset(13, 0),
        UDim2.fromOffset(170, 48)
    )

    label.Font = Enum.Font.GothamBold

    local button = New("TextButton", {
        Parent = frame,

        BackgroundColor3 = self.Library.Theme.PanelLight,

        BorderSizePixel = 0,

        Position = UDim2.new(1, -230, 0, 8),

        Size = UDim2.fromOffset(215, 32),

        Text = "",

        AutoButtonColor = false,

        ZIndex = 16,
    })

    AddStroke(button, self.Library.Theme.BorderDim, 0.15, 1)

    local valueLabel = AddText(
        button,
        component.Value or "",
        9,
        UDim2.fromOffset(10, 0),
        UDim2.new(1, -40, 1, 0)
    )

    valueLabel.TextColor3 = self.Library.Theme.Text

    local arrow = AddText(
        button,
        "⌄",
        13,
        UDim2.new(1, -28, 0, 0),
        UDim2.fromOffset(20, 32)
    )

    arrow.TextXAlignment = Enum.TextXAlignment.Right
    arrow.TextColor3 = self.Library.Theme.Cyan

    local MAX_VISIBLE_OPTIONS = 5
    local OPTION_HEIGHT = 32
    local OPTION_PADDING = 2

    local popup = New("Frame", {
        Name = "Dropdown",

        Parent = self.Library.Overlay,

        BackgroundColor3 = self.Library.Theme.Panel,

        BorderSizePixel = 0,

        Size = UDim2.fromOffset(215, 0),

        Visible = false,

        ZIndex = 200,

        ClipsDescendants = true,
    })

    AddStroke(popup, self.Library.Theme.CyanDark, 0.1, 1)
    AddAngularCorners(popup, self.Library.Theme.Cyan)

    local list = New("ScrollingFrame", {
        Parent = popup,

        BackgroundTransparency = 1,

        BorderSizePixel = 0,

        Position = UDim2.fromOffset(0, 0),

        Size = UDim2.fromScale(1, 1),

        CanvasSize = UDim2.fromOffset(0, 0),

        AutomaticCanvasSize = Enum.AutomaticSize.Y,

        ScrollBarThickness = 3,

        ScrollBarImageColor3 = self.Library.Theme.CyanDark,

        ZIndex = 201,
    })

    component.List = list

    AddPadding(list, 4, 4, 4, 4)

    local layout = New("UIListLayout", {
        Parent = list,

        SortOrder = Enum.SortOrder.LayoutOrder,

        Padding = UDim.new(0, OPTION_PADDING),
    })

    -- Height the popup should be: fits every option up to MAX_VISIBLE_OPTIONS, then scrolls.
    local visibleCount = math.min(#options, MAX_VISIBLE_OPTIONS)
    local popupHeight = (visibleCount * OPTION_HEIGHT)
        + (math.max(visibleCount - 1, 0) * OPTION_PADDING)
        + 8 -- top/bottom padding

    popup.Size = UDim2.fromOffset(215, popupHeight)
    popup:SetAttribute("DropdownDesiredHeight", popupHeight)

    local optionRows = {}

    for index, option in ipairs(options) do
        local optionButton = New("TextButton", {
            Parent = list,

            BackgroundColor3 = self.Library.Theme.Element,

            BackgroundTransparency = 1,

            BorderSizePixel = 0,

            Size = UDim2.new(1, 0, 0, OPTION_HEIGHT),

            Text = "",

            AutoButtonColor = false,

            LayoutOrder = index,

            ZIndex = 202,
        })

        local check = AddText(
            optionButton,
            "✓",
            9,
            UDim2.fromOffset(8, 0),
            UDim2.fromOffset(16, OPTION_HEIGHT)
        )

        check.TextColor3 = self.Library.Theme.Cyan
        check.Font = Enum.Font.GothamBold
        check.TextTransparency = 1

        local optionLabel = AddText(
            optionButton,
            option,
            9,
            UDim2.fromOffset(24, 0),
            UDim2.new(1, -34, 1, 0)
        )

        optionLabel.TextColor3 = self.Library.Theme.TextSecondary

        optionRows[option] = {
            Button = optionButton,
            Label = optionLabel,
            Check = check,
        }

        self.Library:_Connect(optionButton.MouseEnter, function()
            Tween(optionButton, TWEEN_FAST, {
                BackgroundColor3 = self.Library.Theme.CyanDim,
                BackgroundTransparency = 0.35,
            })

            Tween(optionLabel, TWEEN_FAST, {
                TextColor3 = self.Library.Theme.White,
            })
        end)

        self.Library:_Connect(optionButton.MouseLeave, function()
            if component.Value == option then
                return
            end

            Tween(optionButton, TWEEN_FAST, {
                BackgroundTransparency = 1,
            })

            Tween(optionLabel, TWEEN_FAST, {
                TextColor3 = self.Library.Theme.TextSecondary,
            })
        end)

        self.Library:_Connect(optionButton.MouseButton1Click, function()
            component:Set(option)
            component:Close()
        end)
    end

    component.Popup = popup

    local function RefreshSelection()
        for option, row in pairs(optionRows) do
            local selected = option == component.Value

            row.Label.TextColor3 = selected
                and self.Library.Theme.White
                or self.Library.Theme.TextSecondary

            row.Check.TextTransparency = selected and 0 or 1

            row.Button.BackgroundTransparency = selected and 0.65 or 1
            row.Button.BackgroundColor3 = selected
                and self.Library.Theme.CyanDim
                or self.Library.Theme.Element
        end
    end

    --// Pass false as the second argument to update the shown value without
    --// running the callback, the same as Toggle and Slider. Callers already
    --// passed false expecting that; ignoring it caused callback loops.
    function component:Set(value: string, fireCallback: boolean?)
        self.Value = value
        valueLabel.Text = value

        RefreshSelection()

        if self.Callback and fireCallback ~= false then
            self.Callback(value)
        end
    end

    function component:Get()
        return self.Value
    end

    function component:Open()
        if self.IsOpen then
            return
        end

        self.Library:_CloseDropdowns(self)

        self.IsOpen = true
        popup.Visible = true

        -- Scroll to the currently selected option so it's visible on open.
        local row = optionRows[self.Value]

        if row then
            local target = math.max(
                0,
                row.Button.Position.Y.Offset - (popupHeight / 2) + (OPTION_HEIGHT / 2)
            )

            list.CanvasPosition = Vector2.new(0, target)
        end

        -- Position immediately, then keep the popup attached to the
        -- dropdown button while the root ScrollingFrame is moving.
        self.Library:_PositionDropdown(button, popup)

        -- Remember every ScrollingFrame between the button and the UI root.
        -- The nearest one is the page/root scroll and is allowed to move.
        -- If another nested ScrollingFrame moves, close the dropdown because
        -- its content has changed independently from the dropdown anchor.
        component.RootScrollingFrame = nil
        component.ScrollingParents = {}

        local ancestor = button.Parent
        while ancestor do
            if ancestor:IsA("ScrollingFrame") then
                if not component.RootScrollingFrame then
                    component.RootScrollingFrame = ancestor
                end

                table.insert(component.ScrollingParents, {
                    Object = ancestor,
                    Position = ancestor.AbsolutePosition,
                    Size = ancestor.AbsoluteSize,
                    CanvasPosition = ancestor.CanvasPosition,
                })
            end

            ancestor = ancestor.Parent
        end

        arrow.Text = "⌃"
    end

    function component:Close()
        if not self.IsOpen then
            return
        end

        self.IsOpen = false
        popup.Visible = false

        arrow.Text = "⌄"
    end

    self.Library:_Connect(button.MouseButton1Click, function()
        if component.IsOpen then
            component:Close()
        else
            component:Open()
        end
    end)

    -- The popup lives outside the ScrollingFrame, so Roblox will not move it
    -- automatically when the page scrolls. Keep it locked to the button.
    self.Library:_Connect(RunService.RenderStepped, function()
        if not component.IsOpen or not popup.Visible then
            return
        end

        if not button:IsDescendantOf(self.Library.ScreenGui) then
            component:Close()
            return
        end

        for _, state in ipairs(component.ScrollingParents) do
            local scrollingFrame = state.Object

            if not scrollingFrame:IsDescendantOf(self.Library.ScreenGui) then
                component:Close()
                return
            end

            local positionChanged = scrollingFrame.AbsolutePosition ~= state.Position
            local sizeChanged     = scrollingFrame.AbsoluteSize ~= state.Size
            local canvasChanged   = scrollingFrame.CanvasPosition ~= state.CanvasPosition

            -- This includes the root ScrollingFrame. If the user scrolls the
            -- page/root while a dropdown is open, close it immediately.
            if positionChanged or sizeChanged or canvasChanged then
                component:Close()
                return
            end
        end

        self.Library:_PositionDropdown(button, popup)
    end)

    self.Library:_Connect(UserInputService.InputBegan, function(input, processed)
        if processed then
            return
        end

        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local mousePosition = UserInputService:GetMouseLocation()

            local position = button.AbsolutePosition
            local size = button.AbsoluteSize

            local inside =
                mousePosition.X >= position.X
                and mousePosition.X <= position.X + size.X
                and mousePosition.Y >= position.Y
                and mousePosition.Y <= position.Y + size.Y

            local popupPosition = popup.AbsolutePosition
            local popupSize = popup.AbsoluteSize

            local insidePopup =
                mousePosition.X >= popupPosition.X
                and mousePosition.X <= popupPosition.X + popupSize.X
                and mousePosition.Y >= popupPosition.Y
                and mousePosition.Y <= popupPosition.Y + popupSize.Y

            if not inside and not insidePopup then
                component:Close()
            end
        end
    end)

    RefreshSelection()

    table.insert(self.Library._dropdowns, component)
    table.insert(self.Components, component)

    return component
end

--//==============================================================
--// Keybind
--//==============================================================

function Library.SectionMethods:AddKeybind(
    name: string,
    defaultKey: Enum.KeyCode,
    callback
)
    local component = {}
    component.Library = self.Library

    component.Key = defaultKey
    component.Callback = callback
    component.Listening = false

    local frame = New("Frame", {
        Parent = self.Holder,

        BackgroundColor3 = self.Library.Theme.Element,

        BackgroundTransparency = 0.1,

        BorderSizePixel = 0,

        Size = UDim2.new(1, 0, 0, 42),

        LayoutOrder = #self.Components + 1,

        ZIndex = 15,
    })

    component.Frame = frame

    local label = AddText(
        frame,
        name:upper(),
        9,
        UDim2.fromOffset(13, 0),
        UDim2.new(1, -150, 1, 0)
    )

    label.Font = Enum.Font.GothamBold

    local keyButton = New("TextButton", {
        Parent = frame,

        BackgroundColor3 = self.Library.Theme.PanelLight,

        BorderSizePixel = 0,

        Position = UDim2.new(1, -125, 0, 7),

        Size = UDim2.fromOffset(110, 28),

        Text = defaultKey.Name,

        TextColor3 = self.Library.Theme.Cyan,

        TextSize = 11,

        Font = Enum.Font.GothamBold,

        AutoButtonColor = false,

        ZIndex = 16,
    })

    AddStroke(keyButton, self.Library.Theme.BorderDim, 0.15, 1)

    component.Button = keyButton

    function component:SetKey(key: Enum.KeyCode)
        self.Key = key
        keyButton.Text = key.Name
        self.Listening = false
    end

    function component:GetKey()
        return self.Key
    end

    self.Library:_Connect(keyButton.MouseButton1Click, function()
        component.Listening = true
        keyButton.Text = "PRESS KEY"
        keyButton.TextColor3 = self.Library.Theme.Warning
    end)

    self.Library:_Connect(UserInputService.InputBegan, function(input, processed)
        if processed then
            return
        end

        if component.Listening then
            if input.KeyCode ~= Enum.KeyCode.Unknown then
                component:SetKey(input.KeyCode)

                keyButton.TextColor3 = self.Library.Theme.Cyan
            end

            return
        end

        if input.KeyCode == component.Key then
            if component.Callback then
                component.Callback()
            end
        end
    end)

    table.insert(self.Components, component)

    return component
end

--//==============================================================
--// Priority
--//==============================================================

--// options (all optional):
--//   Values       true to give every row an editable number (e.g. a wait time)
--//   ValueLabel   short caption shown in the header, e.g. "WAIT (S)"
--//   Default      value for rows added without one (default 0)
--//   Min, Max     clamp for typed values (default 0 .. math.huge)
--//   Draggable    false to turn off drag-to-reorder (default on)
--//
--// Rows are reordered by dragging the name. The drop is applied as a run of
--// MoveUp / MoveDown calls, so any override a caller installed on those two
--// still sees every step.
function Library.SectionMethods:AddPriority(
    name: string,
    values: {string}?,
    options: {[string]: any}?
)
    options = options or {}

    local component = {}
    component.Library = self.Library

    component.Priority = {}
    component.Values = {}

    local hasValues = options.Values == true
    local draggable = options.Draggable ~= false
    local defaultValue = tonumber(options.Default) or 0
    local minValue = tonumber(options.Min) or 0
    local maxValue = tonumber(options.Max) or math.huge

    local ROW_HEIGHT = 34
    local ROW_GAP = 3
    local ROW_STRIDE = ROW_HEIGHT + ROW_GAP

    local function ClampValue(value)
        return math.clamp(tonumber(value) or defaultValue, minValue, maxValue)
    end

    --// Keeps Values the same length as Priority.
    local function FitValues()
        for index = 1, #component.Priority do
            component.Values[index] = ClampValue(component.Values[index])
        end

        for index = #component.Values, #component.Priority + 1, -1 do
            component.Values[index] = nil
        end
    end

    if values then
        for _, value in ipairs(values) do
            table.insert(component.Priority, value)
        end
    end

    FitValues()

    local frame = New("Frame", {
        Parent = self.Holder,

        BackgroundColor3 = self.Library.Theme.Element,

        BackgroundTransparency = 0.1,

        BorderSizePixel = 0,

        Size = UDim2.new(1, 0, 0, 0),

        AutomaticSize = Enum.AutomaticSize.Y,

        LayoutOrder = #self.Components + 1,

        ZIndex = 15,
    })

    component.Frame = frame

    AddStroke(
        frame,
        self.Library.Theme.BorderDim,
        0.15,
        1
    )

    AddPadding(frame, 10, 10, 10, 10)

    -- Header
    local header = New("Frame", {
        Parent = frame,

        BackgroundTransparency = 1,

        Size = UDim2.new(1, 0, 0, 36),

        ZIndex = 16,
    })

    local title = AddText(
        header,
        name:upper(),
        10,
        UDim2.fromOffset(0, 0),
        UDim2.new(1, -100, 0, 20)
    )

    title.Font = Enum.Font.GothamBold

    local subtitleText = "TARGET PRIORITY LIST"

    if draggable then
        subtitleText = subtitleText .. "  ·  DRAG TO REORDER"
    end

    if hasValues and options.ValueLabel then
        subtitleText = subtitleText .. "  ·  " .. tostring(options.ValueLabel):upper()
    end

    local subtitle = AddText(
        header,
        subtitleText,
        7,
        UDim2.fromOffset(0, 18),
        UDim2.new(1, -100, 0, 15)
    )

    subtitle.TextColor3 = self.Library.Theme.TextMuted

    local addButton = New("TextButton", {
        Parent = header,

        BackgroundTransparency = 1,

        Position = UDim2.new(1, -80, 0, 0),

        Size = UDim2.fromOffset(80, 30),

        Text = "+ ADD",

        TextColor3 = self.Library.Theme.Cyan,

        TextSize = 10,

        Font = Enum.Font.GothamBold,

        AutoButtonColor = false,

        ZIndex = 17,
    })

    -- List
    local list = New("Frame", {
        Parent = frame,

        BackgroundTransparency = 1,

        Position = UDim2.fromOffset(0, 36),

        Size = UDim2.new(1, 0, 0, 0),

        AutomaticSize = Enum.AutomaticSize.Y,

        ZIndex = 16,
    })

    New("UIListLayout", {
        Parent = list,

        FillDirection = Enum.FillDirection.Vertical,

        SortOrder = Enum.SortOrder.LayoutOrder,

        Padding = UDim.new(0, ROW_GAP),
    })

    component.List = list

    --// Drop marker. Lives on the outer frame, not in the list, so the list
    --// layout does not move it around.
    local dropIndicator = New("Frame", {
        Parent = frame,

        BackgroundColor3 = self.Library.Theme.Cyan,

        BorderSizePixel = 0,

        Size = UDim2.new(1, 0, 0, 2),

        Visible = false,

        ZIndex = 20,
    })

    local rows = {}

    --// Active drag, or nil. Index is the row being dragged, Target where it
    --// would land, StartY the pointer height when the drag began.
    local dragState = nil

    --// Space kept clear on the right of each row for its buttons.
    local rightReserve = hasValues and 190 or 130

    local function TargetIndexFor(pointerY)
        local offset = pointerY - dragState.StartY
        local target = dragState.Index + math.floor(offset / ROW_STRIDE + 0.5)

        return math.clamp(target, 1, #component.Priority)
    end

    local function ShowDropIndicator(target)
        if target == dragState.Index then
            dropIndicator.Visible = false
            return
        end

        --// Above the target row when moving up, below it when moving down.
        local slot = target < dragState.Index and target - 1 or target
        dropIndicator.Position = UDim2.fromOffset(0, 36 + slot * ROW_STRIDE - ROW_GAP)
        dropIndicator.Visible = true
    end

    local function FinishDrag()
        if not dragState then
            return
        end

        local from = dragState.Index
        local target = dragState.Target

        dragState = nil
        dropIndicator.Visible = false

        if not target or target == from then
            --// Nothing moved, but the dragged row is still highlighted.
            component:_Refresh()
            return
        end

        --// Step by index, not by value: an override may relabel every row
        --// after each step (waypoint labels include their number).
        if target < from then
            for index = from, target + 1, -1 do
                local value = component.Priority[index]

                if value == nil then
                    break
                end

                component:MoveUp(value)
            end
        else
            for index = from, target - 1 do
                local value = component.Priority[index]

                if value == nil then
                    break
                end

                component:MoveDown(value)
            end
        end

        component:_Refresh()
    end

    local function Refresh()
        for _, row in pairs(rows) do
            row:Destroy()
        end

        table.clear(rows)
        FitValues()

        for index, value in ipairs(component.Priority) do
            local row = New("Frame", {
                Parent = list,

                BackgroundColor3 = self.Library.Theme.PanelLight,

                BackgroundTransparency = 0.25,

                BorderSizePixel = 0,

                Size = UDim2.new(1, 0, 0, ROW_HEIGHT),

                LayoutOrder = index,

                ZIndex = 17,
            })

            local number = AddText(
                row,
                string.format("%02d", index),
                8,
                UDim2.fromOffset(8, 0),
                UDim2.fromOffset(28, ROW_HEIGHT)
            )

            number.TextColor3 = self.Library.Theme.CyanDark
            number.Font = Enum.Font.GothamBold

            local marker = AddText(
                row,
                index == 1 and "◆" or "◇",
                12,
                UDim2.fromOffset(36, 0),
                UDim2.fromOffset(20, ROW_HEIGHT)
            )

            marker.TextColor3 =
                index == 1
                and self.Library.Theme.Cyan
                or self.Library.Theme.TextMuted

            local nameLabel = AddText(
                row,
                value:upper(),
                9,
                UDim2.fromOffset(60, 0),
                UDim2.new(1, -(rightReserve + 60), 1, 0)
            )

            nameLabel.Font = Enum.Font.GothamBold

            if hasValues then
                local valueBox = New("TextBox", {
                    Parent = row,

                    BackgroundColor3 = self.Library.Theme.Element,

                    BackgroundTransparency = 0.1,

                    BorderSizePixel = 0,

                    Position = UDim2.new(1, -182, 0.5, -11),

                    Size = UDim2.fromOffset(52, 22),

                    Text = tostring(component.Values[index]),

                    PlaceholderText = tostring(defaultValue),

                    TextColor3 = self.Library.Theme.Text,

                    TextSize = 10,

                    Font = Enum.Font.GothamBold,

                    ClearTextOnFocus = false,

                    ZIndex = 18,
                })

                AddCorner(valueBox, 4)

                self.Library:_Connect(valueBox.FocusLost, function()
                    local newValue = ClampValue(valueBox.Text)
                    valueBox.Text = tostring(newValue)
                    component:SetValue(index, newValue)
                end)
            end

            -- Up
            local up = New("TextButton", {
                Parent = row,

                BackgroundTransparency = 1,

                Position = UDim2.new(1, -125, 0, 0),

                Size = UDim2.fromOffset(35, ROW_HEIGHT),

                Text = "▲",

                TextColor3 = self.Library.Theme.TextMuted,

                TextSize = 11,

                Font = Enum.Font.GothamBold,

                AutoButtonColor = false,

                ZIndex = 18,
            })

            -- Down
            local down = New("TextButton", {
                Parent = row,

                BackgroundTransparency = 1,

                Position = UDim2.new(1, -90, 0, 0),

                Size = UDim2.fromOffset(35, ROW_HEIGHT),

                Text = "▼",

                TextColor3 = self.Library.Theme.TextMuted,

                TextSize = 11,

                Font = Enum.Font.GothamBold,

                AutoButtonColor = false,

                ZIndex = 18,
            })

            -- Remove
            local remove = New("TextButton", {
                Parent = row,

                BackgroundTransparency = 1,

                Position = UDim2.new(1, -48, 0, 0),

                Size = UDim2.fromOffset(35, ROW_HEIGHT),

                Text = "×",

                TextColor3 = self.Library.Theme.Danger,

                TextSize = 18,

                Font = Enum.Font.GothamMedium,

                AutoButtonColor = false,

                ZIndex = 18,
            })

            self.Library:_Connect(up.MouseButton1Click, function()
                component:MoveUp(value)
            end)

            self.Library:_Connect(down.MouseButton1Click, function()
                component:MoveDown(value)
            end)

            self.Library:_Connect(remove.MouseButton1Click, function()
                component:Remove(value)
            end)

            if draggable then
                --// Invisible grip over the number, marker and name. The
                --// buttons on the right stay clickable.
                local grip = New("TextButton", {
                    Parent = row,

                    BackgroundTransparency = 1,

                    Position = UDim2.fromOffset(0, 0),

                    Size = UDim2.new(1, -rightReserve, 1, 0),

                    Text = "",

                    AutoButtonColor = false,

                    ZIndex = 19,
                })

                self.Library:_Connect(grip.InputBegan, function(input)
                    if input.UserInputType ~= Enum.UserInputType.MouseButton1
                        and input.UserInputType ~= Enum.UserInputType.Touch
                    then
                        return
                    end

                    if dragState or #component.Priority < 2 then
                        return
                    end

                    dragState = {
                        Index = index,
                        Target = index,
                        StartY = input.Position.Y,
                    }

                    row.BackgroundColor3 = self.Library.Theme.CyanDark
                    row.BackgroundTransparency = 0.45

                    local endConnection

                    endConnection = input.Changed:Connect(function()
                        if input.UserInputState ~= Enum.UserInputState.End then
                            return
                        end

                        endConnection:Disconnect()
                        FinishDrag()
                    end)
                end)
            end

            table.insert(rows, row)
        end
    end

    --// One pointer listener per list, not per row: rows are rebuilt on every
    --// change and would otherwise leak a connection each time.
    self.Library:_Connect(UserInputService.InputChanged, function(input)
        if not dragState then
            return
        end

        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch
        then
            return
        end

        dragState.Target = TargetIndexFor(input.Position.Y)
        ShowDropIndicator(dragState.Target)
    end)

    function component:_Refresh()
        Refresh()
    end

    --// newValues is optional. Without it the current values are kept, trimmed
    --// or padded with the default to fit the new list.
    function component:SetPriority(newPriority: {string}, newValues: {number}?)
        table.clear(self.Priority)

        for _, value in ipairs(newPriority) do
            table.insert(self.Priority, value)
        end

        if newValues then
            table.clear(self.Values)

            for index, value in ipairs(newValues) do
                self.Values[index] = value
            end
        end

        Refresh()
    end

    function component:GetPriority()
        return table.clone(self.Priority)
    end

    function component:GetValues()
        FitValues()
        return table.clone(self.Values)
    end

    function component:GetValue(index: number)
        return ClampValue(self.Values[index])
    end

    --// Callers hook OnValueChanged(index, value, label) to persist edits.
    function component:SetValue(index: number, value: number)
        if not self.Priority[index] then
            return
        end

        self.Values[index] = ClampValue(value)

        if self.OnValueChanged then
            self.OnValueChanged(index, self.Values[index], self.Priority[index])
        end
    end

    function component:Add(value: string, initialValue: number?)
        if table.find(self.Priority, value) then
            return false
        end

        table.insert(self.Priority, value)
        self.Values[#self.Priority] = ClampValue(initialValue)

        Refresh()

        return true
    end

    function component:Remove(value: string)
        local index = table.find(self.Priority, value)

        if not index then
            return false
        end

        table.remove(self.Priority, index)
        table.remove(self.Values, index)

        Refresh()

        return true
    end

    function component:MoveUp(value: string)
        local index = table.find(self.Priority, value)

        if not index or index <= 1 then
            return
        end

        self.Priority[index], self.Priority[index - 1] =
            self.Priority[index - 1], self.Priority[index]
        self.Values[index], self.Values[index - 1] =
            self.Values[index - 1], self.Values[index]

        Refresh()
    end

    function component:MoveDown(value: string)
        local index = table.find(self.Priority, value)

        if not index or index >= #self.Priority then
            return
        end

        self.Priority[index], self.Priority[index + 1] =
            self.Priority[index + 1], self.Priority[index]
        self.Values[index], self.Values[index + 1] =
            self.Values[index + 1], self.Values[index]

        Refresh()
    end

    self.Library:_Connect(addButton.MouseButton1Click, function()
        -- Add your own target selection here.
        -- Example:
        -- component:Add("Skeleton")
    end)

    table.insert(self.Components, component)

    Refresh()

    return component
end

--//==============================================================
--// Dropdown Position
--//==============================================================

function Library:_PositionDropdown(button: GuiObject, popup: GuiObject)
    if not button.Visible or not popup.Visible then
        return
    end

    local camera  = workspace.CurrentCamera
    local overlay = self.Overlay

    if not camera or not overlay then
        return
    end

    local buttonPosition = button.AbsolutePosition
    local buttonSize     = button.AbsoluteSize
    local viewport       = camera.ViewportSize
    local uiScale        = self.UIScale.Scale

    if uiScale <= 0 then
        return
    end

    local overlayPosition = overlay.AbsolutePosition
    local popupWidth      = popup.AbsoluteSize.X

    -- Keep a small margin from the screen edges.
    local edgePadding = 10
    local gap          = 4

    -- Calculate how much room exists above and below the button.
    local spaceAbove = buttonPosition.Y - edgePadding - gap
    local spaceBelow = viewport.Y - (buttonPosition.Y + buttonSize.Y) - edgePadding - gap

    -- The dropdown has at most five visible rows. If the screen is too short
    -- to fit all five, shrink the popup to the available space and let its
    -- ScrollingFrame handle the remaining options.
    local rowHeight   = 32
    local rowPadding  = 2
    local framePadding = 8
    local maxRows     = 5
    local normalHeight = (maxRows * rowHeight)
        + ((maxRows - 1) * rowPadding)
        + framePadding

    local desiredHeight = popup:GetAttribute("DropdownDesiredHeight") or popup.Size.Y.Offset
    local popupHeight   = math.min(desiredHeight, normalHeight)

    -- Prefer below when it fits. Otherwise place it above. If neither side
    -- can fit the full dropdown, use whichever side has more space.
    local placeAbove = false
    local availableSpace = spaceBelow

    if spaceBelow >= popupHeight then
        placeAbove = false
        availableSpace = spaceBelow
    elseif spaceAbove >= popupHeight then
        placeAbove = true
        availableSpace = spaceAbove
    elseif spaceAbove > spaceBelow then
        placeAbove = true
        availableSpace = spaceAbove
    else
        placeAbove = false
        availableSpace = spaceBelow
    end

    -- If there is not enough room for five rows, use all available space.
    -- Keep at least one row visible on very small screens.
    local maxAvailableHeight = math.max(rowHeight + framePadding, availableSpace)
    popupHeight = math.min(popupHeight, maxAvailableHeight)

    if popup.Size.Y.Offset ~= popupHeight then
        popup.Size = UDim2.fromOffset(popupWidth, popupHeight)
    end

    local screenX = buttonPosition.X
    local screenY

    if placeAbove then
        screenY = buttonPosition.Y - popupHeight - gap
    else
        screenY = buttonPosition.Y + buttonSize.Y + gap
    end

    -- Keep the popup inside the horizontal viewport.
    if screenX + popupWidth > viewport.X - edgePadding then
        screenX = viewport.X - popupWidth - edgePadding
    end

    screenX = math.max(edgePadding, screenX)
    screenY = math.max(edgePadding, screenY)

    popup.Position = UDim2.fromOffset(
        (screenX - overlayPosition.X) / uiScale,
        (screenY - overlayPosition.Y) / uiScale
    )
end

function Library:_CloseDropdowns(exception)
    for _, dropdown in ipairs(self._dropdowns) do
        if dropdown ~= exception then
            dropdown:Close()
        end
    end
end

--//==============================================================
--// Notification
--//==============================================================

--//==============================================================
--// Inventory binding
--//
--// The pin panel deals in names and numbers only. Everything that knows how
--// a particular game stores its inventory lives here, in one adapter, and the
--// format is replaceable: pass a parser and the library never has to care.
--//
--// The default understands the common flat encoding of one string holding
--// "Name|Amount" pairs separated by commas.
--//==============================================================
local function ParseDelimitedInventory(text: string?)
    local counts = {}
    local names = {}

    if type(text) ~= "string" then
        return counts, names
    end

    for entry in string.gmatch(text, "([^,]+)") do
        local itemName, amount = string.match(entry, "([^|]+)|(.+)")

        if itemName and counts[itemName] == nil then
            counts[itemName] = tonumber(amount) or 0
            table.insert(names, itemName)
        end
    end

    table.sort(names, function(a, b)
        return string.lower(a) < string.lower(b)
    end)

    return counts, names
end

--// Wires a pin panel to a StringValue holding an inventory. One call replaces
--// the search source, the count source and the change watcher, so a caller
--// never has to reimplement the same three hookups.
function Library:BindPinToValue(pin, valueObject: Instance?, parser)
    if not pin or not valueObject then
        return false
    end

    parser = parser or ParseDelimitedInventory

    local function Read()
        local ok, counts, names = pcall(parser, valueObject.Value)

        if not ok or type(counts) ~= "table" then
            return {}, {}
        end

        return counts, type(names) == "table" and names or {}
    end

    pin:SetSearchSource(function()
        local _, names = Read()
        return names
    end)

    pin:SetCountSource(function()
        local counts = Read()
        return counts
    end)

    local function Refresh()
        local counts = Read()
        pin:UpdateCounts(counts)
    end

    --// Event driven: the value only changes when the server says so, and one
    --// parse refreshes every pinned count.
    self:_Connect(valueObject:GetPropertyChangedSignal("Value"), Refresh)
    Refresh()

    return true
end

--//==============================================================
--// Pin Panel
--//
--// A compact list of named items with a count each, in its own frame beside
--// the window rather than inside a tab. It knows nothing about where the
--// counts come from: the caller pushes them in with UpdateCounts and supplies
--// the searchable names with SetSearchSource, which keeps this library free
--// of any single inventory format.
--//
--// Attached it sits at the right edge; popped out it is dragged anywhere and
--// keeps its own position. GetState and SetState hand that arrangement to the
--// caller to persist, since the library does no file access of its own.
--//==============================================================
function Library:AddPin(name: string?)
    local component = {}
    component.Library = self
    component.Items = {}
    component.Floating = false
    component.SearchSource = nil
    component.CountSource = nil
    component.MaxResults = 12

    local panel = New("Frame", {
        Name = "PinPanel",
        Parent = self.ScreenGui,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -16, 0, 130),
        Size = UDim2.new(0, 194, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = self.Theme.Panel,
        BackgroundTransparency = 0.06,
        BorderSizePixel = 0,
        ZIndex = 40,
    })

    AddCorner(panel, 6)
    AddStroke(panel, self.Theme.BorderDim)
    AddPadding(panel, 8, 8, 8, 8)

    New("UIListLayout", {
        Parent = panel,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 5),
    })

    component.Panel = panel

    local header = New("Frame", {
        Parent = panel,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 18),
        LayoutOrder = 1,
        ZIndex = 41,
    })

    local title = AddText(header, name or "Pinned Items", 13, UDim2.new(0, 0, 0, 0), UDim2.new(1, -24, 1, 0))
    title.TextColor3 = self.Theme.Cyan
    title.ZIndex = 42

    local popButton = New("TextButton", {
        Parent = header,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, 20, 0, 16),
        BackgroundColor3 = self.Theme.Element,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        Text = "<>",
        TextColor3 = self.Theme.TextMuted,
        TextSize = 11,
        Font = Enum.Font.GothamMedium,
        AutoButtonColor = false,
        ZIndex = 42,
    })

    AddCorner(popButton, 4)

    --// A dropdown is unusable here: an inventory can hold hundreds of entries,
    --// so this filters by substring and shows only the first few matches.
    local searchBox = New("TextBox", {
        Parent = panel,
        Size = UDim2.new(1, 0, 0, 22),
        LayoutOrder = 2,
        BackgroundColor3 = self.Theme.Element,
        BackgroundTransparency = 0.15,
        BorderSizePixel = 0,
        Text = "",
        PlaceholderText = "search item...",
        PlaceholderColor3 = self.Theme.TextMuted,
        TextColor3 = self.Theme.Text,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        ClearTextOnFocus = false,
        ZIndex = 41,
    })

    AddCorner(searchBox, 4)
    AddPadding(searchBox, 6, 6, 0, 0)

    local resultHolder = New("Frame", {
        Parent = panel,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = 3,
        Visible = false,
        ZIndex = 41,
    })

    New("UIListLayout", {
        Parent = resultHolder,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
    })

    local itemHolder = New("Frame", {
        Parent = panel,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = 4,
        ZIndex = 41,
    })

    New("UIListLayout", {
        Parent = itemHolder,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 3),
    })

    local emptyLabel = AddText(panel, "no pinned items", 11, UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0, 16))
    emptyLabel.TextColor3 = self.Theme.TextMuted
    emptyLabel.LayoutOrder = 5
    emptyLabel.ZIndex = 41

    --// Counts pushed in with UpdateCounts only arrive when the caller notices
    --// a change. An item pinned just now, or restored from a saved list, has
    --// to be able to ask for its number straight away or it reads 0 until the
    --// next change happens to come along.
    local function ResolveCounts()
        if not component.CountSource then
            return nil
        end

        local ok, counts = pcall(component.CountSource)

        if not ok or type(counts) ~= "table" then
            return nil
        end

        return counts
    end

    local function IndexOf(itemName)
        for index, entry in ipairs(component.Items) do
            if entry.Name == itemName then
                return index
            end
        end

        return nil
    end

    local RefreshResults

    local function RefreshItems()
        for _, child in ipairs(itemHolder:GetChildren()) do
            if not child:IsA("UIListLayout") then
                child:Destroy()
            end
        end

        emptyLabel.Visible = #component.Items == 0

        for index, entry in ipairs(component.Items) do
            local row = New("Frame", {
                Parent = itemHolder,
                Size = UDim2.new(1, 0, 0, 20),
                BackgroundColor3 = self.Theme.PanelLight,
                BackgroundTransparency = 0.25,
                BorderSizePixel = 0,
                LayoutOrder = index,
                ZIndex = 42,
            })

            AddCorner(row, 4)

            local rowName = AddText(row, entry.Name, 11, UDim2.new(0, 6, 0, 0), UDim2.new(1, -96, 1, 0))
            rowName.TextColor3 = self.Theme.Text
            rowName.ZIndex = 43

            local count = AddText(row, tostring(entry.Count or 0), 11, UDim2.new(1, -92, 0, 0), UDim2.new(0, 34, 1, 0))
            count.TextColor3 = (entry.Count or 0) > 0 and self.Theme.Cyan or self.Theme.TextMuted
            count.TextXAlignment = Enum.TextXAlignment.Right
            count.ZIndex = 43

            local function SmallButton(text, offset, colour)
                return New("TextButton", {
                    Parent = row,
                    AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, offset, 0.5, 0),
                    Size = UDim2.new(0, 16, 0, 16),
                    BackgroundTransparency = 1,
                    Text = text,
                    TextColor3 = colour,
                    TextSize = 11,
                    Font = Enum.Font.GothamMedium,
                    AutoButtonColor = false,
                    ZIndex = 43,
                })
            end

            local up = SmallButton("^", -38, self.Theme.TextMuted)
            local down = SmallButton("v", -21, self.Theme.TextMuted)
            local remove = SmallButton("x", -4, self.Theme.Danger)

            self:_Connect(up.MouseButton1Click, function()
                component:MoveUp(entry.Name)
            end)

            self:_Connect(down.MouseButton1Click, function()
                component:MoveDown(entry.Name)
            end)

            self:_Connect(remove.MouseButton1Click, function()
                component:Remove(entry.Name)
            end)
        end

        if component.OnChanged then
            task.spawn(component.OnChanged, component)
        end
    end

    RefreshResults = function()
        for _, child in ipairs(resultHolder:GetChildren()) do
            if not child:IsA("UIListLayout") then
                child:Destroy()
            end
        end

        local query = string.lower(searchBox.Text or "")

        if query == "" or not component.SearchSource then
            resultHolder.Visible = false
            return
        end

        local ok, names = pcall(component.SearchSource)

        if not ok or type(names) ~= "table" then
            resultHolder.Visible = false
            return
        end

        local shown = 0

        for _, itemName in ipairs(names) do
            if shown >= component.MaxResults then
                break
            end

            if type(itemName) == "string"
                and string.find(string.lower(itemName), query, 1, true)
                and not IndexOf(itemName)
            then
                shown += 1

                local result = New("TextButton", {
                    Parent = resultHolder,
                    Size = UDim2.new(1, 0, 0, 18),
                    BackgroundColor3 = self.Theme.Element,
                    BackgroundTransparency = 0.25,
                    BorderSizePixel = 0,
                    Text = "",
                    AutoButtonColor = false,
                    LayoutOrder = shown,
                    ZIndex = 42,
                })

                AddCorner(result, 4)

                local resultName = AddText(result, itemName, 11, UDim2.new(0, 6, 0, 0), UDim2.new(1, -12, 1, 0))
                resultName.TextColor3 = self.Theme.TextSecondary
                resultName.ZIndex = 43

                self:_Connect(result.MouseButton1Click, function()
                    component:AddList(itemName)
                    searchBox.Text = ""
                    RefreshResults()
                end)
            end
        end

        resultHolder.Visible = shown > 0
    end

    self:_Connect(searchBox:GetPropertyChangedSignal("Text"), RefreshResults)

    function component:AddList(itemName: string, count: number?)
        if type(itemName) ~= "string" or itemName == "" then
            return false
        end

        local existing = IndexOf(itemName)

        if existing then
            --// Already pinned. Re-adding with a number means the caller is
            --// giving a fresh count, so take it rather than doing nothing.
            self.Items[existing].Count = tonumber(count) or self.Items[existing].Count or 0
            RefreshItems()
            return false
        end

        local resolved = tonumber(count)

        if not resolved then
            local counts = ResolveCounts()
            resolved = counts and tonumber(counts[itemName]) or 0
        end

        table.insert(self.Items, {
            Name = itemName,
            Count = resolved,
        })

        RefreshItems()
        RefreshResults()
        return true
    end

    function component:Remove(itemName: string)
        local index = IndexOf(itemName)

        if not index then
            return false
        end

        table.remove(self.Items, index)
        RefreshItems()
        RefreshResults()
        return true
    end

    function component:MoveUp(itemName: string)
        local index = IndexOf(itemName)

        if not index or index <= 1 then
            return false
        end

        self.Items[index], self.Items[index - 1] = self.Items[index - 1], self.Items[index]
        RefreshItems()
        return true
    end

    function component:MoveDown(itemName: string)
        local index = IndexOf(itemName)

        if not index or index >= #self.Items then
            return false
        end

        self.Items[index], self.Items[index + 1] = self.Items[index + 1], self.Items[index]
        RefreshItems()
        return true
    end

    function component:GetItems()
        local names = {}

        for _, entry in ipairs(self.Items) do
            table.insert(names, entry.Name)
        end

        return names
    end

    function component:SetItems(names)
        table.clear(self.Items)

        --// Resolved once for the whole list rather than per item, so a long
        --// restored list costs one lookup.
        local counts = ResolveCounts()

        for _, itemName in ipairs(names or {}) do
            if type(itemName) == "string" and itemName ~= "" and not IndexOf(itemName) then
                table.insert(self.Items, {
                    Name = itemName,
                    Count = counts and tonumber(counts[itemName]) or 0,
                })
            end
        end

        RefreshItems()
        RefreshResults()
    end

    --// Counts arrive from outside. Anything not mentioned reads as zero, so a
    --// pinned item that has left the inventory shows 0 rather than a stale
    --// number from the last update.
    function component:UpdateCounts(counts)
        counts = counts or {}

        for _, entry in ipairs(self.Items) do
            entry.Count = tonumber(counts[entry.Name]) or 0
        end

        RefreshItems()
    end

    function component:SetSearchSource(source)
        self.SearchSource = source
        RefreshResults()
    end

    --// Returns the same name to number map UpdateCounts takes. Called only
    --// when an item is added or a list is restored, never from RefreshItems,
    --// which would recurse through OnChanged.
    function component:SetCountSource(source)
        self.CountSource = source

        if #self.Items > 0 then
            self:UpdateCounts(ResolveCounts())
        end
    end

    function component:SetFloating(value: boolean)
        self.Floating = value and true or false

        popButton.Text = self.Floating and ">|" or "<>"
        popButton.TextColor3 = self.Floating and self.Library.Theme.Cyan or self.Library.Theme.TextMuted

        if not self.Floating then
            panel.AnchorPoint = Vector2.new(1, 0)
            panel.Position = UDim2.new(1, -16, 0, 130)
        end
    end

    function component:SetPosition(x: number?, y: number?)
        if not tonumber(x) or not tonumber(y) then
            return
        end

        panel.AnchorPoint = Vector2.new(0, 0)
        panel.Position = UDim2.fromOffset(tonumber(x), tonumber(y))

        --// A saved position can come from a larger screen or another device.
        ClampToParent(panel)
    end

    --// Docks the panel back to its default spot at the right edge.
    function component:ResetPosition()
        self:SetFloating(false)

        if self.OnChanged then
            task.spawn(self.OnChanged, self)
        end
    end

    function component:GetState()
        return {
            Items = self:GetItems(),
            Floating = self.Floating,
            X = math.round(panel.AbsolutePosition.X),
            Y = math.round(panel.AbsolutePosition.Y),
        }
    end

    function component:SetState(state)
        if type(state) ~= "table" then
            return
        end

        self:SetItems(state.Items)
        self:SetFloating(state.Floating == true)

        if state.Floating then
            self:SetPosition(state.X, state.Y)
        end
    end

    function component:SetVisible(value: boolean)
        panel.Visible = value and true or false
    end

    function component:Destroy()
        panel:Destroy()
    end

    self:_Connect(popButton.MouseButton1Click, function()
        component:SetFloating(not component.Floating)

        if component.OnChanged then
            task.spawn(component.OnChanged, component)
        end
    end)

    --// Dragging works in both modes, and dragging while attached pops it out,
    --// which is the gesture someone will reach for first. It is kept on
    --// screen so it cannot be dragged somewhere it can no longer be grabbed.
    self:_MakeDraggable(header, panel, true)

    --// Rotating a device or resizing the window can leave a floating panel
    --// off screen, so it is pulled back whenever the bounds change.
    self:_Connect(self.ScreenGui:GetPropertyChangedSignal("AbsoluteSize"), function()
        if component.Floating then
            ClampToParent(panel)
        end
    end)

    --// The panel grows as items are pinned, which can push its bottom edge
    --// past the screen.
    self:_Connect(panel:GetPropertyChangedSignal("AbsoluteSize"), function()
        if component.Floating then
            ClampToParent(panel)
        end
    end)

    self:_Connect(header.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            if not component.Floating then
                component:SetFloating(true)
            end

            --// Report the drag once it ends, so the new spot is saved.
            local endConnection

            endConnection = input.Changed:Connect(function()
                if input.UserInputState ~= Enum.UserInputState.End then
                    return
                end

                endConnection:Disconnect()
                ClampToParent(panel)

                if component.OnChanged then
                    task.spawn(component.OnChanged, component)
                end
            end)
        end
    end)

    component:SetFloating(false)
    RefreshItems()

    self.Pins = self.Pins or {}
    table.insert(self.Pins, component)

    return component
end

function Library:Notify(title: string, message: string, duration: number?)
    duration = duration or 3

    local notification = New("Frame", {
        Parent = self.ScreenGui,

        AnchorPoint = Vector2.new(1, 1),

        Position = UDim2.new(1, 20, 1, -25),

        Size = UDim2.fromOffset(310, 72),

        BackgroundColor3 = self.Theme.Panel,

        BorderSizePixel = 0,

        ZIndex = 300,
    })

    AddStroke(
        notification,
        self.Theme.CyanDark,
        0.1,
        1
    )

    AddAngularCorners(notification)

    local icon = AddText(
        notification,
        "◇",
        18,
        UDim2.fromOffset(13, 10),
        UDim2.fromOffset(32, 28)
    )

    icon.TextColor3 = self.Theme.Cyan
    icon.Font = Enum.Font.GothamBold

    local titleLabel = AddText(
        notification,
        title:upper(),
        9,
        UDim2.fromOffset(48, 8),
        UDim2.new(1, -60, 0, 18)
    )

    titleLabel.Font = Enum.Font.GothamBold

    local messageLabel = AddText(
        notification,
        message,
        9,
        UDim2.fromOffset(48, 29),
        UDim2.new(1, -60, 0, 28)
    )

    messageLabel.TextColor3 = self.Theme.TextSecondary
    messageLabel.TextWrapped = true

    -- Time line
    local timerLine = New("Frame", {
        Parent = notification,

        BackgroundColor3 = self.Theme.Cyan,

        BorderSizePixel = 0,

        Position = UDim2.new(0, 0, 1, -2),

        Size = UDim2.new(1, 0, 0, 2),

        ZIndex = 301,
    })

    table.insert(self._notifications, notification)

    -- Reposition existing notifications
    for index, existing in ipairs(self._notifications) do
        if existing ~= notification then
            local targetY = -25 - ((#self._notifications - index) * 82)

            Tween(existing, TWEEN_NORMAL, {
                Position = UDim2.new(1, -25, 1, targetY),
            })
        end
    end

    Tween(notification, TWEEN_SMOOTH, {
        Position = UDim2.new(1, -25, 1, -25),
    })

    Tween(timerLine, TweenInfo.new(
        duration,
        Enum.EasingStyle.Linear,
        Enum.EasingDirection.Out
        ), {
            Size = UDim2.new(0, 0, 0, 2),
        })

    task.delay(duration, function()
        if not notification.Parent then
            return
        end

        Tween(notification, TWEEN_NORMAL, {
            Position = UDim2.new(1, 25, 1, -25),
        })

        task.wait(0.2)

        if notification.Parent then
            notification:Destroy()
        end

        local index = table.find(self._notifications, notification)

        if index then
            table.remove(self._notifications, index)
        end
    end)

    return notification
end

--//==============================================================
--// Theme
--//==============================================================

function Library:SetTheme(theme: {[string]: any})
    for key, value in pairs(theme) do
        self.Theme[key] = value
    end

    -- Basic global elements
    self.Window.BackgroundColor3 = self.Theme.Background
    self.Header.BackgroundColor3 = self.Theme.BackgroundLight
    self.Sidebar.BackgroundColor3 = self.Theme.Panel

    self.TitleLabel.TextColor3 = self.Theme.Text
    self.Subtitle.TextColor3 = self.Theme.TextMuted

    self.StatusDot.BackgroundColor3 = self.Theme.Cyan

    self.CloseButton.BackgroundColor3 = self.Theme.Danger
    self.ReopenButton.BackgroundColor3 = self.Theme.Panel
    self.ReopenButton.TextColor3 = self.Theme.Cyan
end

--//==============================================================
--// Destroy
--//==============================================================

function Library:Destroy()
    if self.Destroyed then
        return
    end

    self.Destroyed = true

    for _, connection in ipairs(self._connections) do
        if connection.Connected then
            connection:Disconnect()
        end
    end

    table.clear(self._connections)

    if self.ScreenGui then
        self.ScreenGui:Destroy()
    end

    table.clear(self.Tabs)
    table.clear(self.Sections)
    table.clear(self.Components)
    table.clear(self._dropdowns)
    table.clear(self._notifications)
end

--//==============================================================
--// Return
--//==============================================================

return Library
