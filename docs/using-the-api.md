---
title: Using the API
permalink: /using-the-api/
---

# Using the API

## Namespaces and exports

The recommended call form is:

```lua
QB.<module>.<function>(...)
```

For example, a stateful call such as `QB.entities.create(...)` resolves to
qblib's `entities_create` export. A non-Lua consumer can call generated exports
directly:

```lua
local entity = exports.qblib:entities_create(model, coords)
```

Use the documented `QB` form in Lua. It provides language-server types and keeps consumer code consistent when an implementation changes behind the proxy.

`QB.require`, `QB.config`, `QB.compat`, `QB.util`, and `QB.loops` are loaded
lazily inside the consuming resource. `QB.stream` is loaded the same way on
the client, so model and asset streaming natives execute in the resource that
requested them. These modules are cached for the lifetime of that consumer.
After qblib restarts, an update notification reloads only the local helper and
streaming modules that were already used; untouched modules remain lazy.
Existing module table references are updated in place.

Modules with shared registries, long-lived handles, or central state continue
to dispatch through qblib exports. Direct exports remain available for every
module, including the consumer-local modules, for non-Lua callers and explicit
compatibility use.

## Realms

Each API is available in one or more FiveM realms:

| Label | Available from |
| --- | --- |
| client | A consumer's client scripts |
| server | A consumer's server scripts |
| shared | Both client and server scripts |
| client/server | Both realms, sometimes with realm-specific parameters |

Calling a function from the wrong realm requests an export that was never registered there. Check the function heading or signature before using it from shared code.

## Results and expected failures

qblib uses assertions for programmer errors such as an invalid argument type or an impossible internal state. Recoverable runtime failures normally return `false, reason` or `nil, reason`, as documented by the individual function.

```lua
local entity, reason = QB.entities.create(model, coords)
if not entity then
    print(('Could not create entity: %s'):format(reason))
    return
end
```

Do not discard a second return value when the reference documents one; it is intended to make operational failures diagnosable.

## Promises and coroutine-aware calls

Callbacks and NUI requests use FiveM promises internally. High-level helpers may return an awaited plain result when called across the export boundary and a promise for internal composition. The module reference states which behavior is part of its public contract.

Use promise-returning APIs from a yieldable coroutine such as a command handler or a `CreateThread` callback. Use an explicit callback form when the module provides one and the call site cannot yield.

## Resource ownership

Registrations and long-lived handles are owned by the invoking resource. qblib automatically cleans them up when that resource stops. This covers zones, entities, keybinds, callbacks, events, timers, sounds, NUI requests, and other registered state.

Keep the returned handle when you need to remove or update something before resource shutdown:

```lua
local bind = QB.keybind.add({
    name = 'garage_menu',
    description = 'Open the garage',
    defaultKey = 'G',
})

-- Later:
bind.remove()
```

## Security boundary

Client input is never authoritative. Use server callbacks, token-guarded events, permission checks, and the minigame authorization/proof flow where a client result gates money, inventory, progression, or another valuable action. A progress bar or successful client minigame is presentation, not proof that the server should grant a reward.

## Configuration

qblib's own defaults live in `config.lua`, with server-only values in `server/config.lua`. Consumers can use `QB.config` to define typed, owner-editable settings while retaining a normal authored Lua `Config` table. See the [configuration module]({{ site.baseurl }}/reference/config/) for scopes, validation, persistence, and live-change handlers.
