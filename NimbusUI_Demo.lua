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
	Tooltip = "Drag to change the volume",
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
-- Tab 2: settings for the menu itself
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

local configs = settings:Section("Configs", "Right")

configs:Button({
	Name = "Save settings",
	Callback = function()
		local ok = UI:SaveConfig("demo")
		UI:Notify({
			Title = ok and "Saved" or "Not saved",
			Text = ok and "Settings saved as \"demo\"." or "Could not save the settings.",
			Type = ok and "Success" or "Error",
		})
	end,
})

configs:Button({
	Name = "Load settings",
	Callback = function()
		local ok = UI:LoadConfig("demo")
		UI:Notify({
			Title = ok and "Loaded" or "Nothing to load",
			Text = ok and "Settings loaded from \"demo\"." or "Save the settings first.",
			Type = ok and "Success" or "Warning",
		})
	end,
})

configs:Button({
	Name = "Print config JSON",
	Callback = function()
		print(UI:ExportConfig())
	end,
})

UI:Notify({ Title = "Nimbus UI", Text = "Menu loaded. Press Insert to show or hide it.", Type = "Success" })
