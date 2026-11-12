---
title: "Lookup"
sidebar_position: 5
---


# Lookup

## Shared

Resolves GTA hashes and canonical names against indexed vehicle, ped, object, weapon, weapon-component, and pickup catalogs. Base indexes load on first use, then remain cached for the life of kora_lib.

Namespace: `Kora.lookup` · Source: `modules/lookup/shared.lua`

### How it works

Lookup input may be a signed or unsigned integer, decimal string, hexadecimal string, or case-insensitive canonical name. Hashes normalize to unsigned 32-bit values. Base data is pinned to GTA V data dump revision b65684e (GTA build v3717.0). Records are read-only by contract; copy one before editing.

### Record shape

Records contain namespace, unsigned hash, signedHash, hexHash, name, label, labelKey, category, dlc, source (base, custom, or base+custom), optional contributing resources, and namespace-specific metadata. Vehicle metadata may contain class, manufacturer, type, and seats; ped metadata contains pedType; weapons and components contain their documented names/types; pickups may contain modelName.

### Functions

The functions below are defined in shared.lua and are available from client and server scripts. A successful lookup returns a record. A miss returns nil plus a reason; an ambiguous hash also returns candidate records.

#### `Kora.lookup.get(namespace, value)`

Looks up one hash or canonical name in a specific namespace.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `namespace` | number | vehicle, ped, object, weapon, weapon_component, or pickup. |
| `value` | number | signed/unsigned integer, decimal or hexadecimal hash string, or canonical name. |

**Returns**

- **record** — lookup record on success.
- **reason** — nil on success; catalog_pending, not_found, or ambiguous on a miss.
- **candidates** — candidate records when reason is ambiguous.

**Example**

```lua
local record, reason, candidates = Kora.lookup.get('vehicle', 'adder')
if not record then print(reason) end
```

**Representative console output**

```text
Returns the canonical Adder record, or a reason and candidate list.
```

#### `Kora.lookup.model(value, kind?)`

Looks up a model in vehicle, ped, or object catalogs. Without kind, searches all three and reports cross-namespace collisions as ambiguous.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | number | hash or canonical model name. |
| `kind?` | number | optional vehicle, ped, or object namespace. |

**Returns**

- **record** — matching model record, or nil plus reason.
- **candidates** — candidate records when ambiguous.

**Example**

```lua
local model = Kora.lookup.model('adder', 'vehicle')
```

**Representative console output**

```text
Returns a vehicle model record or nil with a reason.
```

#### `Kora.lookup.weapon(value)`

Looks up a weapon by hash or canonical name.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | number | integer or string hash/name. |

**Returns**

- **record** — weapon record, or nil plus reason and optional candidates.

**Example**

```lua
local weapon = Kora.lookup.weapon('weapon_pistol')
```

**Representative console output**

```text
Record metadata may include modelName and damageType.
```

#### `Kora.lookup.weaponComponent(value)`

Looks up a weapon component by hash or canonical name.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | number | integer or string hash/name. |

**Returns**

- **record** — component record, or nil plus reason and optional candidates.

**Example**

```lua
local component = Kora.lookup.weaponComponent('component_at_pi_flsh')
```

**Representative console output**

```text
Component metadata may include weaponNames, componentType, and attachBone.
```

#### `Kora.lookup.pickup(value)`

Looks up a pickup by hash or canonical name.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | number | integer or string hash/name. |

**Returns**

- **record** — pickup record, or nil plus reason and optional candidates.

**Example**

```lua
local pickup = Kora.lookup.pickup('pickup_medkit')
```

**Representative console output**

```text
Pickup records may include modelName metadata.
```

#### `Kora.lookup.preload(selected?)`

Loads selected base namespaces immediately, or all namespaces when selected is omitted.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `selected?` | array | optional namespace string or dense array of namespace strings. |

**Returns**

- **loaded** — true after all selected base indexes load. Invalid or sparse input raises an assertion error.

**Example**

```lua
Kora.lookup.preload({ 'vehicle', 'weapon' })
```

**Representative console output**

```text
Subsequent lookups use the cached indexes.
```

#### `Kora.lookup.ready()`

