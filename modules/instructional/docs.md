# Instructional buttons

`Kora.instructional.show(buttons)` renders GTA's native `INSTRUCTIONAL_BUTTONS` overlay without NUI focus. Each button requires `label` and exactly one input source: `control`, `command`, or a `Kora.keybind` handle.

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
```

Optional `keyFallback` (non-empty string) is the text shown when GTA has no named glyph for the input, which happens for controls such as `200` (Esc). Without it, such a button shows no key. The bare control number is never displayed.

```lua
{ control = 200, label = 'Close inventory', keyFallback = 'Esc' },
```

`setButtons(buttons)` atomically replaces the displayed list. `hide()` removes the display and `isVisible()` reports whether it is still active. Displays are cleaned up when their owning resource stops.
