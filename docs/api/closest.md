---
title: "Closest"
sidebar_position: 23
---


# Closest

## Client

Finds the nearest player, vehicle, ped, or object near a point. It is a small convenience wrapper around Kora.world.getClosestEntity and returns a simple &#123; id, distance &#125; result. If coords is omitted, the client searches around the local player’s cached position.

Namespace: `Kora.closest` · Source: `modules/closest/client.lua`

### Functions

Choose the entity type to search for. Every function uses a 15 metre radius unless you supply distance.

#### `Kora.closest.player(coords?, distance?)`

Finds the nearest other player. The returned id is a player index, not a ped handle.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `coords?` | vector3 | Optional search center. Defaults to the local player’s cached position. |
| `distance?` | number | Optional positive finite search radius in metres. Defaults to 15.0. |

**Returns**

- **result.id** — player index, or nil when no match exists.
- **result.distance** — distance in metres, or nil when no match exists.

**Example**

```lua
local found = Kora.closest.player(nil, 5.0)
if found.id then print(('Player %d is %.1fm away'):format(found.id, found.distance)) end
```

**Representative console output**

```text
Prints the nearest other player if one is within five metres.
```

#### `Kora.closest.vehicle(coords?, distance?)`

Finds the nearest vehicle and returns its entity handle.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `coords?` | vector3 | Optional search center. Defaults to the local player’s cached position. |
| `distance?` | number | Optional positive finite radius in metres. Defaults to 15.0. |

**Returns**

- **result.id** — vehicle entity handle, or nil if none was found.
- **result.distance** — distance in metres, or nil if none was found.

**Example**

```lua
local found = Kora.closest.vehicle()
if found.id then print('Nearest vehicle:', found.id) end
```

**Representative console output**

```text
Prints the nearest vehicle within the default radius, if one exists.
```

#### `Kora.closest.ped(coords?, distance?)`

Finds the nearest ped other than the local player’s own ped.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `coords?` | vector3 | Optional search center. Defaults to the local player’s cached position. |
| `distance?` | number | Optional positive finite radius in metres. Defaults to 15.0. |

**Returns**

- **result.id** — ped entity handle, or nil if none was found.
- **result.distance** — distance in metres, or nil if none was found.

**Example**

```lua
local found = Kora.closest.ped(nil, 10.0)
if found.id then print(('Ped is %.1fm away'):format(found.distance)) end
```

**Representative console output**

```text
Prints the nearest other ped within ten metres.
```

#### `Kora.closest.object(coords?, distance?)`

Finds the nearest object entity.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `coords?` | vector3 | Optional search center. Defaults to the local player’s cached position. |
| `distance?` | number | Optional positive finite radius in metres. Defaults to 15.0. |

**Returns**

- **result.id** — object entity handle, or nil if none was found.
- **result.distance** — distance in metres, or nil if none was found.

**Example**

```lua
local found = Kora.closest.object(nil, 3.0)
if found.id then print('Nearby object:', found.id) end
```

**Representative console output**

```text
Prints the nearest object if it is within three metres.
```

### Limits and related APIs

coords must contain finite vector3 components. distance must be positive and finite. Player/ped searches exclude the origin player. A nearby result only describes proximity; it does not grant permission for a server action.

## Server

Provides the same nearest-entity helpers on the server. Every call starts with src, the positive integer server ID of the player whose position should be used. If coords is omitted, the module reads that player’s server-side ped position.

Namespace: `Kora.closest` · Source: `modules/closest/server.lua`

### Functions

Pass src first, followed by optional coords and distance. Results use player IDs for player searches and entity handles for other types.

#### `Kora.closest.player(src, coords?, distance?)`

Finds the nearest player other than src and returns that player’s server ID.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Positive server ID whose location is the search origin. |
| `coords?` | vector3 | Optional center; defaults to the src player’s current ped position. |
| `distance?` | number | Optional positive finite radius in metres. Defaults to 15.0. |

**Returns**

- **result.id** — other player’s server ID, or nil when no match exists.
- **result.distance** — distance in metres, or nil when no match exists.

**Example**

```lua
local found = Kora.closest.player(source, nil, 3.0)
if found.id then print(('Nearest player is %d at %.1fm'):format(found.id, found.distance)) end
```

**Representative console output**

```text
Prints the closest other player within three metres of the caller.
```

#### `Kora.closest.vehicle(src, coords?, distance?)`

