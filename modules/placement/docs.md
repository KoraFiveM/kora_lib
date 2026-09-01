# Entity placement module

`QB.placement` is a client-side developer tool for positioning any valid ped,
vehicle, or object model and copying its transform. It creates one temporary,
non-networked preview and always deletes it when the session finishes.

## `QB.placement.start(model)`

Starts at the solid surface currently under the gameplay-camera crosshair. The
model is validated and streamed through qblib's existing entity helpers. A
scripted free camera then lets the player inspect the placement from any angle.

```lua
local result = QB.placement.start('prop_bin_08')
if not result then return print('placement cancelled') end

print(QB.placement.generateSnippet(result))
```

Same-resource calls return an awaitable promise. Calls made through
`@qblib/init.lua` cross the qblib export boundary and return the settled result
directly, matching `QB.zones.startCreator`.

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

## Controls

- Mouse + WASD: fly the scripted camera.
- Arrow keys: move the preview horizontally relative to camera yaw.
- Page Up / Page Down: move the preview vertically.
- Tab: cycle yaw, pitch, and roll.
- `[` / `]`: decrease/increase the selected rotation axis.
- Shift: fast movement, rotation, and camera flight.
- Enter: open the copy/finish summary.
- X: cancel.

All actions use `QB.keybind`, so players may rebind them in FiveM's key
settings. The HUD reads the current binding labels at session start.

## Other API

- `QB.placement.isActive()` reports startup, active editing, and camera
  transition teardown. It is exported as `placement_isActive` automatically.
- `QB.placement.generateSnippet(result)` formats a ready-to-paste Lua table at
  four decimal places without rounding the returned result itself.
- `/qb_place <model>` starts the same flow without writing Lua. A numeric
  argument is treated as a model hash.

Only one placement may run at a time, and it cannot overlap the zone creator.
The preview is translucent, frozen, invincible, non-colliding, and visible only
to the local client. Confirmation copies/returns data; it never persists the
preview or creates a server/networked entity.
