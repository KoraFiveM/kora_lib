---
title: "Zones"
sidebar_position: 37
---


# Zones

Registers local-player trigger areas with enter, exit, and while-inside callbacks. Shapes include rotated boxes, spheres, flat circles, extruded polygons, and convenient point spheres. Each returned handle can test arbitrary coordinates, report player state, or remove the zone.

Namespace: `Kora.zones` · Source: `modules/zones/client.lua`

## Shared shape options

These fields apply to the constructors unless a shape-specific group below narrows them. Callbacks receive the zone handle; inside also receives the player coordinates. A `?` after a name means the option is optional.

### Callbacks and lifecycle

| Option | Type | Description |
| --- | --- | --- |
| `onEnter?` | function | Called once when the tracked local player enters: onEnter(zone). |
| `onExit?` | function | Called once when the player exits: onExit(zone). |
| `inside?` | function | Called each inside tick: inside(zone, coords). Use sparingly; it can run every frame while active. |
| `trackPlayer?` | boolean | Defaults true. Set false for a predicate-only zone used with contains(); it will not track player entry and isInside() remains false. |
| `debug?` | boolean | Draw bounds for development; defaults false. |
| `data?` | any | Arbitrary value copied onto zone.data without validation. |

### Box fields

| Option | Type | Description |
| --- | --- | --- |
| `coords` | vector3 | Required finite center point. |
| `size` | vector3 | Required finite full extents; each component must be greater than zero. |
| `rotation?` | number | Degrees around the vertical axis; defaults 0. |
| `ignoreZ?` | boolean | Ignore height and test the rotated 2D footprint only; defaults false. |

### Sphere and circle fields

| Option | Type | Description |
| --- | --- | --- |
| `coords` | vector3 | Required finite center point. |
| `radius` | number | Required positive finite radius for sphere/circle. Point defaults to Config.zones.defaultPointRadius (1.0m) only when omitted. |
| `includeBoundary?` | boolean | Whether a point exactly on the radius counts inside; defaults true. |
| `circle Z` | ignored | Circle containment ignores height; Z is kept for display/editing only. |

### Polygon fields

| Option | Type | Description |
| --- | --- | --- |
| `points` | vector3[] | Required dense list of at least three finite points; XY positions form the footprint. |
| `thickness?` | number | Positive vertical height from the lowest point’s height; defaults to Config.zones.defaultPolyThickness. |
| `minZ / maxZ?` | number | Set both to define an explicit vertical band. Supplying only one is invalid; this takes precedence over thickness. |
| `ignoreZ?` | boolean | Ignore the vertical band and test only the polygon footprint. |

### Creator controls

| Option | Type | Description |
| --- | --- | --- |
| `Mouse / W A S D` | controls | Look around and fly the creator camera. |
| `G` | key | Switch camera-relative and world-grid movement. |
| `E / left click` | key | Place a point at the crosshair. |
| `Backspace / right click` | key | Undo the last point; when editing a held point, cancel the move. |
| `Tab / scroll wheel` | controls | Choose which setting the wheel adjusts; Tab cycles settings. |
| `Shift` | key | Move faster and adjust the active setting in larger steps. |
| `Enter / X` | key | Confirm a valid shape / cancel the creator. |

## Handle ownership

A handle records its creator resource. That resource can remove and edit it; other resources can inspect it, but ownership-protected changes return false or an error. Zones are automatically removed when their owner stops.

## Creator output versus live zones

startCreator gathers coordinates and settings. Once it returns, call `Kora.zones[result.type](result.opts)` to register a runtime zone. generateSnippet only creates source text.

## Tick cost and callback timing

A shared spatial grid and bounding checks avoid exact shape math for distant zones. The update rate increases near zones; inside callbacks run every frame while the player is inside. Avoid expensive work in inside and move one-time actions into onEnter.

## Scope

