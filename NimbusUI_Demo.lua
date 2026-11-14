--[[
	Nimbus UI demo — a LocalScript that uses every element once.

	Setup: put NimbusUI.lua in a ModuleScript named "NimbusUI" in ReplicatedStorage,
	put this file in a LocalScript in StarterPlayerScripts, then press Play.
	Insert shows or hides the menu.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Library = require(ReplicatedStorage:WaitForChild("NimbusUI"))

local UI = Library.new({
	Title = "Nimbus UI",
	Subtitle = "demo",
	ToggleKey = Enum.KeyCode.Insert,
	-- Touch devices get an on-screen menu button and larger controls automatically.
	-- Uncomment these to try them on a computer:
	-- MobileButton = true,
	-- TouchMode = true,
})

------------------------------------------------------------------------
-- Tab 1: the basic elements
------------------------------------------------------------------------
local main = UI:Tab("Elements")

local general = main:Section("General", "Left")

general:Label("Every element in the library appears once in this menu.")

general:Toggle({
	Name = "Music",
	Flag = "music",
	Default = true,
	Tooltip = "Turns the background music on or off",
	Callback = function(on)
		print("Music:", on)
	end,
})

general:Slider({
	Name = "Volume",
	Flag = "volume",
	Min = 0,
	Max = 100,
	Default = 50,
	Suffix = "%",
	Tooltip = "Drag, or click the number to type an exact value",
	Callback = function(value)
		print("Volume:", value)
	end,
})

general:Slider({
	Name = "Camera sensitivity",
	Flag = "sensitivity",
	Min = 0.1,
	Max = 2,
	Step = 0.05,
	Default = 1,
	Suffix = "x",
})

general:Textbox({
	Name = "Display name",
	Flag = "display_name",
	Placeholder = "Type a name...",
	Callback = function(text, enterPressed)
		print("Display name:", text, enterPressed)
	end,
})

general:Button({
	Name = "Say hello",
	Tooltip = "Shows a notification",
	Callback = function()
		UI:Notify({ Title = "Hello", Text = "You pressed the button.", Type = "Info" })
	end,
})

local choices = main:Section("Choices", "Right")

choices:Dropdown({
	Name = "Graphics quality",
	Flag = "quality",
	Options = { "Low", "Medium", "High", "Ultra" },
	Default = "High",
	Tooltip = "Pick one option",
	Callback = function(value)
		print("Quality:", value)
	end,
})

choices:Dropdown({
	Name = "HUD parts",
	Flag = "hud_parts",
	Options = { "Health", "Minimap", "Chat", "Quest log" },
	Default = { "Health", "Minimap" },
	Multi = true,
	Callback = function(values)
		print("HUD parts:", table.concat(values, ", "))
	end,
})

-- Long lists show 8 rows and scroll. Use MaxVisible to change the row count.
local languages = {}
for i = 1, 20 do
	languages[i] = "Language " .. i
end
choices:Dropdown({
	Name = "Language (scrolling list)",
	Flag = "language",
	Options = languages,
	Default = "Language 1",
	MaxVisible = 8,
})

choices:Keybind({
	Name = "Sprint",
	Flag = "sprint_key",
	Default = Enum.KeyCode.F,
	Mode = "Hold",
	Callback = function(held)
		print("Sprinting:", held)
	end,
	Changed = function(key)
		print("Sprint key is now:", key)
	end,
})

choices:Keybind({
	Name = "Flashlight",
	Flag = "flashlight_key",
	Default = Enum.KeyCode.G,
	Mode = "Toggle",
	Callback = function(on)
		print("Flashlight:", on)
	end,
})

choices:Keybind({
	Name = "Emote",
	Flag = "emote_key",
	Default = Enum.KeyCode.E,
	Mode = "Press",
	Callback = function()
		print("Emote!")
	end,
})

choices:ColorPicker({
	Name = "Trail colour",
	Flag = "trail_colour",
	Default = Color3.fromRGB(255, 170, 60),
	Tooltip = "Click the swatch to open the picker",
	Callback = function(color)
		print("Trail colour:", color)
	end,
})

------------------------------------------------------------------------
-- Tab 2: newer features
------------------------------------------------------------------------
local advanced = UI:Tab("Advanced")

-- Toggle attachments: a keybind and/or a colour swatch on the toggle's own row.
local attachments = advanced:Section("Toggle attachments", "Left")

local nameTags = attachments:Toggle({
	Name = "Name tags",
	Flag = "name_tags",
	Default = true,
	Callback = function(on)
		print("Name tags:", on)
	end,
})
-- The key flips the toggle (Mode "Toggle" is the default for attachments).
nameTags:AddKeybind({
	Flag = "name_tags_key",
	Default = Enum.KeyCode.N,
	Tooltip = "Key that turns name tags on and off",
})
nameTags:AddColorPicker({
	Flag = "name_tags_colour",
	Default = Color3.fromRGB(120, 200, 255),
	Callback = function(color)
		print("Name tag colour:", color)
	end,
})

-- Mode "Hold": the toggle is on only while the key is held.
local zoom = attachments:Toggle({
	Name = "Zoom",
	Flag = "zoom",
	Callback = function(on)
		print("Zoom:", on)
	end,
})
zoom:AddKeybind({ Flag = "zoom_key", Default = Enum.KeyCode.Z, Mode = "Hold" })

-- A toggle with only a colour swatch.
local outline = attachments:Toggle({ Name = "Outline", Flag = "outline" })
outline:AddColorPicker({ Flag = "outline_colour", Default = Color3.fromRGB(255, 90, 90) })

-- Conditional visibility: DependsOn shows an element only while a toggle is on.
local visibility = advanced:Section("Conditional visibility", "Right")

local crosshair = visibility:Toggle({ Name = "Custom crosshair", Flag = "crosshair" })

visibility:Slider({
	Name = "Crosshair size",
	Flag = "crosshair_size",
	Min = 4,
	Max = 40,
	Default = 12,
	Suffix = "px",
	DependsOn = crosshair,
})
local crosshairDot = visibility:Toggle({
	Name = "Centre dot",
	Flag = "crosshair_dot",
	DependsOn = crosshair,
})
-- Dependencies chain: this needs "Centre dot", which itself needs "Custom crosshair".
visibility:ColorPicker({
	Name = "Dot colour",
	Flag = "crosshair_dot_colour",
	Default = Color3.fromRGB(255, 255, 255),
	DependsOn = crosshairDot,
})
visibility:Label("Turn on \"Custom crosshair\" to see its settings.")

-- SetVisible shows or hides any element from code.
local secret = visibility:Label("You found the hidden label.")
secret:SetVisible(false)
visibility:Button({
	Name = "Show / hide a label",
	Callback = function()
		secret:SetVisible(not secret:IsVisible())
	end,
})

------------------------------------------------------------------------
-- Tab 3: settings for the menu itself
------------------------------------------------------------------------
local settings = UI:Tab("Settings")

local appearance = settings:Section("Appearance", "Left")

appearance:ColorPicker({
	Name = "Accent colour",
	Flag = "accent",
	Default = UI.Theme.Accent,
	Callback = function(color)
		UI:SetAccent(color)
	end,
})

-- SetTheme changes the other colours while the menu is open.
appearance:Dropdown({
	Name = "Theme",
	Flag = "theme",
	Options = { "Default", "Midnight", "Light" },
	Default = "Default",
	Callback = function(name)
		if name == "Midnight" then
			UI:SetTheme({
				Background = Color3.fromRGB(10, 14, 26),
				Panel = Color3.fromRGB(15, 20, 36),
				Section = Color3.fromRGB(19, 26, 46),
				Element = Color3.fromRGB(27, 36, 62),
				Hover = Color3.fromRGB(36, 48, 80),
				Border = Color3.fromRGB(44, 58, 96),
				Text = Color3.fromRGB(226, 232, 245),
				SubText = Color3.fromRGB(130, 144, 176),
			})
		elseif name == "Light" then
			UI:SetTheme({
				Background = Color3.fromRGB(236, 237, 241),
				Panel = Color3.fromRGB(226, 227, 233),
				Section = Color3.fromRGB(246, 246, 249),
				Element = Color3.fromRGB(222, 223, 230),
				Hover = Color3.fromRGB(208, 210, 220),
				Border = Color3.fromRGB(190, 192, 204),
				Text = Color3.fromRGB(28, 28, 36),
				SubText = Color3.fromRGB(96, 98, 112),
			})
		else
			-- the accent is left out so the accent picker above keeps its colour
			local defaults = table.clone(Library.DefaultTheme)
			defaults.Accent = nil
			UI:SetTheme(defaults)
		end
	end,
})

appearance:Button({
	Name = "Hide menu",
	Tooltip = "Press Insert to show it again",
	Callback = function()
		UI:SetOpen(false)
	end,
})

local notifications = settings:Section("Notifications", "Left")

for _, kind in ipairs({ "Info", "Success", "Warning", "Error" }) do
	notifications:Button({
		Name = kind,
		Callback = function()
			UI:Notify({ Title = kind, Text = "This is a " .. string.lower(kind) .. " notification.", Type = kind })
		end,
	})
end

-- A persistent notification stays until it is clicked or closed from code.
local banner
notifications:Button({
	Name = "Persistent on / off",
	Callback = function()
		if banner then
			banner.Close()
			banner = nil
		else
			banner = UI:Notify({
				Title = "Maintenance",
				Text = "This stays until you click it or press the button again.",
				Type = "Warning",
				Persistent = true,
			})
		end
	end,
})

local configs = settings:Section("Configs", "Right")

-- A dropdown that lists the saved configs, a name box, and Save / Load / Delete
-- buttons. Type a name and press Save; pick a config in the list to load it.
--
-- Configs last until you leave the game. To keep them in a DataStore, set up
-- examples/ConfigStore.server.lua and examples/RemoteConfigStore.lua, then add:
--     UI:SetConfigStore(require(ReplicatedStorage.RemoteConfigStore)())
configs:ConfigManager({
	Default = "demo",
	Callback = function(action, name, ok)
		print("Config", action, name, ok)
	end,
})

-- The same things from code.
configs:Button({
	Name = "Quick save (code)",
	Tooltip = "Calls UI:SaveConfig(\"quick\")",
	Callback = function()
		local ok = UI:SaveConfig("quick")
		print("Saved:", ok, "- configs:", table.concat(UI:ListConfigs(), ", "))
	end,
})

configs:Button({
	Name = "Print config JSON",
	Callback = function()
		print(UI:ExportConfig())
	end,
})

UI:Notify({ Title = "Nimbus UI", Text = "Menu loaded. Press Insert to show or hide it.", Type = "Success" })
