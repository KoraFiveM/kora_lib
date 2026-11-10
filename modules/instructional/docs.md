# Instructional buttons

`Kora.instructional.show(buttons)` renders GTA's native `INSTRUCTIONAL_BUTTONS` overlay without NUI focus. Each button requires `label` and exactly one input source: `control`, `command`, or a `Kora.keybind` handle.

## API

### `Kora.instructional.show(buttons)`
Creates a display and returns a handle for updating, hiding, or checking it. The first display starts one per-frame drawing thread; the Scaleform movie is released after the last display is hidden. The display is automatically removed when its owner resource stops.

#### Parameters
- `buttons: table[]` — A non-empty array of button definitions. Every entry must be a table with a non-empty `label` and exactly one input source:
  - `label: string` — Text displayed beside the control prompt.
  - `control: number` — GTA control ID. The module resolves its instructional-button token with `GetControlInstructionalButton`.
  - `command: string` — Command/key-mapping name. The module hashes it and adds the `+` prefix when missing.
  - `keybind: Kora.keybind handle` — A keybind handle; the handle's command name supplies the displayed input token.
- At least one button is required. Supplying none, an empty array, a missing label, or zero/multiple input sources raises an assertion before the display is created.

#### Returns
- `handle` — An object with `setButtons`, `hide`, and `isVisible` methods.
- Raises an assertion error — The list or any button is invalid.

#### Example
```lua
local buttons = Kora.instructional.show({
    { control = 32, label = 'Move forward' },
    { keybind = modeKeybind, label = 'Movement: Camera' },
})

cam.setMovementMode('grid')
buttons.setButtons({
    { control = 32, label = 'Move forward' },
    { keybind = modeKeybind, label = 'Movement: Grid' },
})

buttons.hide()
```

`setButtons(buttons)` atomically replaces the displayed list. `hide()` removes the display and `isVisible()` reports whether it is still active. Displays are cleaned up when their owning resource stops.

### `handle.setButtons(buttons)`
Validates and atomically replaces this display's current button list. A failed validation leaves the current list unchanged.

#### Parameters
- `buttons: table[]` — A non-empty array using the same shape and validation rules as `show`.

#### Returns
- `true` — The list was replaced.
- `false` — This display has already been hidden.
- Raises an assertion error — The replacement list is invalid.

### `handle.hide()`
Removes this display from the overlay and releases its ownership tracking. Hiding the same handle again is safe.

#### Returns
- `true` — The display was active and has now been removed.
- `false` — The display was already hidden.

### `handle.isVisible()`
Checks whether this exact display is still registered.

#### Returns
- `boolean` — `true` while the display is active; otherwise `false`.

## Example: update controls with a session

```lua
local buttons = Kora.instructional.show({
    { control = 177, label = 'Exit camera' },
    { control = 10, label = 'Next camera' },
})

-- Change the help text as the current mode changes.
buttons.setButtons({
    { control = 177, label = 'Exit camera' },
    { control = 11, label = 'Previous camera' },
})

-- Hide when the owning interaction ends.
buttons.hide()
```
