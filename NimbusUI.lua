--[[
	Nimbus UI — a compact, flat dark UI library for Roblox (Luau)

	Setup: put this in a ModuleScript (e.g. ReplicatedStorage.NimbusUI)
	and require it from a LocalScript. See NimbusUI_Demo.lua for every element.

	API overview
		local UI = Library.new({ Title, Subtitle, Size, Accent, ToggleKey, NotifyPosition, ConfigFolder,
		                         MobileButton, TouchMode, ConfigStore, NotifyErrors, OnError(message) })
		local tab = UI:Tab("Name")
		local section = tab:Section("Name", "Left" | "Right")

		section:Toggle      { Name, Default, Flag, Tooltip, Callback(bool) }
			-> :AddKeybind { Default, Mode, Flag, Sync, Tooltip, Callback(bool), Changed(key) }
			-> :AddColorPicker { Default, Flag, Tooltip, Callback(Color3) }
		section:Slider      { Name, Min, Max, Default, Step, Suffix, Flag, Tooltip, Callback(number) }
		section:Dropdown    { Name, Options, Default, Multi, MaxVisible, Flag, Tooltip, Callback(value) }   -> :Refresh(options)
		section:Keybind     { Name, Default, Mode = "Press"|"Toggle"|"Hold", Flag, Callback, Changed(key) }
		section:ColorPicker { Name, Default, Flag, Tooltip, Callback(Color3) }
		section:Textbox     { Name, Default, Placeholder, Flag, Callback(text, enterPressed) }
		section:Button      { Name, Tooltip, Callback() }
		section:Label(text)

		Every element returns an object with :Set(value, silent) / :Get() (Button/Label: :SetText / :Set).
		Every element also has :SetVisible(bool) / :IsVisible() and takes the option
		DependsOn = toggle, which shows the element only while that toggle is on.
		Toggles have :OnChanged(fn). Sections have :SetVisible(bool) too.

		UI:Notify { Title, Text, Duration, Persistent, Type = "Info"|"Success"|"Warning"|"Error" }   -> :Close()
		UI:SetAccent(Color3)   UI:SetOpen(bool)   UI:Destroy()
		UI:SetTheme { Background, Panel, Section, Element, Hover, Border, Text, SubText, Accent }
		UI:SaveConfig(name)    UI:LoadConfig(name)    UI:DeleteConfig(name)    UI:ListConfigs() -> { name }
		UI:SetConfigStore { Save(name, json), Load(name), List(), Delete(name) }   (or the ConfigStore option)
		section:ConfigManager { Name, Default, Notify, DependsOn, Callback(action, name, ok) }
		UI:ExportConfig() -> json string    UI:ApplyConfig(json)
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

-- Optional functions that only some environments define; they are nil in a
-- normal Roblox game. Reading them from the environment table keeps the script
-- analyzer from reporting them as unknown globals.
local env = getfenv() :: { [string]: any }
local gethui = env.gethui
local writefile, readfile = env.writefile, env.readfile
local isfolder, makefolder = env.isfolder, env.makefolder
local listfiles, delfile = env.listfiles, env.delfile

local Library = {}
Library.__index = Library

local Tab = {}
Tab.__index = Tab

local Section = {}
Section.__index = Section

local DEFAULT_THEME = {
	Background = Color3.fromRGB(16, 16, 19),
	Panel = Color3.fromRGB(22, 22, 26),
	Section = Color3.fromRGB(27, 27, 32),
	Element = Color3.fromRGB(35, 35, 41),
	Hover = Color3.fromRGB(44, 44, 52),
	Border = Color3.fromRGB(48, 48, 56),
	Text = Color3.fromRGB(225, 225, 230),
	SubText = Color3.fromRGB(135, 135, 148),
	Accent = Color3.fromRGB(150, 115, 255),
	Font = Enum.Font.Gotham,
	FontBold = Enum.Font.GothamBold,
	TextSize = 13,
}

Library.DefaultTheme = table.freeze(table.clone(DEFAULT_THEME))

-- Used by SetTheme. For each colour property, the theme colours it can show,
-- most likely first.
local THEME_KEYS_FOR = {
	BackgroundColor3 = { "Background", "Panel", "Section", "Element", "Hover", "Border" },
	TextColor3 = { "Text", "SubText" },
	PlaceholderColor3 = { "SubText" },
	ScrollBarImageColor3 = { "Border", "SubText" },
	Color = { "Border" },
}
local THEMED_PROPERTIES = {
	Frame = { "BackgroundColor3" },
	CanvasGroup = { "BackgroundColor3" },
	ScrollingFrame = { "BackgroundColor3", "ScrollBarImageColor3" },
	TextLabel = { "BackgroundColor3", "TextColor3" },
	TextButton = { "BackgroundColor3", "TextColor3" },
	TextBox = { "BackgroundColor3", "TextColor3", "PlaceholderColor3" },
	UIStroke = { "Color" },
}
local THEME_COLOR_KEYS = { "Background", "Panel", "Section", "Element", "Hover", "Border", "Text", "SubText" }

-- Element sizes in pixels. Touch devices get larger tap targets.
local DESKTOP_METRICS = {
	Row = 18, -- toggle / keybind / colour rows
	Check = 12, -- toggle box
	Button = 22,
	Field = 20, -- dropdown header, text boxes
	Option = 18, -- dropdown option rows
	Tab = 26,
	Bind = 16, -- keybind button height
	BindWidth = 64,
	SwatchW = 26,
	SwatchH = 12,
	Bar = 8, -- visible slider track
	BarHit = 14, -- slider drag area
	Hue = 14, -- hue strip width
	Spacing = 6,
}
local TOUCH_METRICS = {
	Row = 32,
	Check = 18,
	Button = 34,
	Field = 32,
	Option = 32,
	Tab = 38,
	Bind = 28,
	BindWidth = 76,
	SwatchW = 44,
	SwatchH = 24,
	Bar = 12,
	BarHit = 32,
	Hue = 28,
	Spacing = 8,
}

local NOTIFY_COLORS = {
	Success = Color3.fromRGB(90, 200, 120),
	Warning = Color3.fromRGB(235, 180, 60),
	Error = Color3.fromRGB(235, 85, 85),
}

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function create(className, props, children)
	local inst = Instance.new(className)
	local parent
	for key, value in pairs(props or {}) do
		if key == "Parent" then
			parent = value
		else
			inst[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function tween(inst, duration, props, style)
	local t = TweenService:Create(
		inst,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end

local function addStroke(parent, color)
	return create("UIStroke", {
		Color = color,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

local function addPadding(parent, left, right, top, bottom)
	return create("UIPadding", {
		PaddingLeft = UDim.new(0, left or 0),
		PaddingRight = UDim.new(0, right or 0),
		PaddingTop = UDim.new(0, top or 0),
		PaddingBottom = UDim.new(0, bottom or 0),
		Parent = parent,
	})
end

local function addList(parent, spacing)
	return create("UIListLayout", {
		Padding = UDim.new(0, spacing or 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

local function isPointer(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
end

-- Functions that are told about errors in callbacks (see the OnError and
-- NotifyErrors options of Library.new).
local errorListeners = {}

-- Runs a callback in its own thread, so a callback that yields or fails
-- cannot stop the menu. An error is written to the output and passed to the
-- error listeners.
local function safeCall(fn, ...)
	if typeof(fn) ~= "function" then
		return
	end
	local args = table.pack(...)
	task.spawn(function()
		local ok, err = pcall(fn, table.unpack(args, 1, args.n))
		if not ok then
			local message = tostring(err)
			warn("[NimbusUI] callback error: " .. message)
			for _, listener in ipairs(table.clone(errorListeners)) do
				task.spawn(listener, message)
			end
		end
	end)
end

-- Returns a copy of `list` without repeated values.
local function withoutDuplicates(list)
	local out = {}
	for _, item in ipairs(list) do
		if not table.find(out, item) then
			table.insert(out, item)
		end
	end
	return out
end

local function decimalsOf(step)
	local s = tostring(step)
	local dot = string.find(s, ".", 1, true)
	return dot and (#s - dot) or 0
end

local function getGuiParent()
	if typeof(gethui) == "function" then
		local ok, hui = pcall(gethui)
		if ok and hui then
			return hui
		end
	end
	local player = Players.LocalPlayer
	return player and player:WaitForChild("PlayerGui")
end

-- Config names: 1 to 32 letters, digits, spaces, hyphens or underscores.
local function isValidConfigName(name)
	return type(name) == "string" and #name >= 1 and #name <= 32 and string.match(name, "^[%w _%-]+$") ~= nil
end

local function hasFileSystem()
	return typeof(writefile) == "function" and typeof(readfile) == "function"
end

local function serialize(value)
	local kind = typeof(value)
	if kind == "Color3" then
		return { __type = "Color3", hex = value:ToHex() }
	elseif kind == "EnumItem" then
		-- tostring(EnumItem) is always "Enum.<EnumName>.<ItemName>"
		local enumName = string.match(tostring(value), "^Enum%.([%w_]+)%.")
		return { __type = "EnumItem", enum = enumName, name = value.Name }
	elseif kind == "table" then
		local out = {}
		for k, v in pairs(value) do
			out[k] = serialize(v)
		end
		return out
	end
	return value
end

local function deserialize(value)
	if type(value) ~= "table" then
		return value
	end
	if value.__type == "Color3" then
		local ok, color = pcall(Color3.fromHex, value.hex)
		return ok and color or nil
	elseif value.__type == "EnumItem" then
		local ok, item = pcall(function()
			local enumName = string.gsub(tostring(value.enum), "^Enum%.", "")
			return (Enum :: any)[enumName][value.name]
		end)
		return ok and item or nil
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = deserialize(v)
	end
	return out
end

------------------------------------------------------------------------
-- Library
------------------------------------------------------------------------

function Library.new(options)
	options = options or {}
	local self = setmetatable({}, Library)

	self.Theme = table.clone(DEFAULT_THEME)
	for key, value in pairs(options.Theme or {}) do
		self.Theme[key] = value
	end
	if options.Accent then
		self.Theme.Accent = options.Accent
	end

	self.Flags = {}
	self.ToggleKey = options.ToggleKey or Enum.KeyCode.Insert
	self.ConfigFolder = options.ConfigFolder or "NimbusUI"
	self.MaxNotifications = options.MaxNotifications or 5
	self.Open = true

	-- Touch mode: larger tap targets and long-press tooltips. Detected from the
	-- device unless TouchMode is given.
	if options.TouchMode ~= nil then
		self.Touch = options.TouchMode == true
	else
		self.Touch = UserInputService.TouchEnabled
	end
	self._m = self.Touch and TOUCH_METRICS or DESKTOP_METRICS
	self._scrollers = {}
	self._suppressUntil = 0
	self._tipToken = nil
	self._tipTouch = false

	self._setters = {}
	self._connections = {}
	self._accentHooks = {}
	self._keybinds = {}
	self._tabs = {}
	-- objects whose colour is data (a picked colour, a notification type), not theme
	self._fixedColors = setmetatable({}, { __mode = "k" })
	self._configManagers = {}
	self._store = nil
	self._notifications = {}
	self._notifyCount = 0
	self._activeDrag = nil
	self._listeningBind = nil

	local theme = self.Theme

	self.Gui = create("ScreenGui", {
		Name = "NimbusUI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 50,
		Parent = getGuiParent(),
	})

	-- Window ------------------------------------------------------------
	self.Main = create("Frame", {
		Name = "Main",
		Active = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = options.Size or UDim2.fromOffset(580, 420),
		BackgroundColor3 = theme.Background,
		BorderSizePixel = 0,
		Parent = self.Gui,
	})
	addStroke(self.Main, theme.Border)

	local accentLine = create("Frame", {
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		Parent = self.Main,
	})
	self:_trackAccent(accentLine, "BackgroundColor3")

	local topbar = create("Frame", {
		Position = UDim2.fromOffset(0, 2),
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		Parent = self.Main,
	})
	create("Frame", {
		Position = UDim2.new(0, 0, 1, -1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = theme.Border,
		BorderSizePixel = 0,
		Parent = topbar,
	})
	create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -20, 1, 0),
		Font = theme.FontBold,
		TextSize = theme.TextSize,
		TextColor3 = theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = options.Title or "Nimbus UI",
		Parent = topbar,
	})
	if options.Subtitle then
		create("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -20, 1, 0),
			Font = theme.Font,
			TextSize = 12,
			TextColor3 = theme.SubText,
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = options.Subtitle,
			Parent = topbar,
		})
	end
	self:_makeDraggable(topbar, self.Main)

	local body = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 1, -30),
		Parent = self.Main,
	})
	self._sidebar = create("Frame", {
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 120, 1, 0),
		Parent = body,
	})
	addPadding(self._sidebar, 6, 6, 6, 6)
	addList(self._sidebar, 2)
	create("Frame", {
		Position = UDim2.fromOffset(120, 0),
		Size = UDim2.new(0, 1, 1, 0),
		BackgroundColor3 = theme.Border,
		BorderSizePixel = 0,
		Parent = body,
	})
	self._content = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(121, 0),
		Size = UDim2.new(1, -121, 1, 0),
		Parent = body,
	})

	-- Shrink the window when the screen is smaller than it (phones).
	local windowScale = create("UIScale", { Parent = self.Main })
	local function fitWindow()
		local screen = self.Gui.AbsoluteSize
		local size = self.Main.Size
		if screen.X <= 0 or screen.Y <= 0 or size.X.Offset <= 0 or size.Y.Offset <= 0 then
			return
		end
		windowScale.Scale = math.min(1, (screen.X - 16) / size.X.Offset, (screen.Y - 16) / size.Y.Offset)
	end
	fitWindow()
	self:_connect(self.Gui:GetPropertyChangedSignal("AbsoluteSize"), fitWindow)

	-- On-screen open/close button (on by default on touch devices).
	local wantButton = options.MobileButton
	if wantButton == nil then
		wantButton = UserInputService.TouchEnabled
	end
	if wantButton then
		self:_createMobileButton()
	end

	-- Tooltip -------------------------------------------------------------
	self._tooltip = create("TextLabel", {
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		Font = theme.Font,
		TextSize = 12,
		TextColor3 = theme.Text,
		Text = "",
		Visible = false,
		ZIndex = 100,
		Parent = self.Gui,
	})
	addStroke(self._tooltip, theme.Border)
	addPadding(self._tooltip, 6, 6, 4, 4)

	-- Notifications -------------------------------------------------------
	local onTop = options.NotifyPosition == "TopRight"
	self._notifyHolder = create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, onTop and 0 or 1),
		Position = onTop and UDim2.new(1, -12, 0, 12) or UDim2.new(1, -12, 1, -12),
		Size = UDim2.new(0, 270, 1, -24),
		ZIndex = 90,
		Parent = self.Gui,
	})
	local notifyLayout = addList(self._notifyHolder, 6)
	notifyLayout.VerticalAlignment = onTop and Enum.VerticalAlignment.Top or Enum.VerticalAlignment.Bottom
	notifyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right

	self:SetConfigStore(options.ConfigStore)

	-- Callback errors: always written to the output. NotifyErrors also shows
	-- them as a notification (on by default in Studio), and OnError(message)
	-- lets the game handle them.
	local notifyErrors = options.NotifyErrors
	if notifyErrors == nil then
		notifyErrors = RunService:IsStudio()
	end
	if notifyErrors or typeof(options.OnError) == "function" then
		self._errorListener = function(message)
			if notifyErrors then
				self:Notify({ Title = "Callback error", Text = message, Type = "Error", Duration = 8 })
			end
			if typeof(options.OnError) == "function" then
				local ok, err = pcall(options.OnError, message)
				if not ok then
					warn("[NimbusUI] OnError failed: " .. tostring(err))
				end
			end
		end
		table.insert(errorListeners, self._errorListener)
	end

	-- Global input --------------------------------------------------------
	self:_connect(UserInputService.InputBegan, function(input, gameProcessed)
		if self._listeningBind then
			self._listeningBind(input)
			return
		end
		if gameProcessed then
			return
		end
		if self.ToggleKey and self.ToggleKey ~= Enum.KeyCode.Unknown and input.KeyCode == self.ToggleKey then
			self:SetOpen(not self.Open)
		end
		for _, bind in ipairs(self._keybinds) do
			bind.began(input)
		end
	end)

	self:_connect(UserInputService.InputEnded, function(input)
		if isPointer(input) then
			self._activeDrag = nil
			self:_setScrollLock(false)
		end
		if input.UserInputType == Enum.UserInputType.Touch then
			self:_endTouchTooltip()
		end
		for _, bind in ipairs(self._keybinds) do
			bind.ended(input)
		end
	end)

	self:_connect(UserInputService.InputChanged, function(input)
		if not isMove(input) then
			return
		end
		if self._activeDrag then
			self._activeDrag(input)
		end
		if self._tooltip.Visible and not self._tipTouch then
			self:_placeTooltip(input.Position.X, input.Position.Y)
		end
	end)

	return self
