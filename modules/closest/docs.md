# Closest-entity helpers

`Kora.closest` is a compact compatibility layer over
`Kora.world.getClosestEntity`. Use it when a `{ id, distance }` result is more
convenient than the world module's entity/coordinates/distance tuple. The
default radius is 15 metres.

## API

### `Kora.closest.player(coords?, distance?)`
Client: returns the nearest other player within the radius measured from `coords`, or from the local player's cached position when omitted. Server: pass `src` first; the origin is that player's server-side ped position when `coords` is omitted.

#### Parameters
- `src: integer` — Server only. Positive player server ID used as the search origin.
- `coords: vector3 | vector4 | {x, y, z} | nil` — Optional finite search position. Server calls default to the source player's ped; client calls default to the local player's cached coordinates.
- `distance: number?` — Optional positive finite radius in metres; defaults to `15`.

#### Returns
- `{ id: integer | nil, distance: number | nil }` — Nearest other player's server ID and distance, or both fields `nil` when none is within range.

### `Kora.closest.vehicle(coords?, distance?)`
Finds the nearest vehicle within the radius. Server calls take `src` as their first argument and use that player's ped as the default origin; client calls use the local player's cached coordinates.

#### Parameters
- `src: integer` — Server only. Positive player server ID.
- `coords: vector3 | vector4 | {x, y, z} | nil` — Optional finite search origin.
- `distance: number?` — Optional positive finite radius; defaults to `15` metres.

#### Returns
- `{ id: integer | nil, distance: number | nil }` — Entity handle and distance, or nil fields when there is no match.

### `Kora.closest.ped(coords?, distance?)`
Finds the nearest ped within the radius, excluding the origin player's own ped. The client and server default-origin behavior matches `Kora.closest.player`.

#### Parameters
- `src: integer` — Server only. Positive player server ID.
- `coords: vector3 | vector4 | {x, y, z} | nil` — Optional finite search origin.
- `distance: number?` — Optional positive finite radius; defaults to `15` metres.

#### Returns
- `{ id: integer | nil, distance: number | nil }` — Entity handle and distance, or nil fields when there is no match.

### `Kora.closest.object(coords?, distance?)`
Finds the nearest object within the radius. Unlike player and ped searches, it does not exclude an entity at the origin.

#### Parameters
- `src: integer` — Server only. Positive player server ID.
- `coords: vector3 | vector4 | {x, y, z} | nil` — Optional finite search origin.
- `distance: number?` — Optional positive finite radius; defaults to `15` metres.

#### Returns
- `{ id: integer | nil, distance: number | nil }` — Entity handle and distance, or nil fields when there is no match.

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

## Examples

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
