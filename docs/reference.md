---
title: API index
sidebar_position: 13
---

# API index

Every public kora_lib namespace has a reference page under `docs/reference/`. Each page is derived from the guide kept beside the implementation (`modules/<name>/docs.md` or `local/<name>/docs.md`); see [Documentation upkeep](./contributing.md). The "Published path" column is the path the pages had on the former Jekyll site, kept so the repository smoke test (`test/smoke/api_contract.lua`) can still verify that every module is indexed.

## Core

| Page | Published path | Summary |
| --- | --- | --- |
| [Cache module](./reference/cache.md) | `/reference/cache/` | Local-player state cache and change subscriptions |
| [Configuration](./reference/config.md) | `/reference/config/` | Typed, owner-editable resource settings (Kora.config) |
| [Callback module](./reference/callback.md) | `/reference/callback/` | Promise-based client/server request and response |
| [Events module](./reference/events.md) | `/reference/events/` | Named client/server events with session correlation and rate limits |
| [Lookup module](./reference/lookup.md) | `/reference/lookup/` | GTA hash-to-name lookup for vehicles, peds, objects, weapons |
| [Locales](./reference/locales.md) | `/reference/locales/` | Language selection, lookup and interpolation (Kora.lang) |
| [Resources module](./reference/resources.md) | `/reference/resources/` | Owner tracking and automatic cleanup registries |
| [State module](./reference/state.md) | `/reference/state/` | State-bag and GlobalState waiting and subscriptions |
| [Streaming module](./reference/stream.md) | `/reference/stream/` | Models, animation dictionaries, effects, textures, audio and collision loading |

## Interface and player input

| Page | Published path | Summary |
| --- | --- | --- |
| [Controls](./reference/controls.md) | `/reference/controls/` | Reference-counted control-disable leases |
| [Instructional buttons](./reference/instructional.md) | `/reference/instructional/` | Native instructional-button overlay |
| [Interact module](./reference/interact.md) | `/reference/interact/` | Game-input option selector for zones |
| [Keybind module](./reference/keybind.md) | `/reference/keybind/` | Rebindable press/release key mappings |
| [Minigames](./reference/minigames.md) | `/reference/minigames/` | Server-validated skill-check minigames |
| [NUI module](./reference/nui.md) | `/reference/nui/` | Lua bridge to the React NUI: menus, dialogs, apps, requests |
| [Notify module](./reference/notify.md) | `/reference/notify/` | Toast notifications |
| [Progress bar module](./reference/progressbar.md) | `/reference/progressbar/` | Timed progress bar with animation, props and control disabling |
| [Text UI module](./reference/textui.md) | `/reference/textui/` | Focus-free prompt overlay |
| [Theme compatibility module](./reference/theme.md) | `/reference/theme/` | Forwarder to the kora_theme palette API |

## World and entities

| Page | Published path | Summary |
| --- | --- | --- |
| [Animations](./reference/anim.md) | `/reference/anim/` | Owner-tracked animations and attached props |
| [Blips module](./reference/blips.md) | `/reference/blips/` | Client map blips, categories and the blips settings app |
| [Camera overlay](./reference/camera.md) | `/reference/camera/` | Scripted cameras and camera HUD |
| [Closest-entity helpers](./reference/closest.md) | `/reference/closest/` | Closest ped/vehicle/object helpers |
| [Kora.distance](./reference/distancecheck.md) | `/reference/distancecheck/` | Radius and distance checks |
| [Drawing module](./reference/drawing.md) | `/reference/drawing/` | 3D text drawing |
| [Developer editors](./reference/editor.md) | `/reference/editor/` | Developer zone-creator and placement commands |
| [Entities module](./reference/entities.md) | `/reference/entities/` | Local ped/object/vehicle spawning with scoped streaming |
| [Effects module](./reference/fx.md) | `/reference/fx/` | Particle and screen effects |
| [Freecam](./reference/freecam.md) | `/reference/freecam/` | Owner-bound scripted free camera |
| [Entity placement module](./reference/placement.md) | `/reference/placement/` | In-world entity placement tool |
| [Raycast module](./reference/raycast.md) | `/reference/raycast/` | World-geometry raycasts |
| [Sound module](./reference/sound.md) | `/reference/sound/` | Managed sound playback |
| [Teleport module](./reference/teleport.md) | `/reference/teleport/` | Entity and player teleporting with fade |
| [Vehicle module](./reference/vehicle.md) | `/reference/vehicle/` | Client vehicle helpers |
| [Visual effects](./reference/visuals.md) | `/reference/visuals/` | Screen and drug-effect conveniences |
| [World module](./reference/world.md) | `/reference/world/` | Live entity-pool queries |
| [Zones module](./reference/zones.md) | `/reference/zones/` | Box, sphere, circle and poly zones and the zone creator |

## Gameplay and server systems

| Page | Published path | Summary |
| --- | --- | --- |
| [Actions module](./reference/actions.md) | `/reference/actions/` | Server-authorized action flow with progress and proofs |
| [Commands module](./reference/commands.md) | `/reference/commands/` | Owner-tracked chat commands with permission gating |
| [Discord module](./reference/discord.md) | `/reference/discord/` | Webhooks, REST bot and role directory |
| [Logging module](./reference/logging.md) | `/reference/logging/` | In-memory event log with webhook mirror |
| [Permissions module](./reference/permissions.md) | `/reference/permissions/` | ACE and Discord-role permission gateway |
| [QA module](./reference/qa.md) | `/reference/qa/` | Hooks for the kora_qa test runner |
| [Rewards module](./reference/rewards.md) | `/reference/rewards/` | Weighted reward-pool rolls |
| [Screenshot](./reference/screenshot.md) | `/reference/screenshot/` | Game-view screenshot capture and upload |
| [Skills bridge](./reference/skills.md) | `/reference/skills/` | Optional bridge to kora_skills |
| [Status effects module](./reference/status.md) | `/reference/status/` | Shared status-effect definitions and application |

## Utilities and compatibility

| Page | Published path | Summary |
| --- | --- | --- |
| [Loops module](./reference/loops.md) | `/reference/loops/` | Bounded polling and retry helpers |
| [Print helpers](./reference/prints.md) | `/reference/prints/` | Structured colored console output |
| [Random module](./reference/random.md) | `/reference/random/` | Random selection helpers |
| [Require](./reference/require.md) | `/reference/require/` | Consumer-side Kora.require module loader |
| [Timers module](./reference/timers.md) | `/reference/timers/` | Owner-tracked intervals, timeouts and rate shapers |
| [Utility module](./reference/util.md) | `/reference/util/` | Small shared helpers |
| [ox_lib provider bridge](./reference/ox.md) | `/reference/ox/` | Internal provider behind the optional ox_lib resource |

The `ox` provider is primarily an implementation contract for the separate compatibility resource. Most consumers should start with the [ox_lib migration guide](./migration/ox-lib.md).
