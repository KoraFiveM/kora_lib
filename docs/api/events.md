---
title: "Events"
sidebar_position: 4
---


# Events

## Client

Lets client code call server-side logic through one named, rate-limitable gateway instead of every resource hand-rolling a network event, and lets the server push named messages back to clients. Fire-and-forget; for a request that returns an answer, use `Kora.callback`.

Namespace: `Kora.events` · Source: `local/events/client.lua`

### Prefer this over your own net events

Use `onPush` rather than a module-owned `RegisterNetEvent`/`TriggerClientEvent` pair, so all networked events in the library share one set of gateway names. A push handler runs under `pcall`, so an error inside it is isolated and does not stop other registered pushes from dispatching.

### One handler per name

Registering a name another resource already claimed replaces it and logs a warning naming both resources. Namespace your names (`inventory:useItem`, not `use`). Re-registering your own name (a resource restart) is normal and silent.

### Functions

Use `trigger` to call a server handler and `onPush` to receive named pushes from the server.

#### `Kora.events.trigger(name, ...)`

Triggers the handler registered under `name` on the server. Fire-and-forget: no answer comes back.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Event name; must match a name passed to `Kora.events.register` on the server (1–128 bytes). |
| `...` | any | Forwarded to the server-side handler after `src`. |

**Returns**

- **ok** — `true` if the request was sent.
- **reason** — set when the handshake token never arrived (waited 10 seconds), explaining why nothing was sent.

**Example**

```lua
local ok, err = Kora.events.trigger('inventory:useItem', 'water_bottle')
if not ok then
    print('failed to trigger event:', err)
end
```

**Representative console output**

```text
`ok` is `true` once the request is sent. If the handshake token never arrives, `ok` is `false` and `err` explains why. Need an answer back? Use `Kora.callback.trigger`.
```

#### `Kora.events.onPush(name, handler)`

Registers `handler` to run when the server calls `Kora.events.push(target, name, ...)` for this client.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Push name; must match a name passed to `Kora.events.push` on the server (1–128 bytes). |
| `handler` | fun(...: any) | Called with whatever arguments the server sent, run under `pcall` so an error inside it is logged with the push name and does not stop other pushes. |

**Returns**

- **No return value.**

**Example**

```lua
Kora.events.onPush('inventory:itemUsed', function(itemName)
    print(('used %s'):format(itemName))
end)
```

**Representative console output**

```text
Prints `used water_bottle` when the server calls `Kora.events.push(src, 'inventory:itemUsed', 'water_bottle')`.
```

#### `Kora.events.offPush(name)`

Removes a push handler this resource registered with `Kora.events.onPush`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Push name (1–128 bytes). |

**Returns**

- **removed** — whether the handler was removed; another resource's name returns `false` and stays registered.

**Example**

```lua
local removed = Kora.events.offPush('inventory:itemUsed')
```

**Representative console output**

```text
Rarely needed: a registered handler is removed automatically when the resource that registered it stops.
```

#### `Kora.events.assertName(name)`

Validates an event name so you can check it before registering.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | The name to validate. |

**Returns**

- **No return value; raises an assertion error when `name` is not a 1–128-byte string.**

**Example**

```lua
Kora.events.assertName('inventory:useItem')
```

**Representative console output**

```text
Returns normally for a valid name and raises an assertion error for anything else.
```

### Limits and related APIs

Client receivers ignore malformed handshake tokens and non-string push names before touching their local registries. Names are 1–128 bytes.

## Server

Lets client code call server-side logic through one named, rate-limitable gateway instead of every resource hand-rolling a network event, and lets the server push named messages to clients. Each player gets a per-session token that correlates a request with the source that completed the handshake. Fire-and-forget; for a request that returns an answer, use `Kora.callback`.

Namespace: `Kora.events` · Source: `local/events/server.lua`

### How a request is accepted

