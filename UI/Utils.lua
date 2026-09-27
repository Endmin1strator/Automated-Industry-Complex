--!strict
--!optimize 2

local Players            = game:GetService("Players")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local RunService         = game:GetService("RunService")

local Player             = Players.LocalPlayer
local PlayerGui          = Player:WaitForChild("PlayerGui", 10)

local Library = {}
Library.__index = Library

------//==============================================================
----// Theme
------//==============================================================

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

	Cyan               = Color3.fromRGB(111, 220, 220),
	CyanDark           = Color3.fromRGB(53, 135, 137),
	CyanDim            = Color3.fromRGB(42, 82, 84),

	White              = Color3.fromRGB(242, 244, 242),

	Border             = Color3.fromRGB(79, 91, 91),
	BorderDim          = Color3.fromRGB(51, 61, 61),

	Danger             = Color3.fromRGB(218, 79, 79),
	Warning            = Color3.fromRGB(222, 181, 75),

	Black              = Color3.fromRGB(7, 9, 10),
}

------//==============================================================
----// Constants
------//==============================================================

local WINDOW_SIZE       = Vector2.new(960, 590)
local MIN_WINDOW_SIZE   = Vector2.new(560, 360)
local MAX_WINDOW_SIZE   = Vector2.new(1400, 900)
local RESIZE_HANDLE     = 14

local TWEEN_FAST   = TweenInfo.new(0.12, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local TWEEN_NORMAL = TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local TWEEN_SMOOTH = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

------//==============================================================
----// Utility
------//==============================================================

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
		TextSize = size,

		Font = Enum.Font.GothamMedium,

		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,

		ClipsDescendants = true,
	})

	return label
end

------//==============================================================
----// Angular Decoration
------//==============================================================

