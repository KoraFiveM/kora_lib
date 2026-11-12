---
title: "Keybind module"
sidebar_position: 13
---

# Keybind module

## `Kora.keybind.add(options) -> handle` — client

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

## `Kora.keybind.remove(name)` — client

Removes the calling resource's current live definition and returns whether it
existed. Another resource's binding returns `false` unchanged.

## `Kora.keybind.list()` — client

Returns sorted registration/state metadata without exposing callback functions.
