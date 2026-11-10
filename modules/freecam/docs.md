# Freecam

`Kora.freecam.start(options?)` starts one owner-bound scripted camera. It freezes the player and returns `false, reason` while another freecam is active.

The freecam supports camera-relative movement and grid movement. Holding the fast-move control applies `fastMultiplier`; an optional `focusCoords` keeps the camera pointed at one position and disables mouse-look. When `maxDistance` or `zone` is configured, a candidate movement step is ignored if it leaves the permitted area.

## API

### `Kora.freecam.start(options?)`
Starts the freecam at the supplied position and rotation, or at the current gameplay camera when they are omitted. Only one freecam can be active at once. The player is frozen by default until the session stops.

#### Parameters
- `options: table | nil` — Defaults to an empty table.
  - `coords: vector3 | vector4 | {x, y, z}?` — Initial camera position. Defaults to the current gameplay camera coordinates. Components must be finite.
  - `rotation: vector3 | vector4 | {x, y, z}?` — Initial camera rotation. Defaults to the current gameplay camera rotation.
  - `fov: number?` — Field of view from `10.0` to `120.0`. Defaults to the current gameplay camera FOV.
  - `maxDistance: number?` — Positive finite radius from the initial position. Candidate movement outside this radius is ignored.
  - `zone: QBZoneHandle?` — Optional zone handle with a callable `contains` method. Movement outside the zone is ignored.
  - `focusCoords: vector3 | vector4 | {x, y, z}?` — Optional point the camera should stay aimed at. When set, mouse-look is suppressed.
  - `movementMode: "camera" | "grid"?` — Defaults to `"camera"`. Camera mode moves relative to camera orientation; grid mode moves along world X/Y axes.
  - `moveSpeed: number?` — Base movement speed in metres per second, before the fast multiplier. Defaults to `Config.freecam.cameraMoveSpeed`; must be positive and finite.
  - `lookSensitivity: number?` — Degrees per raw mouse-look unit. Defaults to `Config.freecam.cameraLookSensitivity`; must be positive and finite.
  - `fastMultiplier: number?` — Movement multiplier while the fast-move control is held. Defaults to `Config.freecam.shiftMultiplier`; must be positive and finite.
  - `transitionMs: number?` — Script-camera blend duration. Defaults to `Config.freecam.cameraTransitionMs`; must be finite and non-negative.
  - `upControl: integer?` — Optional non-negative GTA control ID for direct upward movement.
  - `downControl: integer?` — Optional non-negative GTA control ID for direct downward movement.
  - `freezePlayer: boolean?` — Whether to freeze the local ped while the camera is active. Defaults to `true`.

Invalid option types, out-of-range FOV, non-finite coordinates, or a zone without `contains` raise an assertion before the session starts. An active session prevents a second session from starting.

#### Returns
- `handle` — A session handle with the methods below.
- `false, reason` — Returns `false, "A freecam session is already active."` when another session is running.
- Raises an assertion error — Invalid options or failure to create the native scripted camera.

#### Example
```lua
local cam = assert(Kora.freecam.start({
    maxDistance = 50.0,
    zone = buildZone,
    focusCoords = vector3(100.0, 200.0, 30.0),
    movementMode = 'grid',
    upControl = 44,
    downControl = 38,
}))

cam.setFocus(nil)
cam.setMovementMode('grid')
cam.stop()
```

Mouse + WASD flies the camera; Shift accelerates it. `focusCoords` keeps the lens aimed at that point and suppresses mouse-look. Any movement step outside the optional radius or zone is ignored. Per-session `moveSpeed`, `lookSensitivity`, `fastMultiplier`, `transitionMs`, `upControl`, `downControl`, and `freezePlayer` options preserve specialized editor behavior without another camera loop.

The handle provides `stop(reason?)`, `isActive()`, `getCoords()`, `getRotation()`, `getCamera()`, `getMovementMode()`, `setMovementMode(mode)`, and `setFocus(coordsOrNil)`. `getCamera()` exposes the native handle for helpers such as `Kora.raycast.fromCam`.

`Kora.freecam.isActive()` reports whether any freecam session is currently running.

The handle returned from `start` controls only the session created by that call. These methods return `false` or `nil` after the session is no longer active, as indicated below.

### `handle.stop(reason?)`
Stops this session, restores scripted-camera rendering, releases its control lease, and unfreezes the player if this session froze them. An optional reason is accepted for call-site clarity; it does not change cleanup behavior.

#### Returns
- `boolean` — `true` when this handle stopped its active session; `false` if the session was already stopped or replaced.

### `handle.isActive()`
Checks whether this exact handle still owns the active session.

#### Returns
- `boolean` — `true` while its session is current; otherwise `false`.

### `handle.getCoords()`
Reads the current freecam world position as a plain coordinate table.

#### Returns
- `{x: number, y: number, z: number} | nil` — Current position, or `nil` after the session ends.

### `handle.getRotation()`
Reads the current camera rotation.

#### Returns
- `{pitch: number, roll: number, yaw: number} | nil` — Current rotation, or `nil` after the session ends.

### `handle.getCamera()`
Returns the native scripted-camera handle for APIs that need the camera itself, such as `Kora.raycast.fromCam`.

#### Returns
- `integer | nil` — Native camera handle while active; otherwise `nil`.

### `handle.getMovementMode()`
Reads the session's current movement mode.

#### Returns
- `"camera" | "grid" | nil` — Current mode, or `nil` after the session ends.

### `handle.setMovementMode(mode)`
Changes how subsequent movement is calculated.

#### Parameters
- `mode: "camera" | "grid"` — Camera-relative or world-grid movement mode.

#### Returns
- `boolean` — `true` when the handle updates the active session; `false` when the session is no longer current.

### `handle.setFocus(coordsOrNil)`
Changes or clears the point the camera stays aimed at. Passing `nil` clears the focus point and restores mouse-look.

#### Parameters
- `coordsOrNil: vector3 | vector4 | {x, y, z} | nil` — Finite world position to focus on, or `nil` to clear focus.

#### Returns
- `boolean` — `true` when the active session accepts the change; `false` when the session is no longer current.
- Raises an assertion error — A supplied point does not contain finite `x`, `y`, and `z` values.

## Controls and lifecycle

- Mouse movement changes camera rotation unless `focusCoords` is active. WASD moves the camera; Shift applies the configured fast multiplier.
- Grid mode constrains horizontal movement to world X/Y axes. Vertical controls can be supplied through `upControl` and `downControl`.
- Movement steps that cross `maxDistance` or fall outside `zone` are rejected; the camera remains at its previous valid position.
- The session captures its invoking resource for cleanup. Resource shutdown stops the session and restores the player.