local function AddAngularCorners(parent: Instance, color: Color3?)
	local holder = New("Frame", {
		Parent = parent,

		BackgroundTransparency = 1,

		Size = UDim2.fromScale(1, 1),

		ZIndex = parent.ZIndex + 1,

		Active = false,
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

------//==============================================================
----// Connection Manager
------//==============================================================

function Library:_Connect(signal, callback)
	local connection = signal:Connect(callback)

	table.insert(self._connections, connection)

	return connection
end

------//==============================================================
----// Window
------//==============================================================

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
	self.WindowSize        = WINDOW_SIZE
	self._FirstOpen        = true
	self._Loading          = true

	self._dropdowns        = {}
	self._notifications    = {}

	--==========================================================
	-- ScreenGui
	--==========================================================

	local screenGui = New("ScreenGui", {
		Name = "AFTERHE4RTZ_UI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
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

	--==========================================================
	-- Window
	--==========================================================

	local window = New("Frame", {
		Name = "Window",

		Parent = screenGui,

		AnchorPoint = Vector2.new(0.5, 0.5),

		Position = UDim2.fromScale(0.5, 0.5),

		Size = UDim2.fromOffset(
			self.WindowSize.X,
			self.WindowSize.Y
		),

		BackgroundColor3 = self.Theme.Background,

		BorderSizePixel = 0,

		ClipsDescendants = true,

		ZIndex = 10,
	})

	self.Window = window

	AddStroke(window, self.Theme.Border, 0.15, 1)
	AddAngularCorners(window)

	--==========================================================
	-- Resize Handles
	--==========================================================

	local resizeRight = New("TextButton", {
		Name = "ResizeRight",
		Parent = window,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -RESIZE_HANDLE, 0, 58),
		Size = UDim2.new(0, RESIZE_HANDLE, 1, -58 - RESIZE_HANDLE),
		Text = "",
		AutoButtonColor = false,
		ZIndex = 30,
	})

	local resizeBottom = New("TextButton", {
		Name = "ResizeBottom",
		Parent = window,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 58, 1, -RESIZE_HANDLE),
		Size = UDim2.new(1, -58 - RESIZE_HANDLE, 0, RESIZE_HANDLE),
		Text = "",
		AutoButtonColor = false,
		ZIndex = 30,
	})

	local resizeCorner = New("TextButton", {
		Name = "ResizeCorner",
		Parent = window,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -RESIZE_HANDLE - 2, 1, -RESIZE_HANDLE - 2),
		Size = UDim2.fromOffset(RESIZE_HANDLE + 2, RESIZE_HANDLE + 2),
		Text = "◢",
		TextColor3 = self.Theme.CyanDark,
		TextSize = 10,
		Font = Enum.Font.GothamBold,
		AutoButtonColor = false,
		ZIndex = 31,
	})

	self.ResizeRight  = resizeRight
	self.ResizeBottom = resizeBottom
	self.ResizeCorner = resizeCorner

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

		TextSize = 30,

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
		"UTILITY SYSTEM  --//  ONLINE",
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
		"SYSTEM  --//  01",
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

		TextSize = 23,

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
		"AFTERHE4RTZ  --//  UTILITY",
		8,
		UDim2.fromOffset(20, -44),
		UDim2.new(1, -40, 0, 18)
	)

	footer.AnchorPoint = Vector2.new(0, 1)
	footer.TextColor3 = self.Theme.TextMuted

	local version = AddText(
		sidebar,
		"SYSTEM BUILD  --//  01",
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
	-- Initial Loading
	--==========================================================

	local loading = New("Frame", {
		Name = "Loading",
		Parent = window,
		BackgroundColor3 = self.Theme.Background,
		BackgroundTransparency = 0.02,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1),
		Visible = true,
		ZIndex = 500,
	})

	local loadingTitle = AddText(
		loading,
		"INITIALIZING SYSTEM",
		16,
		UDim2.new(0.5, -180, 0.5, -28),
		UDim2.fromOffset(360, 30)
	)

	loadingTitle.TextXAlignment = Enum.TextXAlignment.Center
	loadingTitle.Font = Enum.Font.GothamBold
	loadingTitle.TextColor3 = self.Theme.White
	loadingTitle.ZIndex = 502

	local loadingStatus = AddText(
		loading,
		"LOADING MODULES  --//  0%",
		9,
		UDim2.new(0.5, -180, 0.5, 10),
		UDim2.fromOffset(360, 20)
	)

	loadingStatus.TextXAlignment = Enum.TextXAlignment.Center
	loadingStatus.TextColor3 = self.Theme.TextMuted
	loadingStatus.ZIndex = 502

	local loadingBar = New("Frame", {
		Parent = loading,
		BackgroundColor3 = self.Theme.PanelLight,
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, -150, 0.5, 40),
		Size = UDim2.fromOffset(300, 2),
		ZIndex = 501,
	})

	local loadingFill = New("Frame", {
		Parent = loadingBar,
		BackgroundColor3 = self.Theme.Cyan,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 502,
	})

	self.LoadingFrame  = loading
	self.LoadingTitle  = loadingTitle
	self.LoadingStatus = loadingStatus
	self.LoadingBar    = loadingBar
	self.LoadingFill   = loadingFill

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

		TextSize = 24,

		Font = Enum.Font.GothamBold,

		AutoButtonColor = false,

		Visible = false,

		Active = true,

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

	--==========================================================
	-- Resize
	--==========================================================

	self:_MakeResizable(resizeRight, "Right")
	self:_MakeResizable(resizeBottom, "Bottom")
	self:_MakeResizable(resizeCorner, "Corner")

	-- Build everything first, then reveal the finished window.
	task.defer(function()
		self:_FinishInitialLoad()
	end)

	return self
end

------//==============================================================
----// Responsive Scale
------//==============================================================

function Library:_UpdateScale()
	if self.Destroyed then
		return
	end

	local camera = workspace.CurrentCamera

	if not camera then
		return
	end

	local viewport = camera.ViewportSize

	local windowSize = self.WindowSize or WINDOW_SIZE

	local scaleX = (viewport.X - 40) / windowSize.X
	local scaleY = (viewport.Y - 40) / windowSize.Y

	local scale = math.min(scaleX, scaleY)

	scale = math.clamp(scale, 0.55, 1)

	self.UIScale.Scale = scale
end

------//==============================================================
----// Resizable
------//==============================================================

