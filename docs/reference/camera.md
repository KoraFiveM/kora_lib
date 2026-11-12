---
title: "Camera overlay"
sidebar_position: 22
---

# Camera overlay

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