Reports whether the client has atomically received the custom resource overlay.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `—` |  | No parameters. |

**Returns**

- **ready** — boolean.

**Example**

```lua
if Kora.lookup.ready() then print("custom lookup catalog is ready") end
```

**Representative console output**

```text
Base records can be used before the client overlay is ready.
```

#### `Kora.lookup.awaitReady(timeout?)`

Waits for the custom overlay to arrive, with a bounded timeout.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `timeout?` | number | optional non-negative integer milliseconds; defaults to 10000. |

**Returns**

- **ready** — true when the overlay arrives.
- **error** — nil on success, or timeout message on failure.

**Example**

```lua
local ready, err = Kora.lookup.awaitReady(5000)
if not ready then print(err) end
```

**Representative console output**

```text
Returns false, "Lookup catalog synchronization timed out." when the timeout expires.
```

### Limits and related APIs

Invalid namespaces, empty values, malformed hex, non-integral numeric values, or hashes outside the unsigned 32-bit range raise assertions. Base data is available during custom synchronization; custom-only misses report catalog_pending until the overlay is ready.

## Client

Receives the server’s custom lookup overlay in versioned batches and publishes a client snapshot only after every batch for that version arrives.

Namespace: `Kora.lookup` · Source: `modules/lookup/client.lua`

### How it works

The client requests synchronization after the secure event handshake and retries every four seconds until ready. Batches can arrive out of order; duplicate, stale, or conflicting batches do not publish a partial/mixed overlay. Lookup APIs are documented under Shared.

### Limits and related APIs

The client receives the custom overlay, not a fresh asset scan. A base lookup can succeed while the custom snapshot is pending; custom misses should be treated as pending until ready.

## Server

Scans discovered resources at kora_lib startup, builds the custom catalog overlay, and sends it to clients as versioned batches.

Namespace: `Kora.lookup` · Source: `modules/lookup/server.lua`

### How it works

The scanner checks stream asset names, readable text archetypes, known metadata, and optional kora_lib.lookup.json files. Binary or ambiguous asset files may be skipped with warnings. The scan yields between resources and caps directory entries to keep startup work bounded. The generated base catalog is separate and is not rebuilt by this scan.

### Limits and related APIs

Install, remove, or change a custom lookup file and restart kora_lib to rescan. The explicit JSON format supports entries and exclusions; supplied hashes must match the JOAAT hash of the entry name.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/lookup/docs.md` or `local/lookup/docs.md`) that the reference above does not state.

### Overview

`Kora.lookup` resolves GTA hash values to canonical vehicle, ped, object, weapon,
weapon-component, and pickup names on both the client and server. Base records
come from compact generated Lua indexes and each namespace is loaded only on
its first use. Loaded indexes and materialized records remain cached for the
lifetime of kora_lib; there is no SQL, expiry, or periodic scan.

The generated catalog is pinned to
[`DurtyFree/gta-v-data-dumps@b65684e`](https://github.com/DurtyFree/gta-v-data-dumps/tree/b65684e00f689fdec405c5f1055322c802d3c895),
GTA build `v3717.0 (Online 1.72) [DLC: mp2025_02_g9ec]`. Its object namespace
covers the upstream list of creatable objects, not every hidden map archetype.
Exact provenance and counts live in `modules/lookup/data/source.json`.

### API

```lua
local record, reason, candidates = Kora.lookup.get('vehicle', hash)

Kora.lookup.model(value, kind)       -- kind: vehicle, ped, or object
Kora.lookup.model(value)             -- searches all three model namespaces
Kora.lookup.weapon(value)
Kora.lookup.weaponComponent(value)
Kora.lookup.pickup(value)