function Library:_MakeResizable(handle: GuiObject, direction: string)
	local resizing = false
	local resizeStart: Vector2
	local startSize: Vector2

	self:_Connect(handle.InputBegan, function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		if self.Destroyed or not self.Visible or self._Loading then
			return
		end

		resizing = true
		resizeStart = input.Position
		startSize = self.WindowSize

		local changedConnection

		changedConnection = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				resizing = false

				if changedConnection then
					changedConnection:Disconnect()
				end
			end
		end)
	end)

	self:_Connect(UserInputService.InputChanged, function(input)
		if not resizing then
			return
		end

		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		local scale = self.UIScale.Scale

		if scale <= 0 then
			return
		end

		local delta = (input.Position - resizeStart) / scale
		local width = startSize.X
		local height = startSize.Y

		if direction == "Right" or direction == "Corner" then
			width = startSize.X + delta.X
		end

		if direction == "Bottom" or direction == "Corner" then
			height = startSize.Y + delta.Y
		end

		local camera = workspace.CurrentCamera

		if camera then
			local viewport = camera.ViewportSize
			local absolutePosition = self.Window.AbsolutePosition

			local maxWidth = (viewport.X - absolutePosition.X - 20) / scale
			local maxHeight = (viewport.Y - absolutePosition.Y - 20) / scale

			width = math.min(width, maxWidth, MAX_WINDOW_SIZE.X)
			height = math.min(height, maxHeight, MAX_WINDOW_SIZE.Y)
		end

		width = math.max(width, MIN_WINDOW_SIZE.X)
		height = math.max(height, MIN_WINDOW_SIZE.Y)

		self.WindowSize = Vector2.new(width, height)
		self.Window.Size = UDim2.fromOffset(width, height)

		self:_UpdateScale()
	end)

	self:_Connect(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			resizing = false
		end
	end)
end

------//==============================================================
--// Initial Loading
----//==============================================================

	function Library:_FinishInitialLoad()
		if self.Destroyed or not self._Loading then
			return
		end

		local loading = self.LoadingFrame
		local title = self.LoadingTitle
		local status = self.LoadingStatus
		local bar = self.LoadingBar
		local fill = self.LoadingFill

		if not loading or not title or not status or not bar or not fill then
			self._Loading = false
			return
		end

		local stages = {
			{Percent = 0.28, Text = "LOADING MODULES  --//  28%"},
			{Percent = 0.55, Text = "BUILDING INTERFACE  --//  55%"},
			{Percent = 0.78, Text = "INDEXING COMPONENTS  --//  78%"},
			{Percent = 1, Text = "SYSTEM READY  --//  100%"},
		}

		for _, stage in ipairs(stages) do
			if self.Destroyed then
				return
			end

			status.Text = stage.Text

			Tween(fill, TWEEN_NORMAL, {
				Size = UDim2.fromScale(stage.Percent, 1),
			})

			task.wait(0.07)
		end

		task.wait(0.08)

		self._Loading = false
		self._FirstOpen = false

		Tween(loading, TWEEN_SMOOTH, {
			BackgroundTransparency = 1,
		})

		Tween(title, TWEEN_SMOOTH, {
			TextTransparency = 1,
		})

		Tween(status, TWEEN_SMOOTH, {
			TextTransparency = 1,
		})

		Tween(bar, TWEEN_SMOOTH, {
			BackgroundTransparency = 1,
		})

		task.delay(0.34, function()
			if self.Destroyed then
				return
			end

			loading.Visible = false
		end)
	end

------//==============================================================
--// Draggable
------//==============================================================

function Library:_MakeDraggable(handle: GuiObject, target: GuiObject)
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
	end)
end

------//==============================================================
----// Set Visible
------//==============================================================

function Library:SetVisible(value: boolean)
	if self.Destroyed then
		return
	end

	if self.Visible == value then
		return
	end

	self.Visible = value

	if value then
		self.ReopenButton.Visible = false
		self.Window.Visible = true

		local scale = self.UIScale

		local originalScale = scale.Scale

		scale.Scale = originalScale * 0.94

		Tween(scale, TWEEN_SMOOTH, {
			Scale = originalScale,
		})

		self:_FadeWindow(0)
	else
		self:_CloseDropdowns()

		local scale = self.UIScale
		local originalScale = scale.Scale

		Tween(scale, TWEEN_NORMAL, {
			Scale = originalScale * 0.96,
		})

		task.delay(0.18, function()
			if self.Destroyed or self.Visible then
				return
			end

			self.Window.Visible = false
			self.ReopenButton.Visible = true

			scale.Scale = originalScale
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

------//==============================================================
----// Tab
------//==============================================================

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

------//==============================================================
----// Section
------//==============================================================

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

------//==============================================================
----// Label
------//==============================================================

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

------//==============================================================
----// Button
------//==============================================================

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

------//==============================================================
----// Toggle
------//==============================================================

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

	local knob = New("Frame", {
		Parent = toggle,

		BackgroundColor3 = self.Library.Theme.TextMuted,

		BorderSizePixel = 0,

		Position = UDim2.fromOffset(3, 3),

		Size = UDim2.fromOffset(14, 14),

		ZIndex = 17,
	})

	AddCorner(knob, 2)

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

------//==============================================================
----// Slider
------//==============================================================

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

------//==============================================================
----// Textbox
------//==============================================================

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

		TextSize = 9,

		Font = Enum.Font.GothamMedium,

		ClearTextOnFocus = false,

		TextXAlignment = Enum.TextXAlignment.Left,

		ZIndex = 16,
	})

	AddPadding(box, 9, 9, 0, 0)
	AddStroke(box, self.Library.Theme.BorderDim, 0.15, 1)

	component.TextBox = box

	function component:Set(value: string)
		self.Value = value
		box.Text = value

		if self.Callback then
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

