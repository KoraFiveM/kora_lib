# Blips module

## Overview
The blips module creates map blips for the calling client only, cleaning them up automatically when the resource that created them stops.

## API

### `QB.blips.create(coords, options)`
Creates a map blip.

#### Parameters
- `coords: vector3 | vector4 | {x, y, z}` — World coordinates to place the blip at.
- `options: table | nil`
  - `sprite: number` — Blip sprite id. Defaults to `Config.blips.defaultSprite`.
  - `color: number` — Blip color index. Defaults to `Config.blips.defaultColor`.
  - `scale: number` — Blip scale. Defaults to `Config.blips.defaultScale`.
  - `shortRange: boolean` — Whether the blip only shows near the player. Defaults to `Config.blips.defaultShortRange` (`true`).
  - `label: string` — Blip name shown on the map/legend. Left as the sprite's own default label when omitted.
  - `category: number` — Blip category, for legend grouping.
  - `route: boolean` — Draws a waypoint route line to the blip. If `color` is also set, the route is colored to match.

#### Returns
- `number | false` — The created blip handle, or `false` if creation failed.
- `string | nil` — The reason for failure, when the first value is `false`.

#### Behavior
1. The calling resource is captured immediately via `GetInvokingResource()` (falling back to `GetCurrentResourceName()`).
2. The blip is created with `AddBlipForCoord`, then sprite/color/scale/shortRange/category/label/route are applied.
3. The blip is tracked against the invoking resource and automatically removed if that resource stops.

#### Example
```lua
local blip, err = QB.blips.create(GetEntityCoords(PlayerPedId()), {
    sprite = 1,
    color = 2,
    label = 'Test Blip',
    route = true,
})

if not blip then
    print('failed to create blip:', err)
end
```

### `QB.blips.remove(blip)`
Removes one tracked blip immediately.

#### Parameters
- `blip: number` — The blip handle returned by `QB.blips.create`.

#### Returns
- `boolean` — `true` on success.
- `string | nil` — The reason for failure, when the first value is `false` (not tracked by this module, or already gone).

#### Example
```lua
local ok, err = QB.blips.remove(blip)
if not ok then
    print('failed to remove blip:', err)
end
```