Zones track the local player only and exist on the client. A server cannot use them to prove a player was in an area; validate consequential actions with server-side coordinates and rules.

## Functions

Create a zone once and keep its returned handle. The library tracks player entry and cleans up zones when their owning resource stops.

### `Kora.zones.box(opts)`

Creates a rotated 3D box. Size means full width, depth, and height, not half-extents.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `opts` | table | Requires coords and size vector3 values; see shared shape options and box-specific fields. |

**Returns**

- **zone** — handle with id, type, resource, data, remove, contains, isInside, and setDebug methods.

**Example**

```lua
local zone = Kora.zones.box({
    coords = vector3(100.0, 200.0, 30.0),
    size = vector3(4.0, 4.0, 3.0), rotation = 45.0,
    onEnter = function(zone) print('Entered', zone.id) end,
    onExit = function() print('Left the box') end,
})
```

**Representative console output**

```text
Prints when the player enters and leaves the box.
```

### `Kora.zones.sphere(opts)`

Creates a spherical 3D trigger zone.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `opts` | table | Requires coords and positive radius; see shared shape options. |

**Returns**

- **zone** — zone handle.

**Example**

```lua
local zone = Kora.zones.sphere({
    coords = vector3(100.0, 200.0, 30.0), radius = 3.0,
    inside = function() DrawText('Press E to interact') end,
})
```

**Representative console output**

```text
Shows interaction text while the player remains inside.
```

### `Kora.zones.circle(opts)`

Creates an exact flat circle that checks only XY distance. The player can be at any elevation.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `opts` | table | Requires coords and positive radius; see shared shape options. |

**Returns**

- **zone** — zone handle.

**Example**

```lua
local market = Kora.zones.circle({
    coords = vector3(100.0, 200.0, 30.0), radius = 12.0,
    onEnter = function() print('Entered the market area') end,
})
```

**Representative console output**

```text
Prints when the player crosses into the map area, regardless of elevation.
```

### `Kora.zones.poly(opts)`

Creates a 2D polygon footprint with a vertical height band. It is not a tilted 3D surface.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `opts` | table | Requires at least three vector3 points; optionally set thickness or both minZ/maxZ. |

**Returns**

- **zone** — zone handle.

**Example**

```lua
local lot = Kora.zones.poly({
    points = { vector3(100, 200, 30), vector3(110, 200, 30), vector3(110, 210, 30), vector3(100, 210, 30) },
    thickness = 4.0,
})
```

**Representative console output**

```text
Creates a ground-level footprint four meters tall.
```

### `Kora.zones.point(opts)`

Creates a sphere zone with a small default radius, useful for a single interaction location.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `opts` | table | Requires coords; radius and callbacks are optional. |

**Returns**

- **zone** — same handle type as sphere.

**Example**

```lua
local counter = Kora.zones.point({ coords = vector3(100.0, 200.0, 30.0), onEnter = function() print('At the counter') end })
```

**Representative console output**

```text
Prints when the player reaches the counter.
```

### `Kora.zones.startCreator(zoneType, existingOpts?)`

Opens an in-world camera tool to place points and adjust a zone shape, then shows a generated Lua snippet. It returns settings only; it does not register the live zone.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `zoneType` | 'box' \| 'sphere' \| 'poly' | Shape the creator will configure. |
| `existingOpts?` | table | Optional valid starting settings to reposition or resize. |

**Returns**

- **result** — &#123; type, opts &#125; when confirmed.
- **nil** — cancelled, disabled, or another creator already active.

**Example**

```lua
RegisterCommand('makezone', function()
    local result = Kora.zones.startCreator('box')
    if result then print(Kora.zones.generateSnippet(result.type, result.opts)) end
end, false)
```

**Representative console output**

```text
Prints the Lua code for the configured box; a developer must add a constructor call to create it.
```

### `Kora.zones.generateSnippet(zoneType, opts)`

