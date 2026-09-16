# Configuration

`QB.config` lets a resource keep a normal authored Lua `Config` table while
registering typed, owner-editable settings. qblib never rewrites `config.lua`:
the owning resource saves only changes to `config.local.lua`.

## Quick start

Put the config file after `@qblib/init.lua` in `shared_scripts` so the same
schema exists on both server and client:

```lua
-- config.lua
Config = QB.config.define({
    chat = {
        localRange = QB.config.number(20.0, {
            label = 'Local chat range', min = 1, max = 100, live = true,
        }),
        showDistance = QB.config.boolean(true, { scope = 'client' }),
    },
})

QB.config.onChange('chat.localRange', function(value, previous)
    -- Reconfigure the running resource and return false to refuse the change.
end)
```

`define` returns the ordinary plain table the resource already consumes. The
value remains available as `Config.chat.localRange`; schemas do not require a
new accessor or a wrapper at call sites.

## Fields and validation

Use `boolean`, `string`, `integer`, `number`, `enum`, `color`, `vector2`,
`vector3`, `vector4`, `object`, `list`, `map`, and `optional` to make a field
explicit. `list(default, item, options)` and `map(default, item, options)`
use their `item` descriptor for every entry; this is the right way to allow
editable empty or dynamically-sized collections. `optional(nil, inner)`
creates a nullable field.

The common options are `label`, `description`, `scope`, `live`, `min`, `max`,
`step`, `minLength`, `maxLength`, `pattern`, and `sensitive`. `enum` receives
its allowed entries in `options`. `color` accepts `#RRGGBB`; numeric fields
reject non-finite values; vector fields accept native CfxLua vectors and the
plain component tables sent by the editor.

Authored defaults are validated when the schema is defined. Invalid defaults,
reversed bounds, non-positive steps, invalid length limits, and malformed Lua
patterns fail immediately instead of publishing a configuration that cannot be
saved or reset through the editor.

Mark a value `sensitive = true` when it must never be shown or changed in the
in-game editor. Do not register secrets, convars, database-managed data,
executable values, or runtime state as editable settings.

## Scopes and lifecycle

`shared` is the default. `client` fields are synchronized to clients; `server`
fields are excluded from every client snapshot.
A root declared with `{ scope = 'server' }` therefore publishes an empty
client configuration. Define client-only fields in a shared config file so the
server can validate and persist them, then attach the side-effect handler in
the client realm.

Every field is **Restart required** by default. Set `live = true` only when
changing the live `Config` value is safe, and register `onChange` when the
resource has additional side effects to reconfigure. A handler receives
`(value, previous)` and may return `false` to reject the update; qblib then
restores the saved override and revision. Server handlers are deliberately
not run for client-scoped settings.

## Migrating an existing table

Use `QB.config.adopt(Config)` at the end of an existing `config.lua` to retain
its public shape and comments. The bridge infers safe scalar, vector, list,
map, and object fields. It deliberately omits functions and untyped empty
tables, since legacy configs commonly use them as callbacks or resource-filled
registries. Keep those values on `Config`; use explicit `object`, `list`, or
`map` descriptors when an empty collection is intentionally configurable.

Use `QB.config.extend(values, { scope = 'server' })` from a later
`server/config.lua` to add a server-only branch without putting it in a
client-downloaded config file. `scope = 'client'` is supported for an
equivalent client-only branch when the server also declares the schema.

## Persistence and editor flow

The server bridge reads `config.local.lua` at startup, validates only known
fields, and leaves the authored `config.lua` untouched. Saving writes a
deterministic generated Lua table containing only values that differ from the
authored defaults. Resetting a field removes that field’s override. The last
file is retained as `config.local.lua.bak`; if the primary override is invalid
at startup, qblib uses that backup instead.

Each resource writes only its own files through `SaveResourceFile`. qblib’s
central catalog coordinates requests but never receives cross-resource
filesystem access. Add both generated files to the resource’s `.gitignore`.

qblib’s ACE-gated `/config` workspace reads the catalog, shows saved
and running values, and labels a field **Applies now** or **Restart required**.
Sensitive fields are removed before they reach the workspace. Grant access
explicitly with `add_ace <principal> qblib.config.edit allow`; qbadmin may
optionally open the workspace through `QB.config.open()` but is not required.

## Server catalog API

The following server API is primarily for privileged integration points such
as qbadmin; ordinary resources use the consumer API above:

- `QB.config.catalog()` lists registered resource schemas.
- `QB.config.read(resource)` returns schema, saved values, running values, and
  revision.
- `QB.config.commit(resource, request)` validates and delegates a save to the
  resource-local bridge.
- `QB.config.reset(resource, request)` removes one override through that
  bridge.

`QB.config.register(definition)` is qblib’s internal bridge registration API.
It only accepts a registration from the resource it names.

## Live consumer API

Resources that consume another resource's setting should keep a local value
through `bind`, rather than repeatedly calling an export in gameplay code:

```lua
local targetSettings
QB.config.bind('qbtarget', { 'target' }, function(value)
    targetSettings = value
    rebuildTargeting(value)
end)
```

`QB.config.get(resource, path)` returns a copied active value, or
`nil, 'not_ready'` before its snapshot arrives. `QB.config.whenReady({
'qbtarget', 'qbhud' }, handler)` runs once the listed active snapshots are
available. Bindings receive an initial callback and subsequent live active
changes. They are process-local: qblib distributes network snapshots to each
client resource and broadcasts server changes locally, so no gameplay read
performs database or export work.

Owners can use `QB.config.register(values, options)` as the named alias of
`define`, `QB.config.onValidate(handler)` to reject a complete proposed server
snapshot, and `QB.config.onApply(handler)` to reconfigure server behavior for
eligible live changes. Validation and apply hooks run only on the owning
server; client-scoped fields do not invoke server apply hooks.