end

function Library:_connect(signal, fn)
	local connection = signal:Connect(fn)
	table.insert(self._connections, connection)
	return connection
end

function Library:_onAccent(fn)
	table.insert(self._accentHooks, fn)
end

function Library:_trackAccent(inst, property)
	self:_onAccent(function(color)
		inst[property] = color
	end)
end

function Library:_beginDrag(fn, input)
	self._activeDrag = fn
	-- stop the columns from scrolling while a slider or picker is dragged
	self:_setScrollLock(true)
	fn(input)
end

function Library:_setScrollLock(locked)
	for _, scroller in ipairs(self._scrollers) do
		scroller.ScrollingEnabled = not locked
	end
end

-- Connects a click handler that is skipped when the press was a long-press
-- used to read a tooltip.
function Library:_onClick(button, fn)
	button.MouseButton1Click:Connect(function()
		if os.clock() < self._suppressUntil then
			return
		end
		fn()
	end)
end

-- A small draggable button that shows or hides the menu. Tap to toggle.
function Library:_createMobileButton()
	local theme = self.Theme
	local button = create("TextButton", {
		Name = "MobileButton",
		AutoButtonColor = false,
		Text = "",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		ZIndex = 80,
		Parent = self.Gui,
	})
	create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = button })
	addStroke(button, theme.Border)
	for i = 0, 2 do
		local line = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, (i - 1) * 7),
			Size = UDim2.fromOffset(20, 2),
			BackgroundColor3 = theme.Accent,
			BorderSizePixel = 0,
			ZIndex = 81,
			Parent = button,
		})
		self:_trackAccent(line, "BackgroundColor3")
	end

	local dragged = false
	button.InputBegan:Connect(function(input)
		if not isPointer(input) then
			return
		end
		dragged = false
		local startPos = input.Position
		local startFrame = button.Position
		self._activeDrag = function(move)
			local delta = move.Position - startPos
			if not dragged and math.abs(delta.X) + math.abs(delta.Y) < 8 then
				return -- still a tap
			end
			dragged = true
			button.Position = UDim2.new(
				startFrame.X.Scale,
				startFrame.X.Offset + delta.X,
				startFrame.Y.Scale,
				startFrame.Y.Offset + delta.Y
			)
		end
	end)
	button.MouseButton1Click:Connect(function()
		if not dragged then
			self:SetOpen(not self.Open)
		end
	end)

	self.MobileButton = button
	return button