Formats valid shape settings as a readable Kora.zones constructor snippet.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `zoneType` | 'box' \| 'sphere' \| 'poly' | Shape whose constructor will be printed. |
| `opts` | table | Valid options for that shape. |

**Returns**

- **snippet** — Lua source string.

**Example**

```lua
print(Kora.zones.generateSnippet('sphere', { coords = vector3(100.0, 200.0, 30.0), radius = 3.0 }))
```

**Representative console output**

```text
Prints a Kora.zones.sphere({...}) code block.
```

### `Kora.zones.getInside(resource?)`

Lists zones the local player was recorded inside on the most recent zone tick.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `resource?` | string | When supplied, only return zones owned by that resource. |

**Returns**

- **zones** — array of the original zone handles; order is unspecified.

**Example**

```lua
for _, zone in ipairs(Kora.zones.getInside()) do
    print(zone.type, zone.id, zone.resource)
end
```

**Representative console output**

```text
Prints the type and owner of each zone currently containing the player.
```

### `Kora.zones.setDebug(id?, enabled)`

Enables or disables debug drawing for one zone ID, or all zones when ID is omitted.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id?` | integer | Zone ID; omit to update all registered zones. |
| `enabled` | boolean | Whether to draw debug bounds. |

**Returns**

- **changed** — boolean; false when a foreign resource tries to edit an owned zone.

**Example**

```lua
Kora.zones.setDebug(nil, true)
```

**Representative console output**

```text
Turns on debug drawing for every registered zone.
```

### `Kora.zones.edit(handle, opts)`

Updates supported fields of a live box, sphere, or circle without changing the handle. Validation completes before any field is changed.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `handle` | zone handle | A zone returned by a constructor. |
| `opts` | table | Supported fields: coords, onEnter, and onExit. Use false to detach a callback. |

**Returns**

- **zone** — the same handle after the edit.
- **nil, reason** — if another resource owns it or validation fails.

**Example**

```lua
Kora.zones.edit(zone, { coords = vector3(120.0, 200.0, 30.0), onExit = false })
```

**Representative console output**

```text
Moves the zone and removes its exit callback.
```

### `Kora.zones.isCreatorActive()`

Reports whether the in-world creator currently owns player input.

**Parameters**



**Returns**

- **active** — boolean.

**Example**

```lua
if Kora.zones.isCreatorActive() then print('Zone tool is controlling input') end
```

**Representative console output**

```text
Prints while the creator is active.
```

### `zone:remove()`

Removes this zone and stops its callbacks/debug drawing.

**Parameters**



**Returns**

- **removed** — boolean; false if already removed or owned by another resource.

**Example**

```lua
if zone:remove() then print('Zone removed') end
```

**Representative console output**

```text
Prints after successfully removing the zone.
```

### `zone:contains(coords)`

Tests an arbitrary point against this zone’s exact shape, independent of the player.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `coords` | vector3 | Point to test. |

**Returns**

- **inside** — boolean.

**Example**

```lua
if zone:contains(GetEntityCoords(PlayerPedId())) then print('Player coordinates are inside') end
```

**Representative console output**

```text
Prints when the supplied point lies within the shape.
```

### `zone:isInside()`

Reads whether the local player is currently inside this zone.

**Parameters**



**Returns**

- **inside** — boolean, based on live zone tracking.

**Example**

```lua
if zone:isInside() then print('You are in the zone') end
```

**Representative console output**

```text
Prints while the local player is within the zone.
```

### `zone:setDebug(enabled)`

Changes debug rendering for this one zone.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `enabled` | boolean | Whether to draw this zone. |

**Returns**

- **changed** — boolean; false when the caller does not own the zone.

**Example**

```lua
zone:setDebug(true)
```

**Representative console output**

```text
Draws the zone bounds for development.
```

## Limits and related APIs

All coordinates and dimensions must be finite; radii and box dimensions must be positive. Polygon arrays need at least three points. Removing a zone while inside does not call onExit.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/zones/docs.md` or `local/zones/docs.md`) that the reference above does not state.

