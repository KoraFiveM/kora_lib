---
title: API module map
sidebar_position: 16
---

# API module map

Every public kora_lib namespace has a reference page under `docs/api/` (see the [API reference](./api/index.md) for namespaces and realms). Each page combines the function reference with the guide kept beside the implementation (`modules/<name>/docs.md` or `local/<name>/docs.md`); see [Documentation upkeep](./contributing.md). The "Published path" column is the path the pages had on the former Jekyll site, kept so the repository smoke test (`test/smoke/api_contract.lua`) can still verify that every module is indexed.

## Core

| Page | Published path | Summary |
| --- | --- | --- |
| [Cache module](./api/cache.md) | `/reference/cache/` | Local-player state cache and change subscriptions |
| [Configuration](./api/config.md) | `/reference/config/` | Typed, owner-editable resource settings (Kora.config) |
| [Callback module](./api/callback.md) | `/reference/callback/` | Promise-based client/server request and response |
| [Events module](./api/events.md) | `/reference/events/` | Named client/server events with session correlation and rate limits |
| [Lookup module](./api/lookup.md) | `/reference/lookup/` | GTA hash-to-name lookup for vehicles, peds, objects, weapons |
| [Locales](./api/locales.md) | `/reference/locales/` | Language selection, lookup and interpolation (Kora.lang) |
| [Resources module](./api/resources.md) | `/reference/resources/` | Owner tracking and automatic cleanup registries |
| [State module](./api/state.md) | `/reference/state/` | State-bag and GlobalState waiting and subscriptions |
| [Streaming module](./api/stream.md) | `/reference/stream/` | Models, animation dictionaries, effects, textures, audio and collision loading |

## Interface and player input

| Page | Published path | Summary |
| --- | --- | --- |
| [Controls](./api/controls.md) | `/reference/controls/` | Reference-counted control-disable leases |
| [Instructional buttons](./api/instructional.md) | `/reference/instructional/` | Native instructional-button overlay |
| [Interact module](./api/interact.md) | `/reference/interact/` | Game-input option selector for zones |
| [Keybind module](./api/keybind.md) | `/reference/keybind/` | Rebindable press/release key mappings |
| [Minigames](./api/minigames.md) | `/reference/minigames/` | Server-validated skill-check minigames |
| [NUI module](./api/nui.md) | `/reference/nui/` | Lua bridge to the React NUI: menus, dialogs, apps, requests |
| [Notify module](./api/notify.md) | `/reference/notify/` | Toast notifications |
| [Progress bar module](./api/progressbar.md) | `/reference/progressbar/` | Timed progress bar with animation, props and control disabling |
| [Text UI module](./api/textui.md) | `/reference/textui/` | Focus-free prompt overlay |
| [Theme compatibility module](./api/theme.md) | `/reference/theme/` | Forwarder to the kora_theme palette API |

## World and entities

| Page | Published path | Summary |
| --- | --- | --- |
| [Animations](./api/anim.md) | `/reference/anim/` | Owner-tracked animations and attached props |
| [Blips module](./api/blips.md) | `/reference/blips/` | Client map blips, categories and the blips settings app |
| [Camera overlay](./api/camera.md) | `/reference/camera/` | Scripted cameras and camera HUD |
| [Closest-entity helpers](./api/closest.md) | `/reference/closest/` | Closest ped/vehicle/object helpers |
| [Kora.distance](./api/distancecheck.md) | `/reference/distancecheck/` | Radius and distance checks |
| [Drawing module](./api/drawing.md) | `/reference/drawing/` | 3D text drawing |
| [Developer editors](./api/editor.md) | `/reference/editor/` | Developer zone-creator and placement commands |
| [Entities module](./api/entities.md) | `/reference/entities/` | Local ped/object/vehicle spawning with scoped streaming |
| [Effects module](./api/fx.md) | `/reference/fx/` | Particle and screen effects |
| [Freecam](./api/freecam.md) | `/reference/freecam/` | Owner-bound scripted free camera |
| [Entity placement module](./api/placement.md) | `/reference/placement/` | In-world entity placement tool |
| [Raycast module](./api/raycast.md) | `/reference/raycast/` | World-geometry raycasts |
| [Sound module](./api/sound.md) | `/reference/sound/` | Managed sound playback |
| [Teleport module](./api/teleport.md) | `/reference/teleport/` | Entity and player teleporting with fade |
| [Vehicle module](./api/vehicle.md) | `/reference/vehicle/` | Client vehicle helpers |
| [Visual effects](./api/visuals.md) | `/reference/visuals/` | Screen and drug-effect conveniences |
| [World module](./api/world.md) | `/reference/world/` | Live entity-pool queries |
| [Zones module](./api/zones.md) | `/reference/zones/` | Box, sphere, circle and poly zones and the zone creator |

## Gameplay and server systems

| Page | Published path | Summary |
| --- | --- | --- |
| [Actions module](./api/actions.md) | `/reference/actions/` | Server-authorized action flow with progress and proofs |
| [Commands module](./api/commands.md) | `/reference/commands/` | Owner-tracked chat commands with permission gating |
| [Discord module](./api/discord.md) | `/reference/discord/` | Webhooks, REST bot and role directory |
| [Logging module](./api/logging.md) | `/reference/logging/` | In-memory event log with webhook mirror |
| [Permissions module](./api/permissions.md) | `/reference/permissions/` | ACE and Discord-role permission gateway |
| [QA module](./api/qa.md) | `/reference/qa/` | Hooks for the kora_qa test runner |
| [Rewards module](./api/rewards.md) | `/reference/rewards/` | Weighted reward-pool rolls |
| [Screenshot](./api/screenshot.md) | `/reference/screenshot/` | Game-view screenshot capture and upload |
| [Skills bridge](./api/skills.md) | `/reference/skills/` | Optional bridge to kora_skills |
| [Status effects module](./api/status.md) | `/reference/status/` | Shared status-effect definitions and application |

## Utilities and compatibility

| Page | Published path | Summary |
| --- | --- | --- |
| [Loops module](./api/loops.md) | `/reference/loops/` | Bounded polling and retry helpers |
| [Print helpers](./api/prints.md) | `/reference/prints/` | Structured colored console output |
| [Random module](./api/random.md) | `/reference/random/` | Random selection helpers |
| [Require](./api/require.md) | `/reference/require/` | Consumer-side Kora.require module loader |
| [Timers module](./api/timers.md) | `/reference/timers/` | Owner-tracked intervals, timeouts and rate shapers |
| [Utility module](./api/util.md) | `/reference/util/` | Small shared helpers |
| [ox_lib provider bridge](./api/ox.md) | `/reference/ox/` | Internal provider behind the optional ox_lib resource |

The `ox` provider is primarily an implementation contract for the separate compatibility resource. Most consumers should start with the [ox_lib migration guide](./migration/ox-lib.md).
