---
title: Events and callbacks
sidebar_position: 9
---

# Events and callbacks

This page lists the event names and server callbacks kora_lib registers itself. Use [`Kora.events`](./api/events.md) and [`Kora.callback`](./api/callback.md) for your own resources. Names are public for debugging but are internal protocol: do not trigger them directly, and never treat knowing a name or token as authorization.

## Infrastructure

| Event | Direction | Purpose |
| --- | --- | --- |
| `kora_lib:events:invoke`, `kora_lib:events:handshake`, `kora_lib:events:handshake:response`, `kora_lib:events:push` | client and server | Transport for `Kora.events` (session token handshake, calls and pushes). |
| `kora_lib:callback:clientInvoke`, `kora_lib:callback:clientResponse` | client and server | Transport for server-to-client callbacks. |
| `kora_lib:server:updated` / `kora_lib:client:updated` | local, each realm | Fired when kora_lib finishes loading so consumers can reload stateless helper modules. |
| `kora_lib:client:localeChanged` | client local | Fired when the language changes. |
| `kora_lib:notify:send` | local client / server to client | Fired by `Kora.notify` when `Config.third_party_notify` is `true`. |

## Configuration editor

`kora_lib:server:configRequested` (client to server), `kora_lib:client:configSnapshot`, `kora_lib:client:configUpdated`, `kora_lib:client:configOpened`, and the local server event `kora_lib:server:configChanged`.

## Other modules

| Event | Module | Purpose |
| --- | --- | --- |
| `kora_lib:editor:startZoneCreator`, `kora_lib:editor:startPlacement` | editor | Server tells the client to start a tool. |
| `kora_lib:commands:keybind:add`, `:remove`, `:sync`, `:execute` | commands | Keybind bookkeeping for `Kora.commands`. |
| `kora_lib:server:screenshotCaptured`, `:screenshotFailed`, `:screenshotProgressed`, `kora_lib:client:screenshotRequested` | screenshot | Screenshot request and result transport. |
| `kora_lib:lookup:syncBatch` | lookup | Server pushes lookup data batches to clients. |
| `kora_lib:status:apply`, `kora_lib:status:remove` | status | Server pushes status effects to a client. |
| `kora_lib:qa:client` | qa | kora_qa hook transport. |
| `kora_lib:blips:changed`, `kora_lib:blips:toggleCategory` | blips | Blip settings changes. |

## Server callbacks

Registered through `Kora.callback.register`, with rate limits: `kora_lib:minigames:start`, `kora_lib:minigames:submit`, `kora_lib:minigames:cancel`, `kora_lib:blips:isAdmin`, and the configuration editor callbacks `kora_lib:config`, `kora_lib:configCatalog`, `kora_lib:configRead`, `kora_lib:configCommit`, `kora_lib:configReset`, `kora_lib:configRestart`, `kora_lib:config:advanced`.

## Legacy events handled

For compatibility, kora_lib registers `qb-menu:client:openMenu`, `qb-menu:client:closeMenu`, `qb-radialmenu:client:AddOption`, `qb-radialmenu:client:RemoveOption`, and the `progressbar:client:*` events. See [Legacy compatibility](./legacy-compat.md). The qb-radialmenu bridge also registers internal events under `kora_lib:radialmenuCompat:client:`.

## NUI callbacks

`kora_lib:nui:response`, `kora_lib:nui:event`, `kora_lib:nui:theme`, `kora_lib:app:action`, `kora_lib:app:change`, `kora_lib:app:hold`, `kora_lib:form:position`, `kora_lib:dispatchfeed:ready`, `kora_lib:oxLocale`. See [User interface](./ui.md).
