---
title: "Blips"
sidebar_position: 21
---


# Blips

## Shared

Publishes the fixed pause-map category catalogue for both client and server code.

Namespace: `Kora.blips` · Source: `modules/blips/shared.lua`

### Functions

The shared realm exposes a defensive copy of canonical category names and ids.

#### `Kora.blips.getCategoryIds()`

Returns a fresh name-to-id map for the built-in blip category catalogue.

**Parameters**



**Returns**

- **categories** — table mapping canonical names to native category ids.

**Example**

```lua
local categories = Kora.blips.getCategoryIds()
print(categories.Police)
```

**Representative console output**

```text
The returned copy can be changed without modifying the module catalogue.
```

### Limits and related APIs

The category ids are fixed; use canonical names for new code. Numeric native category ids remain a compatibility path in client create.

## Client

Creates and owns client-local map blips, groups them into a fixed category catalogue, and lets each player hide categories or individual blips. Tracked handles are cleaned up when their creating resource stops.

Namespace: `Kora.blips` · Source: `modules/blips/client.lua · modules/blips/settings.lua`

### How it works

Blips are local to the client that creates them. Category visibility is stored locally. Hiding a blip sets native display to zero and removes its active route; showing restores the configured display and route, while a hidden category remains hidden. The /blips settings screen uses the same preference state.

### create options table

Common display and category settings supplied as the second argument to create. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `sprite??` | integer | Non-negative sprite id; defaults to Config.blips.defaultSprite. |
| `color??` | integer | Non-negative native color index; defaults to Config.blips.defaultColor. |
| `scale??` | number | Positive finite scale; defaults to Config.blips.defaultScale. |
| `shortRange??` | boolean | Restricts display to nearby players; defaults to configured value, normally true. |
| `category??` | string \| number | Fixed category name/legacy alias or numeric native category; defaults to Other. Unknown strings assert. |
| `name??` | string | Location label shown below GTA’s category heading. |
| `label??` | string | Legacy explicit map-label override. |
| `display??` | integer | Non-negative native display mode; defaults to configured mode. |
| `route??` | boolean | Draws a waypoint route; pass color to select route color. |
| `info??` | KoraBlipInfo | Pause-map detail panel with title and supported row types. |

### Categories

The built-in catalogue maps Other=12, Bank=13, Bar=14, Business=15, Clothing=16, Convenience=17, Dispatch=18, Evidence=19, Fuel=20, Garage=21, Gang Garage=22, Grooming=23, Hospital=24, Impound=25, Jewellery=26, Job Garage=27, Juice=28, Liquor=29, Mechanic=30, Pharmacy=31, Police=32, Recycling=33, Restaurant=34, Scrapyard=35, Tattoo=36, Vehicle Dealer=37, Vehicle Tracking=38, Weapons=39, Trucking=40. Matching names is trimmed and case-insensitive; legacy aliases include Ammu-Nation→Weapons and Barber→Grooming.

### Detail panels

info rows support text, name, header, wrappedText, or icon. Icon rows may include icon, color, and checked. An image may reference a streamed texture dictionary/name pair. The renderer refreshes the highlighted panel while the pause map rebuilds its columns.

### Functions

Create/remove markers, inspect registry snapshots, and control visibility by category or individual handle.

#### `Kora.blips.create(coords, options?)`

Creates a map marker and tracks it to the calling resource.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `coords` | vector3 \| vector4 | Finite world position. |
| `options?` | table | Optional sprite, color, label, category, route, and details. |

**Returns**

- **blip** — native handle, or false on failure.
- **reason** — failure detail when false is returned.

**Example**

```lua
local blip, err = Kora.blips.create(vector3(215.2, -810.1, 30.7), {
    sprite = 225, color = 3, category = 'Mechanic',
    name = 'Downtown Garage', route = true,
})
if not blip then print(err) end
```

**Representative console output**

```text
Creates a client-local mechanic marker with a waypoint route.
```

#### `Kora.blips.getCategories()`

Returns category metadata ordered by native category id.

**Parameters**



**Returns**

- **categories** — records with key, name, label, id, visible, and count.

**Example**

```lua
for _, item in ipairs(Kora.blips.getCategories()) do print(item.name, item.count) end
```

**Representative console output**

```text
Provides current local visibility and registration counts.
```

#### `Kora.blips.getCategory(category)`

