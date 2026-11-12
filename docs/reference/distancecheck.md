---
title: "Kora.distance"
sidebar_position: 24
---

# Kora.distance

Cheap radius checks between the local player, arbitrary coordinates, and
entities. Every function returns a boolean: `true` when the measured distance is
within `distance` (default `5.0`). Client functions measure from the local
player (`Kora.cache.get('coords')`); server functions take `src` first and measure
from that player's ped (requires OneSync for a valid server-side ped position).

## Client

### Kora.distance.player(coords, distance?)
True if the local player is within `distance` of `coords` (`{x,y,z}`).
```lua
if Kora.distance.player(shopCoords, 2.5) then openShop() end
```

### Kora.distance.coords(coords1, coords2, distance?)
True if two points are within `distance` of each other. (Same on both realms.)

### Kora.distance.entity(entity, distance?)
True if the local player is within `distance` of `entity`.

### Kora.distance.x(point, distance?) / Kora.distance.y(point, distance?)
True if the local player is within `distance` on a single axis only.

### Kora.distance.xy(point, distance?)
True if the local player is within `distance` on the X/Y plane, ignoring Z —
useful when height shouldn't count (e.g. a marker under a multi-storey building).

## Server

Same functions, but each takes `src` first and measures from that player:
```lua
Kora.distance.player(src, coords, distance?)
Kora.distance.entity(src, entity, distance?)
Kora.distance.x(src, point, distance?)   -- and y / xy
Kora.distance.coords(coords1, coords2, distance?)   -- no src; pure point-to-point
```

### Kora.distance.playerNearAny(src, list, opts) [server only]
True if `src` is within `opts.radius` (default `5.0`) of any entry in `list`,
using `opts.coordsOf(entry)` to read that entry's coordinates. Returns the
matching entry (the nearest one, if several qualify) as a second value, or
`nil` when nothing matched. Built on `Kora.util.nearest` — the common "is the
player near any of these configured locations" check used by door, vendor and
pickup-spot lists instead of each resource hand-rolling the same loop:
```lua
local found, location = Kora.distance.playerNearAny(src, Config.locations, {
    radius = 2.5,
    coordsOf = function(entry) return entry.coords end,
})
```

## Notes
- Distance uses squared components, avoiding temporary vector allocations and
  square roots in these frequent checks while preserving Euclidean-radius
  results.
- Arguments are asserted: a missing, incomplete, or non-finite coordinate table raises rather
  than silently returning a wrong answer.
- Every source-based server call requires a positive integer player server ID.
- Source-based server checks also require a live player ped. Server entity
  checks require a positive integer handle that still exists, so invalid or
  unavailable handles raise before coordinate lookup.
- The default radius is `5.0` when `distance` is omitted. An explicit radius
  must be a finite non-negative number; `false` is invalid rather than a
  shorthand for the default.
- Use the server form for any meaningful action. It reads the source player's
  server-side ped position, but proximity is only one authorization condition:
  also validate ownership, permissions, the requested action, and current
  server state. Do not accept a client-supplied radius or target position as
  proof that an action is allowed.
