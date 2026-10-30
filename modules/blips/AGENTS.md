# blips module guide

## Purpose
This module creates map blips visible only to the calling client, with automatic cleanup when the resource that created them stops. Same shape as `modules/entities`, applied to blips instead of world entities.

## Public API
- `QB.blips.create(coords, options)`
  - Creates a blip at `coords` (`AddBlipForCoord`).
  - `options.sprite` / `options.color` / `options.scale` / `options.shortRange` default from `Config.blips` when omitted.
  - `options.category` accepts a fixed catalogue name/legacy alias or numeric
    native category and defaults to `Other`. Every created blip receives
    `SetBlipCategory`; an unknown string is an assertion so typos cannot drift
    client category ids.
  - `options.name` is the location text supplied beneath GTA's native category
    heading; never prefix it with the category because the pause map does that
    automatically. A name equal to the category becomes an empty location label
    so the heading is not repeated. `options.label` remains an explicit legacy
    override. All category/name/label inputs are trimmed and whitespace-normalized.
  - `options.display` defaults to `Config.blips.defaultDisplay` and is retained
    so visibility controls can restore the caller's native display mode.
  - `options.route` draws a waypoint line to the blip (`SetBlipRoute`); if `options.color` is also set, the route is colored to match (`SetBlipRouteColour`).
  - `options.info` opts the blip into the pause-map detail panel. `setInfo` and `clearInfo` may only be called by the resource that created the blip.
  - Returns the blip handle, or `false, error` if creation failed.
- `QB.blips.remove(blip)`
  - Removes one tracked blip immediately and drops it from tracking.
  - Returns `true`, or `false, error` if the blip isn't tracked by this module or no longer exists.
- `QB.blips.getCategoryIds()` is shared and returns a fresh canonical category
  name-to-id map. Do not expose the mutable internal catalogue.
- `getCategories`, `getCategory`, and `getRegistered` provide client snapshots
  for category settings UI; registered records retain actual native handles and
  include their creating resource.
- `isCategoryVisible`, `hideCategory`, and `showCategory` manage the locally
  persisted category preference. `hide` and `show` manage one tracked handle.
- `/blips` opens the built-in compact AppShell category settings. Its adapter
  is `settings.lua`, explicitly loaded after `modules/**/client.lua` so both
  the registry and `QB.nui` exist. Resource-owner metadata must remain hidden
  unless `kora_lib:blips:isAdmin` confirms the viewer server-side; malformed
  callback sources fail closed before permission resolution.

## Implementation notes
- Ownership tracking is delegated entirely to `QB.resources.registry` (`local/resources`) rather than hand-rolled here — see that module's `AGENTS.md` for why. `blips` is the first consumer.
- Named category ids are a fixed shared catalogue in `shared.lua` (12-40). Never
  allocate them in creation order: that would make the same name resolve to
  different ids across resources, clients, or restarts.
- Visibility is implemented with `SetBlipDisplay(blip, 0)` and restored from the
  tracked display setting. Hidden blips also disable active routes; show restores
  the configured route and route color. Category state is stored in client KVPs.
- The settings adapter's official sprite artwork map is deliberately limited to
  sprite ids registered by first-party callers. Add the documented
  `radar_<name>` and real file extension when a first-party caller adds a sprite;
  unknown/custom ids must keep the generic icon rather than guessing a URL.
- The registry's `onDispose` callback guards with `DoesBlipExist` before calling `RemoveBlip` — a blip can stop existing for reasons outside this module's control (e.g. the underlying entity/waypoint system clearing it), and `RemoveBlip` on an already-gone handle is undefined behavior rather than a safe no-op.
- `AddBlipForCoord`'s failure mode (returning `0` or a falsy handle) is treated as a hard failure, same as `modules/entities`'s `0`/`DoesEntityExist` check after `CreatePed`/`CreateObjectNoOffset`/`CreateVehicle`.
- No model streaming step is needed (unlike `modules/entities`) — blips are a pure UI/map concept with no in-world asset to load.
- Detail-panel state is held beside the blip registry and must be cleared by the registry disposer, `clearInfo`, and `QB.blips.remove`. Image texture dictionaries are reference-counted across panels and released on final use. The frontend renderer is one client-local thread, never one thread per blip, and skips its fast pause-map poll while there are no detail panels. GTA continuously rebuilds pause-map columns, so an actively highlighted detail panel must be reasserted every frame or it flashes once and disappears; use `Wait(0)` only for that active state, retaining the low-frequency poll everywhere else.

## Best practices
- Always check the first return value of `QB.blips.create` before using the handle — a blip can fail to create.
- Call `QB.blips.remove` for anything that needs to disappear before your resource stops; don't just drop your reference to the handle.
- Pass `options.color` alongside `options.route` if you want the route line colored to match the blip — it isn't inferred automatically from the blip's own color unless you pass it to both.