Returns one category record by canonical name, alias, or native id.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `category` | string \| number | Category name/alias or numeric native id. |

**Returns**

- **category** — record, or nil when not recognized.

**Example**

```lua
local police = Kora.blips.getCategory('Police')
if police then print(police.visible, police.count) end
```

**Representative console output**

```text
Returns the local category snapshot.
```

#### `Kora.blips.getRegistered()`

Returns snapshots of every currently registered local blip.

**Parameters**



**Returns**

- **blips** — array of records containing handle, resource, category, name/label, sprite, color, display, route, and effective visibility.

**Example**

```lua
for _, item in ipairs(Kora.blips.getRegistered()) do print(item.label, item.visible) end
```

**Representative console output**

```text
Snapshots expose metadata for UI; handles remain owned by their creating resource.
```

#### `Kora.blips.isCategoryVisible(category)`

Reads the player’s current local visibility preference for a category.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `category` | string \| number | Category name/alias or native id. |

**Returns**

- **visible** — boolean.

**Example**

```lua
print(Kora.blips.isCategoryVisible(17))
```

**Representative console output**

```text
Reports whether category 17 is visible.
```

#### `Kora.blips.hideCategory(category)`

Persists a local preference that hides every registered and future blip in the category.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `category` | string \| number | Category name/alias or native id. |

**Returns**

- **changed** — boolean.

**Example**

```lua
Kora.blips.hideCategory('Fuel')
```

**Representative console output**

```text
Returns whether the preference changed.
```

#### `Kora.blips.showCategory(category)`

Clears the local hidden preference for a category.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `category` | string \| number | Category name/alias or native id. |

**Returns**

- **changed** — boolean.

**Example**

```lua
Kora.blips.showCategory('Fuel')
```

**Representative console output**

```text
Returns whether the preference changed.
```

#### `Kora.blips.hide(blip)`

Hides one tracked blip owned by the calling resource.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `blip` | number | Handle returned by create. |

**Returns**

- **hidden** — boolean.
- **reason** — error when handle is invalid or not caller-owned.

**Example**

```lua
local ok, err = Kora.blips.hide(blip)
```

**Representative console output**

```text
Hides the marker and disables its route.
```

#### `Kora.blips.show(blip)`

Shows one tracked owned blip, unless its category is still hidden.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `blip` | number | Handle returned by create. |

**Returns**

- **shown** — boolean.
- **reason** — error when handle is invalid or not caller-owned.

**Example**

```lua
local ok, err = Kora.blips.show(blip)
```

**Representative console output**

```text
Restores the configured display and route when category visibility permits.
```

#### `Kora.blips.setInfo(blip, info)`

Sets or replaces pause-map detail content for an owned blip.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `blip` | number | Owned blip handle. |
| `info` | table | Detail panel payload containing title and supported rows. |

**Returns**

- **updated** — boolean.
- **reason** — error when handle is not caller-owned.

**Example**

```lua
Kora.blips.setInfo(blip, {
    title = 'Open repair contract',
    rows = { { kind = 'name', label = 'Vehicle', value = 'Buffalo STX' } },
})
```

**Representative console output**

```text
The panel appears when the player highlights the blip on the pause map.
```

#### `Kora.blips.clearInfo(blip)`

Removes pause-map detail content from an owned blip.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `blip` | number | Owned blip handle. |

**Returns**

- **cleared** — boolean.

**Example**

```lua
Kora.blips.clearInfo(blip)
```

**Representative console output**

```text
The base map marker remains registered.
```

#### `Kora.blips.remove(blip)`

Removes one owned tracked native blip and its detail-panel state.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `blip` | number | Handle returned by create. |

**Returns**

- **removed** — boolean.
- **reason** — error when untracked or already missing.

**Example**

```lua
local ok, err = Kora.blips.remove(blip)
```

**Representative console output**

```text
The handle is no longer valid after removal.
```

### Limits and related APIs

