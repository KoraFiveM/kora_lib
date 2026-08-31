# Closest-entity compatibility helpers

These helpers wrap `QB.world.getClosestEntity` and return
`{ id = integer|nil, distance = number|nil }`. The default radius is 15m.

Client signatures:

- `QB.closest.player(coords?, distance?)`
- `QB.closest.vehicle(coords?, distance?)`
- `QB.closest.ped(coords?, distance?)`
- `QB.closest.object(coords?, distance?)`

Server signatures take a player source first:

- `QB.closest.player(src, coords?, distance?)`
- `QB.closest.vehicle(src, coords?, distance?)`
- `QB.closest.ped(src, coords?, distance?)`
- `QB.closest.object(src, coords?, distance?)`

Player results contain a player ID, while the other helpers contain the entity
handle. Omitted coordinates default to the calling/local player's position.