------//==============================================================
----// Dropdown
------//==============================================================

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

	local popup = New("Frame", {
		Name = "Dropdown",

		Parent = self.Library.Overlay,

		BackgroundColor3 = self.Library.Theme.Panel,

		BorderSizePixel = 0,

		Size = UDim2.fromOffset(215, 0),

		AutomaticSize = Enum.AutomaticSize.Y,

		Visible = false,

		ZIndex = 200,
	})

	AddStroke(popup, self.Library.Theme.CyanDark, 0.1, 1)
	AddAngularCorners(popup, self.Library.Theme.Cyan)

	AddPadding(popup, 4, 4, 4, 4)

	local layout = New("UIListLayout", {
		Parent = popup,

		SortOrder = Enum.SortOrder.LayoutOrder,

		Padding = UDim.new(0, 2),
	})

	for index, option in ipairs(options) do
		local optionButton = New("TextButton", {
			Parent = popup,

			BackgroundColor3 = self.Library.Theme.Element,

			BackgroundTransparency = 1,

			BorderSizePixel = 0,

			Size = UDim2.new(1, 0, 0, 32),

			Text = "",

			AutoButtonColor = false,

			LayoutOrder = index,

			ZIndex = 201,
		})

		local optionLabel = AddText(
			optionButton,
			option,
			9,
			UDim2.fromOffset(10, 0),
			UDim2.new(1, -20, 1, 0)
		)

		optionLabel.TextColor3 = self.Library.Theme.TextSecondary
		optionLabel.ZIndex = 202

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

	function component:Set(value: string)
		self.Value = value
		valueLabel.Text = value

		if self.Callback then
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

		-- UIListLayout/AutomaticSize updates AbsoluteSize on the next render step.
		-- Position once now and once after the layout has calculated the popup size.
		self.Library:_PositionDropdown(button, popup)
		task.defer(function()
			if self.IsOpen and popup.Parent and popup.Visible then
				self.Library:_PositionDropdown(button, popup)
			end
		end)

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

	self.Library:_Connect(UserInputService.InputBegan, function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		if not component.IsOpen then
			return
		end

		local mousePosition = UserInputService:GetMouseLocation()

		local function IsInside(guiObject: GuiObject)
			local position = guiObject.AbsolutePosition
			local size = guiObject.AbsoluteSize

			return mousePosition.X >= position.X
				and mousePosition.X <= position.X + size.X
				and mousePosition.Y >= position.Y
				and mousePosition.Y <= position.Y + size.Y
		end

		-- Do not close when clicking either the dropdown button or popup options.
		if IsInside(button) or IsInside(popup) then
			return
		end

		component:Close()
	end)

	table.insert(self.Library._dropdowns, component)
	table.insert(self.Components, component)

	return component
end

------//==============================================================
----// Keybind
------//==============================================================

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

		TextSize = 9,

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

------//==============================================================
----// Priority
------//==============================================================

