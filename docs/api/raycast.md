---
title: "Raycast"
sidebar_position: 31
---


# Raycast

Casts a line through the client’s rendered world and reports whether it hit, the hit vector3, entity handle, and surface normal. Use a one-call helper for a single ray, or start several rays together when they must describe the same frame.

Namespace: `Kora.raycast` · Source: `modules/raycast/client.lua`

## Coordinate grabber options

Pass these values in the optional data table to customize getCoords. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `type?` | 'object' | Enable temporary object-preview mode. |
| `object?` | string \| integer | Preview model name or finite integer hash. Only used in object mode. |
| `heading?` | number | Initial object heading in degrees. Defaults to 180. |
| `maxDistance?` | number | Positive maximum ray length in metres. Defaults to 50. |
| `flags?` | integer | Shape-test intersection flags. Defaults to all intersections. |

## Ray return values

When hit is true, coords is a vector3. entity is an entity handle, except 0 means the ray struck world geometry such as a wall or floor. Check entity ~= 0 before passing it to an entity native.

## Starting parallel rays

The game resolves shape tests once per frame. Start all rays that should describe the same moment, then await each. Awaiting one before starting the next serializes the work across frames.

## Coordinate grabber cleanup

Only one coordinate grabber can be active. It releases its controls and UI and deletes any temporary preview on confirmation, cancel, errors, or resource stop.

## Functions

Cast between explicit points, from a camera, or begin a non-blocking shape test and read it later.

### `Kora.raycast.fromCoords(startCoords, endCoords, flags?, ignoreEntity?)`

Starts a world ray and waits until it settles. A shape test still pending after one second is treated as a miss.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `startCoords` | vector3 | Finite ray origin. |
| `endCoords` | vector3 | Finite destination point. |
| `flags?` | integer | Shape-test intersection mask. Defaults -1 for world, vehicles, peds, objects, and water. |
| `ignoreEntity?` | integer | Entity to exclude. Defaults to the local player ped. |

**Returns**

- **hit** — boolean indicating whether the ray struck anything.
- **coords** — vector3 hit position, present only on a hit.
- **entity** — struck entity handle; 0 means bare world geometry.
- **normal** — vector3 surface normal, present only on a hit.

**Example**

```lua
local hit, coords, entity = Kora.raycast.fromCoords(vector3(100.0, 200.0, 30.0), vector3(100.0, 200.0, 0.0))
if hit then print('Hit entity:', entity) end
```

**Representative console output**

```text
Reports the first hit along the segment, or hit=false if no geometry was struck.
```

### `Kora.raycast.fromCamera(maxDistance, flags?, ignoreEntity?)`

Builds a ray from the gameplay camera’s position and direction, then waits for the result.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `maxDistance` | number | Positive finite maximum ray length in metres. |
| `flags?` | integer | Intersection mask. Defaults to all supported intersections. |
| `ignoreEntity?` | integer | Entity excluded from the hit test; defaults to the local player ped. |

**Returns**

- **hit** — boolean indicating whether the ray struck anything.
- **coords** — vector3 hit position, present only on a hit.
- **entity** — struck entity handle; 0 means bare world geometry.
- **normal** — vector3 surface normal, present only on a hit.

**Example**

```lua
local hit, coords, entity = Kora.raycast.fromCamera(50.0)
if hit then print('Aiming at:', entity == 0 and 'world' or entity) end
```

**Representative console output**

```text
Reports what the player’s gameplay camera is pointing at within 50 metres.
```

### `Kora.raycast.fromCam(cam, maxDistance, flags?, ignoreEntity?)`

Casts from a scripted camera, such as a freecam camera handle.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `cam` | integer | Scripted camera handle. |
| `maxDistance` | number | Positive finite maximum ray length in metres. |
| `flags?` | integer | Optional intersection mask. |
| `ignoreEntity?` | integer | Optional ignored entity; defaults to the local player ped. |

**Returns**

- **hit** — boolean indicating whether the ray struck anything.
- **coords** — vector3 hit position, present only on a hit.
- **entity** — struck entity handle; 0 means bare world geometry.
- **normal** — vector3 surface normal, present only on a hit.

**Example**

```lua
local hit, coords, entity = Kora.raycast.fromCam(cameraHandle, 50.0)
if hit then print('Freecam hit:', entity) end
```

**Representative console output**

```text
Reports the surface or entity the scripted camera points at.
```

### `Kora.raycast.start(startCoords, endCoords, flags?, ignoreEntity?)`

Starts an asynchronous ray and immediately returns its raw handle. Read it later with await or poll.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `startCoords` | vector3 | Finite ray origin. |
| `endCoords` | vector3 | Finite ray destination. |
| `flags?` | integer | Optional intersection mask; defaults to all. |
| `ignoreEntity?` | integer | Optional entity to exclude. |