All supplied display values are validated before native creation. Category settings affect only the local player. A resource can change or remove only its own blip handles; unknown string categories fail fast.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/blips/docs.md` or `local/blips/docs.md`) that the reference above does not state.

### API

#### `Kora.blips.create(coords, options)`
Creates a map blip.

##### Parameters
- `coords: vector3 | vector4 | {x, y, z}` — Finite world coordinates to place the blip at.
- `options: table | nil`
  - `sprite: number` — Blip sprite id. Defaults to `Config.blips.defaultSprite`.
  - `color: number` — Blip color index. Defaults to `Config.blips.defaultColor`.
  - `scale: number` — Blip scale. Defaults to `Config.blips.defaultScale`.
  - `shortRange: boolean` — Whether the blip only shows near the player. Defaults to `Config.blips.defaultShortRange` (`true`).
  - `category: number | string` — A fixed category name, supported legacy alias,
    or numeric native category. Defaults to `Other`. Unknown strings fail fast.
  - `name: string` — Location name shown after GTA's native category heading.
    The category is not embedded in this text because the pause map adds it.
  - `label: string` — Backwards-compatible explicit map-label override.
  - `display: integer` — Native display mode. Defaults to
    `Config.blips.defaultDisplay` (`4`) and is restored after the blip is shown.
  - `route: boolean` — Draws a waypoint route line to the blip. If `color` is also set, the route is colored to match.
  - `info: KoraBlipInfo` — Optional detail panel shown when the player highlights the blip in the pause map.

All supplied options are validated before kora_lib creates a native blip: sprite,
color, and display are non-negative integers; scale is positive and finite;
and `shortRange` and `route` are booleans. Values default only when omitted.

#### Fixed pause-map categories

Pass a fixed category name for normal service blips. Category matching trims
whitespace and is case-insensitive. Every blip receives a category; omission
uses `Other` (12). Unknown strings assert instead of silently consuming or
changing native category ids.

| Category | ID | Category | ID |
| --- | ---: | --- | ---: |
| Other | 12 | Bank | 13 |
| Bar | 14 | Business | 15 |
| Clothing | 16 | Convenience | 17 |
| Dispatch | 18 | Evidence | 19 |
| Fuel | 20 | Garage | 21 |
| Gang Garage | 22 | Grooming | 23 |
| Hospital | 24 | Impound | 25 |
| Jewellery | 26 | Job Garage | 27 |
| Juice | 28 | Liquor | 29 |
| Mechanic | 30 | Pharmacy | 31 |
| Police | 32 | Recycling | 33 |
| Restaurant | 34 | Scrapyard | 35 |
| Tattoo | 36 | Vehicle Dealer | 37 |
| Vehicle Tracking | 38 | Weapons | 39 |
| Trucking | 40 | | |

Legacy aliases remain accepted: `Ammu-Nation` → `Weapons`, `Clothing Store` →
`Clothing`, `Tattoo Artist` → `Tattoo`, `Hairdresser`/`Barber` → `Grooming`,
`Police Station` → `Police`, `Dispatch calls` → `Dispatch`, and `Rob's Liquor`
→ `Liquor`. Numeric values remain a backwards-compatible pass-through to
`SetBlipCategory`, but fixed names should be used by new code.

```lua
for _, store in ipairs(Config.shops) do
    Kora.blips.create(store.coords, {
        sprite = 73,
        color = 47,
        category = 'Clothing',
        name = store.name,
    })
end
```

`Kora.blips.getCategoryIds()` returns a fresh canonical name-to-id table in both
client and server realms. Mutating the returned table does not alter kora_lib's
catalogue.

#### Registry and player visibility

- `Kora.blips.getCategories()` returns categories ordered by native id. Each
  record contains `key`, `name`, `label`, `id`, `visible`, and `count`.
- `Kora.blips.getCategory(category)` returns one category record. Names, aliases,
  and numeric native ids are accepted.
- `Kora.blips.getRegistered()` returns snapshots containing `handle`, `resource`,
  numeric `category`, `categoryKey`, `name`, `label`, `sprite`, `color`,
  `display`, `route`, and effective `visible` state.
- `Kora.blips.isCategoryVisible(category)` reads the player's current preference.
- `Kora.blips.hideCategory(category)` and `Kora.blips.showCategory(category)` persist
  the preference locally and return whether it changed.
- `Kora.blips.hide(blip)` and `Kora.blips.show(blip)` change one tracked native blip
  owned by the calling resource and return `true`, or `false, error` when the
  handle is invalid, untracked, or owned by another resource.

A hidden blip uses display mode `0`. Showing it restores its configured display
mode. Hiding also disables an active route line; showing restores the route and
its configured color. `show(blip)` never overrides a hidden category.

```lua
for _, category in ipairs(Kora.blips.getCategories()) do
    print(category.label, category.count, category.visible)
end

Kora.blips.hideCategory('Fuel')
Kora.blips.showCategory('Fuel')
```

