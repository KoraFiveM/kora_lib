---
title: "Entities"
sidebar_position: 27
---


# Entities

## Client

Creates and tracks client-local peds, objects, and vehicles, plus scoped local entities that exist only while the player is nearby. Models are streamed on demand and owned entities are cleaned up when the calling resource stops.

Namespace: `Kora.entities` · Source: `modules/entities/client.lua`

### How it works

create auto-detects model type and always creates non-networked entities. createScoped uses the spatial zone grid and creates a fresh local handle on each entry; its registration handle persists across entries. remove is ownership restricted. requestControl/delete operate on existing networked entities and require the caller to have already obtained server authorization.

### create options table

createScoped accepts the same fields plus a required radius in metres. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `heading??` | number | Finite heading overriding coords.w or plain-table coords.heading; defaults to 0.0. |
| `preset??` | string | Currently static: freeze, blockNonTempEvents, and invincible default true. |
| `freeze??` | boolean | Explicit override for preset freeze behavior. |
| `blockNonTempEvents??` | boolean | Explicit ped-only event behavior override; ignored for objects/vehicles. |
| `invincible??` | boolean | Explicit override for invincibility. |
| `radius` | number | Required by createScoped; positive finite metres around coords. |

### Local and networked entities

create and createScoped do not network entities or register them as script-host mission entities; other clients do not see these copies. The module owns cleanup. createVehicle, described in the server realm, creates a OneSync networked vehicle and returns its network id.

### Scope handle

The scope handle contains stable id/resource values, entity for the current spawn or nil outside range, remove() to unregister and delete, and isSpawned() to query live state. Do not keep an entity handle across exit/re-entry. A pending model load is guarded so a leave/re-enter does not lose the intended spawn.

### Functions

Create local objects, manage their lifetime, register proximity-scoped content, or request control of an authorized networked entity.

#### `Kora.entities.create(model, coords, options?)`

Streams model and creates a local entity at coords. Type is detected from model metadata.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `model` | string \| number | Model name or hash. |
| `coords` | vector3 \| vector4 | Finite position; vector4.w supplies heading. |
| `options?` | table | Optional heading and entity behavior settings. |

**Returns**

- **entity** — local handle, or false on load/create failure.
- **reason** — failure explanation when false is returned.

**Example**

```lua
local entity, err = Kora.entities.create('a_m_y_beach_01', vector4(100.0, 200.0, 30.0, 90.0), {
    preset = 'static',
})
if not entity then print(err) end
```

**Representative console output**

```text
Creates a local static ped with heading 90 degrees.
```

#### `Kora.entities.createScoped(model, coords, options)`

Registers a local entity that spawns only within options.radius metres of coords.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `model` | string \| number | Model name or hash. |
| `coords` | vector3 \| vector4 | Finite fixed world position. |
| `options` | table | Required options including positive radius and create settings. |

**Returns**

- **scope** — persistent handle with id/resource/entity, remove(), and isSpawned().

**Example**

```lua
local scope = Kora.entities.createScoped('prop_bin_08', vector3(100.0, 200.0, 30.0), { radius = 75.0, freeze = true })`
if scope:isSpawned() then print(scope.entity) end
```

**Representative console output**

```text
The entity handle is nil while outside range and changes after re-entry.
```

#### `Kora.entities.remove(entity)`

Deletes one local entity tracked to the calling resource.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entity` | number | Handle returned by create. |

**Returns**

- **removed** — boolean.
- **reason** — error for untracked, foreign-owned, or missing handles.

**Example**

```lua
local ok, err = Kora.entities.remove(entity)
```

**Representative console output**

```text
Returns true after deleting and untracking the local entity.
```

#### `Kora.entities.requestControl(entity, timeout?)`

Requests network control for an existing live networked entity, waiting up to timeout.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entity` | number | Existing networked entity handle. |
| `timeout?` | integer | Non-negative timeout in milliseconds; defaults to 1000. |

**Returns**

- **controlled** — boolean.

**Example**

```lua
local controlled = Kora.entities.requestControl(vehicle, 1500)
```

**Representative console output**

```text
Returns false if control cannot be acquired within the bound.
```

#### `Kora.entities.delete(entity, timeout?)`

Obtains control, marks the entity as mission-owned, and deletes it.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entity` | number | Existing networked entity handle. |
| `timeout?` | integer | Non-negative control timeout in milliseconds; defaults to 1000. |

**Returns**

- **deleted** — boolean.

**Example**

```lua
local deleted = Kora.entities.delete(networkedVehicle, 1500)
```

**Representative console output**

```text
This is intended for a server-authorized network entity, not arbitrary client deletion.
```

### Limits and related APIs

Model load or native creation can fail and returns false plus a reason. options boolean fields are validated before streaming. Only remove entities owned by the caller; requestControl/delete have no ownership restriction, so authorize those operations on the server first.

## Server

Creates networked vehicles through the server setter native for OneSync-compatible server ownership.

Namespace: `Kora.entities` · Source: `modules/entities/server.lua`

### Functions

