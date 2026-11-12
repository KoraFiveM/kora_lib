---
title: "World"
sidebar_position: 36
---


# World

## Client

Client-side world helpers use streamed game data and cached player coordinates where documented. Ground, street, zone, direction, waypoint, and spawn checks save each resource from repeating native-call details.

Namespace: `Kora.world` · Source: `modules/world/client.lua`

### Ground search options

Pass an options table as the final argument to a play function. Omit the table or any field to use its default. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `height?` | number | Finite starting height for the ground search; default comes from Config.world. |
| `attempts?` | integer | Positive number of search attempts; default comes from Config.world. |
| `retryDelay?` | integer | Non-negative delay in milliseconds between attempts; default comes from Config.world. |

### What each result represents

Nearby query entries contain an entity handle, its coordinates, and distance from the requested center. Results are sorted nearest first. Player searches enumerate connected player peds; the local ped is excluded by default in client searches.

### Use server checks for decisions

Client search results describe streamed/client-visible state and can change immediately. For rewards, damage, transfers, or other protected actions, resolve the target on the server and enforce your own ownership and permission rules.

### Functions

Use these helpers for local UI and client behavior. A client result is not proof for a server-authoritative action.

#### `Kora.world.getNearbyEntities(entityType, coords, radius, options?)`

Finds every matching live entity within a positive radius.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entityType` | 'ped' \| 'vehicle' \| 'object' \| 'player' | Which kind of entity pool to search. Players are enumerated separately from ordinary peds. |
| `coords` | vector3 | Finite center point for the search. |
| `radius` | number | Finite positive distance in meters. |
| `options?` | table | Optional models, predicate, includeInvisible, includeOwnPed, and excludeEntities filters. |

**Returns**

- **matches** — array of &#123; entity, coords, distance &#125;, ordered by distance.

**Example**

```lua
local matches = Kora.world.getNearbyEntities('vehicle', GetEntityCoords(PlayerPedId()), 20.0)
for _, match in ipairs(matches) do
    print(('vehicle %d is %.1fm away'):format(match.entity, match.distance))
end
```

**Representative console output**

```text
Prints each nearby vehicle handle and its distance.
```

#### `Kora.world.getClosestEntity(entityType, coords, options?)`

Returns only the nearest matching entity, using options.radius or Config.world.defaultRadius.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entityType` | 'ped' \| 'vehicle' \| 'object' \| 'player | Pool to search. |
| `coords` | vector3 | Finite center point. |
| `options?` | table | Same filters as getNearbyEntities plus optional positive radius. |

**Returns**

- **entity** — handle, or false if there is no match.
- **coords** — matched entity coordinates, or nil.
- **distance** — meters from the search point, or nil.

**Example**

```lua
local vehicle, position, distance = Kora.world.getClosestEntity('vehicle', GetEntityCoords(PlayerPedId()), { radius = 15.0 })
if vehicle then print(('nearest is %.1fm away'):format(distance)) end
```

**Representative console output**

```text
Prints the nearest vehicle distance when one is found.
```

#### `Kora.world.getGroundCoords(coords, options?)`

Requests collision and makes a bounded search for the ground height.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `coords` | vector3 | Finite location to resolve. |
| `options?` | table | Optional height, attempts, and retryDelay. |

**Returns**

- **coords** — resolved vector3.
- **false, error** — if no ground is found or input is invalid.

**Example**

```lua
local ground = Kora.world.getGroundCoords(vector3(215.0, -810.0, 40.0))
if ground then print(ground) end
```

**Representative console output**

```text
Returns the location with its ground Z coordinate.
```

#### `Kora.world.getStreetNames(coords?)`

Gets the street name and optional crossing at a location.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `coords?` | vector3 | Location; omitted means cached player coordinates. |

**Returns**

- **street** — localized street name.
- **crossing?** — second street name when available.

**Example**

```lua
local street, crossing = Kora.world.getStreetNames()
print(street, crossing or '')
```

**Representative console output**

```text
Prints the current street and, when available, its crossing.
```

#### `Kora.world.getZoneName(coords?)`

Gets the localized map area name and its internal zone code.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `coords?` | vector3 | Location; omitted means cached player coordinates. |

**Returns**

- **localizedLabel** — readable area name.
- **zoneCode** — internal map code.

**Example**

```lua
local label, code = Kora.world.getZoneName()
print(label, code)
```

**Representative console output**

```text
Prints an area name such as a district and its code.
```

#### `Kora.world.getCardinalDirection(value?, options?)`

