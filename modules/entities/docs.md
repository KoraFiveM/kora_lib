# Entities module

## Overview
The entities module spawns local (non-networked) peds, objects, and vehicles for the calling client only, streaming the model automatically and cleaning entities up automatically when the resource that created them stops.

## API

### `QB.entities.create(model, coords, options)`
Creates a local entity.

#### Parameters
- `model: string | number` -- The model name or hash to spawn. Its kind (ped/vehicle/object) is detected automatically -- there's no type parameter to set.
- `coords: vector3 | vector4 | {x, y, z, w?, heading?}` -- World coordinates. `x`/`y`/`z` are always read; a heading on `coords` (`.w` for a real `vector4`, or `.heading` for a plain table using that convention) is used unless `options.heading` overrides it.
- `options: table | nil`
  - `heading: number` -- Overrides any heading on `coords`. Falls back to `coords.w`, then `coords.heading`, then `0.0`.
  - `preset: "static"` -- Applies `freeze = true` and `blockNonTempEvents = true` before any explicit overrides below.
  - `freeze: boolean` -- Overrides the preset's freeze value, in either direction.
  - `blockNonTempEvents: boolean` -- Overrides the preset's value, in either direction. Peds only; ignored for objects/vehicles.

#### Returns
- `number | false` -- The created entity handle, or `false` if the model never loaded or the entity failed to create.
- `string | nil` -- The reason for failure, when the first value is `false`.

#### Behavior
1. The calling resource is captured immediately via `GetInvokingResource()` (falling back to `GetCurrentResourceName()`), before any streaming wait happens.
2. `model` is streamed with `QB.stream.loadModel`; inside its callback, the now-resolved model hash is classified with `IsModelAPed`/`IsModelAVehicle` (anything else falls back to `object`), the matching entity is created, and the model asset is released automatically right after, exactly as `loadModel` already documents.
3. The entity is created non-networked and is not registered as a script-host mission entity -- it exists only for the local client.
4. `freeze`/`blockNonTempEvents` (resolved from `preset` + explicit overrides) are applied immediately after creation. `blockNonTempEvents` only takes effect if the model was classified as a ped.
5. The entity is tracked against the invoking resource and automatically deleted if that resource stops.

#### Example
```lua
-- A frozen, non-reactive decorative ped -- type is detected from the model
local entity, err = QB.entities.create('a_m_y_beach_01', GetEntityCoords(PlayerPedId()), {
    preset = 'static',
})

if not entity then
    print('failed to spawn entity:', err)
end
```

```lua
-- Heading taken from the vector4's .w, no options.heading needed
QB.entities.create('a_m_y_beach_01', vector4(100.0, 200.0, 30.0, 90.0), {
    preset = 'static',
})
```

```lua
-- A prop, frozen but without disabling any ped-only behavior (it's not a ped)
QB.entities.create('prop_bin_08', vector3(100.0, 200.0, 30.0), {
    freeze = true,
})
```

Called cross-resource via export (e.g. from resource `my_script`):
```lua
local entity = exports.qblib:entities_create('a_m_y_beach_01', coords, { preset = 'static' })
-- tracked as owned by 'my_script'; deleted automatically if my_script stops
```

### `QB.entities.remove(entity)`
Deletes one tracked entity on demand. Only entities this module created are accepted — an untracked handle is refused rather than deleted, so the export can't be used as a generic delete-any-entity primitive against entities owned by other resources or the world.

#### Parameters
- `entity: number` -- An entity handle previously returned by `create`.

#### Returns
- `boolean` -- `true` if deleted.
- `string | nil` -- Set when the entity isn't tracked by this module, or no longer exists.

#### Example
```lua
local entity = QB.entities.create('a_m_y_beach_01', coords, { preset = 'static' })

-- later, before the resource stops
local ok, err = QB.entities.remove(entity)
if not ok then print('remove failed:', err) end
```

## Notes
- Entities from this module are never networked -- each client that calls `create` spawns its own independent copy, invisible to other players.
- Entity kind is always auto-detected from `model` -- there's no way to force a mismatched interpretation (e.g. spawn a vehicle model as a ped).
- A real `vector4` only has `.w` for heading, not `.heading` -- `.heading` is read as a fallback for plain tables that use that name by convention instead.
- `pedType` passed to the underlying `CreatePed` native is functionally inert (confirmed via upstream native reference) -- ped type is assigned automatically by the game.
- `blockNonTempEvents` only ever affects peds; passing it for an object/vehicle is a harmless no-op, not an error.
- If a resource stops without ever calling `QB.entities.remove` on its entities, they are still cleaned up automatically via `onClientResourceStop`.
