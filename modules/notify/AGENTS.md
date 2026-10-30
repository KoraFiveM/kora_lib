# notify module guide

## Purpose
Sends a title/message/duration notification to a player (or every connected player), rendered by the NUI's `Toast` component unless a server opts into routing it through its own third-party notify resource instead.

## Public API
- `QB.notify.send(payload)` (client) — Shows `payload` on the local player.
- `QB.notify.send(src, payload)` (server) — Pushes `payload` to `src` (or `-1` for every connected player) via `QB.events.push`, which the client answers with its own `QB.notify.send(payload)`.
- `QB.notify.sendToAll(payload)` (server) — `QB.notify.send(-1, payload)`.
- `QB.notify.assert(payload)` (shared) — Validates a payload, raising an assertion error if malformed. Used internally by `send`, but exported for callers that want to validate before sending.
- `QB.notify.withDefaults(payload)` (shared) — Returns a copy with `duration`/`type`/`position` resolved from `Config.notify`.

## Implementation notes
- **`Config.third_party_notify`**: when `true`, both realms fire `TriggerEvent`/`TriggerClientEvent('kora_lib:notify:send', payload)` instead of going through the built-in NUI path — a consumer server can register its own handler on that event to route notifications through a different notification resource without kora_lib's NUI ever getting involved.
- **Built-in path goes through `QB.nui.send("notify", payload)`** (client), not `SendNuiMessage` directly, per the root `AGENTS.md` "UI conventions" — the NUI's `Toast` component (`web/src/components/notify/Toast.tsx`) listens for the `"notify"` action.
- **Send never throws**: both `send` functions run their body inside `pcall`, so a malformed payload (caught by `QB.notify.assert`) is silently dropped rather than raising into the caller — a notification failing to validate shouldn't be able to break whatever gameplay code triggered it.
- **Server→client uses `QB.events.push`/`onPush`, not a dedicated event**: the `QB.events.onPush('notify', QB.notify.send)` registration at the bottom of this module's own `client.lua` is what turns a server-side `QB.notify.send(src, payload)` into a client-side `QB.notify.send(payload)` call — see `local/events/AGENTS.md` for the push mechanism itself.
- **Duration bounds** (`Config.notify.defaultDuration`, `Config.notify.maxDuration`) live in `Config`, checked by the shared `QB.notify.assert`.
- **Defaults are resolved Lua-side, not in the NUI** (`QB.notify.withDefaults`): `Config.notify.defaultType`/`defaultPosition`/`defaultDuration` are never transmitted, so if the browser had to apply them it would need its own copy of values a server owner can change. `send` resolves them into the payload instead, and the Toast component keeps its own hardcoded fallbacks only for the case where some other caller posts a bare payload straight to the `"notify"` action.
- **`title`/`message` are type-checked, not just presence-checked**: they're rendered as text in the NUI, and a table arriving as a React child would crash the entire NUI root (not just that toast). The Toast component independently re-checks on ingestion — defence in depth, since `QB.nui.send` can reach the action without going through `QB.notify.send` at all.
- **The third-party path forwards the raw payload**, deliberately skipping `withDefaults` — another notify resource has its own defaults and shouldn't have kora_lib's silently substituted underneath it.

## Best practices
- Prefer `sendToAll` over looping `send(playerId, ...)` yourself for server-wide announcements — it's a single `QB.events.push(-1, ...)` rather than one push per player.
- Keep `message` reasonably short — the NUI's `Toast` is a fixed-size overlay element, not a full-screen dialog.
