# QB.distance

Cheap radius checks between the local player, arbitrary coordinates, and
entities. Every function returns a boolean: `true` when the measured distance is
within `distance` (default `5.0`). Client functions measure from the local
player (`QB.cache.get('coords')`); server functions take `src` first and measure
from that player's ped (requires OneSync for a valid server-side ped position).

## Client

### QB.distance.player(coords, distance?)
True if the local player is within `distance` of `coords` (`{x,y,z}`).
```lua
if QB.distance.player(shopCoords, 2.5) then openShop() end
```

### QB.distance.coords(coords1, coords2, distance?)
True if two points are within `distance` of each other. (Same on both realms.)

### QB.distance.entity(entity, distance?)
True if the local player is within `distance` of `entity`.

### QB.distance.x(point, distance?) / QB.distance.y(point, distance?)
True if the local player is within `distance` on a single axis only.

### QB.distance.xy(point, distance?)
True if the local player is within `distance` on the X/Y plane, ignoring Z —
useful when height shouldn't count (e.g. a marker under a multi-storey building).

## Server

Same functions, but each takes `src` first and measures from that player:
```lua
QB.distance.player(src, coords, distance?)
QB.distance.entity(src, entity, distance?)
QB.distance.x(src, point, distance?)   -- and y / xy
QB.distance.coords(coords1, coords2, distance?)   -- no src; pure point-to-point
```

## Notes
- Distance is Euclidean via FiveM's `#(vectorA - vectorB)`.
- Arguments are asserted: a missing/incomplete coordinate table raises rather
  than silently returning a wrong answer.
- The default radius is `5.0` when `distance` is omitted.