end

function Library:_makeDraggable(handle, target)
	handle.InputBegan:Connect(function(input)
		if not isPointer(input) then
			return
		end
		local startPos = input.Position
		local startFrame = target.Position
		self._activeDrag = function(move)
			local delta = move.Position - startPos
			target.Position = UDim2.new(
				startFrame.X.Scale,
				startFrame.X.Offset + delta.X,
				startFrame.Y.Scale,
				startFrame.Y.Offset + delta.Y
			)
		end
	end)
end

function Library:_attachTooltip(inst, text)
	if not text or text == "" then
		return
	end
	inst.MouseEnter:Connect(function()
		-- touches can fire MouseEnter without a matching MouseLeave
		if UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch then
			self:_showTooltip(text)
		end
	end)
	inst.MouseLeave:Connect(function()
		if not self._tipTouch then
			self:_hideTooltip()
		end
	end)

	-- Touch has no hover: press and hold to read the tooltip. The release of
	-- that press does not click the element.
	inst.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local token = {}
		self._tipToken = token
		local start = input.Position
		task.delay(0.45, function()
			if self._tipToken ~= token then
				return -- released, or another press started
			end
			local delta = input.Position - start
			if math.abs(delta.X) + math.abs(delta.Y) > 12 then
				return -- the finger moved: a drag or a scroll, not a hold
			end
			self._tipTouch = true
			self._suppressUntil = math.huge
			self._activeDrag = nil
			-- above the finger so it is not covered
			self:_showTooltip(text, input.Position.X - 14, input.Position.Y - 64)
		end)
	end)
end

function Library:_endTouchTooltip()
	local token = self._tipToken
	self._tipToken = nil
	if not self._tipTouch then
		return
	end
	self._tipTouch = false
	-- swallow the click that the release of the long-press produces
	self._suppressUntil = os.clock() + 0.15
	task.delay(1.5, function()
		if not self._tipTouch and (self._tipToken == nil or self._tipToken == token) then
			self:_hideTooltip()
		end
	end)
end

-- Pointer position in the ScreenGui's coordinate space.
function Library:_pointerPosition()
	local position = UserInputService:GetMouseLocation()
	if not self.Gui.IgnoreGuiInset then
		-- GetMouseLocation counts the top bar inset; ScreenGui offsets do not
		position -= GuiService:GetGuiInset()
	end
	return position
end

-- Puts the tooltip next to (x, y) and keeps it on screen.
function Library:_placeTooltip(x, y)
	local tip = self._tooltip
	local screen = self.Gui.AbsoluteSize
	local size = tip.AbsoluteSize
	local px, py = x + 14, y + 12
	if px + size.X > screen.X - 4 then
		px = x - size.X - 8
	end
	if py + size.Y > screen.Y - 4 then
		py = y - size.Y - 8
	end
	tip.Position = UDim2.fromOffset(math.max(px, 4), math.max(py, 4))
end

-- Shows the tooltip at (x, y), or at the pointer when no position is given,
-- so it never appears at a stale position.
function Library:_showTooltip(text, x, y)
	if not x or not y then
		local pointer = self:_pointerPosition()
		x, y = pointer.X, pointer.Y
	end
	local tip = self._tooltip
	tip.Text = text
	self:_placeTooltip(x, y)
	tip.Visible = true
	-- the label resizes to the new text a moment later; place it again then
	task.defer(function()
		if tip.Visible and tip.Text == text then
			self:_placeTooltip(x, y)
		end
	end)
end

function Library:_hideTooltip()
	self._tooltip.Visible = false
end

function Library:_registerFlag(flag, value, setter)
	if not flag then
		return
	end
	self.Flags[flag] = value
	self._setters[flag] = setter
end

function Library:_updateFlag(flag, value)
	if flag then
		self.Flags[flag] = value
	end
end

function Library:SetOpen(open)
	self.Open = open
	self.Main.Visible = open
	if not open then
		self:_hideTooltip()
	end
end

-- Changes theme colours while the menu is open. `changes` is a table with any
-- of: Background, Panel, Section, Element, Hover, Border, Text, SubText, Accent.
--   UI:SetTheme({ Background = Color3.fromRGB(12, 16, 28), Text = Color3.new(1, 1, 1) })
--   UI:SetTheme(Library.DefaultTheme) -- back to the defaults
function Library:SetTheme(changes)
	if type(changes) ~= "table" then
		return
	end
	local theme = self.Theme
	local old = {}
	for _, key in ipairs(THEME_COLOR_KEYS) do
		old[key] = theme[key]
		if typeof(changes[key]) == "Color3" then
			theme[key] = changes[key]
		end
	end

	-- Every themed object currently shows one of the old colours; move it to
	-- the new colour of the same theme key. Elements read the theme table when
	-- their state changes, so later changes use the new colours too.
	for _, inst in ipairs(self.Gui:GetDescendants()) do
		local properties = THEMED_PROPERTIES[inst.ClassName]
		if properties and not self._fixedColors[inst] then
			for _, property in ipairs(properties) do
				local current = inst[property]
				for _, key in ipairs(THEME_KEYS_FOR[property]) do
					if current == old[key] then
						if theme[key] ~= current then
							inst[property] = theme[key]
						end
						break
					end
				end
			end
		end
	end

	if typeof(changes.Accent) == "Color3" then
		self:SetAccent(changes.Accent)
	end
end

function Library:SetAccent(color)
	self.Theme.Accent = color
	for _, hook in ipairs(self._accentHooks) do
		pcall(hook, color)
	end
end

function Library:Destroy()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	table.clear(self._keybinds)
	local listenerIndex = table.find(errorListeners, self._errorListener)
	if listenerIndex then
		table.remove(errorListeners, listenerIndex)
	end
	self._activeDrag = nil
	self._listeningBind = nil
	self.Gui:Destroy()
