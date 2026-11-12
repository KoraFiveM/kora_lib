---
title: "Entity placement module"
sidebar_position: 30
---

# Entity placement module

`Kora.placement` is a client-side developer tool for positioning any valid ped,
vehicle, or object model and copying its transform. It creates one temporary,
non-networked preview and always deletes it when the session finishes.

## `Kora.placement.start(model, options?)`

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

## Controls

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

## Other API

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
