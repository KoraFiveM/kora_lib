---
title: Configuration
sidebar_position: 7
---

# Configuration

kora_lib's own settings live in two plain Lua files that are edited directly by the server owner. There is no database or UI for them. (The separate [`Kora.config`](./api/config.md) module is for consumer resources that want typed, editable settings of their own.)

| File | Realm | Purpose |
| --- | --- | --- |
| `config.lua` | shared (listed in `shared_scripts`) | Defines the global `Config` table used by most modules. |
| `server/config.lua` | server | Adds `Config.discord` for the Discord role directory. |

Restart `kora_lib` after editing either file. Per-server override files named `config.local.lua` and `config.local.lua.bak` are git-ignored by this repository (`.gitignore`); they are written by the `Kora.config` machinery for consumer resources, not read by kora_lib's own `config.lua`.

## `config.lua`

| Key | Defaults | What it controls |
| --- | --- | --- |
| `Config.third_party_notify` | `false` | When `true`, notifications are routed through the `kora_lib:notify:send` event instead of kora_lib's NUI toast. See [Notifications](./api/notify.md). |
| `Config.nui` | `clipboardFocus = true`, `clipboardUnfocusedFirst = true` | Clipboard handling in the NUI. |
| `Config.ui` | `interact = true`, `apps.draggableDefault = false` | Shared UI switches. |
| `Config.screenshot` | `debugConvar`, `defaultEncoding = 'jpg'`, `defaultQuality = 0.92`, `maxWidth = 1920`, `maxHeight = 1080`, `requestTimeout = 30000`, `uploadBytesPerSecond`, `maxBytes` | Screenshot capture limits. See [Screenshots](./api/screenshot.md). |
| `Config.interact` | `previousControls`, `nextControls`, `selectControls`, `cancelControls` | Control IDs used by the interaction selector. See [Interactions](./api/interact.md). |
| `Config.callback` | `timeout = 30000` | Default callback timeout in milliseconds. |
| `Config.cache` | `tickInterval = 200` | Local-player cache sampling interval in milliseconds. |
| `Config.notify` | `defaultDuration = 5000`, `maxDuration = 120000`, `defaultType = 'info'`, `defaultPosition = 'top-right'` | Notification defaults and limits. |
| `Config.sound` | `defaultReleaseAfter = 10000`, `defaultRange = 30.0` | Sound defaults. |
| `Config.blips` | sprite, colour, scale, display and category defaults, plus an `info` table for the legend tooltip | Blip defaults. See [Blips](./api/blips.md) for each option. |
| `Config.progressbar` | `maxDuration = 600000`, `maxProps = 2`, `cancelControls = { 73, 322 }`, `defaultMoveMode = 'controls'`, `bottomOffset = 10` | Progress bar limits. |
| `Config.radialmenuCompat` | `enableVehicleExtras`, `flipVehicleTime`, `jobInteractions` | Entries added by the qb-radialmenu bridge. See [Legacy compatibility](./legacy-compat.md). |
| `Config.world` | `defaultRadius`, `groundHeight`, `groundAttempts`, `groundRetryDelay` | World query defaults. |
| `Config.teleport` | `fadeTime`, waypoint launch and ground-probing options | Teleport behaviour. |
| `Config.drawing` | `text3d` font, scale, colour, distance, outline | 3D text defaults. |
| `Config.editor` | `enabled = true`, `permission = 'editor'`, `permissionPrefix = 'kora_lib'`, `zoneCommand = 'kora_zonecreator'`, `placementCommand = 'kora_place'` | Developer editor commands and their ACE. See [Commands](./commands.md) and [Permissions](./permissions.md). |
| `Config.placement` | raycast distance, move and rotation speeds, camera options, preview alpha, `confirmTimeout`, HUD options, `enabled` | Entity placement tool. |
| `Config.freecam` | `freezePlayer`, camera speeds, transition time | Free camera. |
| `Config.zones` | grid size, tick intervals (`tickFar`, `tickNear`, `tickInside`), debug alphas, `debug`, and a `creator` sub-table | Zone engine and in-world zone creator. See [Zones](./api/zones.md). |
| `Config.minigames` | session, authorization and proof TTLs, per-player limits, `inputLimits`, `callbackRateLimits`, and one table per minigame | Minigame defaults and anti-abuse limits. See [Minigames](./api/minigames.md). |

The exact value of every key is in `config.lua`; the module reference page for each module explains how its table is used.

## `server/config.lua`

| Key | Default | Meaning |
| --- | --- | --- |
| `Config.discord.roleSyncInterval` | `300000` | Interval between Discord role syncs, in milliseconds. |
| `Config.discord.cacheMaxAge` | `600000` | Maximum age of cached Discord authorization data, in milliseconds. |
| `Config.discord.databaseTimeout` | `60000` | How long to wait for `kora_sql` to become ready, in milliseconds. |

## Convars

Set these in `server.cfg`. Secrets must use `set` (server-only), never `setr`.

| Convar | Realm | Default | Used by |
| --- | --- | --- | --- |
| `kora_lib_discord_webhook` | server | empty | Default webhook URL for [Discord](./api/discord.md) `sendWebhook`. |
| `kora_lib_discord_bot_token` | server | empty | Enables the Discord REST bot helpers. |
| `kora_lib_discord_guild_id` | server | empty | Default guild ID for Discord bot helpers. |
| `kora_lib_log_webhook` | server | empty | Mirrors every [log](./api/logging.md) event to a Discord webhook. When empty, `kora_core_log_webhook` is used as a fallback. |
| `kora_lib_screenshot_debug` | server | `0` | Set to `1` to enable screenshot diagnostics. Either this convar or the one named by `Config.screenshot.debugConvar` set to `1` enables it. |
| `kora_locale` | shared | `en` | Default language for [Locales](./api/locales.md). |
| `kora_locales` | shared | empty | Comma or space separated list of enabled language codes. `en` and the default language are always included. |
| `fft_kora_hooks` | client | `false` | Set to `true` (for example `setr fft_kora_hooks true`) to enable optional FFT test hooks, which observe `Kora.nui.send`. Development only. |
| `ox:progressPropLimit` | client | `2` | Read by the ox_lib provider module (`Kora.ox`) to cap progress bar props. |
