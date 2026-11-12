---
title: "Config"
sidebar_position: 2
---


# Config

## Client

Keeps an authored Lua Config table while registering typed, owner-editable settings for the in-game configuration workspace. kora_lib does not rewrite config.lua; the owning resource persists only overrides to config.local.lua.

Namespace: `Kora.config` · Source: `modules/config/client.lua · modules/config/consumer.lua · modules/config/editor_client.lua`

### How it works

Place the owner’s config.lua after @kora_lib/init.lua in shared_scripts so both realms declare the same base schema. Config values remain ordinary Lua values at use sites. Client snapshots contain only client/shared, sanitized fields; server-scoped and sensitive values are excluded.

### Field descriptor options

These metadata fields are passed as the second argument to scalar/object/list/map/optional descriptors. Type-specific fields are described in the API overview. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `label?` | string | Human-readable editor label. |
| `description?` | string | Explains the setting and its runtime effect. |
| `scope?` | string | shared by default; client or server controls distribution/ownership. |
| `live?` | boolean | When true, an accepted value can apply without restarting; defaults to restart required. |
| `min / max / step?` | number | Numeric bounds and increments. |
| `minLength / maxLength / pattern?` | string or number | String validation constraints. |
| `sensitive?` | boolean | Sensitive fields are never shown or changed in the in-game editor. |
| `advanced?` | boolean | Classifies a field for the workspace Advanced filter; it is not an access permission. |

### Schema kinds

Use boolean, string, integer, number, enum, color, vector2, vector3, vector4, object, list, map, and optional descriptors. enum uses options for allowed values; list/map take an item descriptor; map can set keyType and requiredKeys; optional wraps an inner descriptor and can explicitly clear a previously non-nil default.

### Live consumers

get returns a copied active value; bind calls immediately when a snapshot is ready and again when that path changes. bind returns an unsubscribe function. whenReady runs once all named snapshots arrive. Cache reads do not perform a database request at gameplay call sites.

### Functions

Owner-side consumer functions and typed schema constructors are available in the client realm. The root Config table is returned/retained by define, adopt, and extend.

#### `Kora.config.boolean(value, options?)`

Creates a typed boolean schema descriptor for a field in Config.define, Config.adopt, or Config.extend.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | boolean | Authored default value; it is validated against this descriptor kind. |
| `options?` | table | Optional labels, scope, validation constraints, editor behavior, and type-specific settings. |

**Returns**

- **descriptor** — schema descriptor consumed by define/adopt/extend; the owning Config value is returned as a plain Lua table.

**Example**

```lua
Config = Kora.config.define({ setting = Kora.config.boolean(true) })
```

**Representative console output**

```text
Returns a typed descriptor; invalid defaults or options are rejected when the schema is declared.
```

#### `Kora.config.string(value, options?)`

Creates a typed string schema descriptor for a field in Config.define, Config.adopt, or Config.extend.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | string | Authored default value; it is validated against this descriptor kind. |
| `options?` | table | Optional labels, scope, validation constraints, editor behavior, and type-specific settings. |

**Returns**

- **descriptor** — schema descriptor consumed by define/adopt/extend; the owning Config value is returned as a plain Lua table.

**Example**

```lua
Config = Kora.config.define({ setting = Kora.config.string('default') })
```

**Representative console output**

```text
Returns a typed descriptor; invalid defaults or options are rejected when the schema is declared.
```

#### `Kora.config.integer(value, options?)`

Creates a typed integer schema descriptor for a field in Config.define, Config.adopt, or Config.extend.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | integer | Authored default value; it is validated against this descriptor kind. |
| `options?` | table | Optional labels, scope, validation constraints, editor behavior, and type-specific settings. |

**Returns**

- **descriptor** — schema descriptor consumed by define/adopt/extend; the owning Config value is returned as a plain Lua table.

**Example**

```lua
Config = Kora.config.define({ setting = Kora.config.integer(1) })
```

**Representative console output**

```text
Returns a typed descriptor; invalid defaults or options are rejected when the schema is declared.
```

#### `Kora.config.number(value, options?)`

Creates a typed number schema descriptor for a field in Config.define, Config.adopt, or Config.extend.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | number | Authored default value; it is validated against this descriptor kind. |
| `options?` | table | Optional labels, scope, validation constraints, editor behavior, and type-specific settings. |

**Returns**

- **descriptor** — schema descriptor consumed by define/adopt/extend; the owning Config value is returned as a plain Lua table.

**Example**

```lua
Config = Kora.config.define({ setting = Kora.config.number(1) })
```

**Representative console output**

```text
Returns a typed descriptor; invalid defaults or options are rejected when the schema is declared.
```

#### `Kora.config.enum(value, options?)`

Creates a typed enum schema descriptor for a field in Config.define, Config.adopt, or Config.extend.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | enum | Authored default value; it is validated against this descriptor kind. |
| `options?` | table | Optional labels, scope, validation constraints, editor behavior, and type-specific settings. |

**Returns**

- **descriptor** — schema descriptor consumed by define/adopt/extend; the owning Config value is returned as a plain Lua table.

**Example**

```lua
Config = Kora.config.define({ setting = Kora.config.enum('basic', { options = { 'basic', 'advanced' } }) })
```

**Representative console output**

```text
Returns a typed descriptor; invalid defaults or options are rejected when the schema is declared.
```

#### `Kora.config.color(value, options?)`

Creates a typed color schema descriptor for a field in Config.define, Config.adopt, or Config.extend.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | color | Authored default value; it is validated against this descriptor kind. |
| `options?` | table | Optional labels, scope, validation constraints, editor behavior, and type-specific settings. |

