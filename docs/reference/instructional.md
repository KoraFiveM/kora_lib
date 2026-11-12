---
title: "Instructional buttons"
sidebar_position: 11
---

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

`setButtons(buttons)` atomically replaces the displayed list. `hide()` removes the display and `isVisible()` reports whether it is still active. Displays are cleaned up when their owning resource stops.
