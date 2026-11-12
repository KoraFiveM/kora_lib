---
title: "Permissions"
sidebar_position: 42
---


# Permissions

Checks server-side FiveM ACE permissions with an optional additive Discord-role mapping. The calling resource supplies its own permission names and level order, so the module does not assume a specific framework. ACE checks are always available; a Discord lookup can grant an explicitly mapped permission but cannot override an ACE result or accidentally grant access when the bot/cache is unavailable.

Namespace: `Kora.permissions` · Source: `modules/permissions/server.lua`

## Permission options table

The final argument accepts either a prefix string for ACE-only checks or this table for ACE plus explicitly mapped Discord roles. A `?` after a name means the option is optional.

### prefixOrOptions table

| Option | Type | Description |
| --- | --- | --- |
| `prefix?` | string | ACE namespace prefix. For example kora_core checks kora_core.admin. If omitted, only group.* ACE objects are checked. |
| `discordRoles?` | table | Map a permission/level name to one role name or a non-empty dense array of role names or role IDs. Matching any mapped role grants that mapped value. Omit or leave empty for ACE-only behavior. |

## How ACE names are checked

For a level such as admin, getLevel checks the configured prefix object (for example kora_core.admin) and group.admin. hasPermission additionally checks command.&lt;permission>. The ACE native result must be a real boolean true; invalid or failed Discord lookups do not grant access.

## Level order controls rank

Put the strongest level first, for example &#123; god, admin, mod, user &#125;. getLevel returns the first match. hasLevel uses that order so a resolved admin also satisfies a mod requirement.

## Granting permission is separate

This module only checks permissions. Add ACE principals in server.cfg or from server-side administrative code. A client request or hidden menu option never replaces server-side authorization.

## Functions

Resolve a player’s highest level, check a ranked or single permission, or inspect the ACE objects used in a decision.

### `Kora.permissions.getLevel(src, levels, prefixOrOptions?)`

Returns the first level the player has, searching the supplied list from highest privilege to lowest. The level named user is treated as the default floor when it appears in levels.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Positive player server ID. Console source 0 is not a player and is rejected. |
| `levels` | string[] | Dense array ordered most privileged first, such as &#123; god, admin, mod, user &#125;. Maximum 32 entries. |
| `prefixOrOptions?` | string \| table | Optional ACE prefix such as kora_core, or settings table described above. |

**Returns**

- **level** — highest matching level string, or user if no higher level matches.

**Example**

```lua
local levels = { 'god', 'admin', 'mod', 'user' }
local level = Kora.permissions.getLevel(source, levels, 'kora_core')
print('Player level:', level)
```

**Representative console output**

```text
Prints the highest configured level the player holds.
```

### `Kora.permissions.hasLevel(src, required, levels, prefixOrOptions?)`

Checks whether the player meets a ranked requirement. A higher resolved level satisfies a lower requirement when levels is ordered most privileged first.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Positive player server ID. |
| `required` | string | Level the player must meet, such as mod. |
| `levels` | string[] | Dense ordered level list shared with getLevel. |
| `prefixOrOptions?` | string \| table | Optional ACE prefix or permissions options table. |

**Returns**

- **allowed** — boolean.

**Example**

```lua
local levels = { 'god', 'admin', 'mod', 'user' }
if Kora.permissions.hasLevel(source, 'mod', levels, 'kora_core') then
    print('Player can use moderator tools')
end
```

**Representative console output**

```text
Prints when the resolved level is mod, admin, or god.
```

### `Kora.permissions.hasPermission(src, permission, prefixOrOptions?)`

Checks one named permission without using a ranked level list.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Positive player server ID. |
| `permission` | string | Non-empty permission name. The special name user always passes. |
| `prefixOrOptions?` | string \| table | Optional ACE prefix or mapping table. |

**Returns**

- **allowed** — boolean.

**Example**

```lua
if Kora.permissions.hasPermission(source, 'admin', 'kora_core') then
    print('Admin command allowed')
end
```

**Representative console output**

```text
Prints only when this player has the admin permission.
```

### `Kora.permissions.explain(src, levels, prefixOrOptions?)`

Diagnostic helper that shows each ACE object checked for the supplied levels and the raw result returned by IsPlayerAceAllowed. It also returns the level getLevel resolves. Discord mappings are not evaluated by this diagnostic.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Positive player server ID. |
| `levels` | string[] | Dense ordered list of non-empty level names. |
| `prefixOrOptions?` | string \| table | Optional ACE prefix or mapping table; only the prefix affects this ACE report. |

**Returns**

- **checks** — array of &#123; level, object, raw, type, allowed &#125; entries.
- **resolved** — level getLevel would return for the same inputs.

**Example**

```lua
local checks, resolved = Kora.permissions.explain(source, { 'admin', 'mod', 'user' }, 'kora_core')
print('Resolved:', resolved)
for _, check in ipairs(checks) do
    print(check.object, check.raw, check.type, check.allowed)
end
```

**Representative console output**

```text
Prints each ACE object and its raw result, then the resolved level.
```

## Limits and related APIs

Every public check requires a positive integer player source. Levels must be a dense list of at most 32 non-empty strings. Discord role lists must also be dense and non-empty when supplied.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/permissions/docs.md` or `local/permissions/docs.md`) that the reference above does not state.

### Overview
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

### API

#### `Kora.permissions.hasLevel(src, required, levels, prefixOrOptions?)` -- server
Checks a ranked requirement using the same ACE/Discord resolution as
`getLevel`. `levels` is ordered most-privileged first, so an `admin` result
satisfies a `mod` requirement without ACE principal chaining.

```lua
local LEVELS = { 'god', 'admin', 'mod', 'user' }
if Kora.permissions.hasLevel(source, 'mod', LEVELS, options) then
    -- admin and god also pass
end
```

#### `Kora.permissions.hasPermission(src, permission, prefixOrOptions?)` -- server
Checks whether a player holds one specific permission.

##### Example
```lua
if Kora.permissions.hasPermission(source, 'admin', 'kora_core') then
    -- ...
end
```

Called cross-resource via export:
```lua
exports.kora_lib:permissions_hasPermission(source, 'admin', 'myresource')
```

#### `Kora.permissions.explain(src, levels, prefixOrOptions?)` -- server
Diagnostics. Reports every ACE object `getLevel` would consult for `src`, in
order, with the raw value `IsPlayerAceAllowed` returned for each. Nothing gates
on this -- it exists so a "my ACEs look correct but I have no permissions"
report can be answered with evidence rather than inference.

##### Returns
- `table[]` -- one entry per object checked:
  `{ level, object, raw (tostring), type (type()), allowed (boolean) }`.
  `raw`/`type` are strings so a non-boolean return is visible rather than
  coerced away.
- `string` -- the level `getLevel` resolves to for the same inputs.

Each level must be a non-empty string in a dense array; invalid level lists are
rejected before any ACE lookup.