**Returns**

- **descriptor** — schema descriptor consumed by define/adopt/extend; the owning Config value is returned as a plain Lua table.

**Example**

```lua
Config = Kora.config.define({ setting = Kora.config.color('#ffffff') })
```

**Representative console output**

```text
Returns a typed descriptor; invalid defaults or options are rejected when the schema is declared.
```

#### `Kora.config.vector2(value, options?)`

Creates a typed vector2 schema descriptor for a field in Config.define, Config.adopt, or Config.extend.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | vector2 | Authored default value; it is validated against this descriptor kind. |
| `options?` | table | Optional labels, scope, validation constraints, editor behavior, and type-specific settings. |

**Returns**

- **descriptor** — schema descriptor consumed by define/adopt/extend; the owning Config value is returned as a plain Lua table.

**Example**

```lua
Config = Kora.config.define({ setting = Kora.config.vector2(vector2(0.0, 0.0)) })
```

**Representative console output**

```text
Returns a typed descriptor; invalid defaults or options are rejected when the schema is declared.
```

#### `Kora.config.vector3(value, options?)`

Creates a typed vector3 schema descriptor for a field in Config.define, Config.adopt, or Config.extend.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | vector3 | Authored default value; it is validated against this descriptor kind. |
| `options?` | table | Optional labels, scope, validation constraints, editor behavior, and type-specific settings. |

**Returns**

- **descriptor** — schema descriptor consumed by define/adopt/extend; the owning Config value is returned as a plain Lua table.

**Example**

```lua
Config = Kora.config.define({ setting = Kora.config.vector3(vector3(0.0, 0.0, 0.0)) })
```

**Representative console output**

```text
Returns a typed descriptor; invalid defaults or options are rejected when the schema is declared.
```

#### `Kora.config.vector4(value, options?)`

Creates a typed vector4 schema descriptor for a field in Config.define, Config.adopt, or Config.extend.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | vector4 | Authored default value; it is validated against this descriptor kind. |
| `options?` | table | Optional labels, scope, validation constraints, editor behavior, and type-specific settings. |

**Returns**

- **descriptor** — schema descriptor consumed by define/adopt/extend; the owning Config value is returned as a plain Lua table.

**Example**

```lua
Config = Kora.config.define({ setting = Kora.config.vector4(vector4(0.0, 0.0, 0.0, 0.0)) })
```

**Representative console output**

```text
Returns a typed descriptor; invalid defaults or options are rejected when the schema is declared.
```

#### `Kora.config.object(value, options?)`

Creates a typed object schema descriptor for a field in Config.define, Config.adopt, or Config.extend.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | object | Authored default value; it is validated against this descriptor kind. |
| `options?` | table | Optional labels, scope, validation constraints, editor behavior, and type-specific settings. |

**Returns**

- **descriptor** — schema descriptor consumed by define/adopt/extend; the owning Config value is returned as a plain Lua table.

**Example**

```lua
Config = Kora.config.define({ setting = Kora.config.object({}) })
```

**Representative console output**

```text
Returns a typed descriptor; invalid defaults or options are rejected when the schema is declared.
```

#### `Kora.config.list(value, item, options?)`

Creates a typed list schema descriptor for a field in Config.define, Config.adopt, or Config.extend.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | list | Authored default value; it is validated against this descriptor kind. |
| `item` | descriptor | Schema descriptor applied to each collection entry. |
| `options?` | table | Optional labels, scope, validation constraints, editor behavior, and type-specific settings. |

**Returns**

- **descriptor** — schema descriptor consumed by define/adopt/extend; the owning Config value is returned as a plain Lua table.

**Example**

```lua
Config = Kora.config.define({ setting = Kora.config.list({}, Kora.config.string('')) })
```

**Representative console output**

```text
Returns a typed descriptor; invalid defaults or options are rejected when the schema is declared.
```

#### `Kora.config.map(value, item, options?)`

Creates a typed map schema descriptor for a field in Config.define, Config.adopt, or Config.extend.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | map | Authored default value; it is validated against this descriptor kind. |
| `item` | descriptor | Schema descriptor applied to each collection entry. |
| `options?` | table | Optional labels, scope, validation constraints, editor behavior, and type-specific settings. |

**Returns**

- **descriptor** — schema descriptor consumed by define/adopt/extend; the owning Config value is returned as a plain Lua table.

**Example**

```lua
Config = Kora.config.define({ setting = Kora.config.map({}, Kora.config.string('')) })
```

**Representative console output**

```text
Returns a typed descriptor; invalid defaults or options are rejected when the schema is declared.
```

#### `Kora.config.optional(value, inner, options?)`

Creates a typed optional schema descriptor for a field in Config.define, Config.adopt, or Config.extend.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | optional | Authored default value; it is validated against this descriptor kind. |
| `inner` | descriptor | Schema descriptor for a non-nil optional value. |
| `options?` | table | Optional labels, scope, validation constraints, editor behavior, and type-specific settings. |

**Returns**

- **descriptor** — schema descriptor consumed by define/adopt/extend; the owning Config value is returned as a plain Lua table.

**Example**

```lua
Config = Kora.config.define({ setting = Kora.config.optional(nil, Kora.config.string('default')) })
```

**Representative console output**

```text
Returns a typed descriptor; invalid defaults or options are rejected when the schema is declared.
```

#### `Kora.config.define(values, options?)`

