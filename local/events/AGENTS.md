# events module guide

## Purpose
This module provides token-correlated networked events for calling server-side
logic from the client, plus a server→client push gateway so modules do not each
need their own dedicated `RegisterNetEvent`/`TriggerClientEvent` pair. The
token is protocol correlation, not authorization: a modified client can
complete its own handshake, so every valuable handler must validate
client-controlled input and server-side state.

Promise-based request/response (callbacks) live in their own module — see `local/callback/`.

## Public API
- `Kora.events.register(name, handler)` (server)
  - Registers `handler(src, ...)` to run when the client calls `Kora.events.trigger(name, ...)`.
  - `src` is the triggering player's real server ID; extra arguments are forwarded from the client.
- `Kora.events.trigger(name, ...)` (client)
  - Triggers the handler registered under `name` on the server, attaching the local player's session token.
  - Waits up to 10 seconds for the initial handshake token if it hasn't arrived yet.
  - Returns `true`, or `false, error` if the handshake never completed.
- `Kora.events.push(target, name, ...)` (server)
  - Sends `name` and any extra arguments to a positive finite `target` server ID's `Kora.events.onPush(name, ...)` handler, or every connected player if `target` is `-1`.
  - Not token-gated — the server is always the trusted party for its own `TriggerClientEvent` calls, same as any other server→client event.
- `Kora.events.onPush(name, handler)` (client)
  - Registers `handler(...)` to run when the server calls `Kora.events.push(target, name, ...)` for this client.
  - `handler` runs under `pcall`, so an error inside it can't break the dispatch of other pushes.
- `Kora.events.unregister(name)` (server) / `Kora.events.offPush(name)` (client)
  - Removes the caller's previously registered handler and returns whether it was removed. Rarely needed directly — see resource-scoped cleanup below.
- `Kora.events.assertName(name)` (shared)
  - Name validation (non-empty string, raises otherwise). Used internally, but exported like every `Kora.*` function.

## Implementation notes
- A single fixed gateway event (`kora_lib:events:invoke`) is used for every registered fire-and-forget action; `name` is dispatched to the right handler server-side via an internal registry, so no per-action `RegisterNetEvent` is created.
- The push direction mirrors this with its own fixed gateway (`kora_lib:events:push`); the server dispatches by `name` into a client-side registry populated by `Kora.events.onPush`, instead of registering a `RegisterNetEvent` per pushed action.
- Each connecting client exchanges a handshake (`kora_lib:events:handshake` / `kora_lib:events:handshake:response`) to receive a random per-player token. It filters malformed and out-of-session protocol traffic, but does not authenticate a client because that client can request its own token.
- The gateway handler drops any request whose token doesn't match the triggering player's stored token, or whose `token`/`name` aren't the expected type — invalid input is discarded silently, never asserted, because the payload comes from an untrusted client and must not be able to crash the resource.
- Tokens are cleared on `playerDropped`. A `kora_lib` resource restart clears all tokens; players who stay connected through that restart won't have a valid token again until they re-trigger the handshake (e.g. by reconnecting).
- `Kora.events.trigger` uses an internal `awaitToken()` helper that reuses `Kora.loops.controlled` from the loops module (`modules/loops/`) to wait for the handshake instead of hand-rolling a poll loop. `local/callback/` has its own independent handshake/token pair (same technique, separate state) rather than sharing this module's — see that module's `AGENTS.md` for why.
- **One name, one handler — with a warning on cross-resource collisions.** Both registries are single-slot (`registry[name] = handler`), so a second registration replaces the first; `Kora.resources.registry`/`serverRegistry`'s `track()` moves ownership to match rather than leaving a stale entry under the old owner. Since a cross-resource overwrite is almost always a namespacing mistake rather than intent, `register`/`onPush` print a warning naming both resources when the incoming owner (checked via the registry's `owner()`) differs from the recorded one. Re-registering your own name (i.e. a resource restart) is normal and stays silent. `local/callback`'s two registries do the same.
- **Resource-scoped cleanup** is delegated to `Kora.resources.registry`(client)/`serverRegistry`(server) (`local/resources`) rather than hand-rolled here. Both `Kora.events.register` and `Kora.events.onPush` capture `GetInvokingResource() or GetCurrentResourceName()` at registration time (same reasoning as `modules/zones`/`modules/entities`) and track the event/push name against it; the registry's own sweep removes every handler owned by a resource that stops — a registered handler shouldn't keep firing after its owning resource is gone. `local/callback/`'s two registries work the identical way, for the identical reason.

## Best practices
- Treat all arguments received in a registered handler as untrusted client input — validate them the same way you would a normal `RegisterNetEvent` payload.
- Keep registered handler names namespaced/descriptive to avoid collisions in the shared registry (e.g. `inventory:useItem`, not `use`).
- Don't rely on this as the sole security control for high-value actions — combine with server-side game-state checks (distance, ownership, cooldowns, etc.) same as any other net event.
- Need a response back (not just fire-and-forget)? Use `Kora.callback.register`/`Kora.callback.trigger` from `local/callback/` instead.
