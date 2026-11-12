---
title: "Keybind"
sidebar_position: 13
---


# Keybind

Registers rebindable FiveM press/release actions with primary and optional secondary keys. Handles expose live disabled/pressed state, current binding text, and removal.

Namespace: `Kora.keybind` · Source: `modules/keybind/client.lua`

## How it works

The stable +command/-command wrappers remain registered because FiveM cannot remove native mappings individually. Removing a Kora definition makes the wrappers inert; registering the same name again activates the stable mapping with the new callbacks. Ownership cleanup removes definitions when a resource stops.

## Registration fields

Pass these fields in the options table supplied to add. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `name` | string | Required stable command name without whitespace. |
| `description` | string | Required non-empty label displayed in FiveM key-binding settings. |
| `defaultKey?` | string | Primary default key. Omit or use an empty string for unbound. |
| `defaultMapper?` | string | Primary mapper; defaults to keyboard. |
| `secondaryKey?` | string | Optional alternate key mapping. |
| `secondaryMapper?` | string | Mapper for secondaryKey; defaults to defaultMapper, then keyboard. |
| `disabled?` | boolean | Initial disabled state; only literal true starts disabled. |
| `onPressed?` | function | Called as onPressed(handle) on a valid press. |
| `onReleased?` | function | Called as onReleased(handle) on a valid release. |

## Handle methods

disable(toggle) requires a boolean; disabling clears pressed state without synthesizing a release callback. isDisabled() and isPressed() return live booleans. getCurrentBinding() returns FiveM’s primary display token or nil. remove() removes this exact handle instance, so a stale handle cannot remove a later replacement with the same name.

## Functions

This is a client API. add returns a handle; remove removes a registration owned by the calling resource; list returns sorted public metadata without callbacks.

### `Kora.keybind.add(options)`

Registers a key mapping and returns a handle for controlling and querying it.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `options?` | table | table with required name and description; optional defaultKey, defaultMapper, secondaryKey, secondaryMapper, disabled, onPressed, and onReleased fields. |

**Returns**

- **handle** — metadata plus disable(toggle), isDisabled(), isPressed(), getCurrentBinding(), and remove() methods.

**Example**

```lua
local bind = Kora.keybind.add({
    name = 'inventory',
    description = 'Open inventory',
    defaultKey = 'TAB',
    secondaryKey = 'I',
    onPressed = function(handle) print(handle.getCurrentBinding()) end,
    onReleased = function() closeInventory() end,
})
```

**Representative console output**

```text
Press and release callbacks receive the handle; both are optional.
```

### `Kora.keybind.remove(name)`

Removes the live binding named name if it belongs to the calling resource.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | non-empty stable binding name. |

**Returns**

- **removed** — boolean; false for missing or foreign-owned bindings.

**Example**

```lua
local removed = Kora.keybind.remove('inventory')
```

**Representative console output**

```text
The native key mapping may remain in FiveM settings but is inert until re-registered.
```

### `Kora.keybind.list()`

Returns public registration and state metadata sorted by name.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `—` |  | No parameters. |

**Returns**

- **bindings** — array containing name, description, defaults, owner, and live disabled/pressed state; callbacks are omitted.

**Example**

```lua
for _, bind in ipairs(Kora.keybind.list()) do print(bind.name, bind.isPressed) end
```

**Representative console output**

```text
Sorted metadata for the current client registrations.
```

## Limits and related APIs

Callback errors are caught and logged. Press events are ignored while disabled, already pressed, or while the pause menu is active. A secondary mapping uses FiveM’s alternate ~!+command form.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/keybind/docs.md` or `local/keybind/docs.md`) that the reference above does not state.

### `Kora.keybind.add(options) -> handle` — client

Registers a stable FiveM press/release command pair and user-rebindable mapping.

```lua
local bind = Kora.keybind.add({
    name = 'inventory',
    description = 'Open inventory',
    defaultKey = 'TAB',
    secondaryKey = 'I',
    onPressed = function(handle)
        print('pressed', handle.getCurrentBinding())
    end,
    onReleased = function()
        print('released')
    end,
})
```

Options:

- `name`: stable non-empty command name without whitespace.
- `description`: label shown in FiveM key-binding settings.
- `defaultKey`: primary default key; omit or use an empty string for unbound.
- `defaultMapper`: mapper such as `keyboard`; defaults to `keyboard`.
- `secondaryKey` / `secondaryMapper`: optional alternate mapping registered
  through FiveM's `~!+command` form.
- `disabled`: optional initial disabled state.
- `onPressed(handle)` and `onReleased(handle)`: either or both may be supplied.

The returned handle contains registration metadata and these methods:

- `disable(toggle)` updates the disabled state; disabling also clears held state.
- `isDisabled()` and `isPressed()` read live state.
- `getCurrentBinding()` returns FiveM's current primary display token, or `nil`.
- `remove()` removes this exact registration without affecting a later replacement.

Callbacks are protected with `pcall`. Disabling while pressed clears the held
state without firing a synthetic release. Re-registering a stable name replaces
its callbacks. A stopped owning resource is cleaned up automatically. FiveM
cannot unregister a native mapping individually, so removed settings entries
remain inert until kora_lib stops or the stable name is re-added.

### `Kora.keybind.remove(name)` — client

Removes the calling resource's current live definition and returns whether it
existed. Another resource's binding returns `false` unchanged.

### `Kora.keybind.list()` — client

Returns sorted registration/state metadata without exposing callback functions.
