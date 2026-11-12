---
title: "Commands"
sidebar_position: 39
---


# Commands

Registers server commands with chat suggestions, optional permission checks, safe handler execution, and resource ownership tracking. Registrations and suggestions are cleaned up when the owning resource stops.

Namespace: `Kora.commands` · Source: `modules/commands/server.lua`

## How it works

Command names are server-global. Registering a name already in use replaces its handler and transfers ownership. The RegisterCommand callback remains installed after remove, but becomes a no-op while the name has no active Kora definition. Handler errors are caught and printed so they do not escape the command dispatcher.

## Registration options

Pass opts as the final argument to add. These settings are shared by the registration rather than supplied to the command handler. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `permission?` | string | Defaults to user. A non-user permission is denied unless checkPermission is callable and returns exactly true. The server console source 0 is allowed. |
| `checkPermission?` | function | Called as checkPermission(source, permission). Return true to allow. Errors and all other return values deny access. Required for any non-user permission. |
| `notify?` | function | Called as notify(source, message, type) for permission denial and missing required arguments. Defaults to Kora.notify.send. |
| `resource?` | string | Resource that owns the registration. Defaults to the invoking resource, or the current resource. Ownership controls remove and automatic cleanup. |
| `keybind?` | table | Mirrors the command into a client key mapping. Supports description, defaultKey, defaultMapper, secondaryKey, and secondaryMapper. Mapper defaults to keyboard; description defaults to help or the command name. Keybind execution uses the same dispatcher and permission check as a typed command. |

## Argument suggestions

Each args entry requires a non-empty name and may include help. Static values may be strings or objects shaped &#123; value, label?, help? &#125;. A synchronous provider(source, context) may return dynamic completions; context contains command, argumentIndex, query, and parsed args. Provider functions stay server-side and are never serialized into chat suggestions. Results are normalized, filtered case-insensitively, de-duplicated, and capped at 20.

## Functions

All public functions run on the server. Use add to register; list and suggest expose the active definitions; refresh re-sends chat suggestions to a player; remove clears a registration owned by the calling resource.

### `Kora.commands.add(name, help?, args?, argsRequired?, handler, opts?)`

Registers a command and publishes its chat suggestion. The handler receives the source, parsed string arguments, and raw command text.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | non-empty command name with no whitespace. |
| `help?` | number | optional display text. |
| `args?` | array | optional dense array of suggestion argument definitions. |
| `argsRequired?` | boolean | optional boolean; when true, require at least #args values before calling handler. |
| `handler` | function | callable receiving (source, args, raw). |
| `opts?` | table | optional registration options; see Registration options below. |

**Returns**

- **return** — no value. Registration validation failures raise an assertion error before replacing the current command.

**Example**

```lua
Kora.commands.add('heal', 'Heal yourself', nil, false, function(source)
    healPlayer(source)
end, {
    permission = 'admin',
    checkPermission = function(source, permission)
        return IsPlayerAceAllowed(source, 'myresource.' .. permission)
    end,
})
```

**Representative console output**

```text
Registers /heal; unauthorized execution is denied and notified.
```

### `Kora.commands.remove(name)`

Removes the active command definition, suggestion, and keybind for a command owned by the calling resource. It does not unregister FiveM’s underlying RegisterCommand callback.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | command name owned by the calling resource. |

**Returns**

- **removed** — true when the caller owned and removed the command; false when it was absent or owned by another resource.

**Example**

```lua
local removed = Kora.commands.remove('heal')
print(removed)
```

**Representative console output**

```text
true when this resource owns /heal; false otherwise.
```

### `Kora.commands.refresh(src)`

Re-sends all active chat suggestions to one player, for example after the chat resource reconnects.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | positive integer FiveM player server ID. |

**Returns**

- **return** — no value. Invalid source values raise an assertion error.

**Example**

```lua
AddEventHandler('playerJoining', function()
    Kora.commands.refresh(source)
end)
```

**Representative console output**

```text
Suggestions are sent alphabetically by command name.
```

### `Kora.commands.list()`

Returns public metadata for every active command in alphabetical order.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `—` |  | No parameters. |

**Returns**

- **commands** — array of objects containing name, help, permission, and optional keybind metadata.

**Example**

```lua
for _, command in ipairs(Kora.commands.list()) do
    print(command.name, command.permission)
end
```

**Representative console output**

```text
An alphabetically sorted list; internal handlers and permission callbacks are not returned.
```

### `Kora.commands.suggest(src, name, argumentIndex, query, parsedArgs?)`

Resolves static completions and a synchronous provider for one argument. The same command permission rule is checked before provider execution.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | positive integer player server ID. |
| `name` | string | registered command name, with or without leading /. |
| `argumentIndex` | integer | positive integer argument position. |
| `query` | string | typed prefix; non-string values become an empty prefix and strings are limited to 128 bytes. |
| `parsedArgs?` | array | optional dense array of up to 16 strings, each at most 128 bytes. |

**Returns**

- **suggestions** — array capped at 20 normalized entries shaped as &#123; value, label?, help? &#125;. Invalid input, unknown commands/arguments, or denied permission returns an empty array.

**Example**

```lua
local choices = Kora.commands.suggest(
    source, 'giveitem', 1, 'wat', { 'wat' }
)
```

**Representative console output**

```text
Returns matching suggestions, combining static values and provider output.
```

## Limits and related APIs

Commands are not a gameplay permission system by themselves. Use checkPermission to integrate the server’s authorization model. A non-user permission without a check fails closed. Names should be namespaced when collisions matter. A handler error is caught, logged, and not propagated.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/commands/docs.md` or `local/commands/docs.md`) that the reference above does not state.

### API

#### `Kora.commands.add(name, help, args, argsRequired, handler, opts)` -- server
Registers a command via `RegisterCommand`.

##### Example
```lua
Kora.commands.add('heal', 'Heal yourself', nil, false, function(source)
    -- ...
end, {
    permission = 'admin',
    checkPermission = function(source, permission)
        return IsPlayerAceAllowed(source, 'myresource.' .. permission)
    end,
    keybind = {
        description = 'Heal yourself',
        defaultKey = 'F7',
    },
})
```

The mapping invokes the command with no arguments through the same dispatcher
as `/heal`: permission checks, required-argument rejection, notifications, and
protected handler execution are identical. The server accepts keybind transport
only for a command that is still registered with `opts.keybind`.

Registration validates all public inputs before replacing a command or
publishing its suggestion. Command, permission, and resource names are
non-empty strings; command names cannot contain whitespace. `opts` must be a
table when supplied. `args`, when supplied, must be a dense array of tables
with a non-empty string `name` and optional string `help`. Handlers, permission
checks, and notification callbacks must be callable.

#### `Kora.commands.suggest(src, name, argumentIndex, query, parsedArgs)` -- server

Resolves an argument's static `values` and synchronous `provider`, after applying
the same permission check as command execution. Providers receive
`{command, argumentIndex, query, args}`. Results are normalized to
`{value, label?, help?}`, filtered case-insensitively, de-duplicated, and capped
at 20.

Suggestion requests require a positive integer player source and a positive
integer argument index. `parsedArgs`, when supplied, must be a dense array of
at most 16 strings, each at most 128 bytes. Invalid requests return an empty
list before command permissions or provider code are evaluated.