Declares a typed schema and returns the ordinary Config values table used by the resource. The schema is validated and registered with the configuration workspace.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `values` | number | table of default values and typed descriptors. |
| `options?` | table | optional root settings including scope, descriptions, fileName, and mutation behavior. |

**Returns**

- **Config** — ordinary Lua table containing the active settings.

**Example**

```lua
Config = Kora.config.define({
    chat = {
        localRange = Kora.config.number(20.0, { min = 1, max = 100, live = true }),
        showDistance = Kora.config.boolean(true, { scope = 'client' }),
    },
})
```

**Representative console output**

```text
Config.chat.localRange remains a normal Lua number at use sites.
```

#### `Kora.config.adopt(values, options?)`

Registers an existing plain Config table as editable settings while preserving its public table shape. Unsupported values such as functions are skipped.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `values` | number | existing Config table. |
| `options?` | table | optional root metadata, descriptions, scope, and file settings. |

**Returns**

- **Config** — the same table is schema-annotated and returned.

**Example**

```lua
Config = { enabled = true, radius = 20 }
Kora.config.adopt(Config)
```

**Representative console output**

```text
Existing call sites continue to read Config.enabled and Config.radius.
```

#### `Kora.config.register(values, options?)`

Named equivalent of define for owner resources that prefer an explicit registration verb.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `values` | number | table of defaults and typed descriptors. |
| `options?` | table | optional schema options. |

**Returns**

- **Config** — ordinary active values table.

**Example**

```lua
Config = Kora.config.register({ enabled = Kora.config.boolean(true) })
```

**Representative console output**

```text
Declares and returns the owner Config table.
```

#### `Kora.config.extend(values, options?)`

Adds a server-only, client-only, or shared branch after define/adopt has registered the base schema.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `values?` | number | object table for the extension. options.scope — optional shared/client/server scope; defaults to shared. |

**Returns**

- **Config** — the merged active Config table.

**Example**

```lua
Kora.config.extend({ webhook = Kora.config.string('') }, { scope = 'server' })
```

**Representative console output**

```text
The extension branch is merged into the owner schema while excluded from the opposite realm snapshot when scoped.
```

#### `Kora.config.onChange(path, handler)`

Registers an owner-side callback for changes to one configuration path.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `path` | number | non-empty dotted configuration path. |
| `handler` | function | function(value, previous); return false to reject the change. |

**Returns**

- **return** — no value.

**Example**

```lua
Kora.config.onChange('chat.localRange', function(value, previous)
    rebuildChat(value)
end)
```

**Representative console output**

```text
The handler runs for relevant updates; changes are rejected when it returns false.
```

#### `Kora.config.get(resourceOrPath, path?)`

Returns the active local snapshot value for a resource and path. Tables are copied so callers cannot mutate the shared cache. With one argument, that argument is treated as a path in the current resource.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `resourceOrPath` | number | current-resource path, or resource name when path is also supplied. |
| `path?` | array | optional path string or array for the named resource. |

**Returns**

- **value** — copied setting value, or nil, not_ready before the snapshot arrives.

**Example**

```lua
local range, err = Kora.config.get('kora_target', 'target.distance')
if err == 'not_ready' then return end
```

**Representative console output**

```text
Reads the current cached value without a database or export call.
```

#### `Kora.config.bind(resource, path, handler)`

Subscribes to an owner’s active setting. The handler receives the initial value and later changes; returns an unsubscribe function.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `resource` | number | non-empty owner resource name. |
| `path` | array | setting path string or array. |
| `handler` | function | function(value, previous, metadata). |

**Returns**

- **unsubscribe** — function that removes this binding.

**Example**

```lua
local unbind = Kora.config.bind('kora_target', 'target.distance', function(value)
    rebuildTargeting(value)
end)
```

**Representative console output**

```text
The initial callback runs when a snapshot is available; future relevant active updates invoke it again.
```

#### `Kora.config.whenReady(resources, handler)`

Runs a handler once after all listed configuration snapshots are ready.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `resources` | array | array of resource names. |
| `handler` | function | zero-argument function. |

**Returns**

- **return** — no value.

**Example**

```lua
Kora.config.whenReady({ 'kora_target', 'kora_hud' }, function()
    startIntegrations()
end)
```

**Representative console output**

```text
Runs once when every requested resource is ready.
```

#### `Kora.config.open(resource?)`

Opens the configuration workspace, optionally focused on one registered resource.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `resource?` | number | optional resource name to open directly. |

**Returns**

- **return** — no value; opens the in-game workspace UI.

**Example**

```lua
Kora.config.open('kora_target')
```

**Representative console output**

```text
Requires the workspace ACE permission.
```

### Limits and related APIs

Every authored default and bound is validated when the schema is declared. Do not register secrets, convars, database-managed data, executable values, or runtime state. Client scope is presentation/data distribution, not authorization; server-side validation still governs gameplay.

## Server

Server-side configuration catalog and persistence coordinator. Resources own their own config.local.lua files; kora_lib validates editor requests and delegates saves/resets back through the owning resource bridge.

Namespace: `Kora.config` · Source: `modules/config/server.lua · modules/config/consumer.lua · modules/config/editor_server.lua`

### How it works

The server returns sanitized schemas for the workspace, enforces ACE access, verifies revisions to reject stale edits, and excludes server-scoped/sensitive data from client snapshots. Live server handlers can validate and apply changes. Restart-required changes remain saved but do not change the active value until resource restart.

### Persistence and revisions