### API

#### `Kora.zones.startCreator(zoneType, existingOpts)`
Starts the in-world zone creator: fly its own scripted camera to survey the build site, aim and press the placement key to mark points against the world (no coordinate typing), adjust size/rotation/radius/thickness with the scroll wheel, then confirm to open a summary dialog with the generated `Kora.zones.<type>({...})` snippet and a copy-to-clipboard button.

The creator is a coordinate/configuration builder only. Confirming removes its preview and returns the generated options; it does **not** register a live zone. Create one explicitly with the matching `Kora.zones` constructor (`box`, `sphere`, `circle` or `poly`) and the returned options if the calling resource needs it at runtime.

The creator starts `Kora.freecam` without a distance limit rather than using your normal view, so you can survey a build site from angles walking wouldn't reach. It blends in smoothly from wherever the gameplay camera already was, and blends back out the same way when the creator ends (cancel or confirm) — both eased over `Config.zones.creator.cameraTransitionMs`.

##### Default controls
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

##### Example
```lua
RegisterCommand('my_zone_tool', function()
    local result = Kora.zones.startCreator("box")
    if not result then return print("cancelled (or failed -- see kora_lib's own console)") end

    print("captured:", Kora.zones.generateSnippet(result.type, result.opts))
end, false)
```

An equivalent `/kora_zonecreator [box|sphere|poly]` command (default shape `box`) ships built in, for use without writing any Lua at all. The server command requires the `kora_lib.editor` ACE by default; configure it through `Config.editor`. This is an admin UX gate, not a security boundary against a modified client, so resources that persist captured data must still authorize and validate the change server-side.

#### `Kora.zones.setDebug(id, enabled)`
Changes debug rendering without recreating a zone.

##### Parameters
- `id: integer | nil` — A zone handle's `id`. Omit it to update every currently registered zone.
- `enabled: boolean`

`zone.setDebug(enabled)` is the equivalent single-zone convenience method. Both
return `false` when a foreign resource attempts to change a zone. Debug drawing
is intended for development: it runs every frame while enabled.

#### `Kora.zones.edit(handle, opts)`
Updates a live box, sphere, or circle zone in place and returns the **same** handle. This is deliberately narrow: it supports `coords`, `onEnter`, and `onExit` only. Pass `false` for either callback to detach it. A polygon cannot move this way because its location is its points; shape dimensions, rotation, points, and height ranges require replacing the zone.

All requested fields are validated before any mutation, so an invalid mixed edit leaves the zone unchanged. It returns `nil, "Zone is owned by another resource."` rather than mutating a foreign zone.

```lua
Kora.zones.edit(zone, {
    coords = vector3(120.0, 200.0, 30.0),
    onExit = false,
})
```

### Performance
Zones aren't checked one-by-one against every player position every tick. A shared spatial grid (cell size `Config.zones.gridSize`, 50m by default) buckets zones by horizontal location; each tick only looks at the 3×3 neighborhood of cells around the player, and only runs a zone's real containment test after a cheap bounding-box check confirms the player could plausibly be inside it. Flat circles and any box/poly with `ignoreZ = true` skip the vertical AABB term before their exact XY test, so elevation-free containment is exact rather than a very tall approximation. The small set of zones already entered is also checked for exit, so a teleport or fast vehicle move cannot leave `isInside()` stale after it moves outside that neighborhood.

The check rate itself adapts: `Config.zones.tickFar` (1000ms) when nothing is nearby, `Config.zones.tickNear` (200ms) when something is close or you're inside a zone with no `inside` callback, and `Config.zones.tickInside` (0ms — every frame) only while you're inside a zone that registered an `inside` callback. The near threshold widens automatically for fast-moving vehicles/aircraft so a small zone can't be skipped between two slow-tier checks.
