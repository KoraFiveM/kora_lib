# Camera overlay

`Kora.camera` owns the scripted camera lifecycle and the reusable, pointer-transparent camera HUD. It supports fixed CCTV networks and live player views for news recording or helicopter optics. It never takes NUI focus, so the game retains camera and movement input.

Opening a new session replaces the active one. Closing a session destroys its scripted camera, restores the previous player view mode, removes its instructional controls, and clears the HUD. Fixed camera coordinates are local to the client and are not networked by this module.

## API

### `Kora.camera.open(options)`
Opens the camera HUD and starts a session. When `options.cameras` contains at least one camera, the first camera is activated immediately. With no camera entries, the HUD can still show a live player-operated view for recording, helicopter optics, or operator use.

#### Parameters
- `options: table` — Required session configuration. The function validates the full options table and camera list before replacing the current session.
  - `mode: "cctv" | "recording" | "helicam" | "operator"` — Session mode. Defaults to `"operator"`.
  - `cameras: table[]` — Optional ordered list of fixed camera definitions. Defaults to an empty list. Each entry requires `coords`; see camera fields below.
  - `camera: table` — Backwards-compatible single-camera option. When supplied, it replaces `cameras` with a one-entry list.
  - `title: string` — HUD title, 1–80 characters. Defaults to `"SECURE CAMERA NETWORK"`.
  - `subtitle: string` — HUD subtitle, 1–80 characters. Defaults to `"CITYWIDE MONITORING"` in `cctv` mode or `"FIELD OPTICS"` otherwise.
  - `cameraLabel: string` — Default label when the active camera has no `label`, 1–80 characters. Defaults to `"CAM 01"` in `cctv` mode or `"LIVE UNIT"` otherwise.
  - `recording: boolean` — Initial REC indicator state. Defaults to `false`.
  - `controls: boolean` — Whether to show the exit and camera-switch instructions. Defaults to `true`.
  - `timestamp: boolean` — Whether the HUD shows elapsed time. Defaults to `true`.
  - `viewMode: number` — Optional GTA follow-camera mode from `0` to `4`. The current mode is saved before this value is applied and restored when the session closes.
- `cameras[].coords: vector3 | vector4 | {x, y, z}` — Required finite world position for that fixed camera.
- `cameras[].target: vector3 | vector4 | {x, y, z}` — Optional finite world position for the camera to point at. When omitted, the camera uses its `rotation` instead.
- `cameras[].rotation: vector3 | vector4 | {x, y, z}` — Optional finite rotation. Defaults to zero rotation.
- `cameras[].fov: number` — Optional field of view from `10.0` to `120.0`. Defaults to `52.0`.
- `cameras[].label: string` — Optional camera label, 1–80 characters. Shown in the HUD for the selected camera.
- `cameras[].location: string?` — Optional location text shown in the HUD for the selected camera.

#### Returns
- `true` — The session was opened. Opening while another session is active closes the previous session first.
- Raises an assertion error — `options` or camera entries are malformed, required coordinates are missing, text fields are empty/too long, a numeric value is out of range, or a boolean option has the wrong type.

#### Example
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
```

### `Kora.camera.close(reason)`
Closes the active camera session, restores the player's previous camera view, hides any instructional controls created by the session, and tells the HUD why it closed. Calling this when no session is active is safe.

#### Parameters
- `reason: string | nil` — Optional close reason sent to the HUD. Defaults to `"closed"`.

#### Returns
- `true` — An active session was closed and its camera state was cleaned up.
- `false` — No session was active, so nothing changed.

### `Kora.camera.isOpen()`
Checks whether a camera HUD session is currently active. A session may be active without a scripted camera when using a player-operated mode.

#### Returns
- `boolean` — `true` while the camera session is open; otherwise `false`.

### `Kora.camera.next()`
Switches to the next fixed camera in the current list. The list wraps from the last camera back to the first. This does not change player-operated sessions or a one-camera list.

#### Returns
- `true` — A different camera was activated.
- `false` — No session is open or fewer than two fixed cameras are configured.

### `Kora.camera.previous()`
Switches to the previous fixed camera in the current list. The list wraps from the first camera back to the last.

#### Returns
- `true` — A different camera was activated.
- `false` — No session is open or fewer than two fixed cameras are configured.

### `Kora.camera.setRecording(recording)`
Updates the HUD's recording indicator without changing the active camera or restarting the session.

#### Parameters
- `recording: boolean` — Whether the HUD should show recording as active. Other value types raise an assertion error.

#### Returns
- `true` — The indicator was updated on an active session.
- `false` — No session is open; no HUD update was sent.

#### Example
```lua
Kora.camera.open({ mode = 'recording' })
Kora.camera.setRecording(true)

-- Stop the session when recording ends.
Kora.camera.setRecording(false)
Kora.camera.close('finished')
```

`Kora.camera.isOpen()` reports whether the overlay is active. `Kora.camera.setRecording(true)` updates the REC indicator while leaving the current view in place.

- When `controls` is enabled, the module shows an exit instruction. It adds next/previous instructions only when at least two fixed cameras are configured.
- Escape and the configured exit control close the session. Next/previous controls call the same public switching functions.
- While open, the module sends elapsed-time updates to the HUD once per second; the browser can advance the display between updates.
- `viewMode` is restored when the session closes, including when a replacement session closes the previous one.
- If the resource stops while the session is active, the scripted camera and saved player view are restored.
- A camera entry's `target` takes precedence over its `rotation` because the created camera is pointed at the target position.

For a player-operated view, omit `cameras` and use `mode = 'recording'`, `mode = 'helicam'`, or `mode = 'operator'`. `viewMode` can temporarily set the GTA follow-camera mode and is restored when the overlay closes.
