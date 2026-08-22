# world module guide

## Purpose
Answers "what's near me" against the live entity pool -- `GetGamePool("CPed"/"CVehicle"/"CObject")` for peds/vehicles/objects, `GetActivePlayers()`/`GetPlayerPed` for players (not a real pool type). Added specifically because a crosshair-based targeting system needs "every ped/vehicle/object/player within range" and nothing in qblib answered that -- `modules/entities` only reports entities it spawned itself.

## Why not fold this into `modules/entities`
`modules/entities` is a spawn-and-own module: it creates non-networked local entities and tracks them in a `QB.resources.registry` for delete-on-resource-stop. A pool query reads entities nobody here owns and has no cleanup story at all -- conflating the two would grow `entities`' registry semantics in a direction its own docs don't anticipate. `detectEntityType` in `modules/entities/client.lua` also classifies a **model hash** (for deciding how to spawn something), which is a different operation from classifying a **live entity handle** (what a query needs) -- there was no query logic to extend even at the "just add a function" level.

## Implementation notes
- `poolEntities` is the only place that knows `"player"` isn't a `GetGamePool` type -- every other function treats all four `QBWorldEntityType` values uniformly once it has a list of entity handles.
- Filter order in `collectCandidates` is deliberately cheap-reject-first: self-exclusion and the explicit exclude set are plain table lookups, the model set is one `GetEntityModel` call, visibility is one native, and the caller's `predicate` -- which might do its own raycast or coordinate math -- runs last and only against whatever survived everything else. Same discipline `modules/zones` uses for AABB-then-exact-shape.
- `toVec3`/`distSq` are private copies of the same helpers in `modules/raycast/client.lua` and `modules/zones/client.lua`. Duplicated rather than shared, per the top-level `AGENTS.md`: Lua `local`s don't cross files and this repo has no shared-utils convention.
- Not consumed by qbtarget's own hot loop (the per-frame "what's under the crosshair" resolution) -- that's driven by `QB.raycast.fromCamera`'s single hit-test, which is O(1) per frame versus a pool scan. This module exists for the *other* things a targeting resource (or anything else) needs: "every vehicle within 15m" for a global-type registration, "the closest ped" for AI/spawn logic, etc.
- Client-only, no `shared.lua`/`server.lua` -- pool queries only make sense against the calling client's own streamed-in world, same shape as `modules/raycast`/`modules/stream`/`modules/zones`.

## Testing
`test/smoke/world.lua` mocks `GetGamePool`, `GetActivePlayers`, `GetPlayerPed`, `GetEntityCoords`, `GetEntityModel`, `IsEntityVisible`, `DoesEntityExist`, and reuses `mocks.lua`'s `joaat`. Covers: distance sorting, the model filter (string vs numeric), own-ped exclusion (default and `includeOwnPed`), the exclude list, `includeInvisible`, the predicate running last, and an empty pool returning an empty list (not nil).
