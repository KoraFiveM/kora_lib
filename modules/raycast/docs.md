# Raycast module

## Overview
The raycast module fires world-geometry raycasts and reports what they hit -- coordinates, the struck entity (if any), and the surface normal. It was extracted out of `modules/zones`' in-world zone creator, which used a private camera-aim raycast purely to let a player place a zone point by looking at it. Promoted to its own module and public API so other resources (e.g. a targeting system) can reuse the same raycast primitive across resource boundaries.

## API

### `Kora.raycast.fromCoords(startCoords, endCoords, flags, ignoreEntity)`
Fires a raycast between two explicit points. The helper yields while the
asynchronous shape test is pending and returns only after status `2`
(complete); a result that remains pending for one second is treated as a miss.

#### Parameters
- `startCoords: vector3 | {x, y, z}` -- Ray origin; every component must be finite.
- `endCoords: vector3 | {x, y, z}` -- Ray destination; every component must be finite.
- `flags: integer | nil` -- `StartShapeTestRay` intersect flags. Defaults to `-1` (test against everything: world, vehicles, peds, objects, water).
- `ignoreEntity: integer | nil` -- Entity handle excluded from the test. Defaults to `PlayerPedId()`.

#### Returns
- `boolean` -- `true` if the ray hit something.
- `table | nil` -- {x, y, z} hit coordinates, only present on a hit.
- `number | nil` -- The entity handle struck, only present on a hit (`0` if the ray hit bare world geometry, not an entity).
- `table | nil` -- {x, y, z} surface normal at the hit point, only present on a hit.

### `Kora.raycast.fromCamera(maxDistance, flags, ignoreEntity)`
Convenience wrapper: builds the ray from the gameplay camera's position/rotation out to `maxDistance`, then calls `fromCoords`. Lets a player "look at it" instead of supplying coordinates.

#### Parameters
- `maxDistance: positive finite number` -- Maximum ray length, in meters.
- `flags: integer | nil` -- Same as `fromCoords`.
- `ignoreEntity: integer | nil` -- Same as `fromCoords`.

#### Returns
Same as `fromCoords`.

#### Example
```lua
local hit, coords, entity = Kora.raycast.fromCamera(50.0)
if hit then
    print(('aiming at %s at %.1f, %.1f, %.1f'):format(entity ~= 0 and ('entity ' .. entity) or 'world', coords.x, coords.y, coords.z))
end
```

Called cross-resource via export (e.g. from a targeting resource):
```lua
local hit, coords, entity = exports.kora_lib:raycast_fromCamera(3.0)
if hit and entity ~= 0 then
    -- entity is what the player is currently aiming at
end
```

### `Kora.raycast.fromCam(cam, maxDistance, flags, ignoreEntity)`
Convenience wrapper: builds the ray from a given scripted camera's position/rotation out to `maxDistance`, then calls `fromCoords`. Unlike `fromCamera`, which is hardwired to the gameplay camera, this accepts any scripted-camera handle -- for example, the native handle returned by `Kora.freecam.getCamera()` for the zone creator's aim raycast.

#### Parameters
- `cam: integer` -- Scripted camera handle, e.g. from `CreateCam`/`CreateCamWithParams`.
- `maxDistance: positive finite number` -- Maximum ray length, in meters.
- `flags: number | nil` -- Same as `fromCoords`.
- `ignoreEntity: number | nil` -- Same as `fromCoords`.

#### Returns
Same as `fromCoords`.

#### Example
```lua
local hit, coords, entity = Kora.raycast.fromCam(freecamHandle, 50.0)
if hit then
    print(('freecam aiming at %s at %.1f, %.1f, %.1f'):format(entity ~= 0 and ('entity ' .. entity) or 'world', coords.x, coords.y, coords.z))
end
```

### `Kora.raycast.start(startCoords, endCoords, flags, ignoreEntity)`
Fires the same shape test `fromCoords` does but returns immediately, handing back the raw ray handle instead of a settled result. Pair it with `Kora.raycast.await` or `Kora.raycast.poll`.

