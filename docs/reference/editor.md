---
title: "Developer editors"
sidebar_position: 26
---

# Developer editors

kora_lib includes two in-game developer commands for capturing zone and entity
placement data. They only return or copy Lua data; they never persist it or
create a networked entity.

## Setup

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

## Zone creator

`/kora_zonecreator [box|sphere|poly]` starts the zone creator; omitting the
shape starts a box creator. The result is copied as a `Kora.zones.<shape>({...})`
snippet after confirmation. Invalid shapes show command usage instead of
opening the editor.

## Entity placement

`/kora_place <model>` starts the local placement preview for a model name. The
model argument is limited to letters, numbers, underscores, and hyphens, with
a maximum length of 64 characters. Confirmation returns and copies placement
data; the preview is always local and is deleted when the session ends.

## Security boundary

These commands are an administrator convenience gate, not authorization for
gameplay. A modified client can invoke its own local editor code. Any resource
that stores captured data, changes gameplay, or creates a networked entity must
validate the submitted data and authorize that operation on the server.
