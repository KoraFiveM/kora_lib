# resources module guide

## Purpose
Shared infrastructure for the pattern nearly every owned-state module needs: track which resource created/registered a given id, and automatically release everything a resource owned when it stops. `modules/entities`, `modules/zones`, `modules/cache`, `local/callback`, and `local/events` all used to hand-roll this themselves (a `byResource[resource] = {id set}` table, a reverse `id -> resource` lookup, and a `onClientResourceStop`/`onResourceStop` sweep); `local/resources` factors that shape out into one reusable factory per realm so a module doesn't have to copy it.

## Public API
- `QB.resources.isStarted(resourceName)` (shared)
- `QB.resources.awaitStarted(resourceName, options?)` (shared)
  - Waits for `started` with bounded `timeout` and `interval` options.
  - Returns immediately with `false, "missing"` for an unknown resource and
    `false, "timeout"` when a known dependency does not start in time.
- `QB.resources.registry(onDispose)` (client)
- `QB.resources.serverRegistry(onDispose)` (server)
  - Same shape on both realms, swept on `onClientResourceStop` vs `onResourceStop` respectively. Each creates and returns a new, isolated registry: `{ track, untrack, owner }`.
  - `onDispose(id)` is called once for every id still tracked under a resource when that resource stops — the registry itself never decides how to release an id, only when. This includes qblib itself: its modules use the final stop event to release entities, focus, and state before teardown completes.
  - `registry.track(resource, id)` marks `id` as owned by `resource`. Re-tracking an id already owned by a *different* resource moves it — the old owner's forward index no longer includes it, so that resource stopping later won't dispose an id it no longer owns.
  - `registry.untrack(id)` drops `id`'s tracking and returns the resource it was owned by (or `nil` if it wasn't tracked). Does **not** call `onDispose` — callers that remove something immediately (rather than waiting for their resource to stop) are expected to release it themselves and call `untrack` only to update bookkeeping.
  - `registry.owner(id)` returns the resource currently tracking `id` without changing anything.

## Implementation notes
- **One registry per id space, not one shared table.** Entity handles, blip handles, cache-listener ids, and event/callback names are all unrelated id spaces — sharing a single reverse lookup across them would risk one module's id colliding with another's. Each consuming module calls `QB.resources.registry(...)`/`serverRegistry(...)` once at load time and keeps the returned handle as a module-local upvalue, exactly like it would have kept its own hand-rolled `byResource`/`ownerOf` tables.
- **One sweep handler per registry**, not a single shared dispatcher. Each registry is fully self-contained — creating one is enough to get correct cleanup, with no separate registration step and nothing for a consuming module to forget.
- **Cleanup always runs.** A resource-stop event is the final opportunity to release owned state, including qblib's own state. Disposal failures are contained and logged so one bad id cannot prevent the remainder of the sweep.
- **`track`'s re-track/move behavior exists for name-keyed registries.** `local/callback` and `local/events` track by callback/event *name*, and a second resource registering the same name is expected to take over ownership of it (with a warning printed by the caller — the registry itself doesn't judge whether an overwrite is suspicious, it just keeps the bookkeeping correct either way).
- `untrack` is deliberately inert with respect to disposal — it only removes bookkeeping. This mirrors how `modules/entities`'s `untrack` behaved before migrating here: a manual `remove()` call deletes the entity itself and *then* calls `untrack`, rather than `untrack` deleting it.
- `client.lua` and `server.lua` are two independent implementations, not one shared function — their resource-stop events and ownership tables are realm-specific. Truly realm-neutral helpers can live under the non-exported `QB.compat` bootstrap namespace; opaque token generation is centralized there.

## Consumers
- `modules/entities` — one registry, id = entity handle, `onDispose` deletes the entity.
- `modules/zones` — one registry, id = zone id, `onDispose` runs the same zone-teardown path a manual `remove()` uses.
- `modules/cache` — one registry, id = a synthetic per-listener id (cache listeners aren't 1:1 with a single owned handle — a key can have several listeners from several resources — so each `onChange` registration gets its own id to track).
- `modules/blips` — one registry, id = blip handle, `onDispose` removes the blip.
- `local/callback` — one `registry`/`serverRegistry` per realm, id = callback name.
- `local/events` — one `registry`/`serverRegistry` per realm, id = push/event name.
- External qblib consumers may also create a registry through the imported
  `QB.resources` proxy. Returned methods and the disposer are FiveM funcrefs;
  keep the registry handle in the consuming resource and treat it like any
  other cross-resource qblib handle.

## Best practices
- Create a registry once per module (and per realm), at load time — not per call.
- Keep `onDispose` cheap and idempotent-safe (e.g. guard with a `DoesXExist` check) — it can run for ids whose underlying handle already stopped existing for unrelated reasons.
- Don't reach into another module's registry. If two modules need to share ownership of the same kind of id, that's a sign they should be one module.
