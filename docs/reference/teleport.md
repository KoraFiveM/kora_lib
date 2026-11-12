---
title: "Teleport module"
sidebar_position: 33
---

# Teleport module

Moves local entities or the local player, with a screen fade by default. The
module owns movement; `Kora.visuals.fade` is only the visual transition.

## `Kora.teleport.player(coords, opts?)`

Moves `Kora.cache.ped()` to finite `coords`. A vector4's finite `.w` (or a
table's finite `.heading`) is applied after the move.

## `Kora.teleport.entity(entity, coords, opts?)`

Moves any existing local entity with the same finite-coordinate and heading behavior.
`entity` must be a positive finite integer handle.

`opts.fade` defaults to a 500ms fade. Pass a millisecond value to customise it,
or `false` to move immediately without fading. Options must be a table; fade
must be `false`, `true`, or a finite number.

```lua
Kora.teleport.player(vector4(1073.0, -3102.49, -39.0, 266.61))
Kora.teleport.entity(vehicle, destination, { fade = false })
```

## `Kora.teleport.toWaypoint(opts?)`

Moves the current vehicle when the local player is its driver, otherwise the
player ped, to the active map waypoint. It launches the entity above the
destination while collision loads, performs a bounded ground search, then
places it on the resolved ground.

Options:

- `entity`: override the entity to move.
- `fade`: `false` disables fading; a finite number sets its duration.
- `launchHeight`: finite initial Z used while loading the destination.
- `collisionTimeout`: finite maximum collision wait in milliseconds.
- `groundAttempts`: finite maximum ground probes.
- `groundRetryDelay`: finite milliseconds between ground probes.

Waypoint numeric defaults apply only when omitted; explicit non-numeric or
non-finite values are rejected before movement or fading begins.

It returns `true` on success. A failure returns `false, error`, restores the
original position and heading, unfreezes the entity, clears streaming focus,
and restores the screen even when a native call fails.