**Returns**

- **rayHandle** — handle accepted by await and poll.

**Example**

```lua
local ray = Kora.raycast.start(origin, destination)
local hit, coords, entity = Kora.raycast.await(ray)
```

**Representative console output**

```text
Returns from start immediately; await later returns the settled hit result.
```

### `Kora.raycast.startFromCamera(maxDistance, flags?, ignoreEntity?)`

Starts a non-blocking ray in the gameplay camera direction.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `maxDistance` | number | Positive finite length in metres. |
| `flags?` | integer | Optional intersection mask. |
| `ignoreEntity?` | integer | Optional ignored entity. |

**Returns**

- **rayHandle** — handle accepted by await and poll.

**Example**

```lua
local ray = Kora.raycast.startFromCamera(10.0, 511)
-- Start other same-frame rays before awaiting.
local hit = Kora.raycast.await(ray)
```

**Representative console output**

```text
Starts the camera ray immediately and later returns its result.
```

### `Kora.raycast.await(rayHandle)`

Waits frame by frame for a started ray to settle, up to one second. A ray already settled by another wait returns immediately.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `rayHandle` | integer | Handle returned by start or startFromCamera. |

**Returns**

- **hit** — boolean indicating whether the ray struck anything.
- **coords** — vector3 hit position, present only on a hit.
- **entity** — struck entity handle; 0 means bare world geometry.
- **normal** — vector3 surface normal, present only on a hit.

**Example**

```lua
local ray = Kora.raycast.startFromCamera(30.0)
local hit, coords, entity, normal = Kora.raycast.await(ray)
```

**Representative console output**

```text
Returns the settled hit tuple.
```

### `Kora.raycast.poll(rayHandle)`

Reads a ray without yielding. Use it from a caller-owned tick loop when waiting inside the helper would be inconvenient.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `rayHandle` | integer | Handle returned by start or startFromCamera. |

**Returns**

- **settled** — boolean; ignore the remaining values when false.
- **hit** — boolean result after settlement.
- **coords** — vector3 hit position, if hit.
- **entity** — entity handle, with 0 for world geometry.
- **normal** — vector3 surface normal, if hit.

**Example**

```lua
local ray = Kora.raycast.startFromCamera(20.0)
CreateThread(function()
    while true do
        local settled, hit, coords, entity = Kora.raycast.poll(ray)
        if settled then
            if hit then print('Hit:', entity) end
            break
        end
        Wait(0)
    end
end)
```

**Representative console output**

```text
The loop yields its own frame until the ray settles, then prints the hit entity if one was struck.
```

### `Kora.raycast.getCoords(data?)`

Opens a coordinate grabber using the gameplay camera. E confirms the current hit; Backspace cancels. Object mode creates a temporary local preview that is removed when the tool ends.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `data?` | table | Optional type, object model, heading, maxDistance, and flags settings. See options above. |

**Returns**

- **result** — table with coords vector4 and optional object/heading details, or nil when cancelled.

**Example**

```lua
local result = Kora.raycast.getCoords({ type = 'object', object = 'prop_bin_08' })
if result then print(result.coords) end
```

**Representative console output**

```text
Returns rounded coordinates and a heading when the object placement is confirmed.
```

## Limits and related APIs

Raycasts are client-only because they inspect the local rendered world. Pending shape-test output is never exposed as a valid hit result.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/raycast/docs.md` or `local/raycast/docs.md`) that the reference above does not state.

### API

#### `Kora.raycast.fromCamera(maxDistance, flags, ignoreEntity)`
Convenience wrapper: builds the ray from the gameplay camera's position/rotation out to `maxDistance`, then calls `fromCoords`. Lets a player "look at it" instead of supplying coordinates.

##### Example
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

#### `Kora.raycast.start(startCoords, endCoords, flags, ignoreEntity)`
Fires the same shape test `fromCoords` does but returns immediately, handing back the raw ray handle instead of a settled result. Pair it with `Kora.raycast.await` or `Kora.raycast.poll`.

The engine resolves shape tests once per frame. A caller that needs several rays describing the same instant -- a targeting resource firing a broad world mask and a narrow entity mask, say -- should start all of them and only then await them: awaiting each ray before starting the next serialises them, costing one extra frame of latency and one extra thread wake-up per ray for information the first frame already had.

#### `Kora.raycast.await(rayHandle)`
Waits for a handle from `start`/`startFromCamera` to settle (yielding a frame at a time, bounded to one second, exactly like `fromCoords`) and reports it.

A handle that has already settled -- because another ray started in the same frame was awaited first -- returns immediately without yielding at all. That is what makes starting several rays together cheaper than firing them one at a time.

### Coordinate grabber

#### `Kora.raycast.getCoords(data?)`

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
