---
title: "Callback"
sidebar_position: 3
---


# Callback

## Client

Promise-style request/response calls in both directions. On the client, `Kora.callback.trigger` asks the server for an answer, and `Kora.callback.register` answers requests the server sends to this player. It is the answer-returning counterpart to `Kora.events`, which is fire-and-forget.

Namespace: `Kora.callback` · Source: `local/callback/client.lua`

### Every return value comes back

Called the normal way (from your own resource), `Kora.callback.trigger` waits for the answer and hands back the handler's own return values in full, so `local ok, reason = Kora.callback.trigger(...)` works exactly like calling the handler directly, including a reason after a leading `nil`. A failure (timeout, dropped handshake, handler error) comes back as no values at all, so everything you assign reads as `nil`.

### One handler per name

The client and server registries are independent: a client `Kora.callback.register('foo', ...)` and a server `Kora.callback.register('foo', ...)` do not collide, because each only answers requests coming from the other side. Within one realm there is one handler per name; registering a name another resource already claimed replaces it and logs a warning naming both resources. Namespace your names (`inventory:hasItem`, not `check`).

### Cleaned up when the resource stops

A registered callback is removed automatically when the resource that registered it stops, so a restarting resource can never keep answering with a stale handler.

### Functions

Call these as `Kora.callback.*` from your own resource. `trigger` suspends the calling coroutine until an answer arrives, so call it inside `CreateThread`, a command handler or similar.

#### `Kora.callback.trigger(name, ...)`

Asks the server for an answer: triggers the callback registered under `name` on the server and waits for it to respond.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Callback name; must match a name passed to `Kora.callback.register` on the server (1–128 bytes). |
| `...` | any | Forwarded to the server-side handler after `src`. |

**Returns**

- **Every value the server handler returned, in full (not just the first).**
- **No values if the handshake never completed, the request timed out (`Config.callback.timeout`, 30 seconds by default) or the handler errored. Check kora_lib's own console for which.**

**Example**

```lua
CreateThread(function()
    local ok, reason = Kora.callback.trigger('inventory:removeItem', 'water_bottle')
    if not ok then return print('removeItem failed:', reason) end

    print('item removed')
end)
```

**Representative console output**

