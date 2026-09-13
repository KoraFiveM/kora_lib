# Zones module

## Overview
The zones module gives you box, sphere, and poly trigger zones for the local player, with `onEnter`/`onExit`/`inside` callbacks — similar to ox_lib's zones. Points aren't a separate feature: `QB.zones.point()` is just a sphere with a small default radius, returning the same handle every other shape returns.

## API

### `QB.zones.box(opts)`
Creates a rotatable box zone.

#### Parameters
- `coords: vector3` — Box center.
- `size: vector3` — Full extents (x, y, z), all greater than 0.
- `rotation: number | nil` — Degrees around the Z axis. Defaults to `0`.
- `onEnter: fun(zone) | nil`, `onExit: fun(zone) | nil`, `inside: fun(zone, coords) | nil` — Callbacks.
- `trackPlayer: boolean | nil` — Set `false` for a predicate-only zone that only uses `contains()`. It is then omitted from the player-position grid and `isInside()` remains false. Defaults to `true`.
- `debug: boolean | nil` — Draw the zone's bounds while it exists. Defaults to `false`.
- `data: any` — Arbitrary passthrough value, not validated. Read it back via `zone.data` on the returned handle.

#### Returns
- `table` — A zone handle: `{ id, type, resource, remove(), contains(coords), isInside() }`.

#### Example
```lua
local zone = QB.zones.box({
    coords = vector3(100.0, 200.0, 30.0),
    size = vector3(4.0, 4.0, 3.0),
    rotation = 45.0,
    onEnter = function(zone) print('entered box zone', zone.id) end,
    onExit = function(zone) print('left box zone', zone.id) end,
})
```

### `QB.zones.sphere(opts)`
Creates a sphere zone.

#### Parameters
- `coords: vector3` — Sphere center.
- `radius: number` — Must be greater than 0.
- `onEnter`, `onExit`, `inside`, `trackPlayer`, `debug`, `data` — Same as `box`.

#### Example
```lua
QB.zones.sphere({
    coords = vector3(100.0, 200.0, 30.0),
    radius = 3.0,
    inside = function(zone, coords) DrawText('Press E to interact') end,
})
```

### `QB.zones.poly(opts)`
Creates a polygon zone: a 2D footprint extruded across a vertical height band.

#### Parameters
- `points: vector3[]` — At least 3 points. Only their XY defines the footprint.
- `thickness: number | nil` — Height of the band, measured **upward from the lowest point's Z** (so the zone sits on the surface the points were drawn on, and `thickness` is simply how tall it is). Defaults to `Config.zones.defaultPolyThickness`. Ignored if `minZ`/`maxZ` are given — pass those explicitly for a band that floats above the points.
- `minZ: number | nil`, `maxZ: number | nil` — Explicit height band. Must both be given, or neither.
- `onEnter`, `onExit`, `inside`, `trackPlayer`, `debug`, `data` — Same as `box`.

#### Behavior
This is a **2D footprint plus a height range**, not an arbitrary 3D-oriented volume — matching ox_lib's own poly zones. It covers building floors, parking lots, and interiors well; it does not support a tilted/rotated polygon plane.

#### Example
```lua
QB.zones.poly({
    points = {
        vector3(100.0, 200.0, 30.0),
        vector3(110.0, 200.0, 30.0),
        vector3(110.0, 210.0, 30.0),
        vector3(100.0, 210.0, 30.0),
    },
    thickness = 4.0,
})
```

### `QB.zones.point(opts)`
Creates a point zone. Not a separate shape — a sphere with a small default radius, returning the exact same kind of handle `QB.zones.sphere` does.

#### Parameters
- `coords: vector3` — Point location.
- `radius: number | nil` — Defaults to `Config.zones.defaultPointRadius` (1.0m).
- `onEnter`, `onExit`, `inside`, `trackPlayer`, `debug`, `data` — Same as `box`.

#### Example
```lua
QB.zones.point({ coords = vector3(100.0, 200.0, 30.0) })
```

### `QB.zones.startCreator(zoneType, existingOpts)`
Starts the in-world zone creator: fly its own scripted camera to survey the build site, aim and press the placement key to mark points against the world (no coordinate typing), adjust size/rotation/radius/thickness with the scroll wheel, then confirm to open a summary dialog with the generated `QB.zones.<type>({...})` snippet and a copy-to-clipboard button.

The creator is a coordinate/configuration builder only. Confirming removes its preview and returns the generated options; it does **not** register a live zone. Create one explicitly with `QB.zones[result.type](result.opts)` if the calling resource needs it at runtime.

The creator spins up its own free-flying camera rather than using your normal view, so you can survey a build site from angles walking wouldn't reach. It blends in smoothly from wherever the gameplay camera already was, and blends back out the same way when the creator ends (cancel or confirm) — both eased over `Config.zones.creator.cameraTransitionMs`.

#### Parameters
- `zoneType: "box" | "sphere" | "poly"`
- `existingOpts?: table` — Seeds the creator from an existing zone's opts (same shape `QB.zones.<type>()` takes), so you can reposition/resize an already-built zone instead of starting empty: `QB.zones.startCreator("box", myZoneOpts)`. Any field it doesn't provide falls back to the usual default. Seed values are validated like the real constructors (positive sizes/radius, point cap) and raise synchronously when malformed.

