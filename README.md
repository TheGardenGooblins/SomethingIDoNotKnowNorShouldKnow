# Nimbus UI

A compact, flat dark UI library for Roblox (Luau). It has a draggable window, tabs in a sidebar, two-column sections, and toast notifications.

## Setup

1. Put `NimbusUI.lua` in a **ModuleScript** named `NimbusUI` in `ReplicatedStorage`.
2. Put `NimbusUI_Demo.lua` in a **LocalScript** in `StarterPlayerScripts`.
3. Press Play. **Insert** shows or hides the menu.

## Quick start

```lua
local Library = require(game.ReplicatedStorage.NimbusUI)

local UI = Library.new({ Title = "My Game", ToggleKey = Enum.KeyCode.Insert })
local tab = UI:Tab("Main")
local section = tab:Section("General", "Left")

section:Toggle({ Name = "Music", Flag = "music", Default = true, Callback = function(on) print(on) end })
section:Slider({ Name = "Volume", Flag = "volume", Min = 0, Max = 100, Default = 50, Suffix = "%" })

UI:Notify({ Title = "Hello", Text = "Menu loaded", Type = "Success" })
```

## Elements

| Method | Options |
|---|---|
| `Toggle` | `Name, Default, Flag, Tooltip, Callback(bool)` |
| `Slider` | `Name, Min, Max, Default, Step, Suffix, Flag, Tooltip, Callback(number)` |
| `Dropdown` | `Name, Options, Default, Multi, MaxVisible, Flag, Tooltip, Callback(value)`, plus `:Refresh(options)` |
| `Keybind` | `Name, Default, Mode ("Press"/"Toggle"/"Hold"), Flag, Callback, Changed(key)` |
| `ColorPicker` | `Name, Default, Flag, Tooltip, Callback(Color3)` |
| `Textbox` | `Name, Default, Placeholder, Flag, Callback(text, enterPressed)` |
| `Button` | `Name, Tooltip, Callback()` |
| `Label(text)` | — |

Click the value of a slider to type an exact number. The slider keeps the number inside `Min` and `Max` and rounds it to `Step`.

A dropdown shows at most `MaxVisible` options (8 by default) and scrolls when it has more.

Every element returns an object with `:Set(value, silent)` and `:Get()`. Buttons and labels use `:SetText` and `:Set` instead. Every element also takes `DependsOn` and has `:SetVisible(bool)`; see [Showing and hiding elements](#showing-and-hiding-elements).

## Showing and hiding elements

Every element has `:SetVisible(bool)` and `:IsVisible()`. A hidden element takes no space. Sections have `:SetVisible(bool)` too.

```lua
local hint = section:Label("Only shown when needed")
hint:SetVisible(false)
```

Use the option `DependsOn = toggle` to show an element only while a toggle is on. Every element accepts it.

```lua
local crosshair = section:Toggle({ Name = "Custom crosshair", Flag = "crosshair" })

section:Slider({ Name = "Crosshair size", Min = 4, Max = 40, DependsOn = crosshair })
section:ColorPicker({ Name = "Crosshair colour", DependsOn = crosshair })
section:Label({ Text = "Applies to all weapons.", DependsOn = crosshair })
```

- Dependencies chain. If toggle B depends on toggle A, an element that depends on B is hidden while A is off.
- `SetVisible(false)` always hides the element, even when its toggle is on.
- A hidden element keeps its value, and configs still save and load it.
- `toggle:OnChanged(fn)` calls `fn(state)` on every change of the toggle. It returns a function that removes the listener.
- `element.Instance` is the element's top GUI object, if you need to style it.

## Toggle attachments

A toggle can hold a keybind and a colour swatch on its own row.

```lua
local tags = section:Toggle({ Name = "Name tags", Flag = "name_tags" })

local key = tags:AddKeybind({ Flag = "name_tags_key", Default = Enum.KeyCode.N })
local colour = tags:AddColorPicker({ Flag = "name_tags_colour", Default = Color3.fromRGB(120, 200, 255) })
```

| Method | Options | Returns |
|---|---|---|
| `toggle:AddKeybind` | `Default, Mode, Flag, Sync, Tooltip, Callback(bool), Changed(key)` | a keybind object |
| `toggle:AddColorPicker` | `Default, Flag, Tooltip, Callback(Color3)` | a colour picker object |

The key of an attached keybind controls the toggle:

- `Mode = "Toggle"` (the default) or `"Press"`: each press turns the toggle on or off.
- `Mode = "Hold"`: the toggle is on while the key is held.

`Callback` gets the new state of the toggle. Pass `Sync = false` if the key must not change the toggle. The keybind then works like a normal `Keybind` element.

The picker of an attached swatch opens below the toggle row. Give each attachment its own `Flag` to save it in configs.

## Mobile

On a touch device (`UserInputService.TouchEnabled`) the library does this by itself:

- It shows a small on-screen button that opens and closes the menu. Drag the button to move it.
- It makes rows, buttons, sliders and swatches larger so they are easier to tap.
- It shows a tooltip when you press and hold an element. That press does not click the element.
- It shrinks the window to fit when the screen is smaller than the window.

Two options of `Library.new` override the detection:

| Option | Meaning |
|---|---|
| `MobileButton = true` or `false` | Always show, or never show, the on-screen button. The button is available as `UI.MobileButton`. |
| `TouchMode = true` or `false` | Always use, or never use, the larger controls and press-and-hold tooltips. |

## Notifications

```lua
UI:Notify({ Title = "Saved", Text = "Settings saved.", Duration = 4, Type = "Success" })
-- Type: "Info" (accent colour), "Success", "Warning", "Error"
```

Notifications stack in the bottom-right corner. Pass `NotifyPosition = "TopRight"` to `Library.new` to move them to the top-right. Click a notification to dismiss it.

## Other methods

- `UI:SetAccent(Color3)` changes the accent colour while the game runs.
- `UI:SetOpen(bool)` shows or hides the menu.
- `UI:Destroy()` removes the menu and disconnects everything.
- `UI:SaveConfig(name)` and `UI:LoadConfig(name)` save and load settings by name. They only last for the current session in a normal game.
- `UI:ExportConfig()` returns a JSON string and `UI:ApplyConfig(json)` loads one, so you can store configs yourself, for example in a DataStore through a RemoteEvent.
