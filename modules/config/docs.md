# Configuration

`Kora.config` lets a resource keep a normal authored Lua `Config` table while
registering typed, owner-editable settings. kora_lib never rewrites `config.lua`:
the owning resource saves only changes to `config.local.lua`.

## Quick start

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

## Fields and validation

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

## Everyday and advanced settings

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
`(value, previous)` and may return `false` to reject the update; kora_lib then
restores the saved override and revision. Server handlers are deliberately
not run for client-scoped settings.

## Migrating an existing table

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

## Persistence and editor flow

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
with `add_ace <principal> kora_lib.config.edit allow` (the deprecated `qblib.config.edit` ACE is still honoured); kora_admin may optionally open
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

## Server catalog API

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

## Live consumer API

Resources that consume another resource's setting should keep a local value
through `bind`, rather than repeatedly calling an export in gameplay code:

```lua
local targetSettings
Kora.config.bind('qbtarget', { 'target' }, function(value)
    targetSettings = value
    rebuildTargeting(value)
end)
```

`Kora.config.get(resource, path)` returns a copied active value, or
`nil, 'not_ready'` before its snapshot arrives. `Kora.config.whenReady({
'qbtarget', 'qbhud' }, handler)` runs once the listed active snapshots are
available. Bindings receive an initial callback and subsequent live active
changes. They are process-local: kora_lib distributes network snapshots to each
client resource and broadcasts server changes locally, so no gameplay read
performs database or export work.

Owners can use `Kora.config.register(values, options)` as the named alias of
`define`, `Kora.config.onValidate(handler)` to reject a complete proposed server
snapshot, and `Kora.config.onApply(handler)` to reconfigure server behavior for
eligible live changes. Validation and apply hooks run only on the owning
server; client-scoped fields do not invoke server apply hooks.
