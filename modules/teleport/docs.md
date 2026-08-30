# Teleport module

Moves local entities or the local player, with a screen fade by default. The
module owns movement; `QB.visuals.fade` is only the visual transition.

## `QB.teleport.player(coords, opts?)`

Moves `QB.cache.ped()` to `coords`. A vector4's `.w` (or a table's `.heading`)
is applied after the move.

## `QB.teleport.entity(entity, coords, opts?)`

Moves any existing local entity with the same coordinate and heading behavior.

`opts.fade` defaults to a 500ms fade. Pass a millisecond value to customise it,
or `false` to move immediately without fading.

```lua
QB.teleport.player(vector4(1073.0, -3102.49, -39.0, 266.61))
QB.teleport.entity(vehicle, destination, { fade = false })
```