A request only reaches your handler if the triggering client's session token matches the one the server stored for that player. Anything else (no token, wrong token, wrong types) is dropped without running the handler or raising an error. Token and handler resolution happen before rate quota is consumed, and over-limit events are silently dropped. Rate buckets are cleared on player drop, unregister, replacement, ownership cleanup and window expiry, and each bucket keeps at most `max` timestamps.

### One handler per name

Registering a name another resource already claimed replaces it and logs a warning naming both resources. Namespace your names (`inventory:useItem`, not `use`). Re-registering your own name (a resource restart) is normal and silent. Handlers are removed automatically when their resource stops.

### Functions

Use `register` to answer client triggers and `push` to send a named message to one client or all of them.

#### `Kora.events.register(name, handler, opts?)`

Registers `handler` to run when a client calls `Kora.events.trigger(name, ...)`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Action name (1–128 bytes). |
| `handler` | fun(src: integer, ...: any) | Called with the triggering player's server id, followed by the arguments the client sent. |
| `opts.rateLimit?` | &#123; max: integer, window: integer &#125; \| false | Optional per-player, per-handler sliding window. `max` is 1–10000 events per `window` of 1–86400000 milliseconds. Omitted or `false` means unlimited. |

**Returns**

- **No return value.**

**Example**

```lua
Kora.events.register('inventory:useItem', function(src, itemName)
    -- src is the real player who triggered this, not client-supplied
    print(('player %d used %s'):format(src, itemName))
end)
```

**Representative console output**

```text
Prints `player 12 used water_bottle` (for player 12) each time that client triggers the event. Requests with no token, a wrong token or wrong types are dropped without running the handler, and over-limit events are silently dropped.
```

#### `Kora.events.push(target, name, ...)`

Sends a named push to one client, or to every connected client.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `target` | integer | Server id of the recipient (positive, finite), or `-1` for every connected player. |
| `name` | string | Push name (1–128 bytes). |
| `...` | any | Forwarded to the client-side handler. |

**Returns**

- **No return value.**

**Example**

```lua
Kora.events.push(src, 'inventory:itemUsed', 'water_bottle')
```

**Representative console output**

```text
The recipient's `Kora.events.onPush` handler runs with `water_bottle`. Not token-gated: the server is always the trusted party for its own client events, so this is a thin named wrapper around one shared gateway event.
```

#### `Kora.events.unregister(name)`

Removes a handler this resource registered with `Kora.events.register`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Action name (1–128 bytes). |

**Returns**

- **removed** — whether the handler was removed; another resource's name returns `false` and stays registered.

**Example**

```lua
local removed = Kora.events.unregister('inventory:useItem')
```

**Representative console output**

```text
Rarely needed: a registered handler is removed automatically when the resource that registered it stops.
```

#### `Kora.events.assertName(name)`

Validates an event name so you can check it before registering.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | The name to validate. |

**Returns**

- **No return value; raises an assertion error when `name` is not a 1–128-byte string.**

**Example**

```lua
Kora.events.assertName('inventory:useItem')
```

**Representative console output**

```text
Returns normally for a valid name and raises an assertion error for anything else.
```

### Limits and related APIs

The token is protocol correlation, not authorization: a modified client can complete its own handshake, so never treat knowledge of the token or the gateway event name (`kora_lib:events:invoke`, fixed and public) as permission to grant an item, money, progression or a privileged action. Validate player identity, permission, ownership, distance, cooldowns and current state in every valuable handler. Handshake and gateway traffic must come from a positive finite integer server id; malformed or local invocations are dropped before token state is read, and names over 128 bytes are dropped before registry lookup.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/events/docs.md` or `local/events/docs.md`) that the reference above does not state.

### API

#### `Kora.events.trigger(name, ...)` — client
Triggers the handler registered under `name` on the server.

##### Example
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

### Notes
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

### Push (server → client)

#### `Kora.events.onPush(name, handler)` — client
Registers `handler` to run when the server calls `Kora.events.push(target, name, ...)` for this client.

##### Example
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
