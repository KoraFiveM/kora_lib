---
title: "Require"
sidebar_position: 51
---


# Require

Require lets a resource load a Lua file from itself or another resource and use the value that file returns. Each file runs once per consuming resource; later loads return the saved result. This is useful for sharing configuration tables or helper functions without copying the file.

Namespace: `Kora.require` · Source: `modules/require/loader.lua · init.lua`

## What goes inside a module file?

Put reusable values or functions in the file and return them. For example, a config module can return a table and the calling script stores it in a local variable. If a file returns nothing, Require returns true, matching Lua require behavior.

## Where does the file run?

The file executes inside the resource that requested it, not inside kora_lib. This lets the file use the consumer resource environment. Each consumer resource has its own cache.

## Path and error rules

Paths are relative and use forward slashes. The loader rejects absolute paths, dot/dot-dot path parts, empty path segments, backslashes, and control characters. On client, add target files to the resource files manifest so FiveM can read them. Circular imports raise an error. Failed files are removed from the loading cache so a later call can retry.

## Functions

Use load for a named resource and current for your own resource. Paths start at the resource root.

### `Kora.require.load(resource, paths)`

Loads one module or an ordered list of modules from another resource.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `resource` | string | Resource name such as kora_apartments. |
| `paths` | string \| string[] | Relative path or dense ordered list. The .lua ending is optional; path/init.lua is tried as fallback. |

**Returns**

- **value** — returned value for one path.
- **...values** — one returned value per requested path, in list order.

**Example**

```lua
local config = Kora.require.load('kora_apartments', 'config')
local configAgain = Kora.require.load('kora_apartments', 'config')
```

**Representative console output**

```text
The module runs on the first call. The second call returns the cached result.
```

### `Kora.require.current(paths)`

Loads module file(s) from the resource that included @kora_lib/init.lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `paths` | string \| string[] | Relative path or dense ordered list of paths. |

**Returns**

- **value** — module result; multiple values when paths is a list.

**Example**

```lua
local config, data = Kora.require.current({ 'config', 'public/data' })
```

**Representative console output**

```text
Returns config.lua and public/data.lua (or public/data/init.lua) in the same order.
```

### `Kora.require[local](paths)`

Bracket-notation alias for current. Lua reserves the word local, so Kora.require.local(...) is not valid Lua.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `paths` | string \| string[] | Same as current. |

**Returns**

- **value** — same results as current.

**Example**

```lua
local config = Kora.require['local']('config')
```

**Representative console output**

```text
Loads a module from the current resource. Prefer current because it reads clearly.
```

## Limits and related APIs

When a loaded resource stops, its cached module values are cleared. Avoid modules that only change globals; return a public value instead.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/require/docs.md` or `local/require/docs.md`) that the reference above does not state.

`Kora.require` loads Lua modules from resource files on both the client and
server. Paths are relative to the target resource root. A missing `.lua`
extension is added automatically, with `<path>/init.lua` as a fallback.

Each module runs once per consumer resource and should return its public value.
As with Lua's built-in `require`, a module that returns nothing resolves to
`true`. Cached modules are discarded when their source resource stops.

### Load from a named resource

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

### Load from the current resource

```lua
local config = Kora.require.current('config')
```

`local` is a reserved Lua keyword, so `Kora.require.local(...)` is not valid Lua
syntax. The same alias is available with bracket notation when that wording is
preferred:

On the client, the target files must be included in the target resource's
`files` manifest entry so FiveM makes them available to `LoadResourceFile`.
Required chunks execute in the consumer's Lua environment, matching ordinary
`require` behavior; avoid modules whose only purpose is to mutate globals.

Resource names and paths are validated before any file read. Resource names
cannot be `.` or `..`, or contain `@`, slashes, or control characters; module
paths are relative, cannot contain empty, `.` or `..` segments, and cannot use
backslashes. This keeps `LoadResourceFile` scoped to the intended resource.
