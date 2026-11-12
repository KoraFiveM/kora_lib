---
title: "World module"
sidebar_position: 36
---

# World module

## Overview
The world module answers "what already exists near me right now" by reading the live entity pool (`GetGamePool`/`GetActivePlayers`) — a different job from `modules/entities`, which only spawns and owns entities kora_lib itself created. It was added alongside `modules/drawing` as a foundation for a crosshair-based targeting system (resolving "what model/type is under my aim"), but is independently useful for anything that needs to find nearby peds/vehicles/objects/players — radar scripts, spawn logic, proximity checks.

## API

### `Kora.world.getNearbyEntities(entityType, coords, radius, options)`
Finds every entity of `entityType` within `radius` meters of `coords`.

#### Parameters
- `entityType: "ped" | "vehicle" | "object" | "player"`
- `coords: vector3 | {x, y, z}` — finite coordinates.
- `radius: number` — finite positive meters.
- `options: table | nil`
  - `models: (number | string)[]` — restrict to these models. String entries are `joaat`-hashed. Ignored for `"player"`.
  - `predicate: fun(entity, coords, distance): boolean` — runs last, after every other filter.
  - `includeInvisible: boolean` — include entities `IsEntityVisible` reports as hidden. Defaults to `false`.
  - `includeOwnPed: boolean` — include the local player's own ped. Defaults to `false`.
  - `excludeEntities: number[]` — positive finite integer entity handles to skip outright.

#### Returns
- `{entity: number, coords: table, distance: number}[]` — sorted ascending by distance.

### `Kora.world.getClosestEntity(entityType, coords, options)`
Finds the single nearest entity of `entityType` to `coords`.

#### Parameters
- `entityType: "ped" | "vehicle" | "object" | "player"`
- `coords: vector3 | {x, y, z}`
- `options: table | nil` — same fields as `getNearbyEntities`, plus:
  - `radius: number` — finite positive search radius in meters. Defaults to `Config.world.defaultRadius`.

#### Returns
- `number | false` — the closest matching entity, or `false` if nothing matched within range.
- `table | nil` — its coords, only present on a match.
- `number | nil` — the distance, only present on a match.

#### Example
```lua
local nearest, coords, distance = Kora.world.getClosestEntity("vehicle", GetEntityCoords(PlayerPedId()), { radius = 15.0 })
if nearest then
    print(("nearest vehicle is %.1fm away"):format(distance))
end
```

Called cross-resource via export:
```lua
local matches = exports.kora_lib:world_getNearbyEntities("ped", coords, 20.0)
for _, match in ipairs(matches) do
    print(match.entity, match.distance)
end
```

## Notes
- Optional `options` values must be tables when supplied. Model and exclusion
  lists must be dense arrays with documented entry types, predicates must be
  callable, and boolean filters must be booleans; malformed queries are
  rejected before kora_lib scans a pool or calls a native.
- `"player"` is not a `GetGamePool` pool type — it's enumerated via `GetActivePlayers()`/`GetPlayerPed`, one ped per connected player (including the local one, subject to `includeOwnPed` like `"ped"`).
- Filters run cheapest-first (self-exclusion, explicit exclude list, model set, visibility) before `predicate`, which may be arbitrarily expensive — same discipline `modules/zones` documents for its own AABB-then-exact-shape containment tests.
- Closest-entity and spawn-clear scans retain native coordinates while walking
  candidates. kora_lib makes a plain `{x, y, z}` table only for a predicate or a
  returned match, avoiding one short-lived allocation per otherwise irrelevant
  candidate.
- Pool queries are available on both realms. Client queries inspect streamed entities; server queries inspect OneSync's server entity pools.
- This module reads the world; it doesn't own or track anything, unlike `modules/entities` (which only ever reports entities it created itself) or `modules/zones` (which owns registered volumes). There's nothing to clean up on resource stop here.

## Small helpers

### `Kora.world.getGroundCoords(coords, options?)` (client)

Requests collision and performs a bounded ground search. `height` must be
finite; `attempts` must be a positive finite integer and `retryDelay` a
non-negative finite integer. Defaults come from `Config.world`. Returns the
resolved `{x, y, z}`, or `false, error`. A default applies only when its option
is omitted; explicit invalid values are rejected.

### `Kora.world.getStreetNames(coords?)` (client)

Returns `street, crossing?` using the cached player coordinates when omitted;
an explicit coordinate value must be valid.

### `Kora.world.getZoneName(coords?)` (client)

Returns `localizedLabel, zoneCode` for the given or cached coordinates. An
explicit coordinate value must be valid.

### `Kora.world.getCardinalDirection(value?, options?)` (client)

Returns one of `N`, `NW`, `W`, `SW`, `S`, `SE`, `E`, or `NE`. `value` is a
finite heading in degrees. With `{ entity = true }`, it is treated as an entity
handle; when omitted the cached player ped is used. When supplied, `options`
must be a table and `entity` must be boolean.

### `Kora.world.getWaypointCoords()` (client)

Returns the active waypoint as `{x, y, z}`, or `false, error` when none is set.

### `Kora.world.isSpawnClear(coords, radius, options?)` (client/server)

Returns whether no vehicle is within the finite positive radius. It accepts the normal world
query filters; the client intentionally includes invisible streamed vehicles
because they still occupy the spawn point.

### `Kora.world.resolveNetworkEntity(source, networkId, options?)` (server)

Resolves a client-supplied finite network ID and validates the live entity before
server code acts on it. Options are `entityType` (`ped`, `vehicle`, or
`object`), `maxDistance`, `sameBucket` (true by default), and
`requireDriver`. It returns the entity handle or `false, reason` (not `nil`,
which would drop the reason across the export boundary), where `reason`
is a stable code such as `invalid_network_id`, `entity_unavailable`,
`wrong_entity_type`, `player_unavailable`, `routing_bucket_mismatch`,
`too_far`, or `driver_required`.

### `Kora.world.resolveNearbyPlayer(source, targetSource, options)` (server)

Validates two live player peds using server-authoritative coordinates. Source
and target IDs must be positive finite integers. The
required `maxDistance` option bounds the interaction; `sameBucket` defaults to
true and `allowSelf` defaults to false. On success it returns the target ped
and distance. On failure it returns `nil` with a stable code:
`invalid_player`, `self_not_allowed`, `player_unavailable`,
`target_unavailable`, `routing_bucket_mismatch`, or `too_far`.

```lua
local targetPed, distanceOrReason = Kora.world.resolveNearbyPlayer(source, targetSource, {
    maxDistance = 3.0,
})
if not targetPed then return false, distanceOrReason end
```
