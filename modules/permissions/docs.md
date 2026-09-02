# Permissions module

## Overview
The central server-side permission gateway for FiveM ACEs and optional Discord
roles. The level vocabulary (for example `'user'`/`'mod'`/`'admin'`/`'god'`)
and ACE namespace prefix (for example `'qbcore'`) are supplied by the caller,
so qblib does not impose a framework-specific permission model.

ACE checks are always active. Discord roles are additive: a configured role
can grant access, but a disabled bot, stale role cache, or lookup failure
cannot take away an ACE grant or grant access by accident. In particular,
`group.admin` is checked directly for the `admin` level even when Discord role
mapping is enabled.

The final argument may be the legacy prefix string or an options table:

```lua
local options = {
    prefix = 'qbcore',
    discordRoles = {
        mod = { 'Moderator' },
        admin = { '123456789012345678' }, -- role IDs avoid duplicate-name ambiguity
        god = { 'Owner' },
    },
}
```

Omit `discordRoles` (or leave it empty) for ACE-only behavior. Mapped values
may be one role name/ID or an array; matching any mapped role grants that
permission. Discord checks use `QB.discord.hasAnyRole`, including its bot,
identifier, freshness, and fail-closed rules.

## API

### `QB.permissions.getLevel(src, levels, prefixOrOptions?)` -- server
Resolves the highest privilege level a player holds.

#### Parameters
- `src: integer` -- player server id.
- `levels: string[]` -- ordered most-privileged first. `'user'`, if present, always matches.
- `prefixOrOptions: string | table | nil` -- an ACE prefix string, or
  `{ prefix?: string, discordRoles?: table<string, string|string[]> }`.

#### Returns
- `string` -- the first (most-privileged) level in `levels` the player has via
  `<prefix>.<level>`, `group.<level>`, or a mapped Discord role; otherwise
  `'user'`.

#### Example
```lua
local LEVELS = { 'god', 'admin', 'mod', 'user' }
local level = QB.permissions.getLevel(source, LEVELS, 'qbcore')
```

### `QB.permissions.hasLevel(src, required, levels, prefixOrOptions?)` -- server
Checks a ranked requirement using the same ACE/Discord resolution as
`getLevel`. `levels` is ordered most-privileged first, so an `admin` result
satisfies a `mod` requirement without ACE principal chaining.

```lua
local LEVELS = { 'god', 'admin', 'mod', 'user' }
if QB.permissions.hasLevel(source, 'mod', LEVELS, options) then
    -- admin and god also pass
end
```

### `QB.permissions.hasPermission(src, permission, prefixOrOptions?)` -- server
Checks whether a player holds one specific permission.

#### Parameters
- `src: integer`
- `permission: string` -- `'user'` always returns `true`.
- `prefixOrOptions: string | table | nil` -- an ACE prefix string, or the
  options table described above.

#### Returns
- `boolean` -- `true` if `permission == 'user'`, or the player has
  `<prefix>.<permission>`, `group.<permission>`, `command.<permission>`, or a
  mapped Discord role.

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

### `QB.permissions.explain(src, levels, prefixOrOptions?)` -- server
Diagnostics. Reports every ACE object `getLevel` would consult for `src`, in
order, with the raw value `IsPlayerAceAllowed` returned for each. Nothing gates
on this -- it exists so a "my ACEs look correct but I have no permissions"
report can be answered with evidence rather than inference.

#### Parameters
- `src: integer`
- `levels: string[]` -- as `getLevel`.
- `prefixOrOptions: string | table | nil` -- as `getLevel`. Discord roles are
  ignored here; this reports ACE resolution only.

#### Returns
- `table[]` -- one entry per object checked:
  `{ level, object, raw (tostring), type (type()), allowed (boolean) }`.
  `raw`/`type` are strings so a non-boolean return is visible rather than
  coerced away.
- `string` -- the level `getLevel` resolves to for the same inputs.

#### Example
```lua
local checks, resolved = QB.permissions.explain(source, LEVELS, 'qbcore')
for _, check in ipairs(checks) do
    print(check.object, check.raw, check.type, check.allowed)
end
```

## Notes
- A permission is denied only when NO checked object matched. Note that a
  native returning a number could not cause a denial: `0` is truthy in Lua, so
  a numeric return would make `getLevel` match its FIRST candidate level for
  everyone -- over-permission, not under. A "no permissions" report is almost
  always an `add_principal` naming an identifier the player does not hold;
  `explain` above prints the objects, and qbadmin's console-only
  `qbadmin_whyperms <id>` prints those alongside the player's real identifiers.
- Grants are ordinary ace principals -- add them with `add_ace`/`add_principal` in `server.cfg` or at runtime via `ExecuteCommand`, same as any other FXServer permission.
- ACEs are evaluated before Discord, so `group.admin` continues to work when
  the bot is disabled or its cache is unavailable.
- This module only *checks* permissions. Granting a runtime permission (e.g. tying it to a player identity) is left to the caller -- qbcore's `Core.permissions.addPermission` is one example.