end

------------------------------------------------------------------------
-- Notifications
------------------------------------------------------------------------

function Library:Notify(opts)
	if type(opts) == "string" then
		opts = { Text = opts }
	end
	opts = opts or {}

	local theme = self.Theme
	local duration = tonumber(opts.Duration) or 4
	-- A persistent notification stays until it is clicked or :Close() is called.
	local persistent = opts.Persistent == true or duration <= 0 or duration == math.huge
	local color = NOTIFY_COLORS[opts.Type or ""] or theme.Accent

	self._notifyCount += 1

	local toast = create("CanvasGroup", {
		BackgroundColor3 = theme.Section,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		GroupTransparency = 1,
		LayoutOrder = self._notifyCount,
		Parent = self._notifyHolder,
	})
	create("UICorner", { CornerRadius = UDim.new(0, 3), Parent = toast })

	local stripe = create("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 2, 1, 0),
		Parent = toast,
	})
	self._fixedColors[stripe] = true

	local inner = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = toast,
	})
	addPadding(inner, 12, 10, 8, 10)
	addList(inner, 2)

	if opts.Title then
		create("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 14),
			Font = theme.FontBold,
			TextSize = theme.TextSize,
			TextColor3 = theme.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = opts.Title,
			LayoutOrder = 1,
			Parent = inner,
		})
	end
	create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = theme.Font,
		TextSize = 12,
		TextColor3 = theme.SubText,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = opts.Text or "",
		LayoutOrder = 2,
		Parent = inner,
	})

	local progress = create("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 2),
		Visible = not persistent,
		Parent = toast,
	})

	self._fixedColors[progress] = true

	local entry = { Persistent = persistent }
	local closed = false
	function entry.Close()
		if closed then
			return
		end
		closed = true
		local index = table.find(self._notifications, entry)
		if index then
			table.remove(self._notifications, index)
		end
		local fade = tween(toast, 0.25, { GroupTransparency = 1 })
		fade.Completed:Connect(function()
			toast:Destroy()
		end)
	end

	toast.InputBegan:Connect(function(input)
		if isPointer(input) then
			entry.Close()
		end
	end)

	tween(toast, 0.25, { GroupTransparency = 0 })
	if not persistent then
		tween(progress, duration, { Size = UDim2.new(0, 0, 0, 2) }, Enum.EasingStyle.Linear)
		task.delay(duration, entry.Close)
	end

	table.insert(self._notifications, entry)
	if #self._notifications > self.MaxNotifications then
		-- make room: close the oldest timed notification, or the oldest one if
		-- every notification is persistent
		local oldest = self._notifications[1]
		for _, other in ipairs(self._notifications) do
			if not other.Persistent and other ~= entry then
				oldest = other
				break
			end
		end
		oldest.Close()
	end

	return entry
end

------------------------------------------------------------------------
-- Configs
------------------------------------------------------------------------

function Library:ExportConfig()
	local data = {}
	for flag, value in pairs(self.Flags) do
		data[flag] = serialize(value)
	end
	return HttpService:JSONEncode(data)
end

-- Applies a JSON config. Unknown flags are skipped, and a value that an
-- element cannot use is ignored, so a damaged config cannot break the menu.
function Library:ApplyConfig(json)
	if type(json) ~= "string" then
		return false
	end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, json)
	if not ok or type(data) ~= "table" then
		return false
	end
	for flag, raw in pairs(data) do
		local setter = self._setters[flag]
		if setter then
			local applied, err = pcall(setter, deserialize(raw))
			if not applied then
				warn("[NimbusUI] could not apply flag '" .. tostring(flag) .. "': " .. tostring(err))
			end
		end
	end
	return true
end

-- Config stores ----------------------------------------------------------
-- A config store is a table of four functions. They may yield, so a store can
-- talk to the server (see examples/ConfigStore.client.lua):
--   Save(name, json) -> boolean      Load(name) -> json string or nil
--   List() -> { name, ... }          Delete(name) -> boolean

-- Keeps configs in memory until the player leaves. This is the default.
local function newMemoryStore()
	local configs = {}
	return {
		Save = function(name, json)
			configs[name] = json
			return true
		end,
		Load = function(name)
			return configs[name]
		end,
		List = function()
			local names = {}
			for name in pairs(configs) do
				table.insert(names, name)
			end
			return names
		end,
		Delete = function(name)
			local existed = configs[name] ~= nil
			configs[name] = nil
			return existed
		end,
	}
end

-- Keeps configs as files, in environments that have file functions.
local function newFileStore(folder)
	local saved = {} -- names saved this session, for environments without listfiles
	local function path(name)
		return folder .. "/" .. name .. ".json"
	end
	return {
		Save = function(name, json)
			if typeof(isfolder) == "function" and typeof(makefolder) == "function" and not isfolder(folder) then
				makefolder(folder)
			end
			writefile(path(name), json)
			saved[name] = true
			return true
		end,
		Load = function(name)
			return readfile(path(name))
		end,
		List = function()
			local names = {}
			if typeof(listfiles) == "function" then
				for _, file in ipairs(listfiles(folder)) do
					local name = string.match(file, "([^/\\]+)%.json$")
					if name then
						table.insert(names, name)
					end
				end
			else
				for name in pairs(saved) do
					table.insert(names, name)
				end
			end
			return names
		end,
		Delete = function(name)
			saved[name] = nil
			if typeof(delfile) == "function" then
				delfile(path(name))
				return true
			end
			return false
		end,
	}
end

-- Replaces where configs are kept. Pass nil to go back to the default store.
function Library:SetConfigStore(store)
	if store == nil then
		store = hasFileSystem() and newFileStore(self.ConfigFolder) or newMemoryStore()
	end
	for _, name in ipairs({ "Save", "Load", "List", "Delete" }) do
		if type(store) ~= "table" or type(store[name]) ~= "function" then
			error("[NimbusUI] a config store needs the function " .. name, 2)
		end
	end
	self._store = store
	self:_configsChanged()
end

-- Tells every config manager to read the list of configs again.
function Library:_configsChanged(selectName)
	for _, manager in ipairs(self._configManagers) do
		manager:Refresh(selectName)
	end
end

-- Saves the current settings under `name`. Returns true when it worked.
-- Yields if the config store yields.
function Library:SaveConfig(name)
	name = name or "default"
	if not isValidConfigName(name) then
		return false
	end
	local ok, result = pcall(self._store.Save, name, self:ExportConfig())
	local saved = ok and result ~= false and result ~= nil
	if saved then
		self:_configsChanged(name)
	end
	return saved
end

-- Loads the settings saved under `name`. Returns true when it worked.
function Library:LoadConfig(name)
	name = name or "default"
	if not isValidConfigName(name) then
		return false
	end
	local ok, json = pcall(self._store.Load, name)
	if not ok or type(json) ~= "string" then
		return false
	end
	return self:ApplyConfig(json)
end

-- Returns the names of the saved configs, sorted.
function Library:ListConfigs()
	local ok, result = pcall(self._store.List)
	local names = {}
	if ok and type(result) == "table" then
		for _, name in ipairs(result) do
			if isValidConfigName(name) and not table.find(names, name) then
				table.insert(names, name)
			end
		end
	end
	table.sort(names)
	return names
end

-- Deletes the config saved under `name`. Returns true when it worked.
function Library:DeleteConfig(name)
	if not isValidConfigName(name) then
		return false
	end
	local ok, result = pcall(self._store.Delete, name)
	local deleted = ok and result ~= false and result ~= nil
	if deleted then
		self:_configsChanged()
	end
	return deleted
end

------------------------------------------------------------------------
-- Tabs
------------------------------------------------------------------------

