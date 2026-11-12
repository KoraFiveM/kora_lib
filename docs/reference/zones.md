---
title: "Zones module"
sidebar_position: 37
---

# Zones module

## Overview
The zones module gives you box, sphere, circle, and poly trigger zones for the local player, with `onEnter`/`onExit`/`inside` callbacks — similar to ox_lib's zones. Points aren't a separate feature: `Kora.zones.point()` is just a sphere with a small default radius, returning the same handle every other shape returns.

## API

### `Kora.zones.box(opts)`
Creates a rotatable box zone.

#### Parameters
- `coords: vector3` — Finite Box center coordinates.
- `size: vector3` — Finite full extents (x, y, z), all greater than 0.
- `rotation: finite number | nil` — Degrees around the Z axis. Defaults to `0`.
- `ignoreZ: boolean | nil` — Ignore the Z extent and test the rotated XY rectangle only. Defaults to `false`.
- `onEnter: fun(zone) | nil`, `onExit: fun(zone) | nil`, `inside: fun(zone, coords) | nil` — Callbacks.
- `trackPlayer: boolean | nil` — Set `false` for a predicate-only zone that only uses `contains()`. It is then omitted from the player-position grid and `isInside()` remains false. Defaults to `true`.
- `debug: boolean | nil` — Draw the zone's bounds while it exists. Defaults to `false`.
- `data: any` — Arbitrary passthrough value, not validated. Read it back via `zone.data` on the returned handle.

#### Returns
- `table` — A zone handle: `{ id, type, resource, remove(), contains(coords), isInside() }`.

#### Example
```lua
local zone = Kora.zones.box({
    coords = vector3(100.0, 200.0, 30.0),
    size = vector3(4.0, 4.0, 3.0),
    rotation = 45.0,
    onEnter = function(zone) print('entered box zone', zone.id) end,
    onExit = function(zone) print('left box zone', zone.id) end,
})
```

### `Kora.zones.sphere(opts)`
Creates a sphere zone.

#### Parameters
- `coords: vector3` — Finite sphere center coordinates.
- `radius: finite number` — Must be greater than 0.
- `includeBoundary: boolean | nil` — Whether a point exactly on `radius` counts as inside. Defaults to `true`.
- `onEnter`, `onExit`, `inside`, `trackPlayer`, `debug`, `data` — Same as `box`.

#### Example
```lua
Kora.zones.sphere({
    coords = vector3(100.0, 200.0, 30.0),
    radius = 3.0,
    inside = function(zone, coords) DrawText('Press E to interact') end,
})
```

### `Kora.zones.circle(opts)`
Creates an exact flat 2D circle zone. It tests the XY radius only, so the
point's Z coordinate is always ignored. This is useful for map areas that span
several elevations and for migrating a legacy `CircleZone` with `useZ = false`.

#### Parameters
- `coords: vector3` — Finite circle center coordinates. Z is retained for debugging and editing, but does not affect containment.
- `radius: finite number` — Must be greater than 0.
- `includeBoundary: boolean | nil` — Whether a point exactly on `radius` counts as inside. Defaults to `true`.
- `onEnter`, `onExit`, `inside`, `trackPlayer`, `debug`, `data` — Same as `box`.

#### Example
```lua
Kora.zones.circle({
    coords = vector3(100.0, 200.0, 30.0),
    radius = 12.0,
    onEnter = function() print('entered the map area') end,
})
```

### `Kora.zones.poly(opts)`
Creates a polygon zone: a 2D footprint extruded across a vertical height band.

#### Parameters
- `points: vector3[]` — A dense array of at least 3 points with finite coordinates. Only their XY defines the footprint.
- `thickness: finite number | nil` — Height of the band, measured **upward from the lowest point's Z** (so the zone sits on the surface the points were drawn on, and `thickness` is simply how tall it is). Defaults to `Config.zones.defaultPolyThickness`. Ignored if `minZ`/`maxZ` are given — pass those explicitly for a band that floats above the points.
- `minZ: finite number | nil`, `maxZ: finite number | nil` — Explicit height band. Must both be given, or neither.
- `ignoreZ: boolean | nil` — Ignore the height band and test the XY footprint only. Defaults to `false`; useful for legacy map areas that deliberately span every elevation.
- `onEnter`, `onExit`, `inside`, `trackPlayer`, `debug`, `data` — Same as `box`.

#### Behavior
This is a **2D footprint plus a height range**, not an arbitrary 3D-oriented volume — matching ox_lib's own poly zones. It covers building floors, parking lots, and interiors well; it does not support a tilted/rotated polygon plane. Set `ignoreZ = true` only when the footprint intentionally spans every elevation.

#### Example
```lua
Kora.zones.poly({
    points = {
        vector3(100.0, 200.0, 30.0),
        vector3(110.0, 200.0, 30.0),
        vector3(110.0, 210.0, 30.0),
        vector3(100.0, 210.0, 30.0),
    },
    thickness = 4.0,
})
```

### `Kora.zones.point(opts)`
Creates a point zone. Not a separate shape — a sphere with a small default radius, returning the exact same kind of handle `Kora.zones.sphere` does.
When its radius is omitted, the default is applied without mutating your `opts` table.

