---
title: Commands and key mappings
sidebar_position: 5
---

# Commands and key mappings

These are the commands and key mappings that kora_lib itself registers. Resources can register more through [`Kora.commands`](./reference/commands.md) and [`Kora.keybind`](./reference/keybind.md).

## Commands

| Command | Realm | Access | Description |
| --- | --- | --- | --- |
| `/kora_zonecreator [box\|sphere\|poly]` | server (starts a client tool) | `kora_lib.editor` ACE | Starts the in-world zone creator. Defaults to `box`. Name configurable with `Config.editor.zoneCommand`. See [Developer editors](./reference/editor.md). |
| `/kora_place <model>` | server (starts a client tool) | `kora_lib.editor` ACE | Starts the entity placement tool for a model name. Name configurable with `Config.editor.placementCommand`. |
| `/kora_zonedebug [on\|off]` | client | everyone | Toggles zone debug drawing; omit the argument to toggle. |
| `/blips` | client | everyone to open the app; some actions require the `admin` permission | Opens or closes the blips settings app. See [Blips](./reference/blips.md). |
| `/ox_lib-radial` | client | everyone | Opens the ox_lib-style radial menu registered through the optional ox_lib bridge. It does nothing unless radial items were registered. |
| `kora_lib_discord_sync` | server console | console only | Runs an immediate Discord role sync. Does nothing when run by a player. See [Discord](./reference/discord.md). |

The editor commands print a message instead of running when invoked from the server console, and tell players without access that they lack permission. They are disabled when `Config.editor.enabled` is not `true`.

## Key mappings

| Mapping | Default key | Description |
| --- | --- | --- |
| `kora_lib_radialmenu_open` | `F1` | Opens the qb-radialmenu bridge radial menu. |
| `ox_lib-radial` | `Z` | Opens the ox_lib-style radial menu. |
| `kora_lib_placement_numeric` | `N` | Entity placement: numeric position and rotation entry. |
| `kora_lib_placement_raycast` | `R` | Entity placement: toggle surface placement. |
| `kora_lib_zonecreator_place` / `_undo` / `_place_click` / `_undo_click` / `_cycle` | `E` / `BACK` / left mouse / right mouse / `TAB` | Zone creator actions. |
| `kora_lib_placement_cycle`, `_confirm`, `_cancel`, `_movement` and one per placement action | various | Other entity placement actions, registered with `Kora.keybind`. |
| `kora_lib_command:<name>` | per command | Created for commands registered with a default key through `Kora.commands`. |

The keybind module registers each as a `+name`/`-name` command pair with `RegisterKeyMapping`. Players rebind these in the standard FiveM key bindings settings, which stores them under these names. Renaming one resets every player's binding.
