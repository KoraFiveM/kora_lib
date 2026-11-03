# Sites module

## Overview

Many resources define **sites** that own **interaction points**: a fuel station
and its pumps and chargers, a shop and its counters, a garage and its parking
spots, an armoury and its lockers. `Kora.sites` turns that config into a
flat index once, so that:

- a server purchase validates **one** client-supplied site/point pair with one
  table lookup and one distance check, instead of looping over every site with a
  wide radius;
- prices and other per-point values are resolved once (point, then site, then
  global default) instead of on every purchase;
- the client gets one `Kora.interact` zone per point.

Everything is plain tables: no metatables and no per-object closures.

`Kora.sites` is loaded **inside the consuming resource** by `init.lua`, like
`Kora.util`. The index lives in your resource, so `validate` never sends it
across the exports boundary.

## API

### `Kora.sites.build(defs, opts?)` — shared

Flattens an array of sites into an index.

- `defs` — array of sites. Each site needs an `id` (string without `:`, or an
  integer) and an array of points under `opts.childKey`. Each point needs an
  `id` and finite `coords`; it may have a `type`, a `radius` and any other
  fields. `disabled = true` on a site or a point disables it.
- `opts.childKey` — the field holding a site's points. Defaults to `'children'`.
- `opts.inherit` — fields resolved for each point: the point's own value, else
  the site's, else `opts.globals`. A site or global value may be a plain value
  (used for every point) or a table keyed by point `type`
  (`price = { pump = 1.55, charger = 0.45 }`).
- `opts.globals` — fallback values for `inherit` fields.

Returns `{ sites = { [siteId] = site }, children = { ['siteId:pointId'] = point }, list = { points in order } }`.
Each point in the index is a copy of its definition plus `id` (as a string),
`siteId`, `key` (`'siteId:pointId'`), `disabled`, and the resolved `inherit`
fields. Your config tables are not modified. Malformed definitions raise.
Rebuild the index when the config changes (for example from a
`Kora.config.onChange` handler).

```lua
local index = Kora.sites.build(Config.stations, {
    childKey = 'refills',
    inherit = { 'price' },
    globals = { price = Config.prices }, -- { pump = 1.60, charger = 0.45 }
})
-- index.children['grove:p2'].price -> the pump's own price, else the station's, else the global one
```

### `Kora.sites.get(index, siteId, pointId?)` — shared

Returns the site (when `pointId` is omitted) or the resolved point, or `nil`.
Malformed ids (tables, NaN, ...) return `nil`, so client data can be passed in
directly.

### `Kora.sites.validate(source, index, siteId, pointId, opts)` — server

Resolves a client-supplied pair and checks it on the server. Returns the
point, or `nil, reason`:

| Check | Reason |
|---|---|
| The site exists | `unknown_site` |
| The point exists | `unknown_child` |
| Neither the site nor the point is disabled | `disabled` |
| The point's `type` is in `opts.types` (when given) | `wrong_type` |
| The player's ped exists | `player_unavailable` |
| The player is within the limit of **this** point | `too_far` |

The distance limit is `opts.maxDistance`, widened by the point's own `radius`
if that is larger (a legacy "whole forecourt" point can keep a wide radius
without widening every other point). One of the two is required.

With `opts.vehicleNetId`, the vehicle is also resolved through
`Kora.world.resolveNetworkEntity` (`entityType = 'vehicle'`, `near` the point
within `opts.vehicleDistance`, default the player limit). On success it returns
`point, vehicle`; on failure its reason is passed through (for example
`too_far_from_point` or `routing_bucket_mismatch`).

Prices and amounts must still come from the server: read them from the
returned point, never from the client.

```lua
RegisterNetEvent('fuel:purchase', function(stationId, refillId, netId)
    local src = source
    local refill, vehicleOrReason = Kora.sites.validate(src, index, stationId, refillId, {
        maxDistance = 4.0, types = { 'pump' }, vehicleNetId = netId, vehicleDistance = 8.0,
    })
    if not refill then return notify(src, ('Cannot refuel here (%s)'):format(vehicleOrReason)) end
    local cost = refill.price * litres -- server-side price
end)
```

### `Kora.sites.registerZones(index, optionsByType, opts?)` — client

Adds one `Kora.interact` circle zone per enabled point whose `type` has an entry
in `optionsByType`. An entry is either zone target options shared by every
point of that type, or a function `fn(point)` returning per-point options (or
`nil` to skip that point). The zone radius is the point's `radius`, else
`opts.radius`, else `2.0`. `opts.debug` draws the zones. Zone names are
prefixed with your resource name, so two resources can use the same site ids.

Returns `{ remove() }`; `remove()` deletes every zone it created and returns how
many. Zones are also removed when your resource stops. They live in kora_lib,
so register them inside `Kora.onReady` to get them back after a kora_lib
restart.

```lua
Kora.onReady(function()
    Kora.sites.registerZones(index, {
        pump = function(refill)
            return { { label = 'Refuel', event = 'kora_fuel:client:refuel', args = { refill.siteId, refill.id } } }
        end,
    })
end)
```
