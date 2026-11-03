# Resources module

## Overview
Shared infrastructure for tracking which resource created/registered a given id, and automatically releasing everything a resource owned when it stops. Every module that owns per-resource state (`entities`, `zones`, `cache`, `blips`, `local/callback`, `local/events`) uses this instead of hand-rolling its own resource-ownership table.

## API

### `Kora.resources.isStarted(resourceName)` (shared)

Returns `true` only when `GetResourceState(resourceName)` is `started`.

### `Kora.resources.awaitStarted(resourceName, options?)` (shared)

Waits for a dependency without creating an unbounded startup loop. Options are
`timeout` (default `10000`) and `interval` (default `100`), both milliseconds.
Both must be finite non-negative numbers; `interval = 0` is valid but means a
deliberate per-frame retry until the finite timeout expires. `timeout = 0`
performs one immediate state check without waiting.
The optional `options` argument must be a table when supplied.
Returns `true` when ready, `false, "missing"` for an unknown resource, or
`false, "timeout"` when the deadline expires.

```lua
local ready, reason = Kora.resources.awaitStarted('qbinventory', {
    timeout = 30000,
    interval = 200,
})
if not ready then print(('qbinventory unavailable: %s'):format(reason)) end
```

### `Kora.resources.onStart(resourceName, fn, opts?)` (shared)

Runs `fn(resourceName)` right away if `resourceName` is already started, then
again every time it starts (a restart included). Use it to (re-)register things
with another resource, such as targets in kora_target or anything that must be
redone after that resource restarts, instead of hand-writing an
`onClientResourceStart`/`onResourceStart` handler plus a "wait until started"
loop.

- `opts.runNow` (default `true`) — set `false` to skip the immediate run.
- Returns an integer id for `Kora.resources.off`.
- The immediate run happens in the caller; later runs each get their own thread,
  so `fn` may `Wait`. Errors are printed and do not stop other handlers.
- Handlers are removed automatically when the calling resource stops.
- They live in kora_lib, so a kora_lib restart drops them like any other
  registration. Register them inside `Kora.onReady` if they must survive that
  (see "kora_lib restarts" in `docs/using-the-api.md`); watching `kora_lib`
  itself this way does not work, use `Kora.onReady` for that.

```lua
Kora.onReady(function()
    Kora.resources.onStart('kora_target', function()
        exports.kora_target:AddBoxZone('armory', coords, 1.5, 1.5, options)
    end)
end)
```

### `Kora.resources.onStop(resourceName, fn)` (shared)

Runs `fn(resourceName)` every time `resourceName` stops, for example to drop
cached handles that belonged to it. Same ownership and error handling as
`onStart`. A resource is never told about its own stop. Returns an integer id.

### `Kora.resources.off(id)` (shared)

Removes an `onStart`/`onStop` handler early. Returns `true` when removed;
`false` for an unknown id or one registered by another resource.

### `Kora.resources.registry(onDispose)` (client)
### `Kora.resources.serverRegistry(onDispose)` (server)
Creates a new, isolated ownership registry. Identical shape on both realms — swept on `onClientResourceStop` (client) or `onResourceStop` (server).

#### Parameters
- `onDispose: fun(id: any)` — A callable (including a FiveM callable proxy), called once for every id still tracked under a resource when that resource stops. Invalid disposers fail when the registry is created.

#### Returns
- A table with three functions:
  - `track(resource: string, id: any)` — Marks a non-`nil` `id` as owned by a non-empty resource name up to 256 bytes. If `id` was already tracked under a *different* resource, ownership moves — it's removed from the previous owner's set first.
  - `untrack(id: any): string?` — Drops a non-`nil` id's tracking and returns the resource it was owned by, or `nil` if it wasn't tracked. Does not call `onDispose`.
  - `owner(id: any): string?` — Returns the resource currently tracking a non-`nil` id, without changing anything.

#### Behavior
1. Each call creates a fresh, independent registry — its own forward index and reverse lookup, and its own sweep handler.
2. When a resource stops, `onDispose(id)` runs for every id it still owned, and all tracking for those ids is dropped.
   A disposer cannot re-track an id for that same resource while its sweep is
   active; this prevents stop-time cleanup from recreating state that no later
   stop event can release.
3. Calling `untrack(id)` directly (e.g. from a manual "remove" function) only removes bookkeeping — it's the caller's responsibility to release the underlying thing first.
4. Calling `track(resource, id)` again for an id already owned by a different resource transfers ownership rather than adding a second, stale entry — useful for name-keyed registries (e.g. `local/events`' push handlers) where re-registering an existing name is expected to take it over.

#### Example
```lua
local blipRegistry = Kora.resources.registry(function(blip)
    if DoesBlipExist(blip) then RemoveBlip(blip) end
end)

function Kora.blips.create(coords, options)
    local invokingResource = GetInvokingResource() or GetCurrentResourceName()
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    blipRegistry.track(invokingResource, blip)
    return blip
end

function Kora.blips.remove(blip)
    local owner = blipRegistry.untrack(blip)
    if not owner then return false, "Blip is not tracked by Kora.blips." end
    RemoveBlip(blip)
    return true
end
```