```text
Prints `item removed` when the server handler returns `true`, or `removeItem failed: you don't have that item` when it returns `false, "you don't have that item"`. Must run inside a coroutine (`CreateThread`, a command handler, …) because it suspends until the answer arrives.
```

#### `Kora.callback.register(name, handler)`

Answers requests the server sends to this client: registers `handler` to run when the server calls `Kora.callback.trigger(target, name, ...)` for this player.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Callback name (1–128 bytes). |
| `handler` | fun(...: any): any | Called with whatever arguments the server sent. Every value it returns resolves the server's request. |

**Returns**

- **No return value.**

**Example**

```lua
Kora.callback.register('confirm:action', function(prompt)
    return lib.alertDialog({ header = prompt }) == 'confirm'
end)
```

**Representative console output**

```text
A server-side `Kora.callback.trigger(src, 'confirm:action', 'Accept the trade?')` receives `true` when the player confirms and `false` otherwise.
```

#### `Kora.callback.unregister(name)`

Stops answering a callback this resource registered on the client.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Callback name (1–128 bytes). |

**Returns**

- **removed** — `true` after removing this resource's own handler, `false` when the name belongs to another resource.

**Example**

```lua
local removed = Kora.callback.unregister('confirm:action')
```

**Representative console output**

```text
Rarely needed: a registered callback is removed automatically when the resource that registered it stops. Only the registering resource can remove it.
```

#### `Kora.callback.assertName(name)`

Validates a callback name so you can check it before registering.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | The name to validate. |

**Returns**

- **No return value; raises an assertion error when `name` is not a 1–128-byte string.**

**Example**

```lua
Kora.callback.assertName('confirm:action')
```

**Representative console output**

```text
Returns normally for a valid name and raises an assertion error for anything else. Used internally by `register`, `trigger` and `unregister`.
```

#### `Kora.callback.triggerPacked(name, ...)`

Internal plumbing: makes the same request as `Kora.callback.trigger` but always waits and returns one envelope instead of multiple values.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Callback name (1–128 bytes). |
| `...` | any | Forwarded to the server-side handler. |

**Returns**

- **packed** — `{ n = count, [1] = ..., [2] = ... }` holding every value the handler returned.

**Example**

```lua
local packed = Kora.callback.triggerPacked('inventory:removeItem', 'water_bottle')
```

**Representative console output**

```text
For a handler that returns `true`, `packed` is `{ n = 1, true }`. The consumer proxy in `@kora_lib/init.lua` calls this and unpacks the envelope so a reason after a leading `nil` survives the exports boundary. Use `Kora.callback.trigger` in your own code.
```

### Limits and related APIs

Names are 1–128 bytes. Malformed handshake tokens, request ids and names are discarded before any lookup. The client-to-server direction uses a per-session token for protocol correlation only: it is not authorization, and a modified client can request its own token. See the server realm for what a handler must validate.

## Server

Promise-style request/response calls in both directions. On the server, `Kora.callback.register` answers requests clients send with `Kora.callback.trigger`, and `Kora.callback.trigger(target, ...)` asks a specific client for an answer. It is the answer-returning counterpart to `Kora.events`, which is fire-and-forget.

Namespace: `Kora.callback` · Source: `local/callback/server.lua`

### Rate limiting

`opts.rateLimit` applies only to registrations that receive client requests. Token and callback resolution happen before quota is consumed, and an over-limit request gets an immediate failed response containing its retry delay instead of waiting for the ordinary timeout. Buckets are cleared on player drop, unregister, replacement, ownership cleanup and window expiry, and each active bucket keeps at most `max` timestamps, so long-lived traffic does not accumulate storage.

### Errors and handler results

A handler can return more than one value; all of them are sent back in order. Only a genuine Lua error (an uncaught `error(...)`) rejects the request, and a deliberate `return false, "reason"` is just return values like any other. A raised error is printed to the server console with the callback name, player and full message; the client receives only the message with its leading `file.lua:123:` position removed, so internal paths are not disclosed. The token handshake is limited to 5 answers per player per minute.

### One handler per name

One handler per name per realm. Registering a name another resource already claimed replaces it and logs a warning naming both resources; re-registering your own name (a resource restart) is normal and silent. A registered handler is torn down automatically when its resource stops.

### Functions

Call these as `Kora.callback.*` from your own resource. `trigger` suspends the calling coroutine until the client answers, so call it inside `CreateThread`, a command handler or similar.

#### `Kora.callback.register(name, handler, opts?)`

Answers client requests: registers `handler` to run when a client calls `Kora.callback.trigger(name, ...)`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Callback name (1–128 bytes). |
| `handler` | fun(src: integer, ...: any): any | Called with the triggering player's server id, followed by the arguments the client sent. Every value it returns is sent back, so a handler can `return false, 'reason'` and the caller gets both. |
| `opts.rateLimit?` | &#123; max: integer, window: integer &#125; \| false | Optional per-player, per-callback sliding window. `max` is 1–10000 requests per `window` of 1–86400000 milliseconds. Omitted or `false` means unlimited. |
| `opts.replace?` | boolean | Explicitly allow replacing another resource's callback without a collision warning. |

**Returns**

- **No return value.**

**Example**

```lua
Kora.callback.register('inventory:removeItem', function(src, itemName)
    if not Inventory.HasItem(src, itemName) then
        return false, "you don't have that item"
    end

    Inventory.RemoveItem(src, itemName)
    return true
end)
```

**Representative console output**

```text
A client `Kora.callback.trigger('inventory:removeItem', 'water_bottle')` receives `true` when the item is removed, or `false, "you don't have that item"`. An over-limit request gets an immediate failed response containing its retry delay instead of waiting for the ordinary timeout.
```

#### `Kora.callback.trigger(target, name, ...)`

Asks a specific client for an answer: triggers the callback registered under `name` on that player's client and waits for it to respond.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `target` | integer | Server id of the player to ask (positive, finite). |
| `name` | string | Callback name; must match a name passed to `Kora.callback.register` on the client (1–128 bytes). |
| `...` | any | Forwarded to the client-side handler. |

**Returns**

- **Every value the client handler returned, in full.**
- **No values if the request timed out (`Config.callback.timeout`, 30 seconds by default) or the handler errored. Check kora_lib's own console for which.**

**Example**

```lua
CreateThread(function()
    local confirmed = Kora.callback.trigger(src, 'confirm:action', 'Accept the trade?')
    if confirmed then
        -- proceed
    end
end)
```

**Representative console output**

```text
`confirmed` is `true` when the player accepts, and `nil` when the request times out or the client handler errors. Must run inside a coroutine because it suspends until the answer arrives.
```

#### `Kora.callback.unregister(name)`

Stops answering a callback this resource registered on the server.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Callback name (1–128 bytes). |

**Returns**

- **removed** — `true` after removing this resource's own handler, `false` when the name belongs to another resource.

**Example**

```lua
local removed = Kora.callback.unregister('inventory:removeItem')
```

**Representative console output**

```text
Rarely needed: a registered callback is removed automatically when the resource that registered it stops. Only the registering resource can remove it.
```

#### `Kora.callback.assertName(name)`

Validates a callback name so you can check it before registering.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | The name to validate. |

**Returns**

- **No return value; raises an assertion error when `name` is not a 1–128-byte string.**

**Example**

```lua
Kora.callback.assertName('inventory:removeItem')
```

**Representative console output**

```text
Returns normally for a valid name and raises an assertion error for anything else. Used internally by `register`, `trigger` and `unregister`.
```

#### `Kora.callback.triggerPacked(target, name, ...)`

Internal plumbing: makes the same request as `Kora.callback.trigger` but always waits and returns one envelope instead of multiple values.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `target` | integer | Server id of the player to ask. |
| `name` | string | Callback name (1–128 bytes). |
| `...` | any | Forwarded to the client-side handler. |

**Returns**

- **packed** — `{ n = count, [1] = ..., [2] = ... }` holding every value the handler returned.

**Example**

```lua
local packed = Kora.callback.triggerPacked(src, 'confirm:action', 'Accept the trade?')
```

**Representative console output**

```text
For a handler that returns `true`, `packed` is `{ n = 1, true }`. The consumer proxy in `@kora_lib/init.lua` calls this and unpacks the envelope. Use `Kora.callback.trigger` in your own code.
```

### Limits and related APIs

A callback handler must validate every client-controlled argument plus the relevant server-side permission, ownership, distance, cooldown and current state before changing anything valuable. The per-session token correlates a request with the player who completed the handshake; it is not authorization. The server-to-client direction needs no token because the server is always the trusted party, but a response is only accepted from the player it was addressed to.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/callback/docs.md` or `local/callback/docs.md`) that the reference above does not state.

