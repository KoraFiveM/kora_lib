---
title: "Events module"
sidebar_position: 4
---

# Events module

## Overview
The events module lets client code call server-side logic through one named,
rate-limitable gateway instead of every consumer hand-rolling a network event.
Its per-session token correlates a request with the source that completed the
handshake; it is not authorization. A modified client can request its own
token, so every handler must still validate client-controlled input and
server-side state.

## API

### `Kora.events.register(name, handler, opts?)` — server
Registers `handler` to run when a client calls `Kora.events.trigger(name, ...)`.

#### Parameters
- `name: string` — Logical action name (1–128 bytes).
- `handler: fun(src: integer, ...: any)` — Called with the triggering player's server ID, followed by whatever arguments the client sent.
- `opts.rateLimit: { max: 1–10000 integer, window: 1–86400000 integer } | false | nil`
  — optional per-player, per-handler sliding window in milliseconds.
  Omitted/`false` remains unlimited.

#### Behavior
Requests are only dispatched to `handler` if the triggering client's session token (established during the handshake) matches what the server has stored for that player. Anything else — no token, wrong token, wrong types — is dropped without running `handler` or raising an error. Token and handler resolution happen before rate quota is consumed. Over-limit events are silently dropped.

### `Kora.events.trigger(name, ...)` — client
Triggers the handler registered under `name` on the server.

#### Parameters
- `name: string` — 1–128 bytes; must match a name passed to `Kora.events.register` on the server.
- `...: any` — Forwarded to the server-side handler after `src`.

#### Returns
- `boolean` — `true` if the request was sent.
- `string | nil` — Set when the handshake token never arrived (waited 10s), explaining why nothing was sent.

#### Example
Server:
```lua
Kora.events.register('inventory:useItem', function(src, itemName)
    -- src is the real player who triggered this, not client-supplied
    print(('player %d used %s'):format(src, itemName))
end)
```

Client:
```lua
local ok, err = Kora.events.trigger('inventory:useItem', 'water_bottle')
if not ok then
    print('failed to trigger event:', err)
end
```

## Notes
- One handler per name: registering a name another resource already claimed replaces it and logs a warning naming both resources. Namespace your names (`inventory:useItem`, not `use`) to avoid it. Re-registering your own name — what happens on a resource restart — is normal and silent.
- Every player gets a unique token issued over a per-source handshake. It keeps
  unrelated or malformed protocol traffic out of a handler, but it does not
  authenticate a player: a modified client can complete its own handshake.
- The gateway event name itself (`kora_lib:events:invoke`) is fixed and public.
  Never use knowledge of the token or event name as permission to grant an
  item, money, progression, or privileged action.
- Handshake and gateway traffic must originate from a positive finite integer
  server ID. Malformed/local invocations are dropped before token state is read.
- Gateway names over 128 bytes are dropped before registry lookup or response
  formatting.
- Client receivers likewise ignore malformed handshake tokens and non-string
  push names before touching their local registries.
- Rate buckets are cleared on player drop, unregister/replacement/ownership
  cleanup, and window expiry.
- Each active rate bucket retains at most its configured `max` timestamps, so
  a long-lived high-traffic handler does not accumulate rate-limit storage.
- Validate player identity, permission, ownership, distance, cooldowns, and
  current server state in every valuable handler. The gateway cannot perform
  those application-specific checks for you.

Need a response back instead of fire-and-forget? See the `callback` module (`local/callback/`) — `Kora.callback.register`/`Kora.callback.trigger` work the same way but return a promise, and also support the reverse direction (server asking a client).

## Push (server → client)

### `Kora.events.push(target, name, ...)` — server
Sends a named push to one client, or every connected client.

#### Parameters
- `target: positive finite integer | -1` — Server ID of the recipient, or `-1` for every connected player.
- `name: string` — Logical push name (1–128 bytes).
- `...: any` — Forwarded to the client-side handler.

#### Behavior
Not token-gated. Unlike `trigger`, there's no client identity to verify here — the server is always the trusted party for its own `TriggerClientEvent` calls, so `push` is a thin, named wrapper around one shared gateway event rather than a security control.

### `Kora.events.onPush(name, handler)` — client
Registers `handler` to run when the server calls `Kora.events.push(target, name, ...)` for this client.

#### Parameters
- `name: string` — 1–128 bytes; must match a name passed to `Kora.events.push` on the server.
- `handler: fun(...: any)` — Called with whatever arguments the server sent, run under `pcall`. Errors are logged with the push name.

#### Example
Server:
```lua
Kora.events.push(src, 'inventory:itemUsed', 'water_bottle')
```

Client:
```lua
Kora.events.onPush('inventory:itemUsed', function(itemName)
    print(('used %s'):format(itemName))
end)
```

#### Notes
- `handler` runs under `pcall` — an error inside it is isolated and won't stop other registered pushes from dispatching.
- Prefer this over a module-owned `RegisterNetEvent`/`TriggerClientEvent` pair so all networked events in the library share one set of gateway names.

### `Kora.events.assertName(name)` — either realm
Validates an event name (a 1–128-byte string), raising an assertion error otherwise. Used internally by every function above; exported like every other `Kora.*` function, so a consumer can pre-validate a name before registering.

### `Kora.events.unregister(name)` — server
Removes the caller's handler registered with `Kora.events.register` and returns whether it was removed.

### `Kora.events.offPush(name)` — client
Removes the caller's handler registered with `Kora.events.onPush` and returns whether it was removed.

#### Behavior (both)
Most callers don't need these directly: a registered handler is automatically removed when the resource that registered it stops (`onResourceStop`/`onClientResourceStop`, matching realm). Call them explicitly if a resource wants to stop listening for a specific name without restarting.
Another resource's name returns `false` and remains registered.
