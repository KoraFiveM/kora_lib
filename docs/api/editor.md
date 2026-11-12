---
title: "Editor"
sidebar_position: 26
---


# Editor

Provides administrator-facing commands that start client-side zone and entity placement editors. The editor returns or copies Lua data; it does not persist data or create a networked entity.

Namespace: `Kora.editor` · Source: `modules/editor/server.lua`

## How it works

The configured ACE gate is a convenience for trusted developers, not an authorization boundary for gameplay. A modified client can invoke local editor code. Any consumer that stores captured data or applies gameplay changes must validate and authorize that work on the server.

## Configuration

Set these values in Config.editor before kora_lib starts. They control command registration and the ACE gate. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `Config.editor.enabled` | boolean | Must be true for either command to open an editor. Defaults to true. |
| `Config.editor.permission?` | string | ACE permission name; defaults to editor. |
| `Config.editor.permissionPrefix?` | string | ACE prefix; defaults to kora_lib. When using that default, deprecated kora_lib.editor is also accepted. |
| `Config.editor.zoneCommand?` | string | Name of the zone creator command; defaults to kora_zonecreator. |
| `Config.editor.placementCommand?` | string | Name of the placement command; defaults to kora_place. |

## Commands

### `/kora_zonecreator [box|sphere|poly]`

Starts the configured zone creator for the selected shape. On confirmation, the client copies a Kora.zones.&lt;shape>(...) Lua snippet. Invalid shapes show usage and do not start the editor.

| Field | Details |
| --- | --- |
| Type | Zone creator |
| Arguments | Optional shape: box, sphere, or poly. Defaults to box when omitted; input is case-insensitive. |
| Behavior | Starts the sphere zone editor after the server ACE check passes. |

**Example**

```lua
/kora_zonecreator sphere
```

### `/kora_place <model>`

Starts a local placement preview for the requested model. Confirmation returns and copies placement data. The preview entity is local and is deleted when the editor session ends.

| Field | Details |
| --- | --- |
| Type | Entity placement |
| Arguments | model: required model name, maximum 64 characters, letters/numbers/underscore/hyphen only. |
| Behavior | Starts the local placement preview when the model argument passes validation. |

**Example**

```lua
/kora_place prop_toolchest_05
```

## Limits and related APIs

Both entry points require a player source greater than 0; server console calls print that the command is in-game only. Permission is checked server-side before the start event is sent, but the resulting editor runs locally. Do not treat captured client coordinates or shapes as trusted input.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/editor/docs.md` or `local/editor/docs.md`) that the reference above does not state.

kora_lib includes two in-game developer commands for capturing zone and entity
placement data. They only return or copy Lua data; they never persist it or
create a networked entity.

### Setup

The commands are enabled by default and require the `kora_lib.editor` ACE. Grant
that ACE only to trusted developers or administrators:

```cfg
add_ace group.admin kora_lib.editor allow
```

Configure the commands in `Config.editor`:

```lua
Config.editor = {
    enabled = true,
    permission = 'editor',
    permissionPrefix = 'kora_lib',
    zoneCommand = 'kora_zonecreator',
    placementCommand = 'kora_place',
}
```

Set `enabled = false` to remove both command entry points. Rename either
command by changing its matching configuration field before kora_lib starts.

### Zone creator

`/kora_zonecreator [box|sphere|poly]` starts the zone creator; omitting the
shape starts a box creator. The result is copied as a `Kora.zones.<shape>({...})`
snippet after confirmation. Invalid shapes show command usage instead of
opening the editor.

### Entity placement

`/kora_place <model>` starts the local placement preview for a model name. The
model argument is limited to letters, numbers, underscores, and hyphens, with
a maximum length of 64 characters. Confirmation returns and copies placement
data; the preview is always local and is deleted when the session ends.

### Security boundary

These commands are an administrator convenience gate, not authorization for
gameplay. A modified client can invoke its own local editor code. Any resource
that stores captured data, changes gameplay, or creates a networked entity must
validate the submitted data and authorize that operation on the server.