### API

#### Client asks server

##### `Kora.callback.register(name, handler, opts?)` — server
Registers `handler` to run when a client calls `Kora.callback.trigger(name, ...)`.

###### Parameters
- `name: string` — Logical callback name (1–128 bytes).
- `handler: fun(src: integer, ...: any): any` — Called with the triggering player's server ID, followed by whatever arguments the client sent. Every value it returns resolves the client's promise — a handler can `return false, 'reason'` and the caller gets both values back.
- `opts.rateLimit: { max: 1–10000 integer, window: 1–86400000 integer } | false | nil`
- `opts.replace: boolean` explicitly allows replacing another resource's callback without a collision warning.
  — optional per-player, per-callback sliding window in milliseconds.
  Omitted/`false` remains unlimited. This option only applies to server
  registrations that receive client requests.

Token and callback resolution happen before quota is consumed. An
over-limit request receives an immediate failed response containing its retry
delay instead of waiting for the ordinary callback timeout. Buckets are cleared
on player drop, unregister/replacement/ownership cleanup, and window expiry.
Each active bucket retains at most its configured `max` timestamps, so
long-lived callback traffic does not accumulate rate-limit storage.

##### `Kora.callback.trigger(name, ...)` — client
Triggers the callback registered under `name` on the server.

###### Example
Server:
```lua
Kora.callback.register('inventory:removeItem', function(src, itemName)
    if not Inventory.HasItem(src, itemName) then
        return false, "you don't have that item"
    end

    Inventory.RemoveItem(src, itemName)
    return true
end)
```

Client:
```lua
CreateThread(function()
    local ok, reason = Kora.callback.trigger('inventory:removeItem', 'water_bottle')
    if not ok then return print('removeItem failed:', reason) end

    print('item removed')
end)
```

Every return value reaches the caller, including a reason after a leading `nil` (`return nil, 'reason'`). Call it as `Kora.callback.trigger` (via `@kora_lib/init.lua`): a raw `exports.kora_lib:callback_trigger(...)` call is limited by FiveM's export marshalling, which drops everything after a leading `nil`.

#### Server asks client

##### `Kora.callback.trigger(target, name, ...)` — server
Triggers the callback registered under `name` on a specific client.

###### Example
Client:
```lua
Kora.callback.register('confirm:action', function(prompt)
    return lib.alertDialog({ header = prompt }) == 'confirm'
end)
```

Server:
```lua
CreateThread(function()
    local confirmed = Kora.callback.trigger(src, 'confirm:action', 'Accept the trade?')
    if confirmed then
        -- proceed
    end
end)
```

#### `Kora.callback.assertName(name)` — either realm
Validates a callback name (a 1–128-byte string), raising an assertion error otherwise. Used internally by `register`/`trigger`/`unregister`; exported like every other `Kora.*` function, so a consumer can pre-validate a name before registering.

Both transport directions discard malformed callback IDs and names before a
registry lookup or error response. This keeps an oversized name from being
reflected across the network.

#### `Kora.callback.unregister(name)` — either realm
Unregisters a handler previously registered with `Kora.callback.register` on that same realm.

##### Behavior
Most callers don't need this: a registered callback is automatically unregistered when the resource that registered it stops (`onResourceStop`/`onClientResourceStop`, matching realm). Call it explicitly if a resource wants to stop answering a specific callback without restarting.

Only the registering resource can unregister its callback. Returns `true` after
removing its own name and `false` when the name belongs to another resource.