Use createVehicle when the vehicle must exist as a networked server entity and clients need its network id.

#### `Kora.entities.createVehicle(model, coords, vehicleType?)`

Creates a server networked vehicle with CreateVehicleServerSetter and returns its network id.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `model` | string \| number | Vehicle model name or hash. |
| `coords` | vector3 \| vector4 \| table | Finite world coordinates; vector4.w or table heading can supply heading. |
| `vehicleType?` | string | Server vehicle class; defaults to automobile. |

**Returns**

- **netId** — network id, or false/nil with error when creation fails.
- **reason** — failure detail when provided.

**Example**

```lua
local netId, err = Kora.entities.createVehicle('sultan', vector4(100.0, 200.0, 30.0, 90.0), 'automobile')
if not netId then print(err) end
```

**Representative console output**

```text
Returns the server-created vehicle network id for later state or client references.
```

### Limits and related APIs

Supported vehicle types include automobile, bike, boat, heli, plane, submarine, trailer, and train. Validate player permissions and spawn location before calling; the helper does not define gameplay policy.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/entities/docs.md` or `local/entities/docs.md`) that the reference above does not state.

### API

#### `Kora.entities.createVehicle(model, coords, vehicleType)` (server)

Creates a networked vehicle with `CreateVehicleServerSetter`, making it
compatible with OneSync strict entity lockdown. Returns its network ID for
clients or garage state. `vehicleType` defaults to `automobile`; use `bike`,
`boat`, `heli`, `plane`, `submarine`, `trailer`, or `train` when appropriate.

```lua
local netId, err = Kora.entities.createVehicle('sultan', {
    x = 100.0, y = 200.0, z = 30.0, w = 90.0,
})
```

#### `Kora.entities.create(model, coords, options)`
Creates a local entity.

##### Parameters
- `model: string | number` -- The model name or hash to spawn. Its kind (ped/vehicle/object) is detected automatically -- there's no type parameter to set.
- `coords: vector3 | vector4 | {x, y, z, w?, heading?}` -- Finite world coordinates. `x`/`y`/`z` are always read; a finite heading on `coords` (`.w` for a real `vector4`, or `.heading` for a plain table using that convention) is used unless `options.heading` overrides it.
- `options: table | nil`
  - `heading: number` -- Finite number that overrides any heading on `coords`. Falls back to `coords.w`, then `coords.heading`, then `0.0`.
  - `preset: "static"` -- Applies `freeze = true`, `blockNonTempEvents = true`, and `invincible = true` before any explicit overrides below.
  - `freeze: boolean` -- Overrides the preset's freeze value, in either direction.
  - `blockNonTempEvents: boolean` -- Overrides the preset's value, in either direction. Peds only; ignored for objects/vehicles.
  - `invincible: boolean` -- Overrides the preset's invincibility value, in either direction.

When supplied, `options` must be a table and every documented boolean option
must be a boolean; invalid calls are rejected before kora_lib requests a model or
registers a scoped zone.

##### Example
```lua
-- A frozen, invincible, non-reactive decorative ped -- type is detected from the model
local entity, err = Kora.entities.create('a_m_y_beach_01', GetEntityCoords(PlayerPedId()), {
    preset = 'static',
})

if not entity then
    print('failed to spawn entity:', err)
end
```

```lua
-- Heading taken from the vector4's .w, no options.heading needed
Kora.entities.create('a_m_y_beach_01', vector4(100.0, 200.0, 30.0, 90.0), {
    preset = 'static',
})
```

```lua
-- A prop, frozen but without disabling any ped-only behavior (it's not a ped)
Kora.entities.create('prop_bin_08', vector3(100.0, 200.0, 30.0), {
    freeze = true,
})
```

Called cross-resource via export (e.g. from resource `my_script`):
```lua
local entity = exports.kora_lib:entities_create('a_m_y_beach_01', coords, { preset = 'static' })
-- tracked as owned by 'my_script'; deleted automatically if my_script stops
```

#### `Kora.entities.createScoped(model, coords, options)`
Registers a client-local entity that is spawned only while the local player is
within `options.radius` metres of `coords`. The entity is deleted on exit and
is created again as a new local handle on a later entry. This is intended for
decorative props, ambient peds, and similar local-only content spread across a
large map.

It reuses `Kora.zones`' spatial grid, so scopes far from the player do not load a
model or create a GTA entity. It does not make the entity networked; each
client independently spawns its own copy when in range.

Model streaming runs asynchronously. Leaving and re-entering while a load is
still pending keeps the scope marked inside, so the completed spawn is retained;
spawn errors always release the in-flight guard and allow a later enter to
retry.

#### Networked entities

`Kora.entities.requestControl(entity, timeout?)` requests control of an existing
networked entity. `Kora.entities.delete(entity, timeout?)` obtains control,
marks it as mission-owned, then deletes it. These functions intentionally do
not require kora_lib ownership; call them only after your resource's server has
authorized the operation. `timeout` defaults to `1000` only when omitted and
must otherwise be a non-negative integer in milliseconds.
