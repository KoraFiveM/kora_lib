---
title: "Freecam"
sidebar_position: 29
---


# Freecam

Starts a temporary camera the player can fly with the mouse and keyboard. It is useful for inspecting a scene or choosing a point. By default, the player is frozen safely while the camera is active.

Namespace: `Kora.freecam` · Source: `modules/freecam/client.lua`

## start options

All values are optional and preserve configured defaults when omitted. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `maxDistance?` | number | Finite radius limiting camera travel from its starting point. |
| `zone?` | table | Optional zone that constrains valid movement. |
| `focusCoords?` | vector3 | Point to keep in view; suppresses mouse look while set. |
| `moveSpeed?` | number | Camera movement speed. |
| `lookSensitivity?` | number | Mouse look sensitivity. |
| `fastMultiplier?` | number | Speed multiplier while Shift is held. |
| `transitionMs?` | integer | Camera transition time in milliseconds. |
| `upControl? / downControl?` | integer | Control IDs for vertical movement. |
| `freezePlayer?` | boolean | Whether to freeze player while camera is active; defaults to Config.freecam.freezePlayer (true). Never freezes while player is falling, jumping, airborne, or ragdolling. |

## Methods on the returned camera handle

stop(reason?) closes this session. isActive() checks this handle. getCoords() and getRotation() read the camera position/angle. getCamera() returns its native handle for Kora.raycast.fromCam. getMovementMode() reads the current mode; setMovementMode(mode) changes it. setFocus(vector3 or nil) aims at a point or clears the focus.

## Controls and boundaries

Mouse and WASD fly the view; Shift accelerates. A move beyond maxDistance or outside zone is ignored. Only one session can run, and its resource owns cleanup.

## Functions

start creates one camera session and returns a handle for controlling it. isActive checks whether any session is running.

### `Kora.freecam.start(options?)`

Starts an owner-bound scripted camera. Returns false and a reason if another freecam is already running.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `options?` | table | Optional radius/zone limits, focus point, movement speeds, controls, transition, and player freeze behavior. |

**Returns**

- **camera** — session handle on success.
- **reason** — explanation when another session prevents start.

**Example**

```lua
local cam, err = Kora.freecam.start({
    maxDistance = 50.0,
    focusCoords = vector3(100.0, 200.0, 30.0),
    upControl = 44,
    downControl = 38,
})
if not cam then return print(err) end
cam.setMovementMode('grid')
-- Later: cam.stop()
```

**Representative console output**

```text
A camera opens, the player is frozen when safe, and the returned handle can control the view.
```

### `Kora.freecam.isActive()`

Checks whether any freecam session is running.

**Parameters**



**Returns**

- **active** — boolean.

**Example**

```lua
if Kora.freecam.isActive() then print("Camera is in use") end
```

**Representative console output**

```text
Returns true while a freecam session is active.
```

## Limits and related APIs

start returns false and a reason rather than taking over another resource’s active freecam.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/freecam/docs.md` or `local/freecam/docs.md`) that the reference above does not state.

`Kora.freecam.start(options?)` starts one owner-bound scripted camera. It freezes the player and returns `false, reason` while another freecam is active.

```lua
local cam = assert(Kora.freecam.start({
    maxDistance = 50.0,
    zone = buildZone,
    focusCoords = vector3(100.0, 200.0, 30.0),
    upControl = 44,
    downControl = 38,
}))

cam.setFocus(nil)
cam.setMovementMode('grid')
cam.stop()
```

Mouse + WASD flies the camera; Shift accelerates it. `focusCoords` keeps the lens aimed at that point and suppresses mouse-look. Any movement step outside the optional radius or zone is ignored. Per-session `moveSpeed`, `lookSensitivity`, `fastMultiplier`, `transitionMs`, `upControl`, `downControl`, and `freezePlayer` options preserve specialized editor behavior without another camera loop. `freezePlayer` defaults to `Config.freecam.freezePlayer` (true); the ped is never frozen while falling, jumping, ragdolling or airborne (movement input is blocked regardless).

The handle provides `stop(reason?)`, `isActive()`, `getCoords()`, `getRotation()`, `getCamera()`, `getMovementMode()`, `setMovementMode(mode)`, and `setFocus(coordsOrNil)`. `getCamera()` exposes the native handle for helpers such as `Kora.raycast.fromCam`.

`Kora.freecam.isActive()` reports whether any freecam session is currently running.
