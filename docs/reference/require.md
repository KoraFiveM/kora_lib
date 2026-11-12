---
title: "Require"
sidebar_position: 51
---

# Require

`Kora.require` loads Lua modules from resource files on both the client and
server. Paths are relative to the target resource root. A missing `.lua`
extension is added automatically, with `<path>/init.lua` as a fallback.

Each module runs once per consumer resource and should return its public value.
As with Lua's built-in `require`, a module that returns nothing resolves to
`true`. Cached modules are discarded when their source resource stops.

## Load from a named resource

Pass a string to load one module:

```lua
local config = Kora.require.load('kora_apartments', 'config')
```

Pass an ordered array to receive one return value per module:

```lua
local config, data, params = Kora.require.load('kora_apartments', {
    'config',
    'public/data',
    'params',
})
```

## Load from the current resource

```lua
local config = Kora.require.current('config')
```

`local` is a reserved Lua keyword, so `Kora.require.local(...)` is not valid Lua
syntax. The same alias is available with bracket notation when that wording is
preferred:

```lua
local config = Kora.require['local']('config')
```

On the client, the target files must be included in the target resource's
`files` manifest entry so FiveM makes them available to `LoadResourceFile`.
Required chunks execute in the consumer's Lua environment, matching ordinary
`require` behavior; avoid modules whose only purpose is to mutate globals.

Resource names and paths are validated before any file read. Resource names
cannot be `.` or `..`, or contain `@`, slashes, or control characters; module
paths are relative, cannot contain empty, `.` or `..` segments, and cannot use
backslashes. This keeps `LoadResourceFile` scoped to the intended resource.
