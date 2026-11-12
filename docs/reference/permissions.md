---
title: "Permissions module"
sidebar_position: 42
---

# Permissions module

## Overview
The central server-side permission gateway for FiveM ACEs and optional Discord
roles. The level vocabulary (for example `'user'`/`'mod'`/`'admin'`/`'god'`)
and ACE namespace prefix (for example `'kora_core'`) are supplied by the caller,
so kora_lib does not impose a framework-specific permission model.

ACE checks are always active. Discord roles are additive: a configured role
can grant access, but a disabled bot, stale role cache, or lookup failure
cannot take away an ACE grant or grant access by accident. In particular,
`group.admin` is checked directly for the `admin` level even when Discord role
mapping is enabled.

The final argument may be the legacy prefix string or an options table:

```lua
local options = {
    prefix = 'kora_core',
    discordRoles = {
        mod = { 'Moderator' },
        admin = { '123456789012345678' }, -- role IDs avoid duplicate-name ambiguity
        god = { 'Owner' },
    },
}
```

Omit `discordRoles` (or leave it empty) for ACE-only behavior. Mapped values
may be one role name/ID or a non-empty dense string array; matching any mapped role grants that
permission. Discord checks use `Kora.discord.hasAnyRole`, including its bot,
identifier, freshness, and fail-closed rules.

## API

### `Kora.permissions.getLevel(src, levels, prefixOrOptions?)` -- server
Resolves the highest privilege level a player holds.

#### Parameters
- `src: positive finite integer` -- player server id.
- `levels: string[]` -- dense, ordered most-privileged first, with at most 32
  entries. `'user'`, if present, always matches.
- `prefixOrOptions: string | table | nil` -- an ACE prefix string, or
  `{ prefix?: string, discordRoles?: table<string, string|string[]> }`; role
  arrays must be non-empty and dense.

#### Returns
- `string` -- the first (most-privileged) level in `levels` the player has via
  `<prefix>.<level>`, `group.<level>`, or a mapped Discord role; otherwise
  `'user'`.

#### Example
```lua
local LEVELS = { 'god', 'admin', 'mod', 'user' }
local level = Kora.permissions.getLevel(source, LEVELS, 'kora_core')
```

### `Kora.permissions.hasLevel(src, required, levels, prefixOrOptions?)` -- server
Checks a ranked requirement using the same ACE/Discord resolution as
`getLevel`. `levels` is ordered most-privileged first, so an `admin` result
satisfies a `mod` requirement without ACE principal chaining.

```lua
local LEVELS = { 'god', 'admin', 'mod', 'user' }
if Kora.permissions.hasLevel(source, 'mod', LEVELS, options) then
    -- admin and god also pass
end
```

### `Kora.permissions.hasPermission(src, permission, prefixOrOptions?)` -- server
Checks whether a player holds one specific permission.

#### Parameters
- `src: positive finite integer`
- `permission: string` -- `'user'` always returns `true`.
- `prefixOrOptions: string | table | nil` -- an ACE prefix string, or the
  options table described above.

#### Returns
- `boolean` -- `true` if `permission == 'user'`, or the player has
  `<prefix>.<permission>`, `group.<permission>`, `command.<permission>`, or a
  mapped Discord role.

#### Example
```lua
if Kora.permissions.hasPermission(source, 'admin', 'kora_core') then
    -- ...
end
```

Called cross-resource via export:
```lua
exports.kora_lib:permissions_hasPermission(source, 'admin', 'myresource')
```

### `Kora.permissions.explain(src, levels, prefixOrOptions?)` -- server
Diagnostics. Reports every ACE object `getLevel` would consult for `src`, in
order, with the raw value `IsPlayerAceAllowed` returned for each. Nothing gates
on this -- it exists so a "my ACEs look correct but I have no permissions"
report can be answered with evidence rather than inference.

#### Parameters
- `src: positive finite integer`
- `levels: string[]` -- as `getLevel`.
- `prefixOrOptions: string | table | nil` -- as `getLevel`. Discord roles are
  ignored here; this reports ACE resolution only.

#### Returns
- `table[]` -- one entry per object checked:
  `{ level, object, raw (tostring), type (type()), allowed (boolean) }`.
  `raw`/`type` are strings so a non-boolean return is visible rather than
  coerced away.
- `string` -- the level `getLevel` resolves to for the same inputs.

Each level must be a non-empty string in a dense array; invalid level lists are
rejected before any ACE lookup.

#### Example
```lua
local checks, resolved = Kora.permissions.explain(source, LEVELS, 'kora_core')
for _, check in ipairs(checks) do
    print(check.object, check.raw, check.type, check.allowed)
end
```

## Notes
- All public permission checks reject `0`, fractional, and non-finite sources
  before calling ACE or Discord helpers. Handle console commands separately;
  their authorization is not a player permission check.
- A permission is denied only when NO checked object matched. Note that a
  native returning a number could not cause a denial: `0` is truthy in Lua, so
  a numeric return would make `getLevel` match its FIRST candidate level for
  everyone -- over-permission, not under. A "no permissions" report is almost
  always an `add_principal` naming an identifier the player does not hold;
  `explain` above prints the objects, and kora_admin's console-only
  `kora_admin_whyperms <id>` prints those alongside the player's real identifiers.
- Grants are ordinary ace principals -- add them with `add_ace`/`add_principal` in `server.cfg` or at runtime via `ExecuteCommand`, same as any other FXServer permission.
- ACEs are evaluated before Discord, so `group.admin` continues to work when
  the bot is disabled or its cache is unavailable.
- This module only *checks* permissions. Granting a runtime permission (e.g. tying it to a player identity) is left to the caller -- kora_core's `Core.permissions.addPermission` is one example.