function Library:Tab(name)
	local theme = self.Theme
	local tab = setmetatable({ Library = self, Name = name, Selected = false }, Tab)

	tab.Button = create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, self._m.Tab),
		Font = theme.Font,
		TextSize = theme.TextSize,
		TextColor3 = theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = name,
		LayoutOrder = #self._tabs + 1,
		Parent = self._sidebar,
	})
	addPadding(tab.Button, 12, 0, 0, 0)

	tab.Indicator = create("Frame", {
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		Position = UDim2.new(0, -12, 0, 5),
		Size = UDim2.new(0, 2, 1, -10),
		Visible = false,
		Parent = tab.Button,
	})
	self:_trackAccent(tab.Indicator, "BackgroundColor3")

	tab.Page = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = self._content,
	})

	local function column(xScale, xOffset)
		local col = create("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.new(xScale, xOffset, 0, 8),
			Size = UDim2.new(0.5, -12, 1, -16),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 2,
			ScrollBarImageColor3 = theme.Border,
			Parent = tab.Page,
		})
		addList(col, 8)
		addPadding(col, 1, 4, 1, 1)
		table.insert(self._scrollers, col)
		return col
	end
	tab.Left = column(0, 8)
	tab.Right = column(0.5, 4)

	self:_onClick(tab.Button, function()
		self:_selectTab(tab)
	end)
	tab.Button.MouseEnter:Connect(function()
		if not tab.Selected then
			tween(tab.Button, 0.15, { TextColor3 = theme.Text })
		end
	end)
	tab.Button.MouseLeave:Connect(function()
		if not tab.Selected then
			tween(tab.Button, 0.15, { TextColor3 = theme.SubText })
		end
	end)

	table.insert(self._tabs, tab)
	if #self._tabs == 1 then
		self:_selectTab(tab)
	end
	return tab
end

function Library:_selectTab(tab)
	local theme = self.Theme
	for _, other in ipairs(self._tabs) do
		local active = other == tab
		other.Selected = active
		other.Page.Visible = active
		other.Indicator.Visible = active
		other.Button.TextColor3 = active and theme.Text or theme.SubText
		other.Button.BackgroundColor3 = active and theme.Section or theme.Panel
	end
end

------------------------------------------------------------------------
-- Sections
------------------------------------------------------------------------

function Tab:Section(name, side)
	local lib = self.Library
	local theme = lib.Theme
	local m = lib._m
	local column = (side == "Right") and self.Right or self.Left

	local frame = create("Frame", {
		BackgroundColor3 = theme.Section,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = #column:GetChildren(),
		Parent = column,
	})
	addStroke(frame, theme.Border)
	addList(frame, 0)

	local header = create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 24),
		Font = theme.FontBold,
		TextSize = 12,
		TextColor3 = theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = name or "Section",
		LayoutOrder = 1,
		Parent = frame,
	})
	addPadding(header, 8, 8, 0, 0)

	local content = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = frame,
	})
	addPadding(content, 8, 8, 2, 8)
	addList(content, m.Spacing)

	return setmetatable({ Library = lib, Frame = frame, Content = content, _order = 0 }, Section)
end

function Section:_next()
	self._order += 1
	return self._order
end

-- Shows or hides the whole section.
function Section:SetVisible(visible)
	self.Frame.Visible = visible ~= false
end

function Section:IsVisible()
	return self.Frame.Visible
end

-- Gives an element its visibility API and applies the DependsOn option:
--   element:SetVisible(bool)   element:IsVisible()   element.Instance
-- An element is shown when SetVisible has not hidden it and, if DependsOn is
-- set, while that toggle is on and visible. The layouts skip hidden elements,
-- so the section closes the gap.
local function finishElement(element, root, opts)
	local wanted = true -- what SetVisible asked for
	local allowed = true -- what DependsOn allows
	local listeners = {}

	local function apply()
		local visible = wanted and allowed
		if root.Visible ~= visible then
			root.Visible = visible
			for _, listener in ipairs(listeners) do
				listener(visible)
			end
		end
	end

	element.Instance = root
	function element:SetVisible(visible)
		wanted = visible ~= false
		apply()
	end
	function element:IsVisible()
		return wanted and allowed
	end
	function element:_onVisible(listener)
		table.insert(listeners, listener)
	end

	local dependency = type(opts) == "table" and opts.DependsOn or nil
	if dependency ~= nil then
		if type(dependency) == "table" and type(dependency.OnChanged) == "function" then
			local function check()
				allowed = dependency:Get() == true and dependency:IsVisible()
				apply()
			end
			dependency:OnChanged(check)
			-- follow the toggle's own visibility too, so chains of dependencies work
			dependency:_onVisible(check)
			check()
		else
			warn("[NimbusUI] DependsOn must be a toggle created by section:Toggle")
		end
	end
	return element
end

local function makeLabel(theme, props)
	local base = {
		BackgroundTransparency = 1,
		Font = theme.Font,
		TextSize = theme.TextSize,
		TextColor3 = theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for k, v in pairs(props) do
		base[k] = v
	end
	return create("TextLabel", base)
end

-- Slider ---------------------------------------------------------------
function Section:Slider(opts)
	opts = opts or {}
	local lib = self.Library
	local theme = lib.Theme
	local m = lib._m
	local min, max = opts.Min or 0, opts.Max or 100
	local step = opts.Step or 1
	local decimals = math.max(decimalsOf(step), decimalsOf(min))
	local suffix = opts.Suffix or ""

	local scale = 10 ^ decimals
	local function round(v)
		local snapped = math.clamp(min + math.floor((v - min) / step + 0.5) * step, min, max)
		-- remove floating point noise such as 0.30000000000000004
		return math.floor(snapped * scale + 0.5) / scale
	end
	local value = round(opts.Default or min)

	local holder = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 16 + m.BarHit),
		LayoutOrder = self:_next(),
		Parent = self.Content,
	})
	local valueWidth = lib.Touch and 96 or 72
	makeLabel(theme, {
		Size = UDim2.new(1, -(valueWidth + 4), 0, 14),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = opts.Name or "Slider",
		Parent = holder,
	})
	-- The value is a text box: click it to type an exact number.
	local valueBox = create("TextBox", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(valueWidth, 16),
		Font = theme.Font,
		TextSize = 12,
		TextColor3 = theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Right,
		ClearTextOnFocus = false,
		Text = "",
		Parent = holder,
	})
	local editing = false
	-- `hit` is the invisible drag area (taller on touch); `bar` is the track.
	local hit = create("TextButton", {
		AutoButtonColor = false,
		Text = "",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 0, m.BarHit),
		Parent = holder,
	})
	local bar = create("Frame", {
		BackgroundColor3 = theme.Element,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, m.Bar),
		Parent = hit,
	})
	addStroke(bar, theme.Border)
	local fill = create("Frame", {
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = bar,
	})
	lib:_trackAccent(fill, "BackgroundColor3")

	local function render()
		local pct = (max == min) and 0 or (value - min) / (max - min)
		fill.Size = UDim2.fromScale(pct, 1)
		if not editing then
			valueBox.Text = string.format("%." .. decimals .. "f", value) .. suffix
		end
	end

	local slider = {}
	function slider:Set(v, silent)
		value = round(tonumber(v) or min)
		render()
		lib:_updateFlag(opts.Flag, value)
		if not silent then
			safeCall(opts.Callback, value)
		end
	end
	function slider:Get()
		return value
	end

	local function fromInput(input)
		local pct = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
		local newValue = round(min + (max - min) * pct)
		if newValue ~= value then
			slider:Set(newValue)
		end
	end
	hit.InputBegan:Connect(function(input)
		if isPointer(input) then
			lib:_beginDrag(fromInput, input)
		end
	end)

	valueBox.Focused:Connect(function()
		editing = true
		valueBox.TextColor3 = theme.Text
		-- show the bare number, selected, so typing replaces it
		valueBox.Text = string.format("%." .. decimals .. "f", value)
		valueBox.CursorPosition = #valueBox.Text + 1
		valueBox.SelectionStart = 1
	end)
	valueBox.FocusLost:Connect(function()
		editing = false
		valueBox.TextColor3 = theme.SubText
		-- accept "42", "42.5", "42,5" and "42%"; anything else is ignored
		local text = string.gsub(valueBox.Text, ",", ".")
		local typed = tonumber(string.match(text, "^%s*(%-?%d*%.?%d+)"))
		if typed and round(typed) ~= value then
			slider:Set(typed) -- clamps to Min/Max and snaps to Step
		else
			render()
		end
	end)

	render()
	lib:_attachTooltip(holder, opts.Tooltip)
	lib:_registerFlag(opts.Flag, value, function(v)
		slider:Set(v)
	end)
	return finishElement(slider, holder, opts)
end