#### Parameters
- `coords: vector3` — Point location.
- `radius: number | nil` — Defaults to `Config.zones.defaultPointRadius` (1.0m) only when omitted; supplied values must be positive and finite.
- `onEnter`, `onExit`, `inside`, `trackPlayer`, `debug`, `data` — Same as `box`.

#### Example
```lua
Kora.zones.point({ coords = vector3(100.0, 200.0, 30.0) })
```

### `Kora.zones.startCreator(zoneType, existingOpts)`
Starts the in-world zone creator: fly its own scripted camera to survey the build site, aim and press the placement key to mark points against the world (no coordinate typing), adjust size/rotation/radius/thickness with the scroll wheel, then confirm to open a summary dialog with the generated `Kora.zones.<type>({...})` snippet and a copy-to-clipboard button.

The creator is a coordinate/configuration builder only. Confirming removes its preview and returns the generated options; it does **not** register a live zone. Create one explicitly with `Kora.zones[result.type](result.opts)` if the calling resource needs it at runtime.

The creator starts `Kora.freecam` without a distance limit rather than using your normal view, so you can survey a build site from angles walking wouldn't reach. It blends in smoothly from wherever the gameplay camera already was, and blends back out the same way when the creator ends (cancel or confirm) — both eased over `Config.zones.creator.cameraTransitionMs`.

#### Parameters
- `zoneType: "box" | "sphere" | "poly"`
- `existingOpts?: table` — Seeds the creator from an existing zone's opts (same shape `Kora.zones.<type>()` takes), so you can reposition/resize an already-built zone instead of starting empty: `Kora.zones.startCreator("box", myZoneOpts)`. Any field it doesn't provide falls back to the usual default. Seed values are validated like the real constructors (finite coordinates/numbers, positive sizes/radius, paired poly height bounds, point cap) and raise synchronously when malformed.

#### Default controls
| Key | Action |
|---|---|
| Mouse | Look around through the shared freecam |
| `W`/`A`/`S`/`D` | Fly the creator's camera |
| `G` | Toggle camera-relative and world-grid movement |
| `E` or Left click | Place a point at whatever the crosshair is aiming at |
| `Backspace` or Right click | Undo the last placed point |
| `Tab` (poly, cycled to "edit point") + `E` / Left click | Pick up the hovered point, fly anywhere, then `E` / Left click again to drop it at the new aim — `Backspace` / Right click cancels the pick-up instead of deleting a point while one is held |
| `Tab` | Cycle which parameter the scroll wheel adjusts |
| Scroll wheel | Adjust the active parameter |
| `Shift` | Hold for faster camera movement, and to adjust the active parameter in bigger steps |
| `Enter` | Confirm (once placement is valid) and open the summary dialog |
| `X` | Cancel |

Clicks aim with the freecam crosshair like `E` (no free cursor), and are separate `MOUSE_BUTTON` keybinds (`kora_lib_zonecreator_place_click` / `kora_lib_zonecreator_undo_click`) running the same handlers; the creator also disables attack/aim controls so a click never fires or punches.

All discrete actions above are registered through `Kora.keybind`, so they're
rebindable through FiveM's own keybind settings. Mouse-look/WASD, Shift, and
the scroll wheel still drive the freecam directly and aren't independent
key mappings. The live bindings and current movement/placement mode are shown
through `Kora.instructional`; the NUI editor card is reserved for shape state.

Mouse-look and movement are suppressed through a `Kora.controls` lease while the creator is active. Confirm, cancel, an internal error, or either owning resource stopping releases the lease.

