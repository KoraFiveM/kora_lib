---
title: Performance and lifecycle
sidebar_position: 14
---

# Performance and lifecycle

kora_lib is designed so ordinary use does not require each resource to own a
per-frame loop. Prefer the direct kora_lib API, retain handles when an object has
a shorter lifetime than its resource, and let kora_lib clean up owner-scoped
state when the resource stops.

## Choose the direct API first

Use `Kora.<module>.<function>` in new resources. The consumer-side proxy loads
stateless helpers lazily, while kora_lib keeps shared registries and active
handles in one place. This avoids copying implementations and avoids a
separate scheduler in every resource.

The `ox_lib` and `PolyZone` compatibility resources are optional. They are
not started by the default server configuration. Install and ensure one only
when an unchanged legacy manifest imports it; new code should use kora_lib
directly. See [legacy compatibility](./legacy-compat.md) and
the [ox_lib migration guide](./migration/ox-lib.md).

## Pick the cheapest fit

| Need | Use | Cost model |
| --- | --- | --- |
| React to the local player entering a fixed area | `Kora.zones.box`, `.sphere`, `.circle`, or `.poly` | One shared spatial-grid pass; no loop per zone. |
| Read a local-player value such as vehicle, weapon, or coords | `Kora.cache` / `Kora.cache.onChange` | One shared cache sampler; handlers run only on changes. |
| Find what exists near a point right now | `Kora.world.getClosestEntity` or `.getNearbyEntities` | Scans the live entity pool for that call; use on an event or sensible interval, not every frame. |
| Check where the camera is aimed | `Kora.raycast.fromCamera` or `Kora.raycast.start` + `.poll` | A shape test only while the feature is active; start related rays together before awaiting them. |
| Populate decorative local entities over a large map | `Kora.entities.createScoped` | Uses the zone grid and streams/spawns only while the player is nearby. |
| Need a moving entity's bounds | The optional `PolyZone` `EntityZone` shim, only for legacy imports | Explicit polling; set the slowest acceptable `waitInMS`. |

## Zones and interaction checks

For a normal static area, use `Kora.zones.box`, `Kora.zones.sphere`,
`Kora.zones.circle`, or `Kora.zones.poly` with `onEnter` and `onExit`. kora_lib indexes these zones in its
shared spatial grid, so it does not run one player-position loop per zone.

```lua
local prompt
local garageZone = Kora.zones.box({
    coords = vector3(215.8, -810.1, 30.7),
    size = vector3(6.0, 6.0, 3.0),
    onEnter = function()
        prompt = Kora.textui.show('Press E to use the garage')
    end,
    onExit = function()
        if prompt then Kora.textui.hide(prompt) end
        prompt = nil
    end,
})

-- Remove early only when the zone's lifetime ends before this resource stops.
garageZone.remove()
```

Use a custom point poll only when the point is not the local player or legacy
timing must be preserved. Pick the slowest interval that feels responsive;
zero waits are a deliberate per-frame cost. The PolyZone EntityZone shim must
poll because moving model bounds cannot live in the static spatial grid; its
`waitInMS` option is explicit and validated.

## Per-frame work is opt-in

kora_lib uses `Wait(0)` only while a feature needs frame-accurate native calls:
an active control lease, visible interaction selector, movement modifier, or
debug zone renderer. Each loop starts lazily and stops when its final lease,
session, effect, or debug zone is gone. Calling the ordinary APIs while those
features are inactive does not create a permanent client loop.

Do not add a second loop to reapply controls, redraw zones, or poll a static
zone. Acquire a `Kora.controls` lease, use a zone callback, or enable debug
drawing instead; kora_lib composes those users into the existing shared loop.

## Observe state changes instead of polling

For local-player state that kora_lib already samples, subscribe to the cache
instead of starting another loop. Handlers run only when the value changes;
they are also removed automatically when the registering resource stops.

```lua
Kora.cache.onChange('vehicle', function(vehicle, previousVehicle)
    if vehicle then
        -- entered a vehicle
    elseif previousVehicle then
        -- left a vehicle
    end
end)
```

Use `Kora.cache.coords()` for ordinary interval or event work. It is sampled on
kora_lib's shared 200ms cache tick; read the native directly only when an engine
feature genuinely needs the current frame's position.

## Own what you create

Most registrations are automatically owned by the invoking resource. This
includes zones, keybinds, event handlers, callbacks, timers, sounds, entities,
and NUI requests. kora_lib releases them on resource stop. Remove a handle
yourself when the feature ends earlier, such as a temporary mission zone or a
modal keybind.

Keep handles with their owner. kora_lib deliberately rejects cross-resource
mutation of tracked animations, props, effects, entities, blips, controls, and
interactive sessions; passing a handle around is not a shared-control API.
When coordination is necessary, expose one narrow operation from the owning
resource rather than making several resources compete over the same state.

Avoid creating the same registration repeatedly on every tick. Create it once,
update its data only when it changes, and remove it when finished. The
[resources reference](./api/resources.md) describes
explicit owner registries for custom cleanup.

## Keep expensive work off the hot path

- Cache static hashes and authored configuration at resource start.
- Use the cache, stream, and zones modules instead of repeatedly querying the
  same native in unrelated loops.
- Keep debug drawing opt-in. PolyZone wrapper `draw(forceDraw)` helpers and
  `debugBlip` are debug-only tools; they do not enable a general zone-render
  loop. An EntityZone debug blip does update while that explicit debug option
  is active so it can follow the entity.
- Server expiry sweeps for status effects, minigame sessions, authorizations,
  and proofs run only while there is expiring state to reclaim, at a coarse
  30-second cadence. They stop again when the last entry is gone.
- Profile a real server before adding caching layers or abstractions. Prefer a
  direct native or existing kora_lib module when it already covers the use case.

## Targeted regression check

The configuration editor includes a lightweight Lua benchmark for its largest
expected catalog shape (60 resources × 500 settings). Run it from the kora_lib
root with `lua test/bench_config_editor.lua`. It reports timings rather than
enforcing a machine-dependent threshold, and asserts the important invariant:
toggling the advanced view populates only the selected resource's rows.

## Performance never replaces server validation

Do not move authorization to the client merely to avoid a server round trip.
Client input, zone presence, minigame success, and UI completion are hints;
the server must validate identity, permission, ownership, distance, cooldown,
and current state before granting anything valuable. Use documented callback
and event rate limits to protect request boundaries. See the [using the API
security boundary](./using-the-api.md#security-boundary),
[callbacks](./api/callback.md), and
[events](./api/events.md).