Finds the nearest vehicle around the selected player or custom search point.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Positive server ID whose location is the default search origin. |
| `coords?` | vector3 | Optional center; defaults to src player’s current ped position. |
| `distance?` | number | Optional positive finite radius in metres. Defaults to 15.0. |

**Returns**

- **result.id** — vehicle entity handle, or nil if none was found.
- **result.distance** — distance in metres, or nil if none was found.

**Example**

```lua
local found = Kora.closest.vehicle(source, nil, 8.0)
if found.id then print('Nearby vehicle:', found.id) end
```

**Representative console output**

```text
Prints a vehicle found within eight metres of the caller.
```

#### `Kora.closest.ped(src, coords?, distance?)`

Finds the nearest ped other than src player’s own ped.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Positive server ID whose location is the default search origin. |
| `coords?` | vector3 | Optional search center. |
| `distance?` | number | Optional positive finite radius in metres. Defaults to 15.0. |

**Returns**

- **result.id** — ped entity handle, or nil if none was found.
- **result.distance** — distance in metres, or nil if no match exists.

**Example**

```lua
local found = Kora.closest.ped(source, nil, 10.0)
if found.id then print('Nearby ped:', found.id) end
```

**Representative console output**

```text
Prints the nearest other ped within ten metres.
```

#### `Kora.closest.object(src, coords?, distance?)`

Finds the nearest object around the selected player or custom search point.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Positive server ID whose location is the default search origin. |
| `coords?` | vector3 | Optional search center. |
| `distance?` | number | Optional positive finite radius in metres. Defaults to 15.0. |

**Returns**

- **result.id** — object entity handle, or nil if none was found.
- **result.distance** — distance in metres, or nil if none was found.

**Example**

```lua
local found = Kora.closest.object(source, nil, 4.0)
if found.id then print(('Object is %.1fm away'):format(found.distance)) end
```

**Representative console output**

```text
Prints the distance when an object is found within four metres.
```

### Limits and related APIs

src must be a positive integer server ID with an active ped. coords must contain finite vector3 components and distance must be positive and finite. Proximity is not authorization; validate valuable actions and state on the server.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/closest/docs.md` or `local/closest/docs.md`) that the reference above does not state.

`Kora.closest` is a compact compatibility layer over
`Kora.world.getClosestEntity`. Use it when a `{ id, distance }` result is more
convenient than the world module's entity/coordinates/distance tuple. The
default radius is 15 metres.

### API

Client calls search from `coords`, or from the local player's cached position
when it is omitted (`nil`):

```lua
Kora.closest.player(coords?, distance?)
Kora.closest.vehicle(coords?, distance?)
Kora.closest.ped(coords?, distance?)
Kora.closest.object(coords?, distance?)
```

Server calls take a positive integer player ID first. If `coords` is omitted
(`nil`), they search from that player's server-side ped position:

```lua
Kora.closest.player(src, coords?, distance?)
Kora.closest.vehicle(src, coords?, distance?)
Kora.closest.ped(src, coords?, distance?)
Kora.closest.object(src, coords?, distance?)
```

Every function returns this table:

| Field | Meaning |
| --- | --- |
| `id` | A player ID for `player`; an entity handle for `vehicle`, `ped`, and `object`; `nil` when no match exists. |
| `distance` | Distance from the search position, or `nil` when no match exists. |

`coords`, when supplied, must have finite `x`, `y`, and `z` values. `distance`,
when supplied, must be a positive finite number. Omitting either uses its
documented default; invalid explicit values are rejected before the world query
runs. The compatibility radius default is 15 metres.

Player and ped searches exclude the origin player's own ped. On the client this
uses `Kora.world`'s built-in default; server searches pass the source ped because
there is no implicit server-side origin. Vehicle and object searches do not
exclude an entity.

### Examples

```lua
-- client.lua: find a nearby vehicle, using the default 15m radius
local closest = Kora.closest.vehicle()
if closest.id then
    print(('Vehicle %d is %.1fm away'):format(closest.id, closest.distance))
end
```

```lua
-- server.lua: find the nearest other player within 3m of source
local closest = Kora.closest.player(source, nil, 3.0)
if closest.id then
    -- Validate ownership, permissions, and current server state before acting.
    print(('Nearest player is %d at %.1fm'):format(closest.id, closest.distance))
end
```

These are discovery helpers, not authorization. For a valuable server action,
validate the requested action and current server state in addition to proximity.
