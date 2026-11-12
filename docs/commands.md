---
title: "Commands"
sidebar_position: 4
---


# Commands

These are commands shipped by Kora Lib. Commands registered by `Kora.commands.add` are created by individual resources, so their names depend on the server’s scripts.

## Built-in commands

### `/config [resource]`

Opens the Kora configuration editor. The optional resource name opens that resource’s settings directly.

| Field | Details |
| --- | --- |
| Context | In-game · server command |
| Arguments | resource? — optional resource name whose settings you want to edit. |
| Access | Requires the kora_lib.config.edit ACE when the standalone Kora Lib command is active. If kora_admin is running, it owns the /config command instead. |

**Example**

```text
/config
/config kora_mining
```

**Result**

Opens the editor or the selected resource page. The command is available only when the configuration editor is enabled.

### `/blips`

Opens or closes the personal map and blip settings panel.

| Field | Details |
| --- | --- |
| Context | In-game · client command |
| Arguments | No arguments. |
| Access | No editor ACE is required. Some settings shown in the panel depend on whether the player has the configured admin permission. |

**Example**

```text
/blips
```

**Result**

Toggles the Blip settings panel.

### `/kora_zonedebug [on|off]`

Turns zone boundary drawing on or off for all currently registered zones.

| Field | Details |
| --- | --- |
| Context | In-game · client command |
| Arguments | on — enable drawing. off — disable drawing. Omit the value to switch to the opposite of the current state. |
| Access | No ACE permission is checked. |

**Example**

```text
/kora_zonedebug
/kora_zonedebug on
/kora_zonedebug off
```

**Result**

Zone outlines appear or disappear. This is a development aid and does not create or edit zones.

### `/kora_zonecreator [box|sphere|poly]`

Starts the in-world zone creator. If you omit the shape, it starts with a box.

| Field | Details |
| --- | --- |
| Context | In-game · server command opens a client editor |
| Arguments | box — rotated box. sphere — 3D sphere. poly — polygon footprint with height. Other values show usage instructions. |
| Access | Requires the kora_lib.editor ACE by default. The editor can be disabled or renamed in Config.editor. |

**Example**

```text
/kora_zonecreator
/kora_zonecreator sphere
/kora_zonecreator poly
```

**Result**

After confirmation, the editor shows and copies a Lua snippet. It does not save or register the zone for you.

### `/kora_place <model>`

Starts a local placement preview for a model so a developer can capture its position and rotation.

| Field | Details |
| --- | --- |
| Context | In-game · server command opens a client editor |
| Arguments | model — required model name, up to 64 letters, numbers, underscores, or hyphens. |
| Access | Requires the kora_lib.editor ACE by default. The editor can be disabled or renamed in Config.editor. |

**Example**

```text
/kora_place prop_chair_01a
```

**Result**

Confirmation returns and copies placement data. The preview is local and is removed when the editor ends.

### `kora_lib_discord_sync`

Starts a full Discord role and online-member synchronization.

| Field | Details |
| --- | --- |
| Context | Server console only |
| Arguments | No arguments. |
| Access | Must be run from the server console. Player-issued attempts are ignored. The Discord bot must be configured and enabled. |

**Example**

```text
kora_lib_discord_sync
# Deprecated alias: kora_lib_discord_sync
```

**Result**

Prints progress and a summary of roles, online members, skipped members, and errors.

## Commands created by your resources

`Kora.commands.add(...)` lets a resource register its own server command. Those commands are not fixed Kora Lib commands, so the list depends on the resources installed on your server. Open the Commands module under Functions / exports for the registration parameters and examples.

## Additional commands

Commands registered by the optional ox_lib bridge that are not covered above.

| Command | Realm | Access | Description |
| --- | --- | --- | --- |
| `/ox_lib-radial` | client | everyone | Opens the ox_lib-style radial menu registered through the optional ox_lib bridge. It does nothing unless radial items were registered. |

The editor commands (`/kora_zonecreator`, `/kora_place`) print a message instead of running when invoked from the server console, and tell players without access that they lack permission. They are disabled when `Config.editor.enabled` is not `true`.

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