Converts a heading into one of eight compass directions.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value?` | number \| integer | Heading in degrees, or entity handle when options.entity is true. Omitted uses the cached player ped. |
| `options?` | table | Set entity = true to read heading from an entity handle. |

**Returns**

- **direction** — N, NW, W, SW, S, SE, E, or NE.

**Example**

```lua
print(Kora.world.getCardinalDirection(GetEntityHeading(PlayerPedId())))
```

**Representative console output**

```text
Prints the nearest compass direction.
```

#### `Kora.world.getWaypointCoords()`

Reads the player waypoint location if one is set.

**Parameters**



**Returns**

- **coords** — vector3.
- **false, error** — when no waypoint is set.

**Example**

```lua
local waypoint = Kora.world.getWaypointCoords()
if waypoint then SetNewWaypoint(waypoint.x, waypoint.y) end
```

**Representative console output**

```text
Returns waypoint coordinates or false when there is no marker.
```

#### `Kora.world.isSpawnClear(coords, radius, options?)`

Checks whether a vehicle occupies a proposed spawn area. The client also counts invisible streamed vehicles.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `coords` | vector3 | Center of the proposed spawn position. |
| `radius` | number | Finite positive search radius in meters. |
| `options?` | table | Optional normal world-query filters. |

**Returns**

- **clear** — boolean.

**Example**

```lua
if Kora.world.isSpawnClear(spawnPoint, 3.0) then
    print('Spawn area is clear')
end
```

**Representative console output**

```text
Prints only when the area has no matching vehicle.
```

### Limits and related APIs

Coordinates must be finite vector3 values and distances must be positive finite numbers. Search arrays must be dense; model names are hashed. Queries do not create or track entities.

## Server

Server-side helpers resolve client-provided network IDs and player targets using authoritative entity state. Use these before acting on a reported entity or distance; still apply your resource’s ownership and gameplay rules.

Namespace: `Kora.world` · Source: `modules/world/server.lua`

### Server validation options

Pass an options table as the final argument to a play function. Omit the table or any field to use its default. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `entityType?` | 'ped' \| 'vehicle' \| 'object' | Required entity class for resolveNetworkEntity. |
| `maxDistance?` | number | Positive distance limit in meters. Required by resolveNearbyPlayer. |
| `sameBucket?` | boolean | Require matching routing buckets. Defaults true. |
| `requireDriver?` | boolean | Require the requesting player to be driving the resolved vehicle. |
| `allowSelf?` | boolean | Allow a player to target themselves in resolveNearbyPlayer. Defaults false. |

### What each result represents

Nearby query entries contain an entity handle, its coordinates, and distance from the requested center. Results are sorted nearest first. Player searches enumerate connected player peds; the local ped is excluded by default in client searches.

### Use server checks for decisions

Client search results describe streamed/client-visible state and can change immediately. For rewards, damage, transfers, or other protected actions, resolve the target on the server and enforce your own ownership and permission rules.

### Functions

Every failure returns a stable reason code so a server event can reject the request clearly.

#### `Kora.world.getNearbyEntities(entityType, coords, radius, options?)`

Finds every matching live entity within a positive radius.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entityType` | 'ped' \| 'vehicle' \| 'object' \| 'player' | Which kind of entity pool to search. Players are enumerated separately from ordinary peds. |
| `coords` | vector3 | Finite center point for the search. |
| `radius` | number | Finite positive distance in meters. |
| `options?` | table | Optional models, predicate, includeInvisible, includeOwnPed, and excludeEntities filters. |

**Returns**

- **matches** — array of &#123; entity, coords, distance &#125;, ordered by distance.

**Example**

```lua
local matches = Kora.world.getNearbyEntities('vehicle', GetEntityCoords(PlayerPedId()), 20.0)
for _, match in ipairs(matches) do
    print(('vehicle %d is %.1fm away'):format(match.entity, match.distance))
end
```

**Representative console output**

```text
Prints each nearby vehicle handle and its distance.
```

#### `Kora.world.getClosestEntity(entityType, coords, options?)`

Returns only the nearest matching entity, using options.radius or Config.world.defaultRadius.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entityType` | 'ped' \| 'vehicle' \| 'object' \| 'player | Pool to search. |
| `coords` | vector3 | Finite center point. |
| `options?` | table | Same filters as getNearbyEntities plus optional positive radius. |

**Returns**

- **entity** — handle, or false if there is no match.
- **coords** — matched entity coordinates, or nil.
- **distance** — meters from the search point, or nil.

**Example**

```lua
local vehicle, position, distance = Kora.world.getClosestEntity('vehicle', GetEntityCoords(PlayerPedId()), { radius = 15.0 })
if vehicle then print(('nearest is %.1fm away'):format(distance)) end
```

**Representative console output**

```text
Prints the nearest vehicle distance when one is found.
```

#### `Kora.world.isSpawnClear(coords, radius, options?)`

Checks whether a vehicle is within a proposed spawn area using the server entity pool.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `coords` | vector3 | Finite center point. |
| `radius` | number | Finite positive radius in meters. |
| `options?` | table | Optional world query filters. |

**Returns**

- **clear** — boolean.

**Example**

```lua
if not Kora.world.isSpawnClear(requestedPosition, 4.0) then
    return false, 'spawn_blocked'
