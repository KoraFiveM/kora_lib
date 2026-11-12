---
title: "Freecam"
sidebar_position: 29
---

# Freecam

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
