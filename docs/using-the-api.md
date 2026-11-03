---
title: Using the API
permalink: /using-the-api/
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

## kora_lib restarts

Everything a consumer registers through kora_lib exports is stored inside
kora_lib: server callbacks and events, `Kora.cache.onChange` listeners, zones,
interact targets, keybinds, timers, state-bag listeners and so on. When kora_lib
restarts, all of it is gone. A consumer that keeps running is **not** told
which registrations it lost: its server callbacks answer "not registered" and
its listeners stay silent until the consumer itself restarts. Only the
consumer-local helpers (`Kora.util`, `Kora.loops`, client `Kora.stream`) are
reloaded automatically.

Put registrations that must survive a kora_lib restart inside `Kora.onReady`:

```lua
Kora.onReady(function()
    Kora.callback.register('garage:list', listVehicles)
    Kora.cache.onChange('vehicle', onVehicleChanged)
end)
```

### `Kora.onReady(fn)` — client/server, consumer-local
Runs `fn()` immediately, then again every time kora_lib restarts while this
resource keeps running (on `kora_lib:client:updated` / `kora_lib:server:updated`,
which kora_lib fires after rebuilding its exports). Returns an integer id.

- `fn` must be safe to run more than once. Registrations keyed by name
  (callbacks, events, keybinds, zones by name) simply replace themselves.
  Anonymous registrations made **outside** kora_lib (your own
  `AddEventHandler`, threads, timers you started with `SetTimeout`) are not
  lost on a kora_lib restart and must not go inside `fn`, or they will be
  duplicated.
- The first run happens synchronously in the caller; an error there raises as
  normal. Later runs each get their own thread, so a handler may `Wait`, and an
  error is printed without stopping the other handlers.
- Handlers belong to the resource that registered them and disappear with it.

### `Kora.offReady(id)` — client/server, consumer-local
Stops a handler from running after later kora_lib restarts. Returns `true` if
`id` was registered, `false` otherwise.

Resources that declare `dependency 'kora_lib'` in their manifest may be
stopped by FXServer together with kora_lib depending on the server build; when
that happens, they start again through their normal load path and `onReady`
runs once as usual. Either way, the safe pattern is the same: restart kora_lib
with `ensure`/`restart` and keep anything that must be re-registered inside
`Kora.onReady`.

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

kora_lib's own defaults live in `config.lua`, with server-only values in `server/config.lua`. Consumers can use `Kora.config` to define typed, owner-editable settings while retaining a normal authored Lua `Config` table. See the [configuration module]({{ site.baseurl }}/reference/config/) for scopes, validation, persistence, and live-change handlers.