#### Player settings UI

Players can run `/blips` to open kora_lib's compact AppShell settings screen. The
screen lists the fixed categories and nests every currently registered blip
beneath its category. Category actions apply immediately, update the open
screen in place, and use the same client KVP preference as
`hideCategory`/`showCategory`; they never change another player's map.

Each registered blip shows its sprite and documented blip-colour name/index/hex
metadata. Sprites used by first-party resources use the official FiveM
`docs-backend.fivem.net/blips/<radar_name>` image. New or custom sprite ids use
a generic map pin instead of guessing a broken asset URL, while retaining a
link to the [FiveM blip reference](https://docs.fivem.net/docs/game-references/blips/).
The creating resource is operational information and appears only when the
server confirms the viewer has the `admin` ACE permission. The check accepts
only a positive finite player source and fails closed for malformed requests.

#### Pause-map blip details

Set `info` to show activity-specific detail when the player highlights a blip in
the pause map. This is best for unique or changing markers such as dispatch
calls, contracts, and tracked evidence; a label and category remain the better
choice for large groups of identical locations.

```lua
local blip = Kora.blips.create(contract.coords, {
    sprite = 68,
    color = 5,
    label = 'Tow Contract',
    info = {
        title = 'Abandoned vehicle',
        money = '$2,500',
        rows = {
            { kind = 'name', label = 'Vehicle', value = 'Buffalo STX' },
            { kind = 'icon', label = 'Difficulty', value = 'Medium', icon = 18, color = 5 },
            { kind = 'wrappedText', value = 'Recover the vehicle without alerting the guards.' },
        },
    },
})
```

`image` accepts `{ dictionary = '...', texture = '...' }` for a streamed pause-menu texture. Shared dictionaries are retained once and released after the final panel using them is cleared or removed. Rows use one of `text`, `name`, `header`, `wrappedText`, or `icon`; icon rows additionally accept `icon`, `color`, and `checked`. While a detailed blip is highlighted, kora_lib refreshes the frontend column every frame because GTA rebuilds pause-map columns continuously; the renderer returns to its low-frequency idle poll as soon as the highlight ends.

The card shares frontend column 1 with GTA's legend, and selecting a legend entry reports the same highlighted blip as hovering it on the map (for a few frames, while the map pans to it). kora_lib therefore draws a card only when all of these hold:

- the pause menu is open, `GetPauseMenuState()` is ready, the frontend is ready for control and not restarting (`requirePauseReady`);
- the legend does not have focus: `IsNavigatingMenuContent()` is false (`blockWhileNavigatingContent`), no pause-menu layout-changed event fired in the last `legendSuppressMs`, and, as a fallback with mouse input, the cursor is left of `legendMinX`;
- the cursor has stayed on the same blip for `hoverStableMs` without a break. After that the card is redrawn every frame as before.

When the legend gains focus while a card is up, the card's slots are emptied once. kora_lib never hides the column (`SHOW_COLUMN(1, false)`); it calls `SHOW_COLUMN(1, true)` only while a card renders (`forceShowColumn`).

| `Config.blips.info` option | Default | Meaning |
| --- | --- | --- |
| `showOnLegendSelect` | `false` | `true` skips the legend checks (the stable-hover and frontend-ready checks still apply). |
| `hoverStableMs` | `120` | Unbroken hover time before the first draw; `0` draws immediately. |
| `requirePauseReady` | `true` | Also require `GetPauseMenuState() == 15`. |
| `blockWhileNavigatingContent` | `true` | Treat `IsNavigatingMenuContent()` as legend focus. Disable if it is true during plain map hover on your build. |
| `legendSuppressMs` | `400` | Hold-back after a menu layout-changed event; `0` disables the check. |
| `legendMinX` | `0.66` | Mouse-only fallback: cursor X at or right of this counts as over the legend; `false`/`0` disables. |
| `forceShowColumn` | `true` | Call `SHOW_COLUMN(1, true)` while the card renders. |

#### `Kora.blips.setInfo(blip, info)`

Replaces a detail panel for a blip created by the calling resource. This also
refreshes the panel when that blip is currently highlighted. It returns `false,
error` if the blip no longer exists or belongs to another resource.

#### `Kora.blips.clearInfo(blip)`

Removes the calling resource's detail panel from one of its tracked blips.
Returns the same success/error shape as `setInfo`.
