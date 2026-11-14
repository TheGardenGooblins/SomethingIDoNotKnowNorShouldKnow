--[[
	Nimbus UI — a compact, flat dark UI library for Roblox (Luau)

	Setup: put this in a ModuleScript (e.g. ReplicatedStorage.NimbusUI)
	and require it from a LocalScript. See NimbusUI_Demo.lua for every element.

	API overview
		local UI = Library.new({ Title, Subtitle, Size, Accent, ToggleKey, NotifyPosition, ConfigFolder })
		local tab = UI:Tab("Name")
		local section = tab:Section("Name", "Left" | "Right")

		section:Toggle      { Name, Default, Flag, Tooltip, Callback(bool) }
		section:Slider      { Name, Min, Max, Default, Step, Suffix, Flag, Tooltip, Callback(number) }
		section:Dropdown    { Name, Options, Default, Multi, Flag, Tooltip, Callback(value) }   -> :Refresh(options)
		section:Keybind     { Name, Default, Mode = "Press"|"Toggle"|"Hold", Flag, Callback, Changed(key) }
		section:ColorPicker { Name, Default, Flag, Tooltip, Callback(Color3) }
		section:Textbox     { Name, Default, Placeholder, Flag, Callback(text, enterPressed) }
		section:Button      { Name, Tooltip, Callback() }
		section:Label(text)

		Every element returns an object with :Set(value, silent) / :Get() (Button/Label: :SetText / :Set).

		UI:Notify { Title, Text, Duration, Type = "Info"|"Success"|"Warning"|"Error" }
		UI:SetAccent(Color3)   UI:SetOpen(bool)   UI:Destroy()
		UI:SaveConfig(name)    UI:LoadConfig(name)
		UI:ExportConfig() -> json string    UI:ApplyConfig(json)
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

-- Optional functions that only some environments define; they are nil in a
-- normal Roblox game. Reading them from the environment table keeps the script
-- analyzer from reporting them as unknown globals.
local env = getfenv() :: { [string]: any }
local gethui = env.gethui
local writefile, readfile = env.writefile, env.readfile
local isfolder, makefolder = env.isfolder, env.makefolder

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

local function safeCall(fn, ...)
	if typeof(fn) ~= "function" then
		return
	end
	local args = table.pack(...)
	task.spawn(function()
		local ok, err = pcall(fn, table.unpack(args, 1, args.n))
		if not ok then
			warn("[NimbusUI] callback error: " .. tostring(err))
		end
	end)
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

	self._setters = {}
	self._connections = {}
	self._accentHooks = {}
	self._keybinds = {}
	self._tabs = {}
	self._memoryConfigs = {}
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
		if self._tooltip.Visible then
			self._tooltip.Position = UDim2.fromOffset(input.Position.X + 14, input.Position.Y + 12)
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
	fn(input)
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
		self._tooltip.Text = text
		self._tooltip.Visible = true
	end)
	inst.MouseLeave:Connect(function()
		self._tooltip.Visible = false
	end)
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
		self._tooltip.Visible = false
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
	local duration = opts.Duration or 4
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

	create("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 2, 1, 0),
		Parent = toast,
	})

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
		Parent = toast,
	})

	local entry = {}
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
	tween(progress, duration, { Size = UDim2.new(0, 0, 0, 2) }, Enum.EasingStyle.Linear)
	task.delay(duration, entry.Close)

	table.insert(self._notifications, entry)
	if #self._notifications > self.MaxNotifications then
		self._notifications[1].Close()
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

function Library:ApplyConfig(json)
	local ok, data = pcall(HttpService.JSONDecode, HttpService, json)
	if not ok or type(data) ~= "table" then
		return false
	end
	for flag, raw in pairs(data) do
		local setter = self._setters[flag]
		if setter then
			setter(deserialize(raw))
		end
	end
	return true
end

