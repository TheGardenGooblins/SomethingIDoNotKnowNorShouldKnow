# Nimbus UI

A compact, flat dark UI library for Roblox (Luau). It has a draggable window, tabs in a sidebar, two-column sections, and toast notifications.

## Setup

1. Put `NimbusUI.lua` in a **ModuleScript** named `NimbusUI` in `ReplicatedStorage`.
2. Put `NimbusUI_Demo.lua` in a **LocalScript** in `StarterPlayerScripts`.
3. Press Play. **Insert** shows or hides the menu. On a phone or tablet, tap the on-screen menu button.

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
| `Label(text)` | — (or `Label({ Text, DependsOn })`) |
| `ThemeManager` | `Keys, FlagPrefix, ResetName, DependsOn, Callback(key, color)`; see [Themes](#themes) |
| `ConfigManager` | `Name, Default, Notify, DependsOn, Callback(action, name, ok)`; see [Configs](#configs) |

Click the value of a slider to type an exact number. The slider keeps the number inside `Min` and `Max` and rounds it to `Step`.

`dropdown:Refresh(options)` replaces the options. It keeps the selection if that option is still in the list. If it is not, the selection is cleared and `Callback` runs with the new value.

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

A notification closes after `Duration` seconds (4 by default). Pass `Persistent = true` to keep it until the player clicks it or your code closes it:

```lua
local banner = UI:Notify({ Title = "Maintenance", Text = "Servers restart soon.", Type = "Warning", Persistent = true })
banner.Close()
```

Notifications stack in the bottom-right corner. Pass `NotifyPosition = "TopRight"` to `Library.new` to move them to the top-right. Click a notification to dismiss it.

## Themes

`UI:SetTheme(changes)` changes colours while the menu is open. Pass only the colours you want to change:

```lua
UI:SetTheme({
	Background = Color3.fromRGB(10, 14, 26),
	Section = Color3.fromRGB(19, 26, 46),
	Text = Color3.fromRGB(226, 232, 245),
})

UI:SetTheme(Library.DefaultTheme) -- back to the default colours
```

The colour names are `Background`, `Panel`, `Section`, `Element`, `Hover`, `Border`, `Text`, `SubText` and `Accent`. To start with other colours, pass the same table as `Theme` to `Library.new`.

### Theme manager

`section:ThemeManager()` adds one colour picker for each theme colour and a reset button. Use it instead of writing your own theme code:

```lua
local manager = section:ThemeManager({
	Keys = { "Accent", "Background", "Panel", "Section" }, -- default: every colour
	ResetName = "Reset UI theme",
	FlagPrefix = "theme_",   -- flags are "theme_Accent", ...; pass false for no flags
	Callback = function(key, color) end,
})

manager:Reset() -- back to the colours the menu had when the manager was created
```

The menu follows the pickers while you drag them. The pickers also follow the theme when your code calls `SetTheme` or `SetAccent`. Because the pickers have flags, configs save and load the theme.

Do not recolour the menu's frames yourself, for example with a loop that looks for frames of a known colour. That stops working after the first change, because the frames no longer have the colour the loop looks for. Use `SetTheme` or the theme manager.

Two theme names can share one colour, for example the same colour for `Background`, `Panel` and `Section` in a flat theme. The library records which name each object uses, so a later `SetTheme` still changes the right objects.

`SetTheme` only changes the names you pass. For example, if you pass `Background` and not `Section`, the sections keep their colour. It writes a warning to the output when a name is unknown or a value is not a `Color3`.

`SetTheme` does not change `Font`, `FontBold` or `TextSize`. Set those in `Theme` when you call `Library.new`.

## Errors in callbacks

Each callback runs in its own thread, so a callback that fails or waits cannot stop the menu. When a callback fails, the library always writes the error to the output. It can also tell you in two other ways:

| Option of `Library.new` | Meaning |
|---|---|
| `NotifyErrors = true` or `false` | Show the error as a red notification. The default is `true` in Studio and `false` in a live game. |
| `OnError = function(message) end` | Call your function with the error message, for example to log it. |

## Other methods

- `UI:SetAccent(Color3)` changes the accent colour while the game runs.
- `UI:SetOpen(bool)` shows or hides the menu.
- `UI:Destroy()` removes the menu and disconnects everything.
- `UI.Flags` holds the current value of every element that has a `Flag`.

## Configs

A config is the value of every element that has a `Flag`, saved under a name. A name can have 1 to 32 letters, digits, spaces, `-` or `_`.

| Method | What it does |
|---|---|
| `UI:SaveConfig(name)` | Saves the current settings. Returns `true` when it worked. |
| `UI:LoadConfig(name)` | Loads saved settings. Returns `true` when it worked. |
| `UI:DeleteConfig(name)` | Deletes a config. Returns `true` when it worked. |
| `UI:ListConfigs()` | Returns the names of the saved configs, sorted. |
| `UI:ExportConfig()` | Returns the current settings as a JSON string. |
| `UI:ApplyConfig(json)` | Loads settings from a JSON string. It skips unknown flags and values an element cannot use. |

### Config manager

`section:ConfigManager()` adds a dropdown that lists the saved configs, a name box, and Save, Load, Delete and Refresh buttons.

```lua
local manager = section:ConfigManager({
	Name = "Saved configs",   -- label of the dropdown
	Default = "default",      -- name in the box at the start
	Notify = true,            -- show a notification after each action
	Callback = function(action, name, ok) end, -- action is "Save", "Load" or "Delete"
})

manager:Refresh() -- read the list of configs again
```

The list updates by itself when you call `UI:SaveConfig` or `UI:DeleteConfig`.

### Where configs are kept

By default, configs stay in memory and are gone when the player leaves. To keep them somewhere else, give the library a config store. A config store is a table with four functions:

```lua
UI:SetConfigStore({
	Save = function(name, json) return true end,   -- return true when saved
	Load = function(name) return json end,         -- return the JSON string, or nil
	List = function() return { "name1", "name2" } end,
	Delete = function(name) return true end,
})
```

You can also pass the store as `ConfigStore` to `Library.new`. The functions may yield, for example to wait for the server. `SaveConfig`, `LoadConfig`, `DeleteConfig` and `ListConfigs` then yield too, so call them from a callback or inside `task.spawn`.

### Saving configs in a DataStore

A LocalScript cannot use DataStores, so the client asks the server through a RemoteEvent. The folder `examples` has both sides:

| File | Where it goes |
|---|---|
| `examples/ConfigStore.server.lua` | A **Script** in `ServerScriptService`. It creates the RemoteEvent `NimbusConfig` and owns the DataStore. |
| `examples/RemoteConfigStore.lua` | A **ModuleScript** named `RemoteConfigStore` in `ReplicatedStorage`. It returns a function that makes a config store. |

Then, in your LocalScript:

```lua
local createRemoteConfigStore = require(ReplicatedStorage:WaitForChild("RemoteConfigStore"))

local UI = Library.new({ Title = "My Game" })
UI:SetConfigStore(createRemoteConfigStore())

section:ConfigManager() -- now lists the configs in the DataStore
```

The request goes like this:

1. The client fires `NimbusConfig` with a request number, an action (`"Save"`, `"Load"`, `"List"` or `"Delete"`), a name and, for `"Save"`, the JSON string.
2. The server checks the request and answers on the same RemoteEvent with the request number, `true` or `false`, and the result.

The server never trusts the client. The example server does these checks, and your own version should keep them:

- **Types**: the request number must be a number, and the action and the name must be strings. The action must be one of the four known actions.
- **Name**: 1 to 32 letters, digits, spaces, `-` or `_`.
- **Size**: at most 16,000 characters in a config, 300 settings in a config and 10 configs for each player.
- **Content**: the JSON must parse. Every value must be a boolean, a finite number, a short string, or a small table of those. The server saves its own re-encoded copy, not the string the client sent.
- **Rate**: each player can send a burst of 6 requests, then 1 request each second.
- **DataStore use**: the server reads a player's configs once when the player joins. It writes them a short time after a change and when the player leaves, with retries. If the read failed, it does not write, so an outage cannot replace saved configs with an empty list.

Configs hold menu settings only. Do not read them on the server to decide anything about gameplay, because a player can put any value in a config.

In Studio, turn on **Enable Studio Access to API Services** (Game Settings > Security) to test DataStores.
