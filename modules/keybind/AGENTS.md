# keybind module guide

## Purpose
Client-side, owner-tracked FiveM `+command`/`-command` mappings with press and
release callbacks, live disabled/pressed state, primary and secondary defaults,
and resource-stop cleanup. The same registry hosts server-owned command
keybindings synchronized by `QB.commands.add(..., { keybind = ... })`.

## Public API
- `QB.keybind.add(name, label, defaultKey, handler, mapper?) -> handle`
- `QB.keybind.remove(name)`
- `QB.keybind.list()`

The handle exposes `disable(toggle)`, `isDisabled()`, `isPressed()`,
`getCurrentBinding()`, and `remove()`. Callback errors are contained and logged.
An extended options-table form remains available for qblib's internal command
keybind synchronization.

## Native lifetime
FiveM cannot unregister individual commands or key mappings. Removing a binding
clears its owned definition and state, making the stable native wrappers inert.
Re-adding the same name activates those wrappers with the new callbacks. A
secondary mapping is registered once with the `~!+name` alternate form.

## Testing
`test/smoke/keybind.lua` covers press/release, disabled state, current binding,
secondary mappings, callback isolation, replacement, manual removal, command
mapping synchronization, and resource-owner cleanup.
