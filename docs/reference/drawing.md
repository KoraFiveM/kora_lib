---
title: "Drawing module"
sidebar_position: 25
---

# Drawing module

## Overview
The drawing module renders world-space visuals -- currently just 3D text -- via plain client-side drawing natives, distance-culled so a caller drawing many of them a frame doesn't pay for the ones nowhere near the player. Added alongside `modules/world` as a foundation for a crosshair-based targeting system's interaction prompt, but generically useful to any resource that needs a floating world-space label: shops, ATMs, gathering nodes, vehicle keys.

## API

### `Kora.drawing.text3d(coords, text, options)`
Draws one frame of world-space 3D text anchored at `coords`. Not a persistent registration -- like a raw `DrawMarker` call, call it again every frame it should stay visible.

#### Parameters
- `coords: vector3 | {x, y, z}` -- finite world position to anchor the text to.
- `text: string` -- non-empty. Multi-line via GTA's own `"~n~"` token, not `"\n"`.
- `options: table | nil` -- any field omitted falls back to `Config.drawing.text3d`.
  Explicit values are validated; `false` is not treated as an omitted option.
  - `font: integer` -- non-negative.
  - `scale: number` -- positive and finite.
  - `color: {r, g, b, a}` -- integer channels from `0` to `255`.
  - `maxDistance: number` -- finite non-negative meters from `PlayerPedId()`; beyond this, no native calls run at all.
  - `outline: boolean`.

#### Returns
Nothing.

#### Example
```lua
CreateThread(function()
    while HasTarget() do
        Kora.drawing.text3d(GetEntityCoords(targetEntity), "[E] Open")
        Wait(0)
    end
end)
```

Called cross-resource via export (e.g. from a targeting resource):
```lua
exports.kora_lib:drawing_text3d(promptCoords, ("%d options"):format(#options), { scale = 0.4 })
```

## Notes
- Distance culling happens before any drawing native runs, using squared components to avoid a square root in a per-frame primitive. This is the whole reason `maxDistance` lives in this primitive instead of every caller re-deriving the same distance check.
- Client-only: drawing only makes sense against the calling client's own screen, so this module has no `shared.lua`/`server.lua`, the same shape as `modules/raycast`/`modules/stream`/`modules/world`.
- Uses the standard `SetDrawOrigin`/`EndTextCommandDisplayText`/`ClearDrawOrigin` idiom rather than manual `World3dToScreen2d` math.