-- Uses writefile/readfile when the environment has them; otherwise keeps
-- configs in memory for this session (use ExportConfig to store elsewhere).
function Library:SaveConfig(name)
	name = name or "default"
	local json = self:ExportConfig()
	if hasFileSystem() then
		local ok = pcall(function()
			if typeof(isfolder) == "function" and typeof(makefolder) == "function" and not isfolder(self.ConfigFolder) then
				makefolder(self.ConfigFolder)
			end
			writefile(self.ConfigFolder .. "/" .. name .. ".json", json)
		end)
		return ok
	end
	self._memoryConfigs[name] = json
	return true
end

function Library:LoadConfig(name)
	name = name or "default"
	local json
	if hasFileSystem() then
		local ok, result = pcall(readfile, self.ConfigFolder .. "/" .. name .. ".json")
		if ok then
			json = result
		end
	else
		json = self._memoryConfigs[name]
	end
	if not json then
		return false
	end
	return self:ApplyConfig(json)
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
		Size = UDim2.new(1, 0, 0, 26),
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
		return col
	end
	tab.Left = column(0, 8)
	tab.Right = column(0.5, 4)

	tab.Button.MouseButton1Click:Connect(function()
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
	addList(content, 6)

	return setmetatable({ Library = lib, Frame = frame, Content = content, _order = 0 }, Section)
end

function Section:_next()
	self._order += 1
	return self._order
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

-- Toggle ---------------------------------------------------------------
function Section:Toggle(opts)
	opts = opts or {}
	local lib = self.Library
	local theme = lib.Theme
	local state = opts.Default == true

	local row = create("TextButton", {
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		Text = "",
		LayoutOrder = self:_next(),
		Parent = self.Content,
	})
	local box = create("Frame", {
		BackgroundColor3 = theme.Element,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0.5, -6),
		Size = UDim2.fromOffset(12, 12),
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
		Position = UDim2.fromOffset(20, 0),
		Size = UDim2.new(1, -20, 1, 0),
		TextColor3 = state and theme.Text or theme.SubText,
		Text = opts.Name or "Toggle",
		Parent = row,
	})

	local toggle = {}
	function toggle:Set(value, silent)
		state = value == true
		fill.Visible = state
		label.TextColor3 = state and theme.Text or theme.SubText
		lib:_updateFlag(opts.Flag, state)
		if not silent then
			safeCall(opts.Callback, state)
		end
	end
	function toggle:Get()
		return state
	end

	row.MouseButton1Click:Connect(function()
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
	return toggle
end

-- Slider ---------------------------------------------------------------
function Section:Slider(opts)
	opts = opts or {}
	local lib = self.Library
	local theme = lib.Theme
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
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = self:_next(),
		Parent = self.Content,
	})
	makeLabel(theme, {
		Size = UDim2.new(1, 0, 0, 14),
		Text = opts.Name or "Slider",
		Parent = holder,
	})
	local valueLabel = makeLabel(theme, {
		Size = UDim2.new(1, 0, 0, 14),
		TextColor3 = theme.SubText,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
		Parent = holder,
	})
	local bar = create("TextButton", {
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = theme.Element,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 19),
		Size = UDim2.new(1, 0, 0, 8),
		Parent = holder,
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
		valueLabel.Text = string.format("%." .. decimals .. "f", value) .. suffix
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
	bar.InputBegan:Connect(function(input)
		if isPointer(input) then
			lib:_beginDrag(fromInput, input)
		end
	end)

	render()
	lib:_attachTooltip(holder, opts.Tooltip)
	lib:_registerFlag(opts.Flag, value, function(v)
		slider:Set(v)
	end)
	return slider
end

-- Dropdown -------------------------------------------------------------
function Section:Dropdown(opts)
	opts = opts or {}
	local lib = self.Library
	local theme = lib.Theme
	local multi = opts.Multi == true
	local options = opts.Options or {}
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
		Size = UDim2.new(1, 0, 0, 20),
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

	local list = create("Frame", {
		BackgroundColor3 = theme.Element,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		LayoutOrder = 3,
		Parent = holder,
	})
	addStroke(list, theme.Border)
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
				Size = UDim2.new(1, 0, 0, 18),
				Font = theme.Font,
				TextSize = 12,
				TextColor3 = theme.SubText,
				TextXAlignment = Enum.TextXAlignment.Left,
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
			button.MouseButton1Click:Connect(function()
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
	function dropdown:Refresh(newOptions)
		options = newOptions or {}
		build()
		dropdown:Set(value, true)
	end

	header.MouseButton1Click:Connect(function()
		setOpen(not open)
	end)

	build()
	dropdown:Set(opts.Default, true)
	lib:_attachTooltip(header, opts.Tooltip)
	lib:_registerFlag(opts.Flag, dropdown:Get(), function(v)
		dropdown:Set(v)
	end)
	return dropdown
end

-- Keybind --------------------------------------------------------------
function Section:Keybind(opts)
	opts = opts or {}
	local lib = self.Library
	local theme = lib.Theme
	local key = opts.Default
	local mode = opts.Mode or "Press"
	local active = false

	local row = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = self:_next(),
		Parent = self.Content,
	})
	makeLabel(theme, {
		Size = UDim2.new(1, -70, 1, 0),
		Text = opts.Name or "Keybind",
		Parent = row,
	})
	local button = create("TextButton", {
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(64, 16),
		BackgroundColor3 = theme.Element,
		BorderSizePixel = 0,
		Font = theme.Font,
		TextSize = 11,
		TextColor3 = theme.SubText,
		Text = "[None]",
		Parent = row,
	})
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

	button.MouseButton1Click:Connect(function()
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
			elseif inputType == Enum.UserInputType.MouseButton1 then
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
	lib:_attachTooltip(row, opts.Tooltip)
	lib:_registerFlag(opts.Flag, key or false, function(v)
		bind:Set(v or nil)
	end)
	return bind
end

-- Color picker ---------------------------------------------------------
function Section:ColorPicker(opts)
	opts = opts or {}
	local lib = self.Library
	local theme = lib.Theme
	local color = opts.Default or Color3.new(1, 1, 1)
	local h, s, v = color:ToHSV()

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
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 1,
		Parent = holder,
	})
	makeLabel(theme, {
		Size = UDim2.new(1, -34, 1, 0),
		Text = opts.Name or "Color",
		Parent = row,
	})
	local swatch = create("TextButton", {
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(26, 12),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Text = "",
		Parent = row,
	})
	addStroke(swatch, theme.Border)

	local panel = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 126),
		Visible = false,
		LayoutOrder = 2,
		Parent = holder,
	})

	local sv = create("TextButton", {
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = Color3.fromHSV(h, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.new(1, -22, 0, 100),
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
		Size = UDim2.new(0, 14, 0, 100),
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

	local hexBox = create("TextBox", {
		BackgroundColor3 = theme.Element,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 106),
		Size = UDim2.new(1, 0, 0, 18),
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
	swatch.MouseButton1Click:Connect(function()
		panel.Visible = not panel.Visible
	end)

	render()
	lib:_attachTooltip(row, opts.Tooltip)
	lib:_registerFlag(opts.Flag, color, function(c)
		picker:Set(c)
	end)
	return picker
end

-- Textbox --------------------------------------------------------------
function Section:Textbox(opts)
	opts = opts or {}
	local lib = self.Library
	local theme = lib.Theme
	local value = opts.Default or ""

	local holder = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 37),
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
		Size = UDim2.new(1, 0, 0, 20),
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
	return textbox
end

-- Button ---------------------------------------------------------------
function Section:Button(opts)
	opts = opts or {}
	local lib = self.Library
	local theme = lib.Theme

	local button = create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = theme.Element,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 22),
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
	button.MouseButton1Click:Connect(function()
		stroke.Color = theme.Accent
		tween(stroke, 0.35, { Color = theme.Border })
		safeCall(opts.Callback)
	end)

	lib:_attachTooltip(button, opts.Tooltip)
	return {
		SetText = function(_, text)
			button.Text = text
		end,
	}
end

-- Label ----------------------------------------------------------------
function Section:Label(text)
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
	return {
		Set = function(_, newText)
			label.Text = newText
		end,
	}
end

return Library