Kora.lookup.preload()                -- every base namespace
Kora.lookup.preload({ 'vehicle', 'weapon' })
Kora.lookup.ready()
Kora.lookup.awaitReady(10000)       -- finite, non-negative timeout in ms
```

`awaitReady` defaults to 10 seconds only when its timeout is omitted; an
explicit timeout must be a non-negative integer.

`preload` accepts one namespace string or a dense array of valid namespace
strings. Invalid or sparse arrays are rejected instead of being treated as an
empty preload request.

`value` may be a signed or unsigned integer, a decimal string, a hexadecimal
string, or a case-insensitive canonical name. Every hash is normalized to its
unsigned 32-bit representation. Invalid namespaces, empty values, malformed
hexadecimal hashes, non-integral numbers, and values outside the 32-bit range
raise an assertion.

Successful calls return a `KoraLookupRecord`. A miss returns one of:

- `nil, 'catalog_pending'` while the client is still receiving the custom
  catalog;
- `nil, 'not_found'` after the custom catalog is ready; or
- `nil, 'ambiguous', candidates` when different canonical names share a hash.

Base hits are available even while the custom catalog is pending. An untyped
`model` call also treats a hash found in more than one model namespace as
ambiguous.

### Records

```lua
{
    namespace = 'vehicle',
    hash = 3078201489,             -- unsigned
    signedHash = -1216765807,
    hexHash = '0xB779A091',
    name = 'adder',
    label = 'Adder',
    labelKey = 'ADDER',
    category = 'SUPER',
    dlc = 'TitleUpdate',
    source = 'base',               -- base, custom, or base+custom
    resources = nil,               -- sorted custom contributors when present
    metadata = {
        class = 'SUPER',
        manufacturer = 'TRUFFADE',
        type = 'CAR',
        seats = 2,
    },
}
```

Other namespace metadata fields are `pedType`; weapon `modelName` and
`damageType`; component `weaponNames`, `componentType`, and `attachBone`; and
pickup `modelName`. Records are read-only by contract. Copy a record before
changing it so a mutation does not alter the process-wide cache.

### Custom resources

At server startup kora_lib scans discovered resources once. It checks streamed
`.ydr` names, readable text `.ytyp` archetypes, and known vehicle, ped, weapon,
and component metadata. Binary `.ytyp` and ambiguous `.yft` files are skipped
with a warning because their model kind cannot safely be inferred from the
filename alone.

A resource can supply `kora_lib.lookup.json` for explicit additions, enrichment,
or exclusions:

```json
{
  "entries": [
    {
      "namespace": "vehicle",
      "name": "my_custom_car",
      "label": "Custom Car",
      "category": "sports",
      "metadata": {
        "class": "sports",
        "manufacturer": "MYMAKE",
        "type": "car",
        "seats": 2
      }
    },
    {
      "namespace": "object",
      "name": "my_custom_prop",
      "hash": "0xF064FDEE"
    }
  ],
  "exclude": [
    { "namespace": "object", "name": "filename_that_is_not_an_object" }
  ]
}
```

`namespace` and `name` are required. If `hash` is present it must equal the
name's JOAAT value; a mismatched entry is rejected. Common optional fields are
`label`, `labelKey`, `category`, and `dlc`. Metadata is namespace-specific and
restricted to the fields documented above.

Identical namespace/hash/name records are merged and retain a sorted list of
contributing resources. Different names with the same hash remain separate
collision candidates. Explicit entries take precedence while retaining
inferred fields they do not replace.

Only the custom overlay is sent to clients. It is split into versioned batches
below 24 KiB and published atomically after every batch arrives; out-of-order,
duplicate, and stale batches are harmless. Clients retry the request after the
secure kora_lib event handshake until the snapshot is ready.

The scan runs only when kora_lib starts and yields between resources, so a large
custom-resource set does not hold one long server tick. Each resource is capped
at 4,096 directory entries; kora_lib warns and skips the remainder rather than
letting a malformed or unusually large resource extend startup indefinitely.
Use `kora_lib.lookup.json` for assets beyond that limit. Restart kora_lib after
installing, removing, or changing a custom resource. The scanner writes no
runtime files.

### Regenerating base data

From the kora_lib resource root:

```sh
node tools/lookup/generate.mjs
node tools/lookup/generate.mjs --check
node --test tools/lookup/generate.test.mjs
```

The generator downloads only the pinned upstream revision, validates every
catalog hash against JOAAT, detects collisions, extracts curated fields, sorts
all numeric keys, and writes the six Lua bundles plus the source manifest. Use
`--input <directory>` to regenerate from an already-downloaded copy containing
the five files named in `source.json`.
