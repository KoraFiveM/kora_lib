---
title: Using the API
sidebar_position: 6
---

# Using the API

## Namespaces and exports

The recommended call form is:

```lua
Kora.<module>.<function>(...)
```

For example, a stateful call such as `Kora.entities.create(...)` resolves to
kora_lib's `entities_create` export. A non-Lua consumer can call generated exports
directly:

```lua
local entity = exports.kora_lib:entities_create(model, coords)
```

Use the documented `Kora` form in Lua. It provides language-server types and keeps consumer code consistent when an implementation changes behind the proxy.

`Kora.require`, `Kora.config`, `Kora.compat`, `Kora.util`, and `Kora.loops` are loaded
lazily inside the consuming resource. `Kora.stream` is loaded the same way on
the client, so model and asset streaming natives execute in the resource that
requested them. These modules are cached for the lifetime of that consumer.
After kora_lib restarts, an update notification reloads already-used stateless
helpers (`Kora.util`, `Kora.loops`, and client-side `Kora.stream`) in place;
untouched modules remain lazy. `Kora.require`, `Kora.config`, and `Kora.compat`
deliberately retain their consumer-local caches, registrations, and
configuration state until that consumer restarts. Existing references to a
refreshed module table stay valid.

Modules with shared registries, long-lived handles, or central state continue
to dispatch through kora_lib exports. Direct exports remain available for every
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

kora_lib uses assertions for programmer errors such as an invalid argument type or an impossible internal state. Recoverable runtime failures normally return `false, reason` or `nil, reason`, as documented by the individual function.

```lua
local entity, reason = Kora.entities.create(model, coords)
if not entity then
    print(('Could not create entity: %s'):format(reason))
    return
end
```

Do not discard a second return value when the reference documents one; it is intended to make operational failures diagnosable.

## Numeric inputs

Pass real, finite Lua numbers to numeric APIs. `NaN`, positive infinity, and
negative infinity are invalid even when Lua classifies them as numbers. Values
documented as IDs, counts, durations, delays, sizes, or limits must also be
whole numbers. kora_lib rejects invalid values before they can reach timers,
loops, native calls, or server-side state; validate consumer-owned input with
`Kora.util.isFiniteNumber(value)` or `Kora.util.isInteger(value)` when useful.

## Promises and coroutine-aware calls

Callbacks and NUI requests use FiveM promises internally. High-level helpers may return an awaited plain result when called across the export boundary and a promise for internal composition. The module reference states which behavior is part of its public contract.

Use promise-returning APIs from a yieldable coroutine such as a command handler or a `CreateThread` callback. Use an explicit callback form when the module provides one and the call site cannot yield.

## Resource ownership

Registrations and long-lived handles are owned by the invoking resource. kora_lib automatically cleans them up when that resource stops. This covers zones, entities, keybinds, callbacks, events, timers, sounds, NUI requests, and other registered state.

Status-effect definitions follow the same rule: their names are owner-scoped,
released on resource stop, and stored as immutable snapshots. A second resource
cannot silently replace a definition, and reading one never returns kora_lib's
live configuration table.

Ownership also protects mutation: a handle returned to one resource does not
give another resource authority to replace, stop, remove, or detach that
owner's tracked state. This applies to animation handles and attached props,
particle and screen effects, entities, blips, TextUI entries, controls,
keybinds, and active UI/minigame/progress sessions. Read-only queries remain
safe to share. If two resources need to control one long-lived feature, keep
the handle in the owning resource and expose a small, purpose-specific export
instead of passing its raw handle around.

Keep the returned handle when you need to remove or update something before resource shutdown:

```lua
local bind = Kora.keybind.add({
    name = 'garage_menu',
    description = 'Open the garage',
    defaultKey = 'G',
})

-- Later:
bind.remove()
```

## Security boundary

Client input is never authoritative. Use server callbacks or events together
with permission checks and the minigame authorization/proof flow where a
client result gates money, inventory, progression, or another valuable action.
Their session tokens only correlate protocol requests; a modified client can
obtain its own token. Validate identity, permission, ownership, distance,
cooldowns, and current server state in the handler. A progress bar or
successful client minigame is presentation, not proof that the server should
grant a reward.

## Configuration

kora_lib's own defaults live in `config.lua`, with server-only values in `server/config.lua`. Consumers can use `Kora.config` to define typed, owner-editable settings while retaining a normal authored Lua `Config` table. See the [configuration module](./api/config.md) for scopes, validation, persistence, and live-change handlers.