Each resource reads known overrides from its own config.local.lua at startup and writes only its own file through SaveResourceFile. The server sends edit requests to the owner bridge and checks the returned revision before publishing changes. The previous override file is retained as config.local.lua.bak. Add generated override and backup files to the owner’s .gitignore.

### Permissions

Grant workspace access explicitly with add_ace &lt;principal> kora_lib.config.edit allow. The deprecated kora_lib.config.edit ACE is still honored. Advanced is only a display filter, not permission control.

### Functions

Use the owner-side consumer functions to declare a schema and hooks. Catalog/read/commit/reset are privileged workspace integration APIs; ordinary resources normally use define/adopt and bind/get instead.

#### `Kora.config.boolean(value, options?)`

Creates a typed boolean schema descriptor for a field in Config.define, Config.adopt, or Config.extend.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | boolean | Authored default value; it is validated against this descriptor kind. |
| `options?` | table | Optional labels, scope, validation constraints, editor behavior, and type-specific settings. |

**Returns**

- **descriptor** — schema descriptor consumed by define/adopt/extend; the owning Config value is returned as a plain Lua table.

**Example**

```lua
Config = Kora.config.define({ setting = Kora.config.boolean(true) })
```

**Representative console output**

```text
Returns a typed descriptor; invalid defaults or options are rejected when the schema is declared.
```

#### `Kora.config.string(value, options?)`

Creates a typed string schema descriptor for a field in Config.define, Config.adopt, or Config.extend.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | string | Authored default value; it is validated against this descriptor kind. |
| `options?` | table | Optional labels, scope, validation constraints, editor behavior, and type-specific settings. |

**Returns**

- **descriptor** — schema descriptor consumed by define/adopt/extend; the owning Config value is returned as a plain Lua table.

**Example**

```lua
Config = Kora.config.define({ setting = Kora.config.string('default') })
```

**Representative console output**

```text
Returns a typed descriptor; invalid defaults or options are rejected when the schema is declared.
```

#### `Kora.config.integer(value, options?)`

Creates a typed integer schema descriptor for a field in Config.define, Config.adopt, or Config.extend.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | integer | Authored default value; it is validated against this descriptor kind. |
| `options?` | table | Optional labels, scope, validation constraints, editor behavior, and type-specific settings. |

**Returns**

- **descriptor** — schema descriptor consumed by define/adopt/extend; the owning Config value is returned as a plain Lua table.

**Example**

```lua
Config = Kora.config.define({ setting = Kora.config.integer(1) })
```

**Representative console output**

```text
Returns a typed descriptor; invalid defaults or options are rejected when the schema is declared.
```

#### `Kora.config.number(value, options?)`

Creates a typed number schema descriptor for a field in Config.define, Config.adopt, or Config.extend.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | number | Authored default value; it is validated against this descriptor kind. |
| `options?` | table | Optional labels, scope, validation constraints, editor behavior, and type-specific settings. |

**Returns**

- **descriptor** — schema descriptor consumed by define/adopt/extend; the owning Config value is returned as a plain Lua table.

**Example**

```lua
Config = Kora.config.define({ setting = Kora.config.number(1) })
```

**Representative console output**

```text
Returns a typed descriptor; invalid defaults or options are rejected when the schema is declared.
```

#### `Kora.config.enum(value, options?)`

Creates a typed enum schema descriptor for a field in Config.define, Config.adopt, or Config.extend.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | enum | Authored default value; it is validated against this descriptor kind. |
| `options?` | table | Optional labels, scope, validation constraints, editor behavior, and type-specific settings. |

**Returns**

- **descriptor** — schema descriptor consumed by define/adopt/extend; the owning Config value is returned as a plain Lua table.

**Example**

```lua
Config = Kora.config.define({ setting = Kora.config.enum('basic', { options = { 'basic', 'advanced' } }) })
```

**Representative console output**

```text
Returns a typed descriptor; invalid defaults or options are rejected when the schema is declared.
```

#### `Kora.config.color(value, options?)`

Creates a typed color schema descriptor for a field in Config.define, Config.adopt, or Config.extend.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | color | Authored default value; it is validated against this descriptor kind. |
| `options?` | table | Optional labels, scope, validation constraints, editor behavior, and type-specific settings. |

**Returns**

- **descriptor** — schema descriptor consumed by define/adopt/extend; the owning Config value is returned as a plain Lua table.

**Example**

```lua
Config = Kora.config.define({ setting = Kora.config.color('#ffffff') })
```

**Representative console output**

```text
Returns a typed descriptor; invalid defaults or options are rejected when the schema is declared.
```

#### `Kora.config.vector2(value, options?)`

Creates a typed vector2 schema descriptor for a field in Config.define, Config.adopt, or Config.extend.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | vector2 | Authored default value; it is validated against this descriptor kind. |
| `options?` | table | Optional labels, scope, validation constraints, editor behavior, and type-specific settings. |

**Returns**

- **descriptor** — schema descriptor consumed by define/adopt/extend; the owning Config value is returned as a plain Lua table.

**Example**

```lua
Config = Kora.config.define({ setting = Kora.config.vector2(vector2(0.0, 0.0)) })
```

**Representative console output**

```text
Returns a typed descriptor; invalid defaults or options are rejected when the schema is declared.
```

#### `Kora.config.vector3(value, options?)`

Creates a typed vector3 schema descriptor for a field in Config.define, Config.adopt, or Config.extend.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | vector3 | Authored default value; it is validated against this descriptor kind. |
| `options?` | table | Optional labels, scope, validation constraints, editor behavior, and type-specific settings. |

**Returns**

