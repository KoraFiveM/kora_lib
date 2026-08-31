# World module

## Overview
The world module answers "what already exists near me right now" by reading the live entity pool (`GetGamePool`/`GetActivePlayers`) — a different job from `modules/entities`, which only spawns and owns entities qblib itself created. It was added alongside `modules/drawing` as a foundation for a crosshair-based targeting system (resolving "what model/type is under my aim"), but is independently useful for anything that needs to find nearby peds/vehicles/objects/players — radar scripts, spawn logic, proximity checks.

## API

### `QB.world.getNearbyEntities(entityType, coords, radius, options)`
Finds every entity of `entityType` within `radius` meters of `coords`.

#### Parameters
- `entityType: "ped" | "vehicle" | "object" | "player"`
- `coords: vector3 | {x, y, z}`
- `radius: number` — meters, must be positive.
- `options: table | nil`
  - `models: (number | string)[]` — restrict to these models. String entries are `joaat`-hashed. Ignored for `"player"`.
  - `predicate: fun(entity, coords, distance): boolean` — runs last, after every other filter.
  - `includeInvisible: boolean` — include entities `IsEntityVisible` reports as hidden. Defaults to `false`.
  - `includeOwnPed: boolean` — include the local player's own ped. Defaults to `false`.
  - `excludeEntities: number[]` — entity handles to skip outright.

#### Returns
- `{entity: number, coords: table, distance: number}[]` — sorted ascending by distance.

### `QB.world.getClosestEntity(entityType, coords, options)`
Finds the single nearest entity of `entityType` to `coords`.

#### Parameters
- `entityType: "ped" | "vehicle" | "object" | "player"`
- `coords: vector3 | {x, y, z}`
- `options: table | nil` — same fields as `getNearbyEntities`, plus:
  - `radius: number` — search radius, meters. Defaults to `Config.world.defaultRadius`.

#### Returns
- `number | false` — the closest matching entity, or `false` if nothing matched within range.
- `table | nil` — its coords, only present on a match.
- `number | nil` — the distance, only present on a match.

#### Example
```lua
local nearest, coords, distance = QB.world.getClosestEntity("vehicle", GetEntityCoords(PlayerPedId()), { radius = 15.0 })
if nearest then
    print(("nearest vehicle is %.1fm away"):format(distance))
end
```

Called cross-resource via export:
```lua
local matches = exports.qblib:world_getNearbyEntities("ped", coords, 20.0)
for _, match in ipairs(matches) do
    print(match.entity, match.distance)
end
```

## Notes
- `"player"` is not a `GetGamePool` pool type — it's enumerated via `GetActivePlayers()`/`GetPlayerPed`, one ped per connected player (including the local one, subject to `includeOwnPed` like `"ped"`).
- Filters run cheapest-first (self-exclusion, explicit exclude list, model set, visibility) before `predicate`, which may be arbitrarily expensive — same discipline `modules/zones` documents for its own AABB-then-exact-shape containment tests.
- Pool queries are available on both realms. Client queries inspect streamed entities; server queries inspect OneSync's server entity pools.
- This module reads the world; it doesn't own or track anything, unlike `modules/entities` (which only ever reports entities it created itself) or `modules/zones` (which owns registered volumes). There's nothing to clean up on resource stop here.

## Small helpers

### `QB.world.getGroundCoords(coords, options?)` (client)

Requests collision and performs a bounded ground search. Options are `height`,
`attempts`, and `retryDelay`; defaults come from `Config.world`. Returns the
resolved `{x, y, z}`, or `false, error`.

### `QB.world.getStreetNames(coords?)` (client)

Returns `street, crossing?` using the cached player coordinates when omitted.

### `QB.world.getZoneName(coords?)` (client)

Returns `localizedLabel, zoneCode` for the given or cached coordinates.

### `QB.world.getCardinalDirection(value?, options?)` (client)

Returns one of `N`, `NW`, `W`, `SW`, `S`, `SE`, `E`, or `NE`. `value` is a
heading in degrees. With `{ entity = true }`, it is treated as an entity
handle; when omitted the cached player ped is used.

### `QB.world.getWaypointCoords()` (client)

Returns the active waypoint as `{x, y, z}`, or `false, error` when none is set.

### `QB.world.isSpawnClear(coords, radius, options?)` (client/server)

Returns whether no vehicle is within the radius. It accepts the normal world
query filters; the client intentionally includes invisible streamed vehicles
because they still occupy the spawn point.
