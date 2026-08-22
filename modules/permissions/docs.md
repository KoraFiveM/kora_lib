# Permissions module

## Overview
A thin wrapper over FiveM's ace/principal system for checking a player's privilege level. The level vocabulary (e.g. `'user'`/`'mod'`/`'admin'`/`'god'`) and the ace namespace prefix (e.g. `'qbcore'`) are supplied by the caller, so multiple resources can share this logic under their own principal namespace.

## API

### `QB.permissions.getLevel(src, levels, prefix)` -- server
Resolves the highest privilege level a player holds.

#### Parameters
- `src: integer` -- player server id.
- `levels: string[]` -- ordered most-privileged first. `'user'`, if present, always matches.
- `prefix: string` -- ace/group principal namespace, e.g. `"qbcore"`.

#### Returns
- `string` -- the first (most-privileged) level in `levels` the player has via `<prefix>.<level>` or `group.<level>`, or `'user'` if none match and `'user'` isn't itself in `levels`.

#### Example
```lua
local LEVELS = { 'god', 'admin', 'mod', 'user' }
local level = QB.permissions.getLevel(source, LEVELS, 'qbcore')
```

### `QB.permissions.hasPermission(src, permission, prefix)` -- server
Checks whether a player holds one specific permission.

#### Parameters
- `src: integer`
- `permission: string` -- `'user'` always returns `true`.
- `prefix: string` -- ace/group/command principal namespace.

#### Returns
- `boolean` -- `true` if `permission == 'user'`, or the player has `<prefix>.<permission>`, `group.<permission>`, or `command.<permission>`.

#### Example
```lua
if QB.permissions.hasPermission(source, 'admin', 'qbcore') then
    -- ...
end
```

Called cross-resource via export:
```lua
exports.qblib:permissions_hasPermission(source, 'admin', 'myresource')
```

## Notes
- Grants are ordinary ace principals -- add them with `add_ace`/`add_principal` in `server.cfg` or at runtime via `ExecuteCommand`, same as any other FXServer permission.
- This module only *checks* permissions. Granting a runtime permission (e.g. tying it to a player identity) is left to the caller -- qbcore's `Core.permissions.addPermission` is one example.