- **descriptor** — schema descriptor consumed by define/adopt/extend; the owning Config value is returned as a plain Lua table.

**Example**

```lua
Config = Kora.config.define({ setting = Kora.config.vector3(vector3(0.0, 0.0, 0.0)) })
```

**Representative console output**

```text
Returns a typed descriptor; invalid defaults or options are rejected when the schema is declared.
```

#### `Kora.config.vector4(value, options?)`

Creates a typed vector4 schema descriptor for a field in Config.define, Config.adopt, or Config.extend.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | vector4 | Authored default value; it is validated against this descriptor kind. |
| `options?` | table | Optional labels, scope, validation constraints, editor behavior, and type-specific settings. |

**Returns**

- **descriptor** — schema descriptor consumed by define/adopt/extend; the owning Config value is returned as a plain Lua table.

**Example**

```lua
Config = Kora.config.define({ setting = Kora.config.vector4(vector4(0.0, 0.0, 0.0, 0.0)) })
```

**Representative console output**

```text
Returns a typed descriptor; invalid defaults or options are rejected when the schema is declared.
```

#### `Kora.config.object(value, options?)`

Creates a typed object schema descriptor for a field in Config.define, Config.adopt, or Config.extend.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | object | Authored default value; it is validated against this descriptor kind. |
| `options?` | table | Optional labels, scope, validation constraints, editor behavior, and type-specific settings. |

**Returns**

- **descriptor** — schema descriptor consumed by define/adopt/extend; the owning Config value is returned as a plain Lua table.

**Example**

```lua
Config = Kora.config.define({ setting = Kora.config.object({}) })
```

**Representative console output**

```text
Returns a typed descriptor; invalid defaults or options are rejected when the schema is declared.
```

#### `Kora.config.list(value, item, options?)`

Creates a typed list schema descriptor for a field in Config.define, Config.adopt, or Config.extend.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | list | Authored default value; it is validated against this descriptor kind. |
| `item` | descriptor | Schema descriptor applied to each collection entry. |
| `options?` | table | Optional labels, scope, validation constraints, editor behavior, and type-specific settings. |

**Returns**

- **descriptor** — schema descriptor consumed by define/adopt/extend; the owning Config value is returned as a plain Lua table.

**Example**

```lua
Config = Kora.config.define({ setting = Kora.config.list({}, Kora.config.string('')) })
```

**Representative console output**

```text
Returns a typed descriptor; invalid defaults or options are rejected when the schema is declared.
```

#### `Kora.config.map(value, item, options?)`

Creates a typed map schema descriptor for a field in Config.define, Config.adopt, or Config.extend.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | map | Authored default value; it is validated against this descriptor kind. |
| `item` | descriptor | Schema descriptor applied to each collection entry. |
| `options?` | table | Optional labels, scope, validation constraints, editor behavior, and type-specific settings. |

**Returns**

- **descriptor** — schema descriptor consumed by define/adopt/extend; the owning Config value is returned as a plain Lua table.

**Example**

```lua
Config = Kora.config.define({ setting = Kora.config.map({}, Kora.config.string('')) })
```

**Representative console output**

```text
Returns a typed descriptor; invalid defaults or options are rejected when the schema is declared.
```

#### `Kora.config.optional(value, inner, options?)`

Creates a typed optional schema descriptor for a field in Config.define, Config.adopt, or Config.extend.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | optional | Authored default value; it is validated against this descriptor kind. |
| `inner` | descriptor | Schema descriptor for a non-nil optional value. |
| `options?` | table | Optional labels, scope, validation constraints, editor behavior, and type-specific settings. |

**Returns**

- **descriptor** — schema descriptor consumed by define/adopt/extend; the owning Config value is returned as a plain Lua table.

**Example**

```lua
Config = Kora.config.define({ setting = Kora.config.optional(nil, Kora.config.string('default')) })
```

**Representative console output**

```text
Returns a typed descriptor; invalid defaults or options are rejected when the schema is declared.
```

#### `Kora.config.define(values, options?)`

Declares a typed schema and returns the ordinary Config values table used by the resource. The schema is validated and registered with the configuration workspace.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `values` | number | table of default values and typed descriptors. |
| `options?` | table | optional root settings including scope, descriptions, fileName, and mutation behavior. |

**Returns**

- **Config** — ordinary Lua table containing the active settings.

**Example**

```lua
Config = Kora.config.define({
    chat = {
        localRange = Kora.config.number(20.0, { min = 1, max = 100, live = true }),
        showDistance = Kora.config.boolean(true, { scope = 'client' }),
    },
})
```

**Representative console output**

```text
Config.chat.localRange remains a normal Lua number at use sites.
```

#### `Kora.config.adopt(values, options?)`

Registers an existing plain Config table as editable settings while preserving its public table shape. Unsupported values such as functions are skipped.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `values` | number | existing Config table. |
| `options?` | table | optional root metadata, descriptions, scope, and file settings. |

**Returns**

- **Config** — the same table is schema-annotated and returned.

**Example**

```lua
Config = { enabled = true, radius = 20 }
Kora.config.adopt(Config)
```

**Representative console output**

```text
Existing call sites continue to read Config.enabled and Config.radius.
```

#### `Kora.config.register(values, options?)`

Named equivalent of define for owner resources that prefer an explicit registration verb.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `values` | number | table of defaults and typed descriptors. |
| `options?` | table | optional schema options. |

**Returns**

- **Config** — ordinary active values table.

**Example**

```lua
Config = Kora.config.register({ enabled = Kora.config.boolean(true) })
```