#### Default controls
| Key | Action |
|---|---|
| Mouse | Look around (drives the creator's own scripted camera) |
| `W`/`A`/`S`/`D` | Fly the creator's camera |
| `E` | Place a point at whatever you're aiming at |
| `Backspace` | Undo the last placed point |
| `Tab` (poly, cycled to "edit point") + `E` | Pick up the hovered point, fly anywhere, then `E` again to drop it at the new aim — `Backspace` cancels the pick-up instead of deleting a point while one is held |
| `Tab` | Cycle which parameter the scroll wheel adjusts |
| Scroll wheel | Adjust the active parameter |
| `Shift` | Hold for faster camera movement, and to adjust the active parameter in bigger steps |
| `Enter` | Confirm (once placement is valid) and open the summary dialog |
| `X` | Cancel |

All discrete actions above are registered through `QB.keybind`, so they're
rebindable through FiveM's own keybind settings. Mouse-look/WASD, Shift, and
the scroll wheel still drive the freecam directly and aren't independent
key mappings.

Mouse-look and movement are suppressed through a `QB.controls` lease while the creator is active. Confirm, cancel, an internal error, or either owning resource stopping releases the lease.

#### Returns
- `{ type, opts }` once confirmed (`opts` matches that shape's own constructor options, so `QB.zones.<type>(result.opts)` recreates it), or `nil` if cancelled, if a creator was already running, or if the creator is disabled (`Config.zones.creator.enabled = false`) -- check qblib's own console to tell which, since that detail doesn't cross the exports boundary. An invalid `zoneType` (or malformed `existingOpts`) raises a synchronous error instead, exactly like the zone constructors themselves. Must run inside a coroutine (`CreateThread`, a command handler, ...), since this suspends until the player confirms or cancels.

#### Example
```lua
RegisterCommand('my_zone_tool', function()
    local result = QB.zones.startCreator("box")
    if not result then return print("cancelled (or failed -- see qblib's own console)") end

    print("captured:", QB.zones.generateSnippet(result.type, result.opts))
end, false)
```

An equivalent `/qb_zonecreator [box|sphere|poly]` command (default shape `box`) ships built in, for use without writing any Lua at all. The server command requires the `qblib.editor` ACE by default; configure it through `Config.editor`. This is an admin UX gate, not a security boundary against a modified client, so resources that persist captured data must still authorize and validate the change server-side.

### `QB.zones.generateSnippet(zoneType, opts)`
Formats zone options into the `QB.zones.<type>({...})` Lua snippet the creator's confirm dialog shows and copies to the clipboard. Pure and deterministic — useful on its own if you already have `opts` (from `startCreator`, or hand-built) and just want the text.

#### Parameters
- `zoneType: "box" | "sphere" | "poly"`
- `opts: table` — same shape as that type's own constructor options.

#### Returns
- `string`

#### Example
```lua
print(QB.zones.generateSnippet("sphere", { coords = vector3(100.0, 200.0, 30.0), radius = 3.0 }))
-- QB.zones.sphere({
--     coords = vector3(100.00, 200.00, 30.00),
--     radius = 3.00,
-- })
```

### `QB.zones.getInside(resource)`
Every zone the local player is currently standing in, across every resource — including zones you didn't create yourself, which is otherwise impossible to see.

#### Parameters
- `resource: string | nil` — Only return zones owned by this resource. Omit for all of them.

#### Returns
- `QBZoneHandle[]` — The same handle objects the constructors returned (identity-comparable with your own references). Unordered.

#### Behavior
Read straight off the enter/exit state the tick loop already maintains, so this costs a registry walk and no containment maths. It reflects the last tick, not a fresh test — for an exact "is this point in this zone right now" answer, use a handle's own `contains(coords)`.

#### Example
```lua
for _, zone in ipairs(QB.zones.getInside()) do
    print(('inside %s zone %d (owned by %s)'):format(zone.type, zone.id, zone.resource))
end
```

### Creator and debug state

- `QB.zones.isCreatorActive()` reports whether the in-world creator is active.
- `QB.zones.edit(handle, opts?)` reopens the creator using a live handle's
  current options, replacing that handle only after confirmation.
- `QB.zones.setDebug(id, enabled)` changes debug rendering for a live zone.

### Zone handle
Every constructor above returns the same shape:
- `id: integer`
- `type: "box" | "sphere" | "poly"`
- `resource: string` — The resource that created this zone.
- `data: any` — Whatever was passed as `opts.data` at creation, unchanged.
- `remove(): nil` — Tears the zone down. Same teardown path a resource stop uses.
- `contains(coords): boolean` — Runs the zone's exact containment test against an arbitrary point.
- `isInside(): boolean` — Whether the local player is currently inside, read live (not a snapshot from creation time).

## Performance
Zones aren't checked one-by-one against every player position every tick. A shared spatial grid (cell size `Config.zones.gridSize`, 50m by default) buckets zones by horizontal location; each tick only looks at the 3×3 neighborhood of cells around the player, and only runs a zone's real containment test after a cheap bounding-box check confirms the player could plausibly be inside it.

The check rate itself adapts: `Config.zones.tickFar` (1000ms) when nothing is nearby, `Config.zones.tickNear` (200ms) when something is close or you're inside a zone with no `inside` callback, and `Config.zones.tickInside` (0ms — every frame) only while you're inside a zone that registered an `inside` callback. The near threshold widens automatically for fast-moving vehicles/aircraft so a small zone can't be skipped between two slow-tier checks.

## Notes
- Zones are local-player-relative only — there's no server-side zone registration or cross-player zone state.
- `onExit` does not fire when a zone is torn down while you're inside it (via `remove()` or because its owning resource stopped) — there's nothing left to call back into at that point.
- Each zone remembers which resource created it (`GetInvokingResource()`), and is automatically removed when that resource stops — you don't need to track/clean up your own zones on resource restart.
- A callback that errors is logged and skipped; it won't break enter/exit tracking for other zones, including ones owned by other resources.
- `QB.zones.startCreator`'s confirm dialog goes through `QB.nui.*` (`modules/nui/`) and needs the NUI page loaded to work — see its docs for the headless-UI conventions this follows.
