# blips module guide

## Purpose
This module creates map blips visible only to the calling client, with automatic cleanup when the resource that created them stops. Same shape as `modules/entities`, applied to blips instead of world entities.

## Public API
- `QB.blips.create(coords, options)`
  - Creates a blip at `coords` (`AddBlipForCoord`).
  - `options.sprite` / `options.color` / `options.scale` / `options.shortRange` default from `Config.blips` when omitted.
  - `options.label` sets the blip's display name via the `BeginTextCommandSetBlipName`/`AddTextComponentSubstringPlayerName`/`EndTextCommandSetBlipName` trio (FiveM has no single-call native for this).
  - `options.category` accepts a numeric native category or a string. A string
    allocates a named custom category (12-133), and every blip using that same
    string is grouped beneath one pause-map legend heading. Left unset (engine
    default) when omitted.
  - `options.route` draws a waypoint line to the blip (`SetBlipRoute`); if `options.color` is also set, the route is colored to match (`SetBlipRouteColour`).
  - Returns the blip handle, or `false, error` if creation failed.
- `QB.blips.remove(blip)`
  - Removes one tracked blip immediately and drops it from tracking.
  - Returns `true`, or `false, error` if the blip isn't tracked by this module or no longer exists.

## Implementation notes
- Ownership tracking is delegated entirely to `QB.resources.registry` (`local/resources`) rather than hand-rolled here — see that module's `AGENTS.md` for why. `blips` is the first consumer.
- The registry's `onDispose` callback guards with `DoesBlipExist` before calling `RemoveBlip` — a blip can stop existing for reasons outside this module's control (e.g. the underlying entity/waypoint system clearing it), and `RemoveBlip` on an already-gone handle is undefined behavior rather than a safe no-op.
- `AddBlipForCoord`'s failure mode (returning `0` or a falsy handle) is treated as a hard failure, same as `modules/entities`'s `0`/`DoesEntityExist` check after `CreatePed`/`CreateObjectNoOffset`/`CreateVehicle`.
- No model streaming step is needed (unlike `modules/entities`) — blips are a pure UI/map concept with no in-world asset to load.

## Best practices
- Always check the first return value of `QB.blips.create` before using the handle — a blip can fail to create.
- Call `QB.blips.remove` for anything that needs to disappear before your resource stops; don't just drop your reference to the handle.
- Pass `options.color` alongside `options.route` if you want the route line colored to match the blip — it isn't inferred automatically from the blip's own color unless you pass it to both.