**Representative console output**

```text
Declares and returns the owner Config table.
```

#### `Kora.config.extend(values, options?)`

Adds a server-only, client-only, or shared branch after define/adopt has registered the base schema.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `values?` | number | object table for the extension. options.scope — optional shared/client/server scope; defaults to shared. |

**Returns**

- **Config** — the merged active Config table.

**Example**

```lua
Kora.config.extend({ webhook = Kora.config.string('') }, { scope = 'server' })
```

**Representative console output**

```text
The extension branch is merged into the owner schema while excluded from the opposite realm snapshot when scoped.
```

#### `Kora.config.onChange(path, handler)`

Registers an owner-side callback for changes to one configuration path.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `path` | number | non-empty dotted configuration path. |
| `handler` | function | function(value, previous); return false to reject the change. |

**Returns**

- **return** — no value.

**Example**

```lua
Kora.config.onChange('chat.localRange', function(value, previous)
    rebuildChat(value)
end)
```

**Representative console output**

```text
The handler runs for relevant updates; changes are rejected when it returns false.
```

#### `Kora.config.get(resourceOrPath, path?)`

Returns the active local snapshot value for a resource and path. Tables are copied so callers cannot mutate the shared cache. With one argument, that argument is treated as a path in the current resource.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `resourceOrPath` | number | current-resource path, or resource name when path is also supplied. |
| `path?` | array | optional path string or array for the named resource. |

**Returns**

- **value** — copied setting value, or nil, not_ready before the snapshot arrives.

**Example**

```lua
local range, err = Kora.config.get('kora_target', 'target.distance')
if err == 'not_ready' then return end
```

**Representative console output**

```text
Reads the current cached value without a database or export call.
```

#### `Kora.config.bind(resource, path, handler)`

Subscribes to an owner’s active setting. The handler receives the initial value and later changes; returns an unsubscribe function.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `resource` | number | non-empty owner resource name. |
| `path` | array | setting path string or array. |
| `handler` | function | function(value, previous, metadata). |

**Returns**

- **unsubscribe** — function that removes this binding.

**Example**

```lua
local unbind = Kora.config.bind('kora_target', 'target.distance', function(value)
    rebuildTargeting(value)
end)
```

**Representative console output**

```text
The initial callback runs when a snapshot is available; future relevant active updates invoke it again.
```

#### `Kora.config.whenReady(resources, handler)`

Runs a handler once after all listed configuration snapshots are ready.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `resources` | array | array of resource names. |
| `handler` | function | zero-argument function. |

**Returns**

- **return** — no value.

**Example**

```lua
Kora.config.whenReady({ 'kora_target', 'kora_hud' }, function()
    startIntegrations()
end)
```

**Representative console output**

```text
Runs once when every requested resource is ready.
```

#### `Kora.config.onValidate(handler)`

Registers a server-only validator for a complete proposed configuration snapshot.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `handler` | function | function receiving the proposed snapshot; return false or an error result to reject the commit. |

**Returns**

- **return** — no value.

**Example**

```lua
Kora.config.onValidate(function(proposed)
    return proposed.chat.localRange <= 100
end)
```

**Representative console output**

```text
Runs only on the owning server before an eligible save is accepted.
```

#### `Kora.config.onApply(handler)`

Registers a server-only hook to reconfigure server behavior for accepted live changes.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `handler` | function | function receiving new and previous values as provided by the bridge. |

**Returns**

- **return** — no value.

**Example**

```lua
Kora.config.onApply(function(value, previous)
    rebuildService(value, previous)
end)
```

**Representative console output**

```text
Server-scoped fields can invoke server apply hooks; client-scoped fields do not.
```

#### `Kora.config.catalog()`

Lists registered resource schemas for privileged workspace integrations.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `—` |  | No parameters. |

**Returns**

- **entries** — array of registered resource catalog summaries.

**Example**

```lua
local resources = Kora.config.catalog()
```

**Representative console output**

```text
Server-only; requires the configuration editor permission.
```

#### `Kora.config.read(resource)`

Reads a resource schema, configured values, active values, and revision.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `resource` | number | registered resource name. |

**Returns**

- **entry** — schema and values table, or nil when the resource is not registered.

**Example**

```lua
local entry = Kora.config.read('kora_target')
```

**Representative console output**

```text
Server-only privileged API; values are returned from the registered owner bridge.
```

#### `Kora.config.commit(resource, request)`

Validates and delegates a settings save to the resource that owns the configuration file.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `resource` | number | registered owner name. |
| `request` | array | table containing path array, proposed value, and positive integer revision. |

**Returns**

- **response** — result table with ok, revision, and optional error.

**Example**

```lua
local result = Kora.config.commit('kora_target', { path = { 'target', 'distance' }, value = 3.0, revision = 4 })
```

**Representative console output**

```text
Rejects invalid or stale revisions and never writes another resource’s files directly.
```

#### `Kora.config.reset(resource, request)`

Delegates removal of one saved override to its owning resource.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `resource` | number | registered owner name. |
| `request` | array | table containing path array and positive integer revision. |

**Returns**

- **response** — result table with ok, revision, and optional error.

**Example**

```lua
local result = Kora.config.reset('kora_target', { path = { 'target', 'distance' }, revision = 4 })
```

**Representative console output**

```text
Reset removes the override and restores the authored default.
```

### Limits and related APIs

