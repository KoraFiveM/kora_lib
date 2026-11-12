---
title: "Placement"
sidebar_position: 30
---


# Placement

Opens a local developer tool for positioning a ped, vehicle, or object model and capturing its transform. It creates one temporary preview, never a networked entity, then returns the model, vector3 position, heading, and rotation after the player confirms. The preview is deleted on every exit path.

Namespace: `Kora.placement` · Source: `modules/placement/client.lua`

## Placement start options

Pass optional defaults to start(model, options). Bounds constrain keyboard, raycast, and numeric placement. A `?` after a name means the option is optional.

### options table

| Option | Type | Description |
| --- | --- | --- |
| `coords?` | vector3 | Optional initial position for the preview. Without it, placement starts at the surface under the gameplay camera crosshair. |
| `rotation?` | vector3 | Optional initial Euler rotation. |
| `bounds?` | table | Optional boundary definition containing points and minZ/maxZ limits. |
| `raycast?` | boolean | Whether placement uses the camera ray to align with a visible surface. |
| `numericInput?` | boolean | Whether to enable the numeric vector entry form. |
| `copy?` | boolean | Whether confirmation copies the generated snippet to the clipboard. false shows a confirmation dialog and still returns the transform. |

## Controls

Mouse and WASD fly the camera; G changes movement mode; arrows and Page Up/Page Down move the preview; Tab selects yaw, pitch, or roll; brackets adjust rotation; Shift speeds movement; Enter opens the finish summary; X cancels. Keybinds can be rebound in FiveM settings.

## What confirmation does

Confirmation returns or copies transform data. It does not save the object, create a networked entity, or authorize a later server change. Validate and authorize any persisted placement on the server.

## Cleanup and limits

Only one placement session can run, and it cannot overlap the zone creator. The preview is local, frozen, translucent, non-colliding, and deleted after confirmation, cancellation, errors, or resource shutdown.

## Functions

Start a placement session, check or cancel it, and format the final result as Lua source.

### `Kora.placement.start(model, options?)`

Streams a valid model, creates a local preview, and opens the placement camera and controls. Confirm to receive the transform; cancel to receive nil.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `model` | string \| integer | Non-empty model name or finite integer hash. |
| `options?` | table | Optional start position, bounds, raycast, numeric input, and clipboard settings listed above. |

**Returns**

- **result** — placement table on confirmation, or nil on cancellation. Same-resource calls may return an awaitable promise; calls across the kora_lib export boundary return the settled result.

**Example**

```lua
local result = Kora.placement.start('prop_bin_08')
if not result then return print('Placement cancelled') end
print(Kora.placement.generateSnippet(result))
```

**Representative console output**

```text
On confirmation, prints a Lua table with the selected model and transform.
```

### `Kora.placement.isActive()`

Reports whether placement is starting, active, or still cleaning up a camera transition.

**Parameters**



**Returns**

- **active** — boolean.

**Example**

```lua
if Kora.placement.isActive() then print('Placement is busy') end
```

**Representative console output**

```text
Prints while a placement session still owns its preview or camera.
```

### `Kora.placement.cancel()`

Cancels the active placement session owned by the calling resource. It cleans up the preview, camera, controls, and dialogs.

**Parameters**



**Returns**

- **cancelled** — true when this resource’s session was cancelled.
- **false, reason** — when another resource owns the active session or there is no caller-owned session.

**Example**

```lua
local cancelled, reason = Kora.placement.cancel()
if not cancelled then print(reason) end
```

**Representative console output**

```text
If cancellation is not available, prints the reason.
```

### `Kora.placement.generateSnippet(result)`

Formats a confirmed placement result as ready-to-paste Lua table source. It formats numbers to four decimal places without changing the original result.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `result` | table | Confirmed result containing model, vector3 coords, heading, and rotation components. All numeric components must be finite. |

**Returns**

- **snippet** — string containing a Lua table literal.

**Example**

```lua
local snippet = Kora.placement.generateSnippet(result)
print(snippet)
```

**Representative console output**

```text
Prints a ready-to-paste Lua table with the placement transform.
```

## Limits and related APIs