#### Returns
- `{ type, opts }` once confirmed (`opts` matches that shape's own constructor options, so `Kora.zones.<type>(result.opts)` recreates it), or `nil` if cancelled, if a creator was already running, or if the creator is disabled (`Config.zones.creator.enabled = false`) -- check kora_lib's own console to tell which, since that detail doesn't cross the exports boundary. An invalid `zoneType` (or malformed `existingOpts`) raises a synchronous error instead, exactly like the zone constructors themselves. Must run inside a coroutine (`CreateThread`, a command handler, ...), since this suspends until the player confirms or cancels.

#### Example
```lua
RegisterCommand('my_zone_tool', function()
    local result = Kora.zones.startCreator("box")
    if not result then return print("cancelled (or failed -- see kora_lib's own console)") end

    print("captured:", Kora.zones.generateSnippet(result.type, result.opts))
end, false)
```

An equivalent `/kora_zonecreator [box|sphere|poly]` command (default shape `box`) ships built in, for use without writing any Lua at all. The server command requires the `kora_lib.editor` ACE by default; configure it through `Config.editor`. This is an admin UX gate, not a security boundary against a modified client, so resources that persist captured data must still authorize and validate the change server-side.

### `Kora.zones.generateSnippet(zoneType, opts)`
Formats zone options into the `Kora.zones.<type>({...})` Lua snippet the creator's confirm dialog shows and copies to the clipboard. Pure and deterministic — useful on its own if you already have `opts` (from `startCreator`, or hand-built) and just want the text.

#### Parameters
- `zoneType: "box" | "sphere" | "poly"`
- `opts: table` — same shape as that type's own constructor options. Numeric values must be finite; a poly snippet preserves either `thickness` or an explicit `minZ`/`maxZ` band.

#### Returns
- `string`

#### Example
```lua
print(Kora.zones.generateSnippet("sphere", { coords = vector3(100.0, 200.0, 30.0), radius = 3.0 }))
-- Kora.zones.sphere({
--     coords = vector3(100.00, 200.00, 30.00),
--     radius = 3.00,
-- })
```

### `Kora.zones.getInside(resource)`
Every zone the local player is currently standing in, across every resource — including zones you didn't create yourself, which is otherwise impossible to see.

#### Parameters
- `resource: string | nil` — Only return zones owned by this resource. Omit for all of them.

#### Returns
- `KoraZoneHandle[]` — The same handle objects the constructors returned (identity-comparable with your own references). Unordered.

#### Behavior
Read straight off the enter/exit state the tick loop already maintains, so this costs a registry walk and no containment maths. It reflects the last tick, not a fresh test — for an exact "is this point in this zone right now" answer, use a handle's own `contains(coords)`.

#### Example
```lua
for _, zone in ipairs(Kora.zones.getInside()) do
    print(('inside %s zone %d (owned by %s)'):format(zone.type, zone.id, zone.resource))
end
```

### `Kora.zones.setDebug(id, enabled)`
Changes debug rendering without recreating a zone.

#### Parameters
- `id: integer | nil` — A zone handle's `id`. Omit it to update every currently registered zone.
- `enabled: boolean`

`zone.setDebug(enabled)` is the equivalent single-zone convenience method. Both
return `false` when a foreign resource attempts to change a zone. Debug drawing
is intended for development: it runs every frame while enabled.

### `Kora.zones.edit(handle, opts)`
Updates a live box, sphere, or circle zone in place and returns the **same** handle. This is deliberately narrow: it supports `coords`, `onEnter`, and `onExit` only. Pass `false` for either callback to detach it. A polygon cannot move this way because its location is its points; shape dimensions, rotation, points, and height ranges require replacing the zone.

All requested fields are validated before any mutation, so an invalid mixed edit leaves the zone unchanged. It returns `nil, "Zone is owned by another resource."` rather than mutating a foreign zone.

```lua
Kora.zones.edit(zone, {
    coords = vector3(120.0, 200.0, 30.0),
    onExit = false,
})
```

### `Kora.zones.isCreatorActive()`
Returns `true` while the in-world creator owns player input. Use it when a consumer has a conflicting keybind and should temporarily yield to the creator. It does not indicate whether any ordinary runtime zones exist.

### Zone handle
Every constructor above returns the same shape:
- `id: integer`
- `type: "box" | "sphere" | "circle" | "poly"`
- `resource: string` — The resource that created this zone.
- `data: any` — Whatever was passed as `opts.data` at creation, unchanged.
- `remove(): boolean` — Tears the zone down. Returns `false` for a foreign or already removed zone.
- `contains(coords): boolean` — Runs the zone's exact containment test against an arbitrary point.
- `isInside(): boolean` — Whether the local player is currently inside, read live (not a snapshot from creation time).
- `setDebug(enabled): boolean` — Enables or disables this zone's debug rendering. Returns `false` for a foreign zone. Equivalent to `Kora.zones.setDebug(zone.id, enabled)`.

## Performance
Zones aren't checked one-by-one against every player position every tick. A shared spatial grid (cell size `Config.zones.gridSize`, 50m by default) buckets zones by horizontal location; each tick only looks at the 3×3 neighborhood of cells around the player, and only runs a zone's real containment test after a cheap bounding-box check confirms the player could plausibly be inside it. Flat circles and any box/poly with `ignoreZ = true` skip the vertical AABB term before their exact XY test, so elevation-free containment is exact rather than a very tall approximation. The small set of zones already entered is also checked for exit, so a teleport or fast vehicle move cannot leave `isInside()` stale after it moves outside that neighborhood.

The check rate itself adapts: `Config.zones.tickFar` (1000ms) when nothing is nearby, `Config.zones.tickNear` (200ms) when something is close or you're inside a zone with no `inside` callback, and `Config.zones.tickInside` (0ms — every frame) only while you're inside a zone that registered an `inside` callback. The near threshold widens automatically for fast-moving vehicles/aircraft so a small zone can't be skipped between two slow-tier checks.

## Notes
- Zones are local-player-relative only — there's no server-side zone registration or cross-player zone state.
- `onExit` does not fire when a zone is torn down while you're inside it (via `remove()` or because its owning resource stopped) — there's nothing left to call back into at that point.
- Each zone remembers which resource created it (`GetInvokingResource()`), and is automatically removed when that resource stops — you don't need to track/clean up your own zones on resource restart.
- A callback that errors is logged and skipped; it won't break enter/exit tracking for other zones, including ones owned by other resources.
- `Kora.zones.startCreator`'s confirm dialog goes through `Kora.nui.*` (`modules/nui/`) and needs the NUI page loaded to work — see its docs for the headless-UI conventions this follows.