Sensitive and server-only values must never be sent to clients. kora_lib cannot restart itself from its own editor; restart-only kora_lib settings must be applied from the server console or a normal server restart. If kora_sql is used by another feature, it is separate from this owner-local configuration file flow.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/config/docs.md` or `local/config/docs.md`) that the reference above does not state.

`Kora.config` lets a resource keep a normal authored Lua `Config` table while
registering typed, owner-editable settings. kora_lib never rewrites `config.lua`:
the owning resource saves only changes to `config.local.lua`.

### Quick start

Put the config file after `@kora_lib/init.lua` in `shared_scripts` so the same
schema exists on both server and client:

```lua
-- config.lua
Config = Kora.config.define({
    chat = {
        localRange = Kora.config.number(20.0, {
            label = 'Local chat range', min = 1, max = 100, live = true,
        }),
        showDistance = Kora.config.boolean(true, { scope = 'client' }),
    },
})

Kora.config.onChange('chat.localRange', function(value, previous)
    -- Reconfigure the running resource and return false to refuse the change.
end)
```

`define` returns the ordinary plain table the resource already consumes. The
value remains available as `Config.chat.localRange`; schemas do not require a
new accessor or a wrapper at call sites.

### Fields and validation

Use `boolean`, `string`, `integer`, `number`, `enum`, `color`, `vector2`,
`vector3`, `vector4`, `object`, `list`, `map`, and `optional` to make a field
explicit. `list(default, item, options)` and `map(default, item, options)`
use their `item` descriptor for every entry; this is the right way to allow
editable empty or dynamically-sized collections. `optional(nil, inner)`
creates a nullable field. Clearing an optional field with a non-nil default
persists an explicit clear and also clears the value for newly connected clients;
resetting it restores the authored default.

The common options are `label`, `description`, `scope`, `live`, `min`, `max`,
`step`, `minLength`, `maxLength`, `pattern`, and `sensitive`. Maps additionally
accept `keyType = 'string' | 'integer' | 'mixed'` and a `requiredKeys` array;
this preserves GTA-style numeric indexes and protects mandatory fallback rows.
`enum` receives
its allowed string or number entries in `options`; entries may be
`{ value = ..., label = ... }` when the displayed label should differ from the
stored value. `color` accepts `#RRGGBB`; numeric fields reject non-finite
values; vector fields accept native CfxLua vectors and the plain component
tables sent by the editor. Fields without authored presentation metadata get
a readable label derived from their complete configuration path and a
type-aware description, so generic leaves such as `enabled`, `max`, or
`window` retain their owning context in the workspace.

The workspace renders every supported kind directly: booleans use a checkbox,
integers and numbers use bounded numeric controls, enums use authored choices,
colours use a picker plus validated text, and vectors expose separate X/Y/Z/W
number inputs. Optional fields have an explicit **Set a value** switch and use
their inner descriptor's normal control when enabled. Objects remain groups of
individually editable leaves rather than requiring an owner to replace an
entire configuration branch at once.

Authored defaults are validated when the schema is defined. Invalid defaults,
reversed bounds, non-positive steps, invalid length limits, and malformed Lua
patterns fail immediately instead of publishing a configuration that cannot be
saved or reset through the editor.

Mark a value `sensitive = true` when it must never be shown or changed in the
in-game editor. Do not register secrets, convars, database-managed data,
executable values, or runtime state as editable settings.

### Everyday and advanced settings

The settings panel starts with Advanced off. Use `advanced = true` in any
field's options for developer tuning, diagnostic controls, internal identifiers,
or settings requiring knowledge of the code. An object marked advanced passes
that classification to its children; `advanced = false` explicitly keeps a
child in the everyday view. Lists, maps, and coordinates default to advanced
unless explicitly overridden. Ordinary scalar fields default to everyday.

```lua
Config = Kora.config.define({
    enabled = Kora.config.boolean(true, { label = 'Enable fuel consumption' }),
    polling = Kora.config.object({
        interval = Kora.config.integer(1000, { min = 100, label = 'Update interval (milliseconds)' }),
    }, { advanced = true }),
})
```

Give everyday settings plain-language labels, units, and descriptions explaining
the effect on gameplay. Prefer enums with readable option labels over free text
for fixed choices. Advanced is a presentation filter, not an access permission;
server authorization and validation apply equally in both views. The toggle
changes neither saved settings nor their live/restart behaviour.

The Advanced preference is saved locally for each user and survives reconnects.
Resource counts follow that preference. Restart actions appear only when a saved
restart-only value differs from the running value, including changes hidden by
the Advanced filter. Opening the editor builds the selected resource's settings
page; other resources keep lightweight placeholders until opened. Cached field
indexes and counts are invalidated when their snapshot or revision changes.

### Scopes and lifecycle

`shared` is the default. `client` fields are synchronized to clients; `server`
fields are excluded from every client snapshot.
A root declared with `{ scope = 'server' }` therefore publishes an empty
client configuration. Define client-only fields in a shared config file so the
server can validate and persist them, then attach the side-effect handler in
the client realm.

Every field is **Restart required** by default. Set `live = true` only when
changing the live `Config` value is safe, and register `onChange` when the
resource has additional side effects to reconfigure. A handler receives
`(value, previous)` and may return `false` to reject the update; kora_lib then
restores the saved override and revision. Server handlers are deliberately
not run for client-scoped settings.

### Migrating an existing table

Use `Kora.config.adopt(Config)` at the end of an existing `config.lua` to retain
its public shape and comments. The bridge infers safe scalar, vector, list,
map, and object fields. It deliberately omits functions and untyped empty
tables, since legacy configs commonly use them as callbacks or resource-filled
registries. Keep those values on `Config`; use explicit `object`, `list`, or
`map` descriptors when an empty collection is intentionally configurable.

