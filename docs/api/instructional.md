---
title: "Instructional"
sidebar_position: 11
---


# Instructional

Displays GTA’s native INSTRUCTIONAL_BUTTONS scaleform overlay without taking NUI focus. Each display is a managed handle whose buttons can be replaced or hidden.

Namespace: `Kora.instructional` · Source: `modules/instructional/client.lua`

## How it works

The overlay draws every frame while at least one display is active. Multiple displays are combined into the same overlay. Handles are owned by the resource that created them and are automatically hidden when that resource stops.

## Button fields

Every button requires a label and exactly one of the three input-source fields below.

| Option | Type | Description |
| --- | --- | --- |
| `control` | number | Control ID rendered through GetControlInstructionalButton. Supply exactly one input source per button. |
| `command` | string | Command/key mapping name. A leading + is added when absent before resolving its displayed control. |
| `keybind` | Kora.keybind handle | A Kora.keybind handle; its name is used to resolve the displayed key. |
| `label` | string | Required non-empty text shown beside the resolved button glyph. |

## Handle methods

setButtons(buttons) validates and atomically replaces this display’s button list, returning true on success or false if the display is no longer active. hide() removes this display and returns true when it existed, otherwise false. isVisible() returns whether this handle still refers to an active display.

## Updating a display

setButtons uses the same non-empty array and exactly-one-input-source rules as show. Invalid updates raise an assertion error and leave the current display unchanged.

## Functions

The module exports show. It returns a handle with setButtons, hide, and isVisible methods.

### `Kora.instructional.show(buttons)`

Creates a managed instructional-button display and returns controls for updating or closing it.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `buttons` | array | non-empty array of button objects. Each requires a non-empty label and exactly one input source: control, command, or keybind. |

**Returns**

- **handle** — table with setButtons(buttons), hide(), and isVisible() methods.

**Example**

```lua
local controls = Kora.instructional.show({
    { control = 32, label = 'Move forward' },
    { keybind = modeKeybind, label = 'Movement: Camera' },
})

controls.setButtons({
    { control = 32, label = 'Move forward' },
    { keybind = modeKeybind, label = 'Movement: Grid' },
})
```

**Representative console output**

```text
Displays the native control hints; no NUI focus is created.
```

## Limits and related APIs

A button must set exactly one of control, command, or keybind. An empty list is rejected. This is a local client presentation helper; it does not authorize gameplay actions.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/instructional/docs.md` or `local/instructional/docs.md`) that the reference above does not state.

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
