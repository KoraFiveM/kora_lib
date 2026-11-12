---
title: "Blips module"
sidebar_position: 21
---

# Blips module

## Overview
The blips module creates map blips for the calling client only, groups them in
a fixed pause-map catalogue, and cleans them up automatically when the resource
that created them stops. It also exposes the registered blips so a client UI can
let each player hide categories without changing the native handles returned to
calling resources.

## API

### `Kora.blips.create(coords, options)`
Creates a map blip.

#### Parameters
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

#### Returns
- `number | false` — The created blip handle, or `false` if creation failed.
- `string | nil` — The reason for failure, when the first value is `false`.

#### Behavior
1. The calling resource is captured immediately via `GetInvokingResource()` (falling back to `GetCurrentResourceName()`).
2. The blip is created with `AddBlipForCoord`, then
   sprite/color/scale/shortRange/category/label/display/route are applied.
3. The blip is tracked against the invoking resource and automatically removed if that resource stops.

#### Example
```lua
local blip, err = Kora.blips.create(GetEntityCoords(PlayerPedId()), {
    sprite = 1,
    color = 2,
    category = 'Business',
    name = 'Test Blip', -- displayed as "Business: Test Blip"
    route = true,
})

if not blip then
    print('failed to create blip:', err)
end
```

### Fixed pause-map categories

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

### Registry and player visibility

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

### Player settings UI

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

### Pause-map blip details

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

### `Kora.blips.setInfo(blip, info)`

Replaces a detail panel for a blip created by the calling resource. This also
refreshes the panel when that blip is currently highlighted. It returns `false,
error` if the blip no longer exists or belongs to another resource.

### `Kora.blips.clearInfo(blip)`

Removes the calling resource's detail panel from one of its tracked blips.
Returns the same success/error shape as `setInfo`.

### `Kora.blips.remove(blip)`
Removes one of the calling resource's tracked blips immediately. It cannot
remove blips created by another resource.

#### Parameters
- `blip: number` — The blip handle returned by `Kora.blips.create`.

#### Returns
- `boolean` — `true` on success.
- `string | nil` — The reason for failure, when the first value is `false` (not
  tracked by this module, owned by another resource, or already gone).

#### Example
```lua
local ok, err = Kora.blips.remove(blip)
if not ok then
    print('failed to remove blip:', err)
end
```