The engine resolves shape tests once per frame. A caller that needs several rays describing the same instant -- a targeting resource firing a broad world mask and a narrow entity mask, say -- should start all of them and only then await them: awaiting each ray before starting the next serialises them, costing one extra frame of latency and one extra thread wake-up per ray for information the first frame already had.

#### Parameters
Identical to `fromCoords`.

#### Returns
- `number` -- Ray handle. Only meaningful to `await`/`poll`.

### `Kora.raycast.startFromCamera(maxDistance, flags, ignoreEntity)`
The `fromCamera` equivalent of `start`: builds the ray from the gameplay camera and returns its handle without waiting.

#### Returns
- `number` -- Ray handle.

### `Kora.raycast.await(rayHandle)`
Waits for a handle from `start`/`startFromCamera` to settle (yielding a frame at a time, bounded to one second, exactly like `fromCoords`) and reports it.

A handle that has already settled -- because another ray started in the same frame was awaited first -- returns immediately without yielding at all. That is what makes starting several rays together cheaper than firing them one at a time.

#### Returns
Same as `fromCoords`.

### `Kora.raycast.poll(rayHandle)`
Non-blocking read of a started ray. Never yields, so a caller driving its own tick loop can start a ray on one tick and consume it on the next without parking a frame inside kora_lib.

#### Returns
- `boolean` -- `settled`. Every other value is meaningless while this is `false`.
- `boolean` -- `hit`.
- `table | nil` -- {x, y, z} hit coordinates.
- `number | nil` -- Entity handle struck (`0` for bare world geometry).
- `table | nil` -- {x, y, z} surface normal.

#### Example
```lua
-- Two masks describing the same instant, resolved in one frame instead of two.
local broad = Kora.raycast.startFromCamera(10.0, 511)
local entities = Kora.raycast.startFromCamera(10.0, 26)

local hit, coords, entity = Kora.raycast.await(broad)
local entityHit, entityCoords, entityHandle = Kora.raycast.await(entities) -- already settled
```

## Notes
- `fromCoords`/`fromCamera` are `start` + `await` in one call; they exist unchanged and remain the right choice for a one-off ray.
- Shape-test output values are undefined while `GetShapeTestResult` reports
  status `1`. kora_lib never exposes those pending coordinates/entity handles to
  callers; this prevents stale handles reaching entity natives such as
  `GetEntityModel`.
- `entityHit` is `0` (not `nil`) when the ray strikes bare world geometry rather than an entity -- check `entity ~= 0` before treating it as an entity handle.
- Client-only: raycasting only makes sense against the calling client's own rendered world/camera, so this module has no `shared.lua`/`server.lua`, the same shape as `modules/stream` and `modules/zones`.
- `modules/zones`' zone creator now calls `Kora.raycast.fromCamera` instead of its own private copy; behavior there is unchanged.

## Coordinate grabber

### `Kora.raycast.getCoords(data?)`

Runs a small blocking coordinate-capture tool using the gameplay camera. With
no options it draws a white orb at the current ray hit. Press E to return the
coordinates or Backspace to cancel. `data` must be a table when supplied;
only an omitted (`nil`) value selects the defaults.

```lua
local result = Kora.raycast.getCoords()
if result then print(result.coords.x, result.coords.y, result.coords.z) end
```

Pass an object model name or finite integer hash for a temporary prop preview. Left and Right adjust only
its heading; the preview is deleted when the grabber finishes and is never the
persisted object itself.

```lua
local result = Kora.raycast.getCoords({
    type = 'object',
    object = 'prop_bin_08',
})

if result then
    print(result.object, result.coords.x, result.coords.y, result.coords.z, result.coords.w)
end
```

The returned values are rounded to two decimal places. `coords.w` is included
only in object mode. Optional `heading`, `maxDistance`, and shape-test `flags`
can override the defaults of 180 degrees, 50 metres, and all intersections.
Numeric coordinate-grabber options must be finite integers where they are native
handles or flags, and `maxDistance` must be positive. Only one coordinate grabber may be active at once. UI, disabled controls, and
the local preview entity are cleaned up on confirmation, cancellation, errors,
or when either kora_lib or the calling resource stops.