Inferred fields receive a readable, path-aware description. Resources should
replace that fallback with a precise explanation of the setting's runtime
effect whenever the code has constraints that the type alone cannot express.
Pass `{ descriptions = { ['feature.setting'] = '...' } }` to `define` or
`adopt` to document legacy fields without wrapping every value in a descriptor.
Common abbreviations such as API, ID, MDT, NPC, TTL, and UI remain capitalised
in generated labels.

Use `Kora.config.extend(values, { scope = 'server' })` from a later
`server/config.lua` to add a server-only branch without putting it in a
client-downloaded config file. `scope = 'client'` is supported for an
equivalent client-only branch when the server also declares the schema.

### Persistence and editor flow

The server bridge reads `config.local.lua` at startup, validates only known
fields, and leaves the authored `config.lua` untouched. Saving writes a
deterministic generated Lua table containing only values that differ from the
authored defaults. Resetting a field removes that field’s override. The last
file is retained as `config.local.lua.bak`; if the primary override is invalid
at startup, kora_lib uses that backup instead.

Each resource writes only its own files through `SaveResourceFile`. kora_lib’s
central catalog coordinates requests but never receives cross-resource
filesystem access. Add both generated files to the resource’s `.gitignore`.

Client snapshot requests are accepted only from a valid connected player and
only for a registered resource. The server returns the already-sanitized
client configuration to that same player; server-scoped and sensitive values
never cross this boundary. Each request carries a monotonic local request ID;
only its latest reply is applied, and a live update invalidates an older pending
snapshot. A delayed network reply therefore cannot roll back current settings.

kora_lib’s ACE-gated `/config` workspace reads the catalog, shows saved
and running values, and labels a field **Applies now** or **Restart required**.
Lists and maps use key/value rows: list keys are consecutive positions, while
maps accept text keys by default and can explicitly opt into integer or mixed
text/integer keys with `keyType`. An explicit scalar item schema uses text,
number, checkbox or enum dropdown controls, with matching browser validation.
Structured or inferred heterogeneous rows retain JSON/plain-text editing.
Required map rows cannot be renamed or deleted; list positions are assigned
automatically. Rows can be added or
deleted in the workspace; the owning resource validates the reconstructed
table before it is persisted. Large collections are paged in the browser so
opening an unusually large configuration does not mount every row at once.
Every registered resource remains in the sidebar while a setting is edited;
the overview also shows its editable-setting count and availability. Sensitive
fields are removed before they reach the workspace. Grant access explicitly
with `add_ace <principal> kora_lib.config.edit allow` (a console source, `kora_admin`'s `canEditConfig` export when that resource is started, or the `admin` permission via `Kora.permissions.hasPermission` also pass); kora_admin may optionally open
the workspace through `Kora.config.open()` but is not required.

The initial catalog transfers only sanitized schemas. Saved and running values
are fetched when a resource is opened from either the overview or sidebar,
which keeps `/config` responsive even on servers with many large resources and
also refreshes the optimistic revision before editing. For a restart-required
setting, an authorised owner can use **Restart resource now** after saving; the
editor asks for confirmation, restarts only that registered resource, reads it
back, and reports whether its persisted configuration loaded successfully.
Editor requests with a missing, fractional, or non-finite revision are rejected
before they reach the owning resource; a valid but stale revision is refused by
the owner.
kora_lib cannot restart itself from its own editor, so its restart-required values
must be applied from the server console or during a normal server restart.

### Server catalog API

The following server API is primarily for privileged integration points such
as kora_admin; ordinary resources use the consumer API above:

- `Kora.config.catalog()` lists registered resource schemas.
- `Kora.config.read(resource)` returns schema, saved values, running values, and
  revision.
- `Kora.config.commit(resource, request)` validates and delegates a save to the
  resource-local bridge.
- `Kora.config.reset(resource, request)` removes one override through that
  bridge.

`Kora.config.register(definition)` is kora_lib’s internal bridge registration API.
It only accepts a registration from the resource it names. Its `revision` is a
positive integer: the consumer begins at `1` and increments it after every
accepted edit, allowing stale editor saves to be refused deterministically.
Catalog discovery and bridge refreshes enforce the same invariant, so a
malformed bridge response cannot poison the stored revision. Successful commit
and reset responses must carry the same valid revision before kora_lib publishes
the resulting local change event.

### Live consumer API

Resources that consume another resource's setting should keep a local value
through `bind`, rather than repeatedly calling an export in gameplay code:

```lua
local targetSettings
Kora.config.bind('kora_target', { 'target' }, function(value)
    targetSettings = value
    rebuildTargeting(value)
end)
```

`Kora.config.get(resource, path)` returns a copied active value, or
`nil, 'not_ready'` before its snapshot arrives. `Kora.config.whenReady({
'kora_target', 'kora_hud' }, handler)` runs once the listed active snapshots are
available. Bindings receive an initial callback and subsequent live active
changes. They are process-local: kora_lib distributes network snapshots to each
client resource and broadcasts server changes locally, so no gameplay read
performs database or export work.

Owners can use `Kora.config.register(values, options)` as the named alias of
`define`, `Kora.config.onValidate(handler)` to reject a complete proposed server
snapshot, and `Kora.config.onApply(handler)` to reconfigure server behavior for
eligible live changes. Validation and apply hooks run only on the owning
server; client-scoped fields do not invoke server apply hooks.
