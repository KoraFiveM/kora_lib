# Callback module

## Overview
The callback module gives you promise-based request/response calls in both directions: a client asking the server for something (`QB.callback.register` on the server, `QB.callback.trigger` on the client), and the server asking a specific client for something (`QB.callback.register` on the client, `QB.callback.trigger` on the server). It's the promise-returning counterpart to `QB.events.register`/`trigger` in `local/events/`, which is fire-and-forget.

## API

### Client asks server

#### `QB.callback.register(name, handler, opts?)` — server
Registers `handler` to run when a client calls `QB.callback.trigger(name, ...)`.

##### Parameters
- `name: string` — Logical callback name (1–128 bytes).
- `handler: fun(src: integer, ...: any): any` — Called with the triggering player's server ID, followed by whatever arguments the client sent. Every value it returns resolves the client's promise — a handler can `return false, 'reason'` and the caller gets both values back.
- `opts.rateLimit: { max: 1–10000 integer, window: 1–86400000 integer } | false | nil`
  — optional per-player, per-callback sliding window in milliseconds.
  Omitted/`false` remains unlimited. This option only applies to server
  registrations that receive client requests.

Token and callback resolution happen before quota is consumed. An
over-limit request receives an immediate failed response containing its retry
delay instead of waiting for the ordinary callback timeout. Buckets are cleared
on player drop, unregister/replacement/ownership cleanup, and window expiry.
Each active bucket retains at most its configured `max` timestamps, so
long-lived callback traffic does not accumulate rate-limit storage.

#### `QB.callback.trigger(name, ...)` — client
Triggers the callback registered under `name` on the server.

##### Parameters
- `name: string` — 1–128 bytes; must match a name passed to `QB.callback.register` on the server.
- `...: any` — Forwarded to the server-side handler after `src`.

##### Returns
- Every value the handler returned, once it answers — in full, not just the first. No values (an empty return) if the handshake never completed, the request timed out (`Config.callback.timeout` (10s by default) with no response), or the handler itself errored — check qblib's own console for which, since that detail doesn't cross the exports boundary. Must run inside a coroutine (`CreateThread`, a command handler, ...), since this suspends until the answer arrives.

##### Example
Server:
```lua
QB.callback.register('inventory:removeItem', function(src, itemName)
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
    local ok, reason = QB.callback.trigger('inventory:removeItem', 'water_bottle')
    if not ok then return print('removeItem failed:', reason) end

    print('item removed')
end)
```

### Server asks client

#### `QB.callback.register(name, handler)` — client
Registers `handler` to run when the server calls `QB.callback.trigger(target, name, ...)` for this client.

##### Parameters
- `name: string` — Logical callback name (1–128 bytes).
- `handler: fun(...: any): any` — Called with whatever arguments the server sent. Every value it returns resolves the server's promise.

#### `QB.callback.trigger(target, name, ...)` — server
Triggers the callback registered under `name` on a specific client.

##### Parameters
- `target: positive finite integer` — Server ID of the player to ask.
- `name: string` — 1–128 bytes; must match a name passed to `QB.callback.register` on the client.
- `...: any` — Forwarded to the client-side handler.

##### Returns
- Every value the client handler returned, once it answers — in full, not just the first. No values if the request times out (`Config.callback.timeout` (10s by default) with no response) or the handler errored — check qblib's own console for which. Must run inside a coroutine (`CreateThread`, a command handler, ...), since this suspends until the answer arrives.

##### Example
Client:
```lua
QB.callback.register('confirm:action', function(prompt)
    return lib.alertDialog({ header = prompt }) == 'confirm'
end)
```

Server:
```lua
CreateThread(function()
    local confirmed = QB.callback.trigger(src, 'confirm:action', 'Accept the trade?')
    if confirmed then
        -- proceed
    end
end)
```

### `QB.callback.assertName(name)` — either realm
Validates a callback name (a 1–128-byte string), raising an assertion error otherwise. Used internally by `register`/`trigger`/`unregister`; exported like every other `QB.*` function, so a consumer can pre-validate a name before registering.

Both transport directions discard malformed callback IDs and names before a
registry lookup or error response. This keeps an oversized name from being
reflected across the network.

### `QB.callback.unregister(name)` — either realm
Unregisters a handler previously registered with `QB.callback.register` on that same realm.

##### Parameters
- `name: string`

#### Behavior
Most callers don't need this: a registered callback is automatically unregistered when the resource that registered it stops (`onResourceStop`/`onClientResourceStop`, matching realm). Call it explicitly if a resource wants to stop answering a specific callback without restarting.

Only the registering resource can unregister its callback. Returns `true` after
removing its own name and `false` when the name belongs to another resource.

## Notes
- `QB.callback.trigger`, called the normal way (from your own resource, like any other `QB.*` function), already `Citizen.Await`s the answer internally and hands you back the handler's own return values, in full, as real multiple return values — `local ok, reason = QB.callback.trigger(...)` works exactly like calling the handler directly. A failure (timeout, dropped handshake, handler error) comes back as no values at all (everything you assign reads as `nil`) rather than a promise you'd `pcall`/`Citizen.Await` yourself, since a rejected promise doesn't survive being handed back across the exports boundary any better than a resolved one would. (If you're calling this from **within qblib itself**, another module in this same resource, you still get the raw promise back and still need your own `Citizen.Await` — the auto-await/multi-value forwarding only kicks in for a genuine cross-resource caller, which is what every consumer resource always is. That raw promise resolves with only the handler's FIRST return value, same as it always has — if you need every value from a same-VM context too, read `p.qblibCallbackResults` after awaiting, a `table.pack`'d `{n = count, ...}` envelope.)
- The client→server direction uses a per-player session token (its own handshake, separate from `local/events/`'s). This is protocol correlation, not authorization: a modified client can request its own token. The server→client direction needs no token — the server is always the trusted party for its own `TriggerClientEvent` calls — but a client's response is only accepted from the player it was actually addressed to. Malformed response IDs are discarded before they reach the pending-request table.
- Both callback gateways reject malformed request IDs (non-integers, non-positive values, NaN, and infinities) before they index internal pending-request state. This keeps malformed client payloads from turning into Lua table-key faults.
- Client-originated callback handshakes and invocations also require a positive finite integer `source` before they access token state.
- Client-side callback dispatch rejects malformed handshake tokens, request IDs,
  and names before it looks up local pending/registered state.
- One handler per name per realm: registering a name another resource already claimed replaces it and logs a warning naming both resources. Namespace your names (`inventory:hasItem`, not `check`). Re-registering your own name — what happens on a resource restart — is normal and silent.
- The client-side and server-side callback registries are independent — a client `QB.callback.register('foo', ...)` and a server `QB.callback.register('foo', ...)` don't collide, since they only ever answer requests coming from the other side.
- A handler can return more than one value — all of them are sent back to the caller, in order. Only genuine Lua errors (an uncaught `error(...)` inside the handler) reject the promise instead; a deliberate `return false, "reason"` is just the handler's own return values like any other.
- A callback handler must validate every client-controlled argument plus the
  relevant server-side permission, ownership, distance, cooldown, and current
  state before changing anything valuable.
- A registered handler is torn down automatically if its owning resource stops, so a stopped/restarting resource can't keep answering requests with a stale handler.
