---
title: "Skills"
sidebar_position: 46
---


# Skills

## Client

Optional bridge to kora_skills. The bridge does not require that resource to be running: reads safely return no skill data when it is unavailable, and minigame settings are left unchanged.

Namespace: `Kora.skills` · Source: `modules/skills/client.lua`

### Functions

Check availability, read a skill snapshot, check a level, or adjust minigame options for client presentation.

#### `Kora.skills.isAvailable()`

Checks whether the optional kora_skills integration is available.

**Parameters**



**Returns**

- **available** — boolean.

**Example**

```lua
if Kora.skills.isAvailable() then print('Skills are enabled') end
```

**Representative console output**

```text
Prints when kora_skills is running.
```

#### `Kora.skills.get(skill)`

Reads the local player’s value for one skill.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `skill` | string | Non-empty skill name. |

**Returns**

- **value** — skill information/value when available; otherwise nil.

**Example**

```lua
local mining = Kora.skills.get('mining')
print(mining)
```

**Representative console output**

```text
Prints the local mining skill value when the provider is available.
```

#### `Kora.skills.getAll()`

Reads the local player’s complete skill collection.

**Parameters**



**Returns**

- **skills** — table of skill data, or nil when unavailable.

**Example**

```lua
local skills = Kora.skills.getAll()
if skills then print('Skill data loaded') end
```

**Representative console output**

```text
Prints only when the optional bridge returned skill data.
```

#### `Kora.skills.hasLevel(skill, level)`

Checks whether the local player meets a skill threshold. This client result is suitable for presentation only; repeat the check on the server for a protected action.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `skill` | string | Non-empty skill name. |
| `level` | integer | Positive required level. |

**Returns**

- **hasLevel** — boolean.

**Example**

```lua
if Kora.skills.hasLevel('mining', 20) then print('Advanced mining option shown') end
```

**Representative console output**

```text
Prints when the local client meets the requested skill level.
```

#### `Kora.skills.adjustMinigame(skill, gameType, opts)`

Returns minigame settings adjusted by the local player’s skill configuration, or the same options when the provider is unavailable.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `skill` | string | Non-empty skill name. |
| `gameType` | string | Non-empty supported minigame name. |
| `opts` | table | Already resolved base settings. |

**Returns**

- **options** — adjusted or unchanged table.

**Example**

```lua
local opts = Kora.skills.adjustMinigame('mining', 'skillbar', { zoneSize = 0.18 })
```

**Representative console output**

```text
Returns the presentation settings for the skill-aware check.
```

## Server

Server-side bridge for authoritative skill reads and awards. Use this realm for gameplay decisions. If kora_skills is unavailable, reads fail safely instead of inventing a skill level.

Namespace: `Kora.skills` · Source: `modules/skills/server.lua`

### Functions

Read or award a skill for a player and resolve authoritative skill-adjusted minigame settings.

#### `Kora.skills.isAvailable()`

Checks whether the optional skills resource is available on the server.

**Parameters**



**Returns**

- **available** — boolean.

**Example**

```lua
if not Kora.skills.isAvailable() then return end
```

**Representative console output**

```text
The function returns true only when the integration can be used.
```

#### `Kora.skills.get(src, skill)`

Reads one skill for the specified player.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Positive player server ID. |
| `skill` | string | Non-empty skill name. |

**Returns**

- **value** — skill data/value when available; otherwise nil.

**Example**

```lua
local level = Kora.skills.get(source, 'mining')
if level then print('Mining data available') end
```

**Representative console output**

```text
Prints when the server can read the requested skill.
```

#### `Kora.skills.getAll(src)`

Reads the player’s full skill collection.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Positive player server ID. |

**Returns**

- **skills** — skill data table, or nil if unavailable.

**Example**

```lua
local skills = Kora.skills.getAll(source)
```

**Representative console output**

```text
Returns the player’s available skill records.
```

#### `Kora.skills.hasLevel(src, skill, level)`

Checks a player’s authoritative skill level.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Positive player server ID. |
| `skill` | string | Non-empty skill name. |
| `level` | integer | Positive required level. |

**Returns**

- **hasLevel** — boolean.

**Example**

```lua
if not Kora.skills.hasLevel(source, 'mining', 20) then return end
```

**Representative console output**

```text
Stops the handler unless the player meets level 20.
```

#### `Kora.skills.add(src, skill, amount, location?, distance?)`

Requests a skill award for a player. Location and distance can constrain the award to a valid place.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Positive player server ID. |
| `skill` | string | Non-empty skill name. |
| `amount` | integer | Positive award amount. |
| `location?` | vector3 | Optional finite coordinates for location validation. |
| `distance?` | number | Optional finite maximum distance when location is provided. |

**Returns**

- **added** — boolean indicating award success.
- **reason** — error or refusal reason when unsuccessful.

**Example**

```lua
local added, reason = Kora.skills.add(source, 'mining', 25, mineCoords, 4.0)
if not added then print(reason) end
```

**Representative console output**

```text
Awards mining experience only when the provider accepts the request.
```

#### `Kora.skills.adjustMinigame(src, skill, gameType, resolvedOptions)`

Adjusts already-resolved minigame settings using the player’s configured skill bonus. It does not create minigame proof or bypass minigame validation.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Positive player server ID. |
| `skill` | string | Non-empty skill name. |
| `gameType` | string | Non-empty minigame type. |
| `resolvedOptions` | table | Trusted base options selected by the server before skill adjustment. |

**Returns**

- **options** — resolved skill-adjusted table.

**Example**

```lua
local adjusted = Kora.skills.adjustMinigame(source, 'mining', 'skillbar', { zoneSize = 0.18 })
```

**Representative console output**

```text
Returns server-resolved settings to pass into the authorized minigame flow.
```

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/skills/docs.md` or `local/skills/docs.md`) that the reference above does not state.

`Kora.skills` is an optional bridge for servers running `kora_skills`. It does not
make kora_lib depend on that resource: every function is safe when `kora_skills` is
absent, stopped, or restarting.

The bridge API is `Kora.skills.isAvailable()`, `Kora.skills.get(...)`,
`Kora.skills.getAll(...)`, `Kora.skills.hasLevel(...)`, `Kora.skills.add(...)`, and
`Kora.skills.adjustMinigame(...)`.

Client:

```lua
if Kora.skills.hasLevel('mining', 20) then
    -- Client-side presentation gate only; the server must repeat this check.
end

local options = Kora.skills.adjustMinigame('mining', 'skillbar', { zoneSize = 0.18 })
```

Server:

```lua
local skill = Kora.skills.get(src, 'mining')
if not Kora.skills.hasLevel(src, 'mining', 20) then return end

local added, err = Kora.skills.add(src, 'mining', 25, mineCoords, 4.0)
```

`Kora.skills.add` is server-only and requires positive integer player source and
award amount, a non-empty skill name, and finite coordinates/distance when a
location is supplied. `hasLevel` requires a positive integer level.
`adjustMinigame` also requires a positive integer player source plus non-empty
skill and game-type names. It maps an already-resolved minigame configuration through the
player's configured skill bonus; it never permits a client to mint a proof or
bypass the minigame server checks.

Client reads and presentation-only minigame adjustment use the same non-empty
skill/game-type and positive integer level requirements. They remain optional:
when `kora_skills` is unavailable, reads return no data and adjustment leaves the
provided options unchanged.
