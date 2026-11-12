---
title: "Camera"
sidebar_position: 22
---


# Camera

Owns a reusable camera HUD and scripted-camera lifecycle for CCTV networks and player-operated views. It does not take NUI focus, so normal game input remains available.

Namespace: `Kora.camera` · Source: `modules/camera/client.lua`

## How it works

Opening a new session closes and replaces an existing one. Fixed cameras are scripted and can be switched; recording, helicopter, and operator modes can use the player’s live view without a fixed camera list. Closing restores the prior follow-camera mode and hides instructional controls.

## open options table

Settings for the overlay are passed as one table. Each fixed camera entry is described after the session fields. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `mode??` | string | cctv, recording, helicam, or operator; defaults to operator. |
| `title??` | string | HUD title, non-empty and at most 80 characters. |
| `subtitle??` | string | HUD subtitle, up to 80 characters. |
| `cameraLabel??` | string | Fallback live camera label, up to 80 characters. |
| `cameras??` | table[] | Fixed camera list. Empty or omitted leaves the player’s native view in place. |
| `camera??` | table | Single fixed camera shorthand; when supplied it replaces cameras with a one-entry list. |
| `recording??` | boolean | Initial REC indicator; defaults false. |
| `controls??` | boolean | Shows instructional exit/switch controls; defaults true. |
| `timestamp??` | boolean | Shows elapsed-time telemetry; defaults true. |
| `viewMode??` | integer | Optional GTA follow camera mode from 0 through 4; prior mode is restored on close. |

## Fixed camera entry

Each entry requires coords as a finite vector3/vector4-compatible value. target and rotation are optional finite coordinate vectors. fov is optional, finite, and constrained to 10.0–120.0; it defaults to 52.0 when creating the scripted camera. label is optional text up to 80 characters. location is displayed as HUD metadata.

## Input and cleanup

Controls default on. The exit control closes the view; next/previous instructions appear only when there are at least two fixed cameras. The active loop ends when the session closes. Resource shutdown restores the player camera.

## Functions

Open/close the overlay, switch fixed cameras, inspect state, and update the recording indicator.

### `Kora.camera.open(options)`

Opens the camera overlay with an optional list of fixed cameras.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `options` | table | Required overlay configuration; see the options section. |

**Returns**

- **opened** — true after successful setup.

**Example**

```lua
Kora.camera.open({
    mode = 'cctv', title = 'SECURITY NETWORK 202',
    cameras = {{ label = 'CAM 01', location = '24/7 Innocence Blvd',
        coords = vector3(24.4, -1340.6, 30.7), target = vector3(24.4, -1340.6, 28.2), fov = 58.0 }},
})
```

**Representative console output**

```text
Opens the overlay and activates the first fixed view.
```

### `Kora.camera.close(reason?)`

Closes an active session and restores the previous camera view and controls.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `reason?` | string | Optional close reason sent with the UI close event. |

**Returns**

- **closed** — boolean; false if already closed.

**Example**

```lua
Kora.camera.close('finished')
```

**Representative console output**

```text
Returns false when no camera overlay was active.
```

### `Kora.camera.isOpen()`

Reports whether the camera overlay session is active.

**Parameters**



**Returns**

- **open** — boolean.

**Example**

```lua
if Kora.camera.isOpen() then Kora.camera.close() end
```

**Representative console output**

```text
Reads current client state.
```

### `Kora.camera.next()`

Switches to the next camera in the current fixed network, wrapping at the end.

**Parameters**



**Returns**

- **changed** — boolean; false unless at least two fixed cameras are active.

**Example**

```lua
Kora.camera.next()
```

**Representative console output**

```text
Activates the next view and updates the overlay metadata.
```

### `Kora.camera.previous()`

Switches to the previous camera, wrapping to the final entry when needed.

**Parameters**



**Returns**

- **changed** — boolean; false unless at least two fixed cameras are active.

**Example**

```lua
Kora.camera.previous()
```

**Representative console output**

```text
Activates the previous view.
```

### `Kora.camera.setRecording(recording)`

Changes the REC indicator without changing the camera view.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `recording` | boolean | New indicator state. |

**Returns**

- **updated** — boolean; false if no session is open.

**Example**

```lua
Kora.camera.setRecording(true)
```

**Representative console output**

```text
Updates the live overlay while leaving the view unchanged.
```

## Limits and related APIs

Camera mode names are validated. Opening while already active replaces the prior view. This module does not provide authorization or make camera locations private; the calling resource must decide who can open a feed.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/camera/docs.md` or `local/camera/docs.md`) that the reference above does not state.

`Kora.camera` owns the scripted camera lifecycle and the reusable, pointer-transparent camera HUD. It supports fixed CCTV networks and live player views for news recording or helicopter optics. It never takes NUI focus, so the game retains camera and movement input.

```lua
Kora.camera.open({
    mode = 'cctv',
    title = 'SECURITY NETWORK 202',
    cameras = {
        {
            label = 'CAM 01',
            location = '24/7 Innocence Blvd',
            coords = vector3(24.4, -1340.6, 30.7),
            target = vector3(24.4, -1340.6, 28.2),
            fov = 58.0,
        },
    },
})

Kora.camera.next()
Kora.camera.previous()
Kora.camera.close('finished')
```

`Kora.camera.isOpen()` reports whether the overlay is active. `Kora.camera.setRecording(true)` updates the REC indicator while leaving the current view in place.

Unless `controls = false`, `Kora.instructional` shows the live exit and camera-switch controls. The NUI overlay is reserved for camera status and telemetry.

For a player-operated view, omit `cameras` and use `mode = 'recording'`, `mode = 'helicam'`, or `mode = 'operator'`. `viewMode` can temporarily set the GTA follow-camera mode and is restored when the overlay closes.
