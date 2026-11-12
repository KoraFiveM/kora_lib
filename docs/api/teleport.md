---
title: "Teleport"
sidebar_position: 33
---


# Teleport

Moves the local player, another existing local entity, or the selected waypoint destination. Screen fading is enabled by default for direct moves; waypoint movement additionally loads collision and resolves ground before placing the entity.

Namespace: `Kora.teleport` · Source: `modules/teleport/client.lua`

## How it works

Coordinates accept vector3 or vector4. vector4.w supplies heading; a table may supply heading instead. A successful direct move returns true. Waypoint movement returns true on success or false plus an error, restoring the entity’s original position/heading and clearing temporary streaming/fade state when movement fails.

## Options

Pass opts as the final argument to player/entity or toWaypoint. The waypoint-only fields apply to toWaypoint. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `fade?` | false \| true \| number | Direct moves default to 500 ms; true selects 500 ms, false moves immediately, and finite number sets milliseconds. Waypoint option accepts the same values. |
| `entity?` | integer handle | toWaypoint only. Overrides the default target (driven vehicle for its driver, otherwise local ped). Must exist. |
| `launchHeight?` | number | toWaypoint only. Finite initial height used while destination collision loads; defaults to Config.teleport.waypointLaunchHeight. |
| `collisionTimeout?` | number | toWaypoint only. Finite maximum collision wait in milliseconds; defaults to Config.teleport.waypointCollisionTimeout. |
| `groundAttempts?` | number | toWaypoint only. Finite maximum ground probes; must resolve to at least one attempt. |
| `groundRetryDelay?` | number | toWaypoint only. Finite milliseconds between ground probes; defaults to Config.teleport.waypointGroundRetryDelay. |

## Functions

All functions run on the client and move local entities. Use entity for an arbitrary existing entity, player for the local ped, and toWaypoint for the active map waypoint.

### `Kora.teleport.entity(entity, coords, opts?)`

Moves an existing local entity to a coordinate, applying an optional heading and screen fade.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entity` | entity handle | positive integer handle for an existing local entity. |
| `coords` | vector3 \| vector4 | vector3/vector4 destination; vector4.w or table.heading is applied as heading when present. |
| `opts?` | table | optional table; fade defaults to 500 ms, true uses 500 ms, false disables fading, and a finite number sets duration. |

**Returns**

- **success** — true after the entity is moved; invalid arguments raise an assertion error.

**Example**

```lua
Kora.teleport.entity(vehicle, vector4(1073.0, -3102.49, -39.0, 266.61))
```

**Representative console output**

```text
Moves the vehicle and applies heading after movement.
```

### `Kora.teleport.player(coords, opts?)`

Moves the local player ped. Equivalent to entity(Kora.cache.ped(), coords, opts).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `coords?` | vector3 \| vector4 | vector3/vector4 destination; vector4.w or table.heading supplies optional heading. |
| `opts?` | table | optional fade options. |

**Returns**

- **success** — true after the ped is moved.

**Example**

```lua
Kora.teleport.player(vector4(1073.0, -3102.49, -39.0, 266.61))
```

**Representative console output**

```text
Moves the local player with a 500 ms fade by default.
```

### `Kora.teleport.toWaypoint(opts?)`

Moves the driven vehicle when the player is its driver; otherwise moves the player ped to the active map waypoint. The entity is raised while collision loads, then a bounded ground search finds the final position.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `opts?` | table | optional table. entity overrides the target; fade controls transition; launchHeight controls initial lift; collisionTimeout bounds collision wait; groundAttempts limits ground probes; groundRetryDelay sets spacing between probes. |

**Returns**

- **success** — true when waypoint ground was resolved and the entity moved.
- **error** — nil on success; string when no waypoint, entity, collision, ground, or native operation fails.

**Example**

```lua
local ok, err = Kora.teleport.toWaypoint({
    fade = 300,
    collisionTimeout = 5000,
    groundAttempts = 20,
})
if not ok then print(err) end
```

**Representative console output**

```text
On failure, restores original position and heading, unfreezes the entity, clears streaming focus, and restores the screen.
```

## Limits and related APIs

Coordinates require finite components. Entity handles must be positive integers and exist locally. Invalid fade/options are rejected before movement/fading. Waypoint numeric defaults apply only when omitted; explicit non-finite values are rejected.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/teleport/docs.md` or `local/teleport/docs.md`) that the reference above does not state.

Moves local entities or the local player, with a screen fade by default. The
module owns movement; `Kora.visuals.fade` is only the visual transition.

### `Kora.teleport.player(coords, opts?)`

Moves `Kora.cache.ped()` to finite `coords`. A vector4's finite `.w` (or a
table's finite `.heading`) is applied after the move.

### `Kora.teleport.entity(entity, coords, opts?)`

Moves any existing local entity with the same finite-coordinate and heading behavior.
`entity` must be a positive finite integer handle.

`opts.fade` defaults to a 500ms fade. Pass a millisecond value to customise it,
or `false` to move immediately without fading. Options must be a table; fade
must be `false`, `true`, or a finite number.

```lua
Kora.teleport.player(vector4(1073.0, -3102.49, -39.0, 266.61))
Kora.teleport.entity(vehicle, destination, { fade = false })
```

### `Kora.teleport.toWaypoint(opts?)`

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
