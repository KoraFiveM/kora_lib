# Callback module

## Overview
The callback module gives you promise-based request/response calls in both directions: a client asking the server for something (`QB.callback.register` on the server, `QB.callback.trigger` on the client), and the server asking a specific client for something (`QB.callback.register` on the client, `QB.callback.trigger` on the server). It's the promise-returning counterpart to `QB.events.register`/`trigger` in `local/events/`, which is fire-and-forget.

## API

### Client asks server

#### `QB.callback.register(name, handler)` — server
Registers `handler` to run when a client calls `QB.callback.trigger(name, ...)`.

##### Parameters
- `name: string` — Logical callback name (must be non-empty).
- `handler: fun(src: integer, ...: any): any` — Called with the triggering player's server ID, followed by whatever arguments the client sent. Its return value (only the first, if it returns more than one) resolves the client's promise.

#### `QB.callback.trigger(name, ...)` — client
Triggers the callback registered under `name` on the server.

##### Parameters
- `name: string` — Must match a name passed to `QB.callback.register` on the server.
- `...: any` — Forwarded to the server-side handler after `src`.

##### Returns
- The handler's return value, once it answers. `nil` if the handshake never completed, the request timed out (`Config.callback.timeout` (10s by default) with no response), or the handler itself errored — check qblib's own console for which, since that detail doesn't cross the exports boundary. Must run inside a coroutine (`CreateThread`, a command handler, ...), since this suspends until the answer arrives.

##### Example
Server:
```lua
QB.callback.register('inventory:hasItem', function(src, itemName)
    return Inventory.HasItem(src, itemName)
end)
```

Client:
```lua
CreateThread(function()
    local hasItem = QB.callback.trigger('inventory:hasItem', 'water_bottle')
    if hasItem == nil then return print('callback failed (see qblib\'s own console for the error)') end

    print('has item:', hasItem)
end)
```

### Server asks client

#### `QB.callback.register(name, handler)` — client
Registers `handler` to run when the server calls `QB.callback.trigger(target, name, ...)` for this client.

##### Parameters
- `name: string` — Logical callback name (must be non-empty).
- `handler: fun(...: any): any` — Called with whatever arguments the server sent. Its return value resolves the server's promise.

#### `QB.callback.trigger(target, name, ...)` — server
Triggers the callback registered under `name` on a specific client.

##### Parameters
- `target: integer` — Server ID of the player to ask.
- `name: string` — Must match a name passed to `QB.callback.register` on the client.
- `...: any` — Forwarded to the client-side handler.

##### Returns
- The client handler's return value, once it answers. `nil` if the request times out (`Config.callback.timeout` (10s by default) with no response) or the handler errored — check qblib's own console for which. Must run inside a coroutine (`CreateThread`, a command handler, ...), since this suspends until the answer arrives.

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
Validates a callback name (non-empty string), raising an assertion error otherwise. Used internally by `register`/`trigger`/`unregister`; exported like every other `QB.*` function, so a consumer can pre-validate a name before registering.

### `QB.callback.unregister(name)` — either realm
Unregisters a handler previously registered with `QB.callback.register` on that same realm.

##### Parameters
- `name: string`

#### Behavior
Most callers don't need this: a registered callback is automatically unregistered when the resource that registered it stops (`onResourceStop`/`onClientResourceStop`, matching realm). Call it explicitly if a resource wants to stop answering a specific callback without restarting.

## Notes
- `QB.callback.trigger`, called the normal way (from your own resource, like any other `QB.*` function), already `Citizen.Await`s the answer internally and hands you back the plain result — a failure (timeout, dropped handshake, handler error) comes back as `nil` rather than a promise you'd `pcall`/`Citizen.Await` yourself, since a rejected promise doesn't survive being handed back across the exports boundary any better than a resolved one would. (If you're calling this from **within qblib itself**, another module in this same resource, you still get the raw promise back and still need your own `Citizen.Await`/`pcall` — the auto-await only kicks in for a genuine cross-resource caller, which is what every consumer resource always is.)
- The client→server direction is protected by a per-player session token (its own handshake, separate from `local/events/`'s). The server→client direction needs no token — the server is always the trusted party for its own `TriggerClientEvent` calls — but a client's response is only accepted from the player it was actually addressed to.
- One handler per name per realm: registering a name another resource already claimed replaces it and logs a warning naming both resources. Namespace your names (`inventory:hasItem`, not `check`). Re-registering your own name — what happens on a resource restart — is normal and silent.
- The client-side and server-side callback registries are independent — a client `QB.callback.register('foo', ...)` and a server `QB.callback.register('foo', ...)` don't collide, since they only ever answer requests coming from the other side.
- If a handler returns more than one value, only the first is sent back — wrap multiple values in a table if you need them all.
- A registered handler is torn down automatically if its owning resource stops, so a stopped/restarting resource can't keep answering requests with a stale handler.
