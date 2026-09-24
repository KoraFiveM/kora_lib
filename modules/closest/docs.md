# Closest-entity helpers

`QB.closest` is a compact compatibility layer over
`QB.world.getClosestEntity`. Use it when a `{ id, distance }` result is more
convenient than the world module's entity/coordinates/distance tuple. The
default radius is 15 metres.

## API

Client calls search from `coords`, or from the local player's cached position
when it is omitted (`nil`):

```lua
QB.closest.player(coords?, distance?)
QB.closest.vehicle(coords?, distance?)
QB.closest.ped(coords?, distance?)
QB.closest.object(coords?, distance?)
```

Server calls take a positive integer player ID first. If `coords` is omitted
(`nil`), they search from that player's server-side ped position:

```lua
QB.closest.player(src, coords?, distance?)
QB.closest.vehicle(src, coords?, distance?)
QB.closest.ped(src, coords?, distance?)
QB.closest.object(src, coords?, distance?)
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
uses `QB.world`'s built-in default; server searches pass the source ped because
there is no implicit server-side origin. Vehicle and object searches do not
exclude an entity.

## Examples

```lua
-- client.lua: find a nearby vehicle, using the default 15m radius
local closest = QB.closest.vehicle()
if closest.id then
    print(('Vehicle %d is %.1fm away'):format(closest.id, closest.distance))
end
```

```lua
-- server.lua: find the nearest other player within 3m of source
local closest = QB.closest.player(source, nil, 3.0)
if closest.id then
    -- Validate ownership, permissions, and current server state before acting.
    print(('Nearest player is %d at %.1fm'):format(closest.id, closest.distance))
end
```

These are discovery helpers, not authorization. For a valuable server action,
validate the requested action and current server state in addition to proximity.
