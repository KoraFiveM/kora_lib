---
title: "Entities module"
sidebar_position: 27
---

# Entities module

## Overview
The entities module spawns local (non-networked) peds, objects, and vehicles for the calling client only, streaming the model automatically and cleaning entities up automatically when the resource that created them stops.

## API

### `Kora.entities.createVehicle(model, coords, vehicleType)` (server)

Creates a networked vehicle with `CreateVehicleServerSetter`, making it
compatible with OneSync strict entity lockdown. Returns its network ID for
clients or garage state. `vehicleType` defaults to `automobile`; use `bike`,
`boat`, `heli`, `plane`, `submarine`, `trailer`, or `train` when appropriate.

```lua
local netId, err = Kora.entities.createVehicle('sultan', {
    x = 100.0, y = 200.0, z = 30.0, w = 90.0,
})
```

### `Kora.entities.create(model, coords, options)`
Creates a local entity.

#### Parameters
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

#### Returns
- `number | false` -- The created entity handle, or `false` if the model never loaded or the entity failed to create.
- `string | nil` -- The reason for failure, when the first value is `false`.

#### Behavior
1. The calling resource is captured immediately via `GetInvokingResource()` (falling back to `GetCurrentResourceName()`), before any streaming wait happens.
2. `model` is streamed with `Kora.stream.loadModel`; inside its callback, the now-resolved model hash is classified with `IsModelAPed`/`IsModelAVehicle` (anything else falls back to `object`), the matching entity is created, and the model asset is released automatically right after, exactly as `loadModel` already documents.
3. The entity is created non-networked and is not registered as a script-host mission entity -- it exists only for the local client.
4. `freeze`/`blockNonTempEvents`/`invincible` (resolved from `preset` + explicit overrides) are applied immediately after creation. `blockNonTempEvents` only takes effect if the model was classified as a ped.
5. The entity is tracked against the invoking resource and automatically deleted if that resource stops.

#### Example
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

### `Kora.entities.remove(entity)`
Deletes one of the calling resource's tracked entities on demand. A different
resource's handle is refused, so the export cannot delete arbitrary local
entities.

#### Parameters
- `entity: number` -- An entity handle previously returned by `create`.

#### Returns
- `boolean` -- `true` if deleted.
- `string | nil` -- Set when the entity is untracked, owned by another
  resource, or no longer exists.

#### Example
```lua
local entity = Kora.entities.create('a_m_y_beach_01', coords, { preset = 'static' })

-- later, before the resource stops
local ok, err = Kora.entities.remove(entity)
if not ok then print('remove failed:', err) end
```

### `Kora.entities.createScoped(model, coords, options)`
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

#### Parameters
- `model`, `coords` — Same as `create`.
- `options` — All options accepted by `create`, plus:
  - `radius: number` — Required. A finite radius greater than zero, in metres.

#### Returns
- `KoraScopedEntityHandle` — A persistent registration handle:
  - `id: number` — The stable scope-registration ID.
  - `resource: string` — The resource that owns it.
  - `entity: number | nil` — The currently spawned local entity, or `nil` while outside its radius. Do not retain this value across an exit/re-entry.
  - `remove(): boolean` — Deletes the active entity, if any, and unregisters the scope. Returns `false` for a foreign or already removed scope.
  - `isSpawned(): boolean` — Whether there is a live local entity right now.

#### Example
```lua
local guard = Kora.entities.createScoped('a_m_y_beach_01', vector4(100.0, 200.0, 30.0, 90.0), {
    radius = 75.0,
    preset = 'static',
})

-- guard.entity is nil until this client enters the 75m radius.
-- `guard.remove()` is optional on resource stop; cleanup is automatic.
```

### Networked entities

`Kora.entities.requestControl(entity, timeout?)` requests control of an existing
networked entity. `Kora.entities.delete(entity, timeout?)` obtains control,
marks it as mission-owned, then deletes it. These functions intentionally do
not require kora_lib ownership; call them only after your resource's server has
authorized the operation. `timeout` defaults to `1000` only when omitted and
must otherwise be a non-negative integer in milliseconds.

## Notes
- Entities from this module are never networked -- each client that calls `create` spawns its own independent copy, invisible to other players.
- Entity kind is always auto-detected from `model` -- there's no way to force a mismatched interpretation (e.g. spawn a vehicle model as a ped).
- A real `vector4` only has `.w` for heading, not `.heading` -- `.heading` is read as a fallback for plain tables that use that name by convention instead.
- `pedType` passed to the underlying `CreatePed` native is functionally inert (confirmed via upstream native reference) -- ped type is assigned automatically by the game.
- `blockNonTempEvents` only ever affects peds; passing it for an object/vehicle is a harmless no-op, not an error.
- If a resource stops without ever calling `Kora.entities.remove` on its entities, they are still cleaned up automatically via `onClientResourceStop`.