-- Dropdown -------------------------------------------------------------
function Section:Dropdown(opts)
	opts = opts or {}
	local lib = self.Library
	local theme = lib.Theme
	local m = lib._m
	local multi = opts.Multi == true
	local options = withoutDuplicates(opts.Options or {})
	local value = multi and {} or nil
	local open = false

	local holder = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = self:_next(),
		Parent = self.Content,
	})
	addList(holder, 3)
	makeLabel(theme, {
		Size = UDim2.new(1, 0, 0, 14),
		Text = opts.Name or "Dropdown",
		LayoutOrder = 1,
		Parent = holder,
	})
	local header = create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = theme.Element,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, m.Field),
		Font = theme.Font,
		TextSize = 12,
		TextColor3 = theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
		LayoutOrder = 2,
		Parent = holder,
	})
	local headerStroke = addStroke(header, theme.Border)
	addPadding(header, 6, 18, 0, 0)
	local arrow = makeLabel(theme, {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(1, 4, 0, 0),
		Size = UDim2.new(0, 10, 1, 0),
		TextSize = 12,
		TextColor3 = theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "+",
		Parent = header,
	})

	-- The option list scrolls once it has more than `maxVisible` rows.
	local optionHeight = m.Option
	local maxVisible = math.max(1, math.floor(tonumber(opts.MaxVisible) or 8))
	local list = create("ScrollingFrame", {
		BackgroundColor3 = theme.Element,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = theme.SubText,
		Visible = false,
		LayoutOrder = 3,
		Parent = holder,
	})
	addStroke(list, theme.Border)
	table.insert(lib._scrollers, list)
	addList(list, 0)
	addPadding(list, 0, 0, 2, 2)

	local dropdown = {}
	local optionButtons = {}

	local function isSelected(option)
		if multi then
			return table.find(value, option) ~= nil
		end
		return value == option
	end

	local function display()
		if multi then
			local names = {}
			for _, item in ipairs(value) do
				table.insert(names, tostring(item))
			end
			header.Text = (#names > 0) and table.concat(names, ", ") or "None"
		else
			header.Text = value ~= nil and tostring(value) or "None"
		end
		for option, button in pairs(optionButtons) do
			button.TextColor3 = isSelected(option) and theme.Accent or theme.SubText
		end
	end
	lib:_onAccent(display)

	local function setOpen(state)
		open = state
		list.Visible = open
		arrow.Text = open and "-" or "+"
		headerStroke.Color = open and theme.Accent or theme.Border
	end

	local function build()
		for _, button in pairs(optionButtons) do
			button:Destroy()
		end
		table.clear(optionButtons)
		for i, option in ipairs(options) do
			local button = create("TextButton", {
				AutoButtonColor = false,
				BackgroundColor3 = theme.Hover,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, optionHeight),
				Font = theme.Font,
				TextSize = 12,
				TextColor3 = theme.SubText,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = tostring(option),
				LayoutOrder = i,
				Parent = list,
			})
			addPadding(button, 8, 0, 0, 0)
			button.MouseEnter:Connect(function()
				button.BackgroundTransparency = 0
			end)
			button.MouseLeave:Connect(function()
				button.BackgroundTransparency = 1
			end)
			lib:_onClick(button, function()
				if multi then
					local nextValue = table.clone(value)
					local index = table.find(nextValue, option)
					if index then
						table.remove(nextValue, index)
					else
						table.insert(nextValue, option)
					end
					dropdown:Set(nextValue)
				else
					dropdown:Set(option)
					setOpen(false)
				end
			end)
			optionButtons[option] = button
		end
		-- 4 = the list's top and bottom padding
		list.Size = UDim2.new(1, 0, 0, math.min(#options, maxVisible) * optionHeight + 4)
		list.CanvasPosition = Vector2.new(0, 0)
		display()
	end

	function dropdown:Set(v, silent)
		if multi then
			local selected = {}
			for _, item in ipairs(type(v) == "table" and v or { v }) do
				if table.find(options, item) and not table.find(selected, item) then
					table.insert(selected, item)
				end
			end
			value = selected
		else
			if v ~= nil and not table.find(options, v) then
				v = nil
			end
			value = v
		end
		display()
		local out = multi and table.clone(value) or value
		lib:_updateFlag(opts.Flag, out)
		if not silent then
			safeCall(opts.Callback, multi and table.clone(value) or value)
		end
	end
	function dropdown:Get()
		return multi and table.clone(value) or value
	end
	-- Replaces the options. A selection that is still in the new list is kept;
	-- one that is not is dropped, and Callback runs because the value changed.
	function dropdown:Refresh(newOptions)
		local before = value
		options = withoutDuplicates(newOptions or {})
		build()
		dropdown:Set(value, true)
		local changed
		if multi then
			changed = #value ~= #before
		else
			changed = value ~= before
		end
		if changed then
			safeCall(opts.Callback, dropdown:Get())
		end
	end

	lib:_onClick(header, function()
		setOpen(not open)
	end)

	build()
	dropdown:Set(opts.Default, true)
	lib:_attachTooltip(header, opts.Tooltip)
	lib:_registerFlag(opts.Flag, dropdown:Get(), function(v)
		dropdown:Set(v)
	end)
	return finishElement(dropdown, holder, opts)
end

-- Keybind --------------------------------------------------------------

-- Builds a keybind button inside `parent` and wires up its behaviour.
-- Shared by Section:Keybind and toggle:AddKeybind. `props` overrides the
-- button's default properties.
local function buildKeybind(lib, parent, opts, props)
	local theme = lib.Theme
	local m = lib._m
	local key = opts.Default
	local mode = opts.Mode or "Press"
	local active = false

	local buttonProps = {
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(m.BindWidth, m.Bind),
		BackgroundColor3 = theme.Element,
		BorderSizePixel = 0,
		Font = theme.Font,
		TextSize = 11,
		TextColor3 = theme.SubText,
		Text = "[None]",
		Parent = parent,
	}
	for k, v in pairs(props or {}) do
		buttonProps[k] = v
	end
	local button = create("TextButton", buttonProps)
	addStroke(button, theme.Border)

	local function keyName(k)
		if not k then
			return "None"
		end
		return (k.Name:gsub("MouseButton", "MB"))
	end

	local function render()
		button.Text = "[" .. keyName(key) .. "]"
		button.TextColor3 = theme.SubText
	end

	local bind = {}
	function bind:Set(k, silent)
		key = k or nil
		active = false
		render()
		lib:_updateFlag(opts.Flag, key or false)
		if not silent then
			safeCall(opts.Changed, key)
		end
	end
	function bind:Get()
		return key
	end
	function bind:IsActive()
		return active
	end

	local function matches(input)
		if not key then
			return false
		end
		if key.EnumType == Enum.KeyCode then
			return input.KeyCode == key
		end
		return input.UserInputType == key
	end

	lib:_onClick(button, function()
		button.Text = "[...]"
		button.TextColor3 = theme.Accent
		lib._listeningBind = function(input)
			local inputType = input.UserInputType
			if inputType == Enum.UserInputType.Keyboard then
				lib._listeningBind = nil
				if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Backspace then
					bind:Set(nil)
				else
					bind:Set(input.KeyCode)
				end
			elseif inputType == Enum.UserInputType.MouseButton2 or inputType == Enum.UserInputType.MouseButton3 then
				lib._listeningBind = nil
				bind:Set(inputType)
			elseif inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
				lib._listeningBind = nil
				render()
			end
		end
	end)

	table.insert(lib._keybinds, {
		began = function(input)
			if not matches(input) then
				return
			end
			if mode == "Toggle" then
				active = not active
				safeCall(opts.Callback, active)
			elseif mode == "Hold" then
				active = true
				safeCall(opts.Callback, true)
			else
				safeCall(opts.Callback)
			end
		end,
		ended = function(input)
			if mode == "Hold" and active and matches(input) then
				active = false
				safeCall(opts.Callback, false)
			end
		end,
	})

	render()
	lib:_registerFlag(opts.Flag, key or false, function(v)
		-- configs can hold anything; only accept a key or mouse button
		bind:Set(typeof(v) == "EnumItem" and v or nil)
	end)
	return bind, button
end

function Section:Keybind(opts)
	opts = opts or {}
	local lib = self.Library
	local theme = lib.Theme
	local m = lib._m

	local row = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, m.Row),
		LayoutOrder = self:_next(),
		Parent = self.Content,
	})
	makeLabel(theme, {
		Size = UDim2.new(1, -(m.BindWidth + 6), 1, 0),
		Text = opts.Name or "Keybind",
		Parent = row,
	})

	local bind = buildKeybind(lib, row, opts)
	lib:_attachTooltip(row, opts.Tooltip)
	return finishElement(bind, row, opts)
end

-- Color picker ---------------------------------------------------------