function Library.SectionMethods:AddPriority(
	name: string,
	values: {string}?
)
	local component = {}
	component.Library = self.Library

	component.Priority = {}

	if values then
		for _, value in ipairs(values) do
			table.insert(component.Priority, value)
		end
	end

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

	local subtitle = AddText(
		header,
		"TARGET PRIORITY LIST",
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

		TextSize = 8,

		Font = Enum.Font.GothamBold,

		AutoButtonColor = false,

		ZIndex = 17,
	})

	-- List
	local list = New("Frame", {
		Parent = frame,

		BackgroundTransparency = 1,

		Size = UDim2.new(1, 0, 0, 0),

		AutomaticSize = Enum.AutomaticSize.Y,

		ZIndex = 16,
	})

	local layout = New("UIListLayout", {
		Parent = list,

		FillDirection = Enum.FillDirection.Vertical,

		SortOrder = Enum.SortOrder.LayoutOrder,

		Padding = UDim.new(0, 3),
	})

	component.List = list

	local rows = {}

	local function Refresh()
		for _, row in pairs(rows) do
			row:Destroy()
		end

		table.clear(rows)

		for index, value in ipairs(component.Priority) do
			local row = New("Frame", {
				Parent = list,

				BackgroundColor3 = self.Library.Theme.PanelLight,

				BackgroundTransparency = 0.25,

				BorderSizePixel = 0,

				Size = UDim2.new(1, 0, 0, 34),

				LayoutOrder = index,

				ZIndex = 17,
			})

			local number = AddText(
				row,
				string.format("%02d", index),
				8,
				UDim2.fromOffset(8, 0),
				UDim2.fromOffset(28, 34)
			)

			number.TextColor3 = self.Library.Theme.CyanDark
			number.Font = Enum.Font.GothamBold

			local marker = AddText(
				row,
				index == 1 and "◆" or "◇",
				12,
				UDim2.fromOffset(36, 0),
				UDim2.fromOffset(20, 34)
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
				UDim2.new(1, -190, 1, 0)
			)

			nameLabel.Font = Enum.Font.GothamBold

			-- Up
			local up = New("TextButton", {
				Parent = row,

				BackgroundTransparency = 1,

				Position = UDim2.new(1, -125, 0, 0),

				Size = UDim2.fromOffset(35, 34),

				Text = "▲",

				TextColor3 = self.Library.Theme.TextMuted,

				TextSize = 9,

				Font = Enum.Font.GothamBold,

				AutoButtonColor = false,

				ZIndex = 18,
			})

			-- Down
			local down = New("TextButton", {
				Parent = row,

				BackgroundTransparency = 1,

				Position = UDim2.new(1, -90, 0, 0),

				Size = UDim2.fromOffset(35, 34),

				Text = "▼",

				TextColor3 = self.Library.Theme.TextMuted,

				TextSize = 9,

				Font = Enum.Font.GothamBold,

				AutoButtonColor = false,

				ZIndex = 18,
			})

			-- Remove
			local remove = New("TextButton", {
				Parent = row,

				BackgroundTransparency = 1,

				Position = UDim2.new(1, -48, 0, 0),

				Size = UDim2.fromOffset(35, 34),

				Text = "×",

				TextColor3 = self.Library.Theme.Danger,

				TextSize = 16,

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

			table.insert(rows, row)
		end
	end

	function component:SetPriority(newPriority: {string})
		table.clear(self.Priority)

		for _, value in ipairs(newPriority) do
			table.insert(self.Priority, value)
		end

		Refresh()
	end

	function component:GetPriority()
		return table.clone(self.Priority)
	end

	function component:Add(value: string)
		if table.find(self.Priority, value) then
			return false
		end

		table.insert(self.Priority, value)

		Refresh()

		return true
	end

	function component:Remove(value: string)
		local index = table.find(self.Priority, value)

		if not index then
			return false
		end

		table.remove(self.Priority, index)

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

		Refresh()
	end

	function component:MoveDown(value: string)
		local index = table.find(self.Priority, value)

		if not index or index >= #self.Priority then
			return
		end

		self.Priority[index], self.Priority[index + 1] =
			self.Priority[index + 1], self.Priority[index]

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

------//==============================================================
----// Dropdown Position
------//==============================================================

function Library:_PositionDropdown(button: GuiObject, popup: GuiObject)
	local position = button.AbsolutePosition
	local size = button.AbsoluteSize

	local camera = workspace.CurrentCamera

	if not camera then
		return
	end

	local viewport = camera.ViewportSize

	local popupHeight = popup.AbsoluteSize.Y
	local popupWidth = popup.AbsoluteSize.X

	local x = position.X
	local y = position.Y + size.Y + 4

	if y + popupHeight > viewport.Y - 10 then
		y = position.Y - popupHeight - 4
	end

	if x + popupWidth > viewport.X - 10 then
		x = viewport.X - popupWidth - 10
	end

	x = math.max(10, x)
	y = math.max(10, y)

	popup.Position = UDim2.fromOffset(x, y)
end

function Library:_CloseDropdowns(exception)
	for _, dropdown in ipairs(self._dropdowns) do
		if dropdown ~= exception then
			dropdown:Close()
		end
	end
end

------//==============================================================
----// Notification
------//==============================================================

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

------//==============================================================
----// Theme
------//==============================================================

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

------//==============================================================
----// Destroy
------//==============================================================

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

------//==============================================================
----// Return
------//==============================================================

return Library
