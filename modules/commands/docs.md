# Commands module

## Overview
Registers a chat command with owner-tracking (dead handlers are cleaned up automatically if the registering resource restarts) and chat-suggestion bookkeeping, with optional pluggable permission gating.

## API

### `QB.commands.add(name, help, args, argsRequired, handler, opts)` -- server
Registers a command via `RegisterCommand`.

#### Parameters
- `name: string`
- `help: string` -- shown in the chat suggestion.
- `args: {name: string, help: string}[] | nil` -- chat-suggestion argument hints.
- `argsRequired: boolean | nil` -- if true, running the command with fewer args than `#args` is rejected before `handler` runs.
- `handler: fun(source: integer, args: string[], raw: string)`
- `opts: table | nil`
  - `permission: string | nil` -- defaults to `'user'`. Anything else requires `checkPermission` to pass, or the command is denied.
  - `checkPermission: fun(source: integer, permission: string): boolean | nil`
  - `notify: fun(source: integer, message: string, type: string) | nil` -- called for the "no permission" / "missing arguments" messages. Defaults to `QB.notify.send(source, {message=, type=})`.
  - `resource: string | nil` -- owning resource for cleanup purposes. Defaults to `GetInvokingResource() or GetCurrentResourceName()`.

#### Example
```lua
QB.commands.add('heal', 'Heal yourself', nil, false, function(source)
    -- ...
end, {
    permission = 'admin',
    checkPermission = function(source, permission)
        return IsPlayerAceAllowed(source, 'myresource.' .. permission)
    end,
})
```

### `QB.commands.remove(name)` -- server
Unregisters a command's bookkeeping and chat suggestion. Does not un-register the underlying `RegisterCommand` handler (FXServer has no API for that) -- the handler checks `commands[name]` on every invocation and becomes a no-op once removed.

### `QB.commands.refresh(src)` -- server
Re-sends every registered command's chat suggestion to one player (e.g. on connect/reconnect).

### `QB.commands.list()` -- server
#### Returns
- `{name: string, help: string, permission: string}[]`

## Notes
- Owner-tracked via `QB.resources.serverRegistry`, keyed by command name: if the resource that registered a command stops (crash or restart) without calling `remove` itself, the command and its chat suggestion are cleaned up automatically.
- A command with no `checkPermission` and a non-`'user'` `permission` is always denied -- there's no framework-level permission system in qblib to fall back on, so an ungated non-default permission fails closed rather than silently allowing everyone.
- A `handler` error is caught and logged (`print`), not propagated -- one broken command can't take down whatever fired it.