-- Builds a colour swatch inside `swatchParent` and the picker panel it opens
-- inside `panelParent`. Shared by Section:ColorPicker and toggle:AddColorPicker.
-- `swatchProps` overrides the swatch's default properties.
local function buildColorPicker(lib, swatchParent, panelParent, opts, swatchProps, panelOrder)
	local theme = lib.Theme
	local m = lib._m
	local color = opts.Default or Color3.new(1, 1, 1)
	local h, s, v = color:ToHSV()

	local props = {
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(m.SwatchW, m.SwatchH),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Text = "",
		Parent = swatchParent,
	}
	for k, value in pairs(swatchProps or {}) do
		props[k] = value
	end
	local swatch = create("TextButton", props)
	addStroke(swatch, theme.Border)

	local panel = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 108 + m.Field),
		Visible = false,
		LayoutOrder = panelOrder or 2,
		Parent = panelParent,
	})

	local sv = create("TextButton", {
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = Color3.fromHSV(h, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.new(1, -(m.Hue + 8), 0, 100),
		Parent = panel,
	})
	addStroke(sv, theme.Border)
	local whiteLayer = create("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = sv,
	})
	create("UIGradient", { Transparency = NumberSequence.new(0, 1), Parent = whiteLayer })
	local blackLayer = create("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = sv,
	})
	create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0), Parent = blackLayer })
	local svCursor = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(6, 6),
		BackgroundTransparency = 1,
		Parent = sv,
	})
	addStroke(svCursor, Color3.new(1, 1, 1))

	local hueBar = create("TextButton", {
		AutoButtonColor = false,
		Text = "",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, m.Hue, 0, 100),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = panel,
	})
	addStroke(hueBar, theme.Border)
	local keypoints = {}
	for i = 0, 6 do
		table.insert(keypoints, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((i / 6) % 1, 1, 1)))
	end
	create("UIGradient", { Rotation = 90, Color = ColorSequence.new(keypoints), Parent = hueBar })
	local hueCursor = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = hueBar,
	})

	for _, fixed in ipairs({ swatch, sv, whiteLayer, blackLayer, hueBar, hueCursor }) do
		lib._fixedColors[fixed] = true
	end

	local hexBox = create("TextBox", {
		BackgroundColor3 = theme.Element,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 106),
		Size = UDim2.new(1, 0, 0, m.Field),
		Font = theme.Font,
		TextSize = 12,
		TextColor3 = theme.Text,
		PlaceholderText = "#FFFFFF",
		ClearTextOnFocus = false,
		Text = "",
		Parent = panel,
	})
	addStroke(hexBox, theme.Border)

	local picker = {}
	local function render()
		color = Color3.fromHSV(h, s, v)
		sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
		swatch.BackgroundColor3 = color
		svCursor.Position = UDim2.fromScale(s, 1 - v)
		hueCursor.Position = UDim2.fromScale(0, h)
		hexBox.Text = "#" .. string.upper(color:ToHex())
	end
	local function commit(silent)
		render()
		lib:_updateFlag(opts.Flag, color)
		if not silent then
			safeCall(opts.Callback, color)
		end
	end

	function picker:Set(c, silent)
		if typeof(c) ~= "Color3" then
			return
		end
		h, s, v = c:ToHSV()
		commit(silent)
	end
	function picker:Get()
		return color
	end
	-- Opens or closes the picker panel.
	function picker:SetOpen(open)
		panel.Visible = open == true
	end

	sv.InputBegan:Connect(function(input)
		if not isPointer(input) then
			return
		end
		lib:_beginDrag(function(i)
			s = math.clamp((i.Position.X - sv.AbsolutePosition.X) / sv.AbsoluteSize.X, 0, 1)
			v = 1 - math.clamp((i.Position.Y - sv.AbsolutePosition.Y) / sv.AbsoluteSize.Y, 0, 1)
			commit()
		end, input)
	end)
	hueBar.InputBegan:Connect(function(input)
		if not isPointer(input) then
			return
		end
		lib:_beginDrag(function(i)
			h = math.clamp((i.Position.Y - hueBar.AbsolutePosition.Y) / hueBar.AbsoluteSize.Y, 0, 1)
			commit()
		end, input)
	end)
	hexBox.FocusLost:Connect(function()
		local ok, parsed = pcall(Color3.fromHex, hexBox.Text)
		if ok and parsed then
			picker:Set(parsed)
		else
			render()
		end
	end)
	lib:_onClick(swatch, function()
		panel.Visible = not panel.Visible
	end)

	render()
	lib:_registerFlag(opts.Flag, color, function(c)
		picker:Set(c)
	end)
	return picker, swatch, panel
end

function Section:ColorPicker(opts)
	opts = opts or {}
	local lib = self.Library
	local theme = lib.Theme
	local m = lib._m

	local holder = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = self:_next(),
		Parent = self.Content,
	})
	addList(holder, 4)

	local row = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, m.Row),
		LayoutOrder = 1,
		Parent = holder,
	})
	makeLabel(theme, {
		Size = UDim2.new(1, -(m.SwatchW + 8), 1, 0),
		Text = opts.Name or "Color",
		Parent = row,
	})

	local picker = buildColorPicker(lib, row, holder, opts)
	lib:_attachTooltip(row, opts.Tooltip)
	return finishElement(picker, holder, opts)
end

-- Toggle ---------------------------------------------------------------
function Section:Toggle(opts)
	opts = opts or {}
	local lib = self.Library
	local theme = lib.Theme
	local m = lib._m
	local state = opts.Default == true

	-- `holder` stacks the toggle row and any colour picker panels attached to it.
	local holder = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = self:_next(),
		Parent = self.Content,
	})
	addList(holder, 4)
	local row = create("TextButton", {
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, m.Row),
		Text = "",
		LayoutOrder = 1,
		Parent = holder,
	})
	local box = create("Frame", {
		BackgroundColor3 = theme.Element,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(m.Check, m.Check),
		Parent = row,
	})
	local boxStroke = addStroke(box, theme.Border)
	local fill = create("Frame", {
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		Visible = state,
		Parent = box,
	})
	lib:_trackAccent(fill, "BackgroundColor3")
	local label = makeLabel(theme, {
		Position = UDim2.fromOffset(m.Check + 8, 0),
		Size = UDim2.new(1, -(m.Check + 8), 1, 0),
		TextColor3 = state and theme.Text or theme.SubText,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = opts.Name or "Toggle",
		Parent = row,
	})

	local toggle = {}
	local changeListeners = {}
	function toggle:Set(value, silent)
		state = value == true
		fill.Visible = state
		label.TextColor3 = state and theme.Text or theme.SubText
		lib:_updateFlag(opts.Flag, state)
		-- listeners run on silent changes too, so dependent elements stay correct
		for _, listener in ipairs(changeListeners) do
			listener(state)
		end
		if not silent then
			safeCall(opts.Callback, state)
		end
	end
	-- Calls fn(state) every time the toggle changes. Returns a function that
	-- removes the listener.
	function toggle:OnChanged(fn)
		table.insert(changeListeners, fn)
		return function()
			local index = table.find(changeListeners, fn)
			if index then
				table.remove(changeListeners, index)
			end
		end
	end
	function toggle:Get()
		return state
	end

	-- Attachments: a keybind and/or colour swatch on the right of the row.
	local attach
	local attachCount = 0
	local attachWidth = 0
	local function attachProps(width)
		if not attach then
			attach = create("Frame", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.fromScale(0, 1),
				AutomaticSize = Enum.AutomaticSize.X,
				ZIndex = 2,
				Parent = row,
			})
			create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = attach,
			})
		end
		attachCount += 1
		attachWidth += width + 6
		-- keep the label clear of the attachments
		label.Size = UDim2.new(1, -(m.Check + 8) - attachWidth, 1, 0)
		return {
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.new(),
			ZIndex = 2,
			LayoutOrder = -attachCount, -- the first attachment sits furthest right
			Parent = attach,
		}
	end

	-- Adds an inline keybind. By default the key drives the toggle:
	--   Mode "Toggle" (default) or "Press": each press flips the toggle
	--   Mode "Hold": the toggle is on while the key is held
	-- Callback receives the toggle's new state. Pass Sync = false for a plain
	-- keybind that does not change the toggle.
	function toggle:AddKeybind(bindOpts)
		bindOpts = table.clone(bindOpts or {})
		local mode = bindOpts.Mode or "Toggle"
		local callback = bindOpts.Callback
		bindOpts.Mode = mode
		if bindOpts.Sync ~= false then
			bindOpts.Callback = function(held)
				if mode == "Hold" then
					toggle:Set(held == true)
				else
					toggle:Set(not state)
				end
				safeCall(callback, state)
			end
		end
		local bind, button = buildKeybind(lib, row, bindOpts, attachProps(m.BindWidth))
		lib:_attachTooltip(button, bindOpts.Tooltip)
		return finishElement(bind, button, bindOpts)
	end

	-- Adds an inline colour swatch. Its picker panel opens below the toggle row.
	function toggle:AddColorPicker(pickerOpts)
		pickerOpts = pickerOpts or {}
		local picker, swatch =
			buildColorPicker(lib, row, holder, pickerOpts, attachProps(m.SwatchW), attachCount + 2)
		lib:_attachTooltip(swatch, pickerOpts.Tooltip)
		return finishElement(picker, swatch, pickerOpts)
	end

	lib:_onClick(row, function()
		toggle:Set(not state)
	end)
	row.MouseEnter:Connect(function()
		boxStroke.Color = theme.Accent
	end)
	row.MouseLeave:Connect(function()
		boxStroke.Color = theme.Border
	end)
	lib:_attachTooltip(row, opts.Tooltip)
	lib:_registerFlag(opts.Flag, state, function(v)
		toggle:Set(v)
	end)
	return finishElement(toggle, holder, opts)
