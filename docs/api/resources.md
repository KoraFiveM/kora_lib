---
title: "Resources"
sidebar_position: 7
---


# Resources

## Shared

Shared infrastructure for waiting on other resources and for tracking which resource created a given id so everything it owned is released automatically when it stops. Modules that own per-resource state (entities, zones, cache, blips, callbacks and events) use this instead of hand-rolling their own ownership table.

Namespace: `Kora.resources` · Source: `local/resources/shared.lua`

### Functions

`isStarted` and `awaitStarted` work in both realms.

#### `Kora.resources.isStarted(resourceName)`

Reports whether a resource is currently started.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `resourceName` | string | The resource to check. |

**Returns**

- **started** — `true` only when `GetResourceState(resourceName)` is `started`.

**Example**

```lua
if Kora.resources.isStarted('kora_inventory') then
    -- safe to call its exports
end
```

**Representative console output**

```text
`true` while `kora_inventory` is started; `false` in every other state, including when it does not exist.
```

#### `Kora.resources.awaitStarted(resourceName, options?)`

Waits for a dependency to start without creating an unbounded startup loop.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `resourceName` | string | The resource to wait for. |
| `options.timeout?` | number | Milliseconds to wait. Default `10000`. `0` performs a single immediate check without waiting. |
| `options.interval?` | number | Milliseconds between checks. Default `100`. `0` is valid and retries every frame until the timeout expires. |

**Returns**

- **ready** — `true` when the resource is started.
- **reason** — `"missing"` for an unknown resource, or `"timeout"` when the deadline expires (only with `false`).

**Example**

```lua
local ready, reason = Kora.resources.awaitStarted('kora_inventory', {
    timeout = 30000,
    interval = 200,
})
if not ready then print(('kora_inventory unavailable: %s'):format(reason)) end
```

**Representative console output**

```text
Continues as soon as `kora_inventory` has started. Otherwise prints `kora_inventory unavailable: missing` or `kora_inventory unavailable: timeout`. `timeout` and `interval` must be finite non-negative numbers, and `options` must be a table when supplied.
```

### Limits and related APIs

`awaitStarted` rejects a non-table `options`, and `timeout` and `interval` must be finite non-negative numbers.

## Client

Creates ownership registries on the client. A registry is swept on `onClientResourceStop`.

Namespace: `Kora.resources` · Source: `local/resources/client.lua`

### How a registry behaves

Each call creates a fresh, independent registry with its own forward index, reverse lookup and sweep handler. When a resource stops, `onDispose(id)` runs for every id it still owned and all tracking for those ids is dropped. A disposer cannot re-track an id for the same resource while its sweep is active, so stop-time cleanup cannot recreate state that no later stop event can release. Re-tracking an id under a different resource transfers ownership rather than adding a second, stale entry, which suits name-keyed registries where re-registering a name is expected to take it over.

### Functions

Identical in shape to the server's `serverRegistry`.

#### `Kora.resources.registry(onDispose)`

Creates a new, isolated ownership registry that remembers which resource created each id and releases everything a resource owned when it stops (swept on `onClientResourceStop`).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `onDispose` | fun(id: any) | Called once for every id still tracked under a resource when that resource stops. May be a FiveM callable proxy; an invalid disposer fails when the registry is created. |

**Returns**

- **registry** — a table with `track(resource, id)`, `untrack(id)` and `owner(id)`.
- **`track(resource, id)` marks a non-`nil` id as owned by a non-empty resource name (up to 256 bytes); an id already owned by a different resource moves to the new owner.**
- **`untrack(id)` drops tracking and returns the owning resource (or `nil`); it does not call `onDispose`.**
- **`owner(id)` returns the resource currently tracking the id without changing anything.**

**Example**

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
    if not owner then return false, 'Blip is not tracked by Kora.blips.' end
    RemoveBlip(blip)
    return true
end
```

**Representative console output**

```text
When a resource that created blips stops, `onDispose` runs for each blip it still owned and removes it. Calling `untrack` yourself removes only the bookkeeping, so release the underlying thing first.
```

### Limits and related APIs

`track` and `untrack` raise an error for a `nil` id. Resource names must be non-empty strings of at most 256 bytes, and `track` raises while that resource is stopping.

## Server

Creates ownership registries on the server. A registry is swept on `onResourceStop`.

Namespace: `Kora.resources` · Source: `local/resources/server.lua`

### How a registry behaves

Each call creates a fresh, independent registry with its own forward index, reverse lookup and sweep handler. When a resource stops, `onDispose(id)` runs for every id it still owned and all tracking for those ids is dropped. A disposer cannot re-track an id for the same resource while its sweep is active, so stop-time cleanup cannot recreate state that no later stop event can release. Re-tracking an id under a different resource transfers ownership rather than adding a second, stale entry.

### Functions

Identical in shape to the client's `registry`.

#### `Kora.resources.serverRegistry(onDispose)`

Creates a new, isolated ownership registry that remembers which resource created each id and releases everything a resource owned when it stops (swept on `onResourceStop`).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `onDispose` | fun(id: any) | Called once for every id still tracked under a resource when that resource stops. May be a FiveM callable proxy; an invalid disposer fails when the registry is created. |

**Returns**

- **registry** — a table with `track(resource, id)`, `untrack(id)` and `owner(id)`.
- **`track(resource, id)` marks a non-`nil` id as owned by a non-empty resource name (up to 256 bytes); an id already owned by a different resource moves to the new owner.**
- **`untrack(id)` drops tracking and returns the owning resource (or `nil`); it does not call `onDispose`.**
- **`owner(id)` returns the resource currently tracking the id without changing anything.**

**Example**

```lua
local blipRegistry = Kora.resources.serverRegistry(function(blip)
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
    if not owner then return false, 'Blip is not tracked by Kora.blips.' end
    RemoveBlip(blip)
    return true
end
```

**Representative console output**

```text
When a resource that created blips stops, `onDispose` runs for each blip it still owned and removes it. Calling `untrack` yourself removes only the bookkeeping, so release the underlying thing first.
```

### Limits and related APIs

`track` and `untrack` raise an error for a `nil` id. Resource names must be non-empty strings of at most 256 bytes, and `track` raises while that resource is stopping.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/resources/docs.md` or `local/resources/docs.md`) that the reference above does not state.

### API

#### `Kora.resources.isStarted(resourceName)` (shared)

Returns `true` only when `GetResourceState(resourceName)` is `started`.

#### `Kora.resources.awaitStarted(resourceName, options?)` (shared)

Waits for a dependency without creating an unbounded startup loop. Options are
`timeout` (default `10000`) and `interval` (default `100`), both milliseconds.
Both must be finite non-negative numbers; `interval = 0` is valid but means a
deliberate per-frame retry until the finite timeout expires. `timeout = 0`
performs one immediate state check without waiting.
The optional `options` argument must be a table when supplied.
Returns `true` when ready, `false, "missing"` for an unknown resource, or
`false, "timeout"` when the deadline expires.
