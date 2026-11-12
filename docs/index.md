---
title: kora_lib documentation
sidebar_position: 1
---

# kora_lib

kora_lib is the shared utility layer for the Kora resource set. It provides a typed `Kora` API for interface components, world interaction, entities, streaming, callbacks, permissions, configuration, and the other foundations most resources need. See `version` in `fxmanifest.lua` for the release version.

## What you get

- **One consistent API.** Consumer resources load `@kora_lib/init.lua` and call namespaced helpers such as `Kora.notify.send`, `Kora.zones.sphere`, and `Kora.callback.trigger`.
- **Client, server, and shared modules.** Every reference page labels the realm where an operation is available.
- **Resource ownership.** Long-lived registrations are associated with the resource that created them and cleaned up when it stops.
- **Typed contracts.** `types.lua` describes functions, options, handles, callbacks, and return values for Lua language servers.
- **Headless interface components.** Menus, prompts, notifications, progress bars, apps, and minigames use kora_lib's shared NUI without holding focus while idle.
- **Migration bridges.** kora_lib provides `qb-menu`, `qb-input`, `progressbar`, `qb-radialmenu`, `qb-minigames`, and `screenshot-basic` identities, and documents its ox_lib compatibility boundary.

## Pages

| Page | Contents |
| --- | --- |
| [Installation](./installation.md) | Install order, adding the proxy to a resource, verification. |
| [Using the API](./using-the-api.md) | Namespaces, realms, results, ownership, security boundary. |
| [Configuration](./configuration.md) | `config.lua`, `server/config.lua` and convars. |
| [Commands and key mappings](./commands.md) | Commands and default keys registered by kora_lib. |
| [Permissions and ACE](./permissions.md) | ACEs for the editor commands and configuration editor. |
| [Events and callbacks](./events.md) | Event, callback and NUI callback names kora_lib registers. |
| [Exports](./exports.md) | How exports are generated and which are provided. |
| [Database](./database.md) | Optional Discord role directory tables. |
| [Dependencies and compatibility](./dependencies.md) | Required and optional resources. |
| [User interface](./ui.md) | The headless NUI app. |
| [Performance and lifecycle](./performance.md) | Cost model and cleanup rules. |
| [API index](./reference.md) | One reference page per `Kora` module. |
| [Legacy compatibility](./legacy-compat.md) | qb-menu, qb-input, progressbar, qb-radialmenu, qb-minigames, screenshot-basic, PolyZone. |
| [ox_lib compatibility](./migration/ox-lib.md) | The optional ox_lib 3.39.0 compatibility resource. |
| [ox_lib contract inventory](./migration/ox-lib-contract.md) | Detailed upstream contract inventory. |
| [Troubleshooting](./troubleshooting.md) | Common problems and fixes. |
| [Documentation upkeep](./contributing.md) | How these pages are maintained. |

## Start with the job

| If you need to... | Start here |
| --- | --- |
| Let a player interact with a location or entity | [Interactions](./reference/interact.md), [zones](./reference/zones.md), [text UI](./reference/textui.md) |
| Show feedback or collect input | [Notifications](./reference/notify.md), [progress bars](./reference/progressbar.md), [NUI](./reference/nui.md), [minigames](./reference/minigames.md) |
| Find, spawn, or move something in the world | [World queries](./reference/world.md), [entities](./reference/entities.md), [vehicles](./reference/vehicle.md), [teleporting](./reference/teleport.md) |
| Exchange client and server data safely | [Callbacks](./reference/callback.md), [events](./reference/events.md), [state bags](./reference/state.md), [permissions](./reference/permissions.md) |
| Give resource owners editable settings | [Config](./reference/config.md) |
| Build a server-authoritative flow | [Actions](./reference/actions.md), [rewards](./reference/rewards.md), [skills](./reference/skills.md), [status effects](./reference/status.md) |

## Quick example

```lua
dependency 'kora_lib'
shared_script '@kora_lib/init.lua'
```

```lua
-- client.lua
Kora.notify.send({
    title = 'Vehicle stored',
    message = 'Your vehicle is now in the garage.',
    type = 'success',
})
```