end

-- Textbox --------------------------------------------------------------
function Section:Textbox(opts)
	opts = opts or {}
	local lib = self.Library
	local theme = lib.Theme
	local m = lib._m
	local value = opts.Default or ""

	local holder = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 17 + m.Field),
		LayoutOrder = self:_next(),
		Parent = self.Content,
	})
	makeLabel(theme, {
		Size = UDim2.new(1, 0, 0, 14),
		Text = opts.Name or "Textbox",
		Parent = holder,
	})
	local box = create("TextBox", {
		BackgroundColor3 = theme.Element,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 17),
		Size = UDim2.new(1, 0, 0, m.Field),
		Font = theme.Font,
		TextSize = 12,
		TextColor3 = theme.Text,
		PlaceholderColor3 = theme.SubText,
		PlaceholderText = opts.Placeholder or "",
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Text = value,
		Parent = holder,
	})
	local boxStroke = addStroke(box, theme.Border)
	addPadding(box, 6, 6, 0, 0)

	local textbox = {}
	function textbox:Set(text, silent)
		value = tostring(text or "")
		box.Text = value
		lib:_updateFlag(opts.Flag, value)
		if not silent then
			safeCall(opts.Callback, value, false)
		end
	end
	function textbox:Get()
		return value
	end

	box.Focused:Connect(function()
		boxStroke.Color = theme.Accent
	end)
	box.FocusLost:Connect(function(enterPressed)
		boxStroke.Color = theme.Border
		value = box.Text
		lib:_updateFlag(opts.Flag, value)
		safeCall(opts.Callback, value, enterPressed)
	end)

	lib:_attachTooltip(box, opts.Tooltip)
	lib:_registerFlag(opts.Flag, value, function(text)
		textbox:Set(text)
	end)
	return finishElement(textbox, holder, opts)
end

-- Button ---------------------------------------------------------------
function Section:Button(opts)
	opts = opts or {}
	local lib = self.Library
	local theme = lib.Theme
	local m = lib._m

	local button = create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = theme.Element,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, m.Button),
		Font = theme.Font,
		TextSize = theme.TextSize,
		TextColor3 = theme.Text,
		Text = opts.Name or "Button",
		LayoutOrder = self:_next(),
		Parent = self.Content,
	})
	local stroke = addStroke(button, theme.Border)

	button.MouseEnter:Connect(function()
		tween(button, 0.12, { BackgroundColor3 = theme.Hover })
	end)
	button.MouseLeave:Connect(function()
		tween(button, 0.12, { BackgroundColor3 = theme.Element })
	end)
	lib:_onClick(button, function()
		stroke.Color = theme.Accent
		tween(stroke, 0.35, { Color = theme.Border })
		safeCall(opts.Callback)
	end)

	lib:_attachTooltip(button, opts.Tooltip)
	return finishElement({
		SetText = function(_, text)
			button.Text = text
		end,
	}, button, opts)
end

-- Label ----------------------------------------------------------------
-- Accepts a string, or a table { Text, DependsOn }.
function Section:Label(text, opts)
	if type(text) == "table" then
		opts = text
		text = opts.Text
	end
	local theme = self.Library.Theme
	local label = makeLabel(theme, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 12,
		TextColor3 = theme.SubText,
		TextWrapped = true,
		Text = text or "",
		LayoutOrder = self:_next(),
		Parent = self.Content,
	})
	return finishElement({
		Set = function(_, newText)
			label.Text = newText
		end,
	}, label, opts)
end

-- Config manager -------------------------------------------------------
-- A dropdown that lists the saved configs, a name box, and Save / Load /
-- Delete / Refresh buttons. Options: { Name, Default, Notify, DependsOn,
-- Callback(action, name, ok) } where action is "Save", "Load" or "Delete".
function Section:ConfigManager(opts)
	opts = opts or {}
	local lib = self.Library
	local manager = {}
	local busy = false
	local visible = true

	local function notify(title, text, kind)
		if opts.Notify ~= false then
			lib:Notify({ Title = title, Text = text, Type = kind })
		end
	end

	local nameBox
	local list = self:Dropdown({
		Name = opts.Name or "Saved configs",
		Options = {},
		Tooltip = opts.Tooltip,
		DependsOn = opts.DependsOn,
		Callback = function(name)
			if name and nameBox then
				nameBox:Set(name, true)
			end
		end,
	})
	nameBox = self:Textbox({
		Name = "Config name",
		Placeholder = "Type a name...",
		Default = opts.Default or "",
		DependsOn = opts.DependsOn,
	})

	-- Reads the list of configs again. Selects `selectName` when it exists.
	local refreshId = 0
	function manager:Refresh(selectName)
		refreshId += 1
		local id = refreshId
		task.spawn(function()
			local names = lib:ListConfigs() -- may yield
			if id ~= refreshId then
				return -- a newer refresh has started
			end
			list:Refresh(names)
			if selectName and table.find(names, selectName) then
				list:Set(selectName, true)
			end
		end)
	end

	local messages = {
		Save = { "Saved", "Saved the config \"%s\".", "Could not save the config \"%s\"." },
		Load = { "Loaded", "Loaded the config \"%s\".", "Could not load the config \"%s\"." },
		Delete = { "Deleted", "Deleted the config \"%s\".", "Could not delete the config \"%s\"." },
	}
	local function run(action, method)
		if busy then
			return
		end
		local name = string.match(nameBox:Get(), "^%s*(.-)%s*$")
		if not isValidConfigName(name) then
			notify("Config name", "Use 1 to 32 letters, digits, spaces, - or _.", "Warning")
			return
		end
		busy = true
		task.spawn(function()
			local ok = method(lib, name) -- may yield
			busy = false
			local message = messages[action]
			if ok then
				notify(message[1], string.format(message[2], name), "Success")
			else
				notify("Config", string.format(message[3], name), "Error")
			end
			safeCall(opts.Callback, action, name, ok)
		end)
	end

	local buttons = {
		self:Button({
			Name = "Save",
			DependsOn = opts.DependsOn,
			Callback = function()
				run("Save", lib.SaveConfig)
			end,
		}),
		self:Button({
			Name = "Load",
			DependsOn = opts.DependsOn,
			Callback = function()
				run("Load", lib.LoadConfig)
			end,
		}),
		self:Button({
			Name = "Delete",
			DependsOn = opts.DependsOn,
			Callback = function()
				run("Delete", lib.DeleteConfig)
			end,
		}),
		self:Button({
			Name = "Refresh list",
			DependsOn = opts.DependsOn,
			Callback = function()
				manager:Refresh()
			end,
		}),
	}

	manager.Dropdown = list
	manager.NameBox = nameBox
	-- The name in the box.
	function manager:Get()
		return nameBox:Get()
	end
	function manager:SetVisible(state)
		visible = state ~= false
		list:SetVisible(visible)
		nameBox:SetVisible(visible)
		for _, button in ipairs(buttons) do
			button:SetVisible(visible)
		end
	end
	function manager:IsVisible()
		return visible and list:IsVisible()
	end

	table.insert(lib._configManagers, manager)
	manager:Refresh()
	return manager
end

return Library