Invalid or unloadable models and a missing initial raycast hit reject the start. Numeric and dialog state is cancelled and focus released if the owner resource stops.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/placement/docs.md` or `local/placement/docs.md`) that the reference above does not state.

`Kora.placement` is a client-side developer tool for positioning any valid ped,
vehicle, or object model and copying its transform. It creates one temporary,
non-networked preview and always deletes it when the session finishes.

### `Kora.placement.start(model, options?)`

Optional gameplay settings preserve the default developer tool:

```lua
local result = Kora.placement.start(model, {
    coords = saved.coords,
    rotation = saved.rotation,
    bounds = { points = boundary, minZ = floor, maxZ = ceiling },
    raycast = true, numericInput = true, copy = false,
})
```

The bounds constrain initial, keyboard, raycast and numeric positioning. R
toggles surface placement; keyboard or numeric movement disables snapping for
fine adjustments. N opens the existing shared numeric vector form. `copy =
false` uses a shared confirmation dialog and returns the same transform without
writing the clipboard. Server-side consumers must still authorize the model,
boundary, transform and placement count. Owning-resource stop also cancels any
numeric/confirmation request and releases its focus.

Starts at the solid surface currently under the gameplay-camera crosshair. The
model is validated and streamed through kora_lib's existing entity helpers. A
scripted free camera then lets the player inspect the placement from any angle.
`model` is a non-empty model name or a finite integer model hash.

```lua
local result = Kora.placement.start('prop_bin_08')
if not result then return print('placement cancelled') end

print(Kora.placement.generateSnippet(result))
```

Same-resource calls return an awaitable promise. Calls made through
`@kora_lib/init.lua` cross the kora_lib export boundary and return the settled result
directly, matching `Kora.zones.startCreator`.

The confirmed result is:

```lua
{
    model = 'prop_bin_08',
    coords = { x = 100.0, y = 200.0, z = 30.0 },
    heading = 270.0,
    rotation = {
        pitch = 0.0,
        roll = 0.0,
        yaw = -90.0,
    },
}
```

Heading and Euler yaw are read independently from the preview entity. The
Euler values use rotation order `2`; heading may therefore be `270` while yaw
is `-90`. Cancelling resolves `nil`. Invalid/unloadable models, a missing
initial raycast hit, disabled placement, or another active creator reject.

The calling resource owns its session. If it stops, kora_lib cancels the session,
closes any open summary, releases controls and camera state, restores the
radar/player state, and deletes the local preview. Stopping kora_lib performs the
same cleanup immediately and rejects the interrupted promise. A confirmed or
cancelled session always deletes its preview; placement never creates a
networked entity.

### Controls

- Mouse + WASD: fly the scripted camera.
- G: toggle camera-relative and world-grid camera movement.
- Arrow keys: move the preview horizontally relative to camera yaw.
- Page Up / Page Down: move the preview vertically.
- Tab: cycle yaw, pitch, and roll.
- `[` / `]`: decrease/increase the selected rotation axis.
- Shift: fast movement, rotation, and camera flight.
- Enter: open the copy/finish summary.
- X: cancel.

All actions use `Kora.keybind`, so players may rebind them in FiveM's key
settings. `Kora.instructional` renders the live bindings and updates the movement
mode and active rotation axis; the NUI HUD is reserved for transform state.

### Other API

- `Kora.placement.isActive()` reports startup, active editing, and camera
  transition teardown. It is exported as `placement_isActive` automatically.
- `Kora.placement.cancel()` releases the invoking resource's active preview,
  camera, controls and dialogs, and returns its pending placement result as
  `nil`. It returns `false, reason` when another resource owns the placement.
- `Kora.placement.generateSnippet(result)` formats a ready-to-paste Lua table at
  four decimal places without rounding the returned result itself. Every
  coordinate, heading, and rotation component must be finite.
- `/kora_place <model>` starts the same flow without writing Lua. A numeric
  argument is treated as a model hash. The server command requires the
  `kora_lib.editor` ACE by default; configure it through `Config.editor`.

Only one placement may run at a time, and it cannot overlap the zone creator.
The preview is translucent, frozen, invincible, non-colliding, and visible only
to the local client. Confirmation copies/returns data; it never persists the
preview or creates a server/networked entity.

The command permission is an admin UX gate, not a security boundary against a
modified client. Any resource that persists or applies captured data must
validate and authorize that change independently on the server.
