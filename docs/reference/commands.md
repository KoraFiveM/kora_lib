---
title: "Commands module"
sidebar_position: 39
---

# Commands module

## Overview
Registers a chat command with owner-tracking (dead handlers are cleaned up automatically if the registering resource restarts) and chat-suggestion bookkeeping, with optional pluggable permission gating.

## API

### `Kora.commands.add(name, help, args, argsRequired, handler, opts)` -- server
Registers a command via `RegisterCommand`.

#### Parameters
- `name: string` -- a non-empty command name without whitespace.
- `help: string` -- shown in the chat suggestion.
- `args: {name: string, help: string, values?: (string | {value: string, label?: string, help?: string})[], provider?: function}[] | nil` -- chat-suggestion argument hints. `values` supplies static completions; synchronous `provider(source, context)` supplies live completions in the same shape. Callable providers remain server-side and are never serialized to clients.
- `argsRequired: boolean | nil` -- if true, running the command with fewer args than `#args` is rejected before `handler` runs.
- `handler: fun(source: integer, args: string[], raw: string)`
- `opts: table | nil`
  - `permission: string | nil` -- defaults to `'user'`. Anything else requires `checkPermission` to pass, or the command is denied.
  - `checkPermission: fun(source: integer, permission: string): boolean | nil`
  - `notify: fun(source: integer, message: string, type: string) | nil` -- called for the "no permission" / "missing arguments" messages. Defaults to `Kora.notify.send(source, {message=, type=})`.
  - `resource: string | nil` -- owning resource for cleanup purposes. Defaults to `GetInvokingResource() or GetCurrentResourceName()`.
  - `keybind: table | nil` -- mirrors the server command into a client key mapping:
    - `description?: string` -- defaults to command help/name.
    - `defaultKey?: string`, `defaultMapper?: string` -- primary mapping; mapper defaults to `keyboard`.
    - `secondaryKey?: string`, `secondaryMapper?: string` -- optional alternate mapping.

#### Example
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

### `Kora.commands.remove(name)` -- server
Unregisters the calling resource's command bookkeeping and chat suggestion, and
returns whether it existed. Does not un-register the underlying `RegisterCommand`
handler (FXServer has no API for that) -- the handler checks `commands[name]`
on every invocation and becomes a no-op once removed.

### `Kora.commands.refresh(src)` -- server
Re-sends every registered command's chat suggestion to one positive finite
integer player ID (e.g. on connect/reconnect), alphabetically by command name.

### `Kora.commands.list()` -- server
#### Returns
- `{name: string, help: string, permission: string, keybind?: table}[]`, sorted
  alphabetically by command name.

### `Kora.commands.suggest(src, name, argumentIndex, query, parsedArgs)` -- server

Resolves an argument's static `values` and synchronous `provider`, after applying
the same permission check as command execution. Providers receive
`{command, argumentIndex, query, args}`. Results are normalized to
`{value, label?, help?}`, filtered case-insensitively, de-duplicated, and capped
at 20.

Suggestion requests require a positive integer player source and a positive
integer argument index. `parsedArgs`, when supplied, must be a dense array of
at most 16 strings, each at most 128 bytes. Invalid requests return an empty
list before command permissions or provider code are evaluated.

## Notes
- Owner-tracked via `Kora.resources.serverRegistry`, keyed by command name: if the resource that registered a command stops (crash or restart) without calling `remove` itself, the command and its chat suggestion are cleaned up automatically.
- Registering an existing command name replaces its handler and transfers ownership to the new resource. This supports deliberate overrides, but command names are server-global: namespace names such as `myresource:heal` where a collision would be unsafe or confusing.
- Keybind sync and execution events accept only a positive finite integer player
  source before they read command state. The normal server console command path
  remains separate and continues to use source `0`.
- Key mappings synchronize on registration, replacement, removal, kora_lib client
  startup, and explicit late-client sync. User-command mappings broadcast once;
  non-user mappings are delivered only after their `checkPermission` accepts
  that player. FiveM owns the persistent settings row; removing a command makes
  its native row inert.
- A command with no `checkPermission` and a non-`'user'` `permission` is always denied -- there's no framework-level permission system in kora_lib to fall back on, so an ungated non-default permission fails closed rather than silently allowing everyone.
- A `handler` error is caught and logged (`print`), not propagated -- one broken command can't take down whatever fired it.
