# entities module guide

## Purpose
This module spawns local, non-networked entities (ped/object/vehicle) that are visible only to the spawning client, with automatic model streaming and automatic cleanup when the resource that created them stops.

## Public API
- `QB.entities.create(model, coords, options)`
  - Loads `model` via `QB.stream.loadModel` and creates a non-networked ped/object/vehicle at `coords`.
  - The entity kind is auto-detected from `model` (`IsModelAPed` / `IsModelAVehicle`, falling back to object) -- callers never specify a type.
  - `options.preset` applies a named bundle of setup behavior (currently only `"static"`: frozen, non-reactive, and invincible).
  - `options.freeze` / `options.blockNonTempEvents` / `options.invincible` explicitly override whatever the preset would set; `blockNonTempEvents` only applies to peds.
  - Returns the entity handle, or `false, error` if the model never loaded or the entity failed to create.
- `QB.entities.remove(entity)`
  - Deletes one tracked entity immediately and drops it from tracking.
  - Returns `true`, or `false, error` if the entity doesn't exist.
- `QB.entities.createScoped(model, coords, { radius = metres, ...options })`
  - Registers a radius around the entity location and creates the local entity only while the player is inside it.
  - Returns a persistent scope handle; `handle.entity` is the transient entity handle (or `nil` outside the scope), and `handle.remove()` unregisters it.
  - Entry state is updated before checking the asynchronous spawn guard. The spawn runs under `pcall` and always clears that guard, so a leave/re-enter during streaming is retained and an exception cannot wedge the scope permanently.

## Implementation notes
- Entities are created **non-networked** (`isNetwork = false`) and **not** registered as script-host mission entities -- cleanup is handled entirely by this module, not by GTA's native pinning.
- `CreatePed`'s `pedType` argument is inert (confirmed via upstream native docs -- the game assigns ped types automatically); `4` is passed purely by convention.
- `CreateObjectNoOffset` is used instead of `CreateObject` so objects land exactly at the given coordinates rather than being adjusted to "ground level" -- important since objects may immediately be frozen in place.
- Entity type is resolved once per call via a private `detectEntityType(modelHash)` helper: `IsModelAPed`/`IsModelAVehicle` are static model-metadata queries that work off the model hash alone (no streaming required), so detection can run inside `loadModel`'s callback using the already-resolved hash. Anything that's neither a ped nor a vehicle model falls through to `object`.
- Heading is resolved by a private `resolveHeading(options, coords)` helper: `options.heading` wins if set, otherwise `coords.w` (a real FiveM `vector4`'s only heading-shaped field), otherwise `coords.heading` (the field name plain "coords with heading" tables commonly use instead, since `vector4` itself has no `.heading`), otherwise `0.0`.
- Entity creation happens inside `QB.stream.loadModel`'s callback, following that function's own documented pattern for building an entity via closure upvalue.
- Ownership tracking is delegated to `QB.resources.registry` (`local/resources`) rather than hand-rolled here — see that module's `AGENTS.md`. Each created entity is tracked against the resource that invoked `create` (`GetInvokingResource()`, falling back to `GetCurrentResourceName()` for direct/non-export calls); the registry's own sweep deletes every entity a resource still owns when it stops, guarded by `DoesEntityExist` since deleting an already-gone handle is undefined behavior.
- `SetBlockingOfNonTemporaryEvents` is a ped-only native; it is silently skipped for objects/vehicles rather than erroring, since `options` has the same shape regardless of `type`. `SetEntityInvincible` applies to every entity type.

## Best practices
- Prefer `options.preset = "static"` for decorative props/inert NPCs instead of setting `freeze`/`blockNonTempEvents`/`invincible` by hand, unless you need to deviate from one of them.
- Don't rely on these entities being networked -- other clients will never see them; use a proper networked spawn (outside this module) if that's required.
- Call `QB.entities.remove` for anything that needs to disappear before your resource stops; don't just drop your reference to the handle.
- Prefer `createScoped` for decorative, client-local world population that is only useful near the player. It uses `QB.zones`' spatial grid rather than a per-entity distance loop.
- `blockNonTempEvents` is safe to pass regardless of what `model` turns out to be -- it's silently ignored for anything detection doesn't classify as a ped.
