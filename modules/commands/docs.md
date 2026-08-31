# Commands module

## Overview
Registers a chat command with owner-tracking (dead handlers are cleaned up automatically if the registering resource restarts) and chat-suggestion bookkeeping, with optional pluggable permission gating.

## API

### `QB.commands.add(name, help, args, argsRequired, handler, opts)` -- server
Registers a command via `RegisterCommand`.

#### Parameters
- `name: string`
- `help: string` -- shown in the chat suggestion.
- `args: {name: string, help: string, values?: (string | {value: string, label?: string, help?: string})[], provider?: function}[] | nil` -- chat-suggestion argument hints. `values` supplies static completions; synchronous `provider(source, context)` supplies live completions in the same shape. Callable providers remain server-side and are never serialized to clients.
- `argsRequired: boolean | nil` -- if true, running the command with fewer args than `#args` is rejected before `handler` runs.
- `handler: fun(source: integer, args: string[], raw: string)`
- `opts: table | nil`
  - `permission: string | nil` -- defaults to `'user'`. Anything else requires `checkPermission` to pass, or the command is denied.
  - `checkPermission: fun(source: integer, permission: string): boolean | nil`
  - `notify: fun(source: integer, message: string, type: string) | nil` -- called for the "no permission" / "missing arguments" messages. Defaults to `QB.notify.send(source, {message=, type=})`.
  - `resource: string | nil` -- owning resource for cleanup purposes. Defaults to `GetInvokingResource() or GetCurrentResourceName()`.
  - `keybind: table | nil` -- mirrors the server command into a client key mapping:
    - `description?: string` -- defaults to command help/name.
    - `defaultKey?: string`, `defaultMapper?: string` -- primary mapping; mapper defaults to `keyboard`.
    - `secondaryKey?: string`, `secondaryMapper?: string` -- optional alternate mapping.

#### Example
```lua
QB.commands.add('heal', 'Heal yourself', nil, false, function(source)
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

### `QB.commands.remove(name)` -- server
Unregisters a command's bookkeeping and chat suggestion. Does not un-register the underlying `RegisterCommand` handler (FXServer has no API for that) -- the handler checks `commands[name]` on every invocation and becomes a no-op once removed.

### `QB.commands.refresh(src)` -- server
Re-sends every registered command's chat suggestion to one player (e.g. on connect/reconnect).

### `QB.commands.list()` -- server
#### Returns
- `{name: string, help: string, permission: string, keybind?: table}[]`

### `QB.commands.suggest(src, name, argumentIndex, query, parsedArgs)` -- server

Resolves an argument's static `values` and synchronous `provider`, after applying
the same permission check as command execution. Providers receive
`{command, argumentIndex, query, args}`. Results are normalized to
`{value, label?, help?}`, filtered case-insensitively, de-duplicated, and capped
at 20.

## Notes
- Owner-tracked via `QB.resources.serverRegistry`, keyed by command name: if the resource that registered a command stops (crash or restart) without calling `remove` itself, the command and its chat suggestion are cleaned up automatically.
- Key mappings synchronize on registration, replacement, removal, qblib client
  startup, and explicit late-client sync. FiveM owns the persistent settings
  row; removing a command makes its native row inert.
- A command with no `checkPermission` and a non-`'user'` `permission` is always denied -- there's no framework-level permission system in qblib to fall back on, so an ungated non-default permission fails closed rather than silently allowing everyone.
- A `handler` error is caught and logged (`print`), not propagated -- one broken command can't take down whatever fired it.
