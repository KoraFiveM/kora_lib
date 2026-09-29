# Freecam

`QB.freecam.start(options?)` starts one owner-bound scripted camera. It freezes the player and returns `false, reason` while another freecam is active.

```lua
local cam = assert(QB.freecam.start({
    maxDistance = 50.0,
    zone = buildZone,
    focusCoords = vector3(100.0, 200.0, 30.0),
}))

cam.setFocus(nil)
cam.setMovementMode('grid')
cam.stop()
```

Mouse + WASD flies the camera; Shift accelerates it. `focusCoords` keeps the lens aimed at that point and suppresses mouse-look. Any movement step outside the optional radius or zone is ignored. The handle provides `stop(reason?)`, `isActive()`, `getCoords()`, `getRotation()`, `getMovementMode()`, `setMovementMode(mode)`, and `setFocus(coordsOrNil)`.

`QB.freecam.isActive()` reports whether any freecam session is currently running.
