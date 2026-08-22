# Events module

## Overview
The events module lets client code call server-side logic through a single, token-guarded gateway instead of a plain `RegisterNetEvent`. It's meant to stop generic exploit menus that blindly fire well-known event names, and to stop one player spoofing another player's action, without requiring every consumer to hand-roll their own token/handshake logic.

## API

### `QB.events.register(name, handler)` — server
Registers `handler` to run when a client calls `QB.events.trigger(name, ...)`.

#### Parameters
- `name: string` — Logical action name (must be non-empty).
- `handler: fun(src: integer, ...: any)` — Called with the triggering player's server ID, followed by whatever arguments the client sent.

#### Behavior
Requests are only dispatched to `handler` if the triggering client's session token (established during the handshake) matches what the server has stored for that player. Anything else — no token, wrong token, wrong types — is dropped without running `handler` or raising an error.

### `QB.events.trigger(name, ...)` — client
Triggers the handler registered under `name` on the server.

#### Parameters
- `name: string` — Must match a name passed to `QB.events.register` on the server.
- `...: any` — Forwarded to the server-side handler after `src`.

#### Returns
- `boolean` — `true` if the request was sent.
- `string | nil` — Set when the handshake token never arrived (waited 10s), explaining why nothing was sent.

#### Example
Server:
```lua
QB.events.register('inventory:useItem', function(src, itemName)
    -- src is the real player who triggered this, not client-supplied
    print(('player %d used %s'):format(src, itemName))
end)
```

Client:
```lua
local ok, err = QB.events.trigger('inventory:useItem', 'water_bottle')
if not ok then
    print('failed to trigger event:', err)
end
```

## Notes
- One handler per name: registering a name another resource already claimed replaces it and logs a warning naming both resources. Namespace your names (`inventory:useItem`, not `use`) to avoid it. Re-registering your own name — what happens on a resource restart — is normal and silent.
- Every player gets a unique token issued over a private per-source handshake when they connect — it isn't shared across players and can't be guessed from the (fixed, non-secret) gateway event name.
- The gateway event name itself (`qblib:events:invoke`) is fixed and public; the per-player token is what's checked, not the event name.
- This is a mitigation against blind/static exploits and cross-player spoofing, not a substitute for validating the actual data a handler receives.

Need a response back instead of fire-and-forget? See the `callback` module (`local/callback/`) — `QB.callback.register`/`QB.callback.trigger` work the same way but return a promise, and also support the reverse direction (server asking a client).

## Push (server → client)

### `QB.events.push(target, name, ...)` — server
Sends a named push to one client, or every connected client.

#### Parameters
- `target: integer` — Server ID of the recipient, or `-1` for every connected player.
- `name: string` — Logical push name (must be non-empty).
- `...: any` — Forwarded to the client-side handler.

#### Behavior
Not token-gated. Unlike `trigger`, there's no client identity to verify here — the server is always the trusted party for its own `TriggerClientEvent` calls, so `push` is a thin, named wrapper around one shared gateway event rather than a security control.

### `QB.events.onPush(name, handler)` — client
Registers `handler` to run when the server calls `QB.events.push(target, name, ...)` for this client.

#### Parameters
- `name: string` — Must match a name passed to `QB.events.push` on the server.
- `handler: fun(...: any)` — Called with whatever arguments the server sent, run under `pcall`.

#### Example
Server:
```lua
QB.events.push(src, 'inventory:itemUsed', 'water_bottle')
```

Client:
```lua
QB.events.onPush('inventory:itemUsed', function(itemName)
    print(('used %s'):format(itemName))
end)
```

#### Notes
- `handler` runs under `pcall` — an error inside it is isolated and won't stop other registered pushes from dispatching.
- Prefer this over a module-owned `RegisterNetEvent`/`TriggerClientEvent` pair so all networked events in the library share one set of gateway names.

### `QB.events.assertName(name)` — either realm
Validates an event name (non-empty string), raising an assertion error otherwise. Used internally by every function above; exported like every other `QB.*` function, so a consumer can pre-validate a name before registering.

### `QB.events.unregister(name)` — server
Removes a handler registered with `QB.events.register`.

### `QB.events.offPush(name)` — client
Removes a handler registered with `QB.events.onPush`.

#### Behavior (both)
Most callers don't need these directly: a registered handler is automatically removed when the resource that registered it stops (`onResourceStop`/`onClientResourceStop`, matching realm). Call them explicitly if a resource wants to stop listening for a specific name without restarting.