end
```

**Representative console output**

```text
Rejects the spawn when a vehicle occupies the area.
```

#### `Kora.world.resolveNetworkEntity(source, networkId, options?)`

Resolves a client-supplied network ID and checks that the live entity meets the requested rules.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `source` | integer | Server player ID that made the request. |
| `networkId` | integer | Positive finite network ID supplied by the client. |
| `options?` | table | Optional entityType, maxDistance, sameBucket, and requireDriver rules. |

**Returns**

- **entity** — server entity handle when valid.
- **nil, reason** — stable failure code such as entity_unavailable, wrong_entity_type, too_far, or driver_required.

**Example**

```lua
local vehicle, reason = Kora.world.resolveNetworkEntity(source, netId, { entityType = 'vehicle', maxDistance = 8.0, requireDriver = true })
if not vehicle then return false, reason end
return inspectVehicle(vehicle)
```

**Representative console output**

```text
Continues only after the server confirms a nearby vehicle and driver.
```

#### `Kora.world.resolveNearbyPlayer(source, targetSource, options)`

Checks that two players exist and are close enough, and by default share a routing bucket.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `source` | integer | Player initiating the interaction. |
| `targetSource` | integer | Player being targeted. |
| `options` | table | Required maxDistance; optional sameBucket (default true) and allowSelf (default false). |

**Returns**

- **targetPed** — validated target ped.
- **distance** — meters between players.
- **nil, reason** — stable code such as target_unavailable, routing_bucket_mismatch, or too_far.

**Example**

```lua
local targetPed, distanceOrReason = Kora.world.resolveNearbyPlayer(source, targetSource, { maxDistance = 3.0 })
if not targetPed then return false, distanceOrReason end
print(('target is %.1fm away'):format(distanceOrReason))
```

**Representative console output**

```text
Prints the distance only after server validation.
```

### Limits and related APIs

Coordinates must be finite vector3 values and distances must be positive finite numbers. Search arrays must be dense; model names are hashed. Queries do not create or track entities.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/world/docs.md` or `local/world/docs.md`) that the reference above does not state.

### API

#### `Kora.world.getClosestEntity(entityType, coords, options)`
Finds the single nearest entity of `entityType` to `coords`.

##### Example
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

### Small helpers

#### `Kora.world.getGroundCoords(coords, options?)` (client)

Requests collision and performs a bounded ground search. `height` must be
finite; `attempts` must be a positive finite integer and `retryDelay` a
non-negative finite integer. Defaults come from `Config.world`. Returns the
resolved `{x, y, z}`, or `false, error`. A default applies only when its option
is omitted; explicit invalid values are rejected.

#### `Kora.world.getStreetNames(coords?)` (client)

Returns `street, crossing?` using the cached player coordinates when omitted;
an explicit coordinate value must be valid.

#### `Kora.world.getZoneName(coords?)` (client)

Returns `localizedLabel, zoneCode` for the given or cached coordinates. An
explicit coordinate value must be valid.

#### `Kora.world.getCardinalDirection(value?, options?)` (client)

Returns one of `N`, `NW`, `W`, `SW`, `S`, `SE`, `E`, or `NE`. `value` is a
finite heading in degrees. With `{ entity = true }`, it is treated as an entity
handle; when omitted the cached player ped is used. When supplied, `options`
must be a table and `entity` must be boolean.

#### `Kora.world.getWaypointCoords()` (client)

Returns the active waypoint as `{x, y, z}`, or `false, error` when none is set.

#### `Kora.world.isSpawnClear(coords, radius, options?)` (client/server)

Returns whether no vehicle is within the finite positive radius. It accepts the normal world
query filters; the client intentionally includes invisible streamed vehicles
because they still occupy the spawn point.

#### `Kora.world.resolveNetworkEntity(source, networkId, options?)` (server)

Resolves a client-supplied finite network ID and validates the live entity before
server code acts on it. Options are `entityType` (`ped`, `vehicle`, or
`object`), `maxDistance`, `sameBucket` (true by default), and
`requireDriver`. It returns the entity handle or `false, reason` (not `nil`,
which would drop the reason across the export boundary), where `reason`
is a stable code such as `invalid_network_id`, `entity_unavailable`,
`wrong_entity_type`, `player_unavailable`, `routing_bucket_mismatch`,
`too_far`, or `driver_required`.

#### `Kora.world.resolveNearbyPlayer(source, targetSource, options)` (server)

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
