---
title: "QA module"
sidebar_position: 43
---

# QA module

## Overview
Hooks for the `kora_qa` in-game test runner. Resources call `Kora.qa.mark` at
meaningful points (`fishing:caught`, `shop:purchase`) so Gherkin scenarios can
observe them (`When the "fishing:caught" mark fires`). kora_qa also sees, with
no instrumentation, the notifications, AppShell/menu opens, server callbacks
and `Kora.commands` commands of a player who is running a scenario.

Everything is a no-op unless kora_qa is started **and** the player has an
active run: each wrapper tests one boolean first, so leaving marks in
production code is free.

## API

### `Kora.qa.mark(name, data?)` -- client
### `Kora.qa.mark(name, data?, target?)` -- server
Records a named point in the active run. `name` is 1-64 characters of
`[A-Za-z0-9_:.-/ ]`; `data` is an optional small table (sanitised: at most 4
levels, 32 keys per table, 512-byte strings; functions and userdata dropped).
Client marks are forwarded to the server with the player's source. On the
server, `target` (player id) attaches the mark to that player's run; without
it, the mark goes to every active run.

```lua
Kora.qa.mark('fishing:caught', { fish = fishName, weight = weight })      -- client
Kora.qa.mark('shop:purchase', { item = item, price = price }, source)     -- server
```

### `Kora.qa.active(src?)`
Client: whether the local player has an active run. Server: whether `src` has
an active run, or with no argument whether anybody does.

### `Kora.qa.onEvent(fn)` / `Kora.qa.offEvent(id)`
Used by kora_qa. Registers a handler for every QA event in this realm and
returns its id; removed automatically when the registering resource stops.
Server handlers receive `(src|nil, event)`, client handlers `(event)`, where
`event = { type, name?, data?, side }` and `type` is one of `mark`, `notify`,
`nui`, `callback`, `command`, `error`, `progress`, `textui`.

### `Kora.qa.setActive(state)` -- client / `Kora.qa.setActive(src, state)` -- server
Used by kora_qa only (other callers raise). Turns event forwarding on or off
for a player. Run state is cleared when kora_qa stops or the player drops.

## What is observed while a player is active
| event | where | how |
|---|---|---|
| `notify` | client | wraps `Kora.nui.send('notify', …)` (covers client and server-pushed notifications) and the `kora_lib:notify:send` third-party event |
| `progress` | client | `Kora.nui.send('progressStart')` (name `start`, data `{ label, duration }`) and `progressCancel` (name `cancel`) from `Kora.progressbar` |
| `textui` | client | `Kora.nui.send('textui:set', …)` from `Kora.textui` (data `{ text, key }`) |
| `nui` | client | wraps `Kora.nui.openApp` (name = app id), `openMenu`/`openInputDialog` (name = title), `openContextMenu`, `openRadialMenu` |
| `callback` | server | wraps handlers registered with `Kora.callback.register` after this module loaded; data = `{ ok, returned, value?, okField?, error? }` |
| `command` | server | wraps handlers registered with `Kora.commands.add`; name = command, data = `{ raw }` |
| `mark` | both | `Kora.qa.mark` |

The wrappers replace those table entries when kora_lib loads (before
`build/finalise.lua` publishes exports), so cross-resource callers go through
them too. Callbacks/commands registered by kora_lib modules that load before
`modules/qa` are not wrapped.

## Notes
- Client events reach the server through one net event that accepts only
  players kora_qa marked active, at most 25 events per second per player.
- Internal helpers live on `Kora.compat.qa`, which is never exported.
