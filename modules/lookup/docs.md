# Lookup module

## Overview

`QB.lookup` resolves GTA hash values to canonical vehicle, ped, object, weapon,
weapon-component, and pickup names on both the client and server. Base records
come from compact generated Lua indexes and each namespace is loaded only on
its first use. Loaded indexes and materialized records remain cached for the
lifetime of qblib; there is no SQL, expiry, or periodic scan.

The generated catalog is pinned to
[`DurtyFree/gta-v-data-dumps@b65684e`](https://github.com/DurtyFree/gta-v-data-dumps/tree/b65684e00f689fdec405c5f1055322c802d3c895),
GTA build `v3717.0 (Online 1.72) [DLC: mp2025_02_g9ec]`. Its object namespace
covers the upstream list of creatable objects, not every hidden map archetype.
Exact provenance and counts live in `modules/lookup/data/source.json`.

## API

```lua
local record, reason, candidates = QB.lookup.get('vehicle', hash)

QB.lookup.model(value, kind)       -- kind: vehicle, ped, or object
QB.lookup.model(value)             -- searches all three model namespaces
QB.lookup.weapon(value)
QB.lookup.weaponComponent(value)
QB.lookup.pickup(value)

QB.lookup.preload()                -- every base namespace
QB.lookup.preload({ 'vehicle', 'weapon' })
QB.lookup.ready()
QB.lookup.awaitReady(10000)
```

`value` may be a signed or unsigned integer, a decimal string, a hexadecimal
string, or a case-insensitive canonical name. Every hash is normalized to its
unsigned 32-bit representation. Invalid namespaces, empty values, malformed
hexadecimal hashes, non-integral numbers, and values outside the 32-bit range
raise an assertion.

Successful calls return a `QBLookupRecord`. A miss returns one of:

- `nil, 'catalog_pending'` while the client is still receiving the custom
  catalog;
- `nil, 'not_found'` after the custom catalog is ready; or
- `nil, 'ambiguous', candidates` when different canonical names share a hash.

Base hits are available even while the custom catalog is pending. An untyped
`model` call also treats a hash found in more than one model namespace as
ambiguous.

## Records

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

## Custom resources

At server startup qblib scans discovered resources once. It checks streamed
`.ydr` names, readable text `.ytyp` archetypes, and known vehicle, ped, weapon,
and component metadata. Binary `.ytyp` and ambiguous `.yft` files are skipped
with a warning because their model kind cannot safely be inferred from the
filename alone.

A resource can supply `qblib.lookup.json` for explicit additions, enrichment,
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
secure qblib event handshake until the snapshot is ready.

The scan runs only when qblib starts. Restart qblib after installing, removing,
or changing a custom resource. The scanner writes no runtime files.

## Regenerating base data

From the qblib resource root:

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
