---
title: "DistanceCheck"
sidebar_position: 24
---


# DistanceCheck

## Client

Boolean radius helpers for checking the local player against a coordinate, an entity, or one axis of a point. The client implementation reads the player position from Kora’s cached coords and avoids allocating vectors or calculating square roots.

Namespace: `Kora.distance` · Source: `modules/distancecheck/client.lua`

### How it works

All checks include the radius boundary: a measured distance exactly equal to distance returns true. The default distance is 5.0 game units. player, entity, and xy measure in the three-dimensional world except xy, which intentionally ignores height. x and y compare only their named axis. Coordinate arguments accept vector3 or vector4; for vector4, the heading component is ignored.

### Functions

Each function returns a boolean and throws an assertion error for invalid input. Client functions use the local player as the origin; coords is the exception because it compares two supplied points directly.

**Parameters (all functions):** See each function for its parameters. The optional distance is a finite, non-negative radius in game units and defaults to 5.0 when omitted.

**Returns (all functions):** true when the measured distance is less than or equal to the radius (including its boundary). false when it is greater than the radius.

#### `Kora.distance.player(coords, distance?)`

Checks the local player’s full 3D distance from a target coordinate.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `coords` | vector3 \| vector4 | vector3 or vector4 target position. |
| `distance?` | number | optional finite, non-negative radius in game units; defaults to 5.0. |

**Returns**

boolean. true when the local player is within or exactly on the radius of coords; false when farther away.

**Example**

```lua
local shop = vector3(25.0, -1345.0, 29.5)
if Kora.distance.player(shop, 2.5) then
    openShopPrompt()
end
```

**Representative console output**

```text
Player 2.0 units away: true
Player 3.0 units away: false
```

#### `Kora.distance.coords(coords1, coords2, distance?)`

Compares two supplied points in 3D. This function has the same signature and behavior on client and server; it does not use the local player or a server source.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `coords1` | vector3 \| vector4 | first vector3 or vector4 position. coords2 — second vector3 or vector4 position. |
| `distance?` | number | optional finite, non-negative radius in game units; defaults to 5.0. |

**Returns**

boolean. true when the Euclidean distance between the points is less than or equal to distance; false otherwise.

**Example**

```lua
local near = Kora.distance.coords(
    vector3(10.0, 20.0, 5.0),
    vector3(13.0, 24.0, 5.0),
    5.0
)
print(near)
```

**Representative console output**

```text
true  -- the points are exactly 5.0 units apart; the boundary is included
```

#### `Kora.distance.entity(entity, distance?)`

Checks the local player’s full 3D distance from an entity’s current coordinates.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entity` | entity handle | positive integer entity handle. |
| `distance?` | number | optional finite non-negative radius; defaults to 5.0. |

**Returns**

boolean — true when the local player is within the radius of the entity.

**Example**

```lua
local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
if vehicle ~= 0 and Kora.distance.entity(vehicle, 3.0) then
    showVehicleAction()
end
```

**Representative console output**

```text
true  -- if the local player is no more than 3.0 units from the vehicle
```

#### `Kora.distance.x(point, distance?)`

Compares only the local player’s X-axis position with the position component of point. The other coordinate axes do not affect the result.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `point` | vector3 \| vector4 | vector3 or vector4 reference position; only its X component is used. |
| `distance?` | number | optional finite, non-negative radius in game units; defaults to 5.0. |

**Returns**

boolean. true when the absolute difference on the X axis is less than or equal to distance; false otherwise.

**Example**

```lua
if Kora.distance.x(doorCoords, 1.0) then
    checkDoorPrompt()
end
```

**Representative console output**

```text
Player X-axis difference = 0.8 units, radius = 1.0: true
```

#### `Kora.distance.y(point, distance?)`

Compares only the local player’s Y-axis position with the position component of point. The other coordinate axes do not affect the result.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `point` | vector3 \| vector4 | vector3 or vector4 reference position; only its Y component is used. |
| `distance?` | number | optional finite, non-negative radius in game units; defaults to 5.0. |

**Returns**

boolean. true when the absolute difference on the Y axis is less than or equal to distance; false otherwise.

**Example**

```lua
if Kora.distance.y(routePoint, 2.0) then
    updateRouteState()
end
```

**Representative console output**

```text
Player Y-axis difference = 1.5 units, radius = 2.0: true
```

#### `Kora.distance.xy(point, distance?)`

Checks the local player against a point on the horizontal plane. Height is ignored; both horizontal axes contribute to the 2D distance.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `point` | vector3 \| vector4 | vector3 or vector4 reference position. |
| `distance?` | number | optional finite, non-negative radius in game units; defaults to 5.0. |

**Returns**

boolean. true when the 2D distance on the horizontal plane is less than or equal to distance; false otherwise.

**Example**

```lua
local marker = vector3(205.0, 310.0, 100.0)
if Kora.distance.xy(marker, 4.0) then
    setMarkerVisible(true)
end
```

**Representative console output**

```text
Horizontal separation = 3.0 units, radius = 4.0: true  -- height does not affect the result
```

### Common use cases

- Gate a client interaction prompt based on the local player’s position.
- Check whether the player is near a vehicle, ped, or other entity handle.
- Use xy for map markers or interiors where vertical separation should not affect proximity.
- Use coords to compare two world positions without referring to the local player.

### Limits and related APIs

These are proximity checks, not authorization. A client result can be manipulated by a modified client. Use server-side checks before granting items, opening protected storage, charging money, or applying other meaningful state changes. Client entity checks also expect a valid local entity handle; the implementation asserts that the handle is a positive integer, while the native coordinate lookup determines whether it is usable.

## Server

Server-side boolean radius helpers for checking a player source against coordinates or an entity. Server forms take src first and read that player’s ped coordinates on the server; coords remains a pure point-to-point helper without a player source.

Namespace: `Kora.distance` · Source: `modules/distancecheck/server.lua`

### How it works

All checks include the radius boundary: a measured distance exactly equal to distance returns true. The default distance is 5.0 game units. player, entity, and xy measure in 3D except xy, which ignores height; x and y compare only one axis. Coordinate arguments accept vector3 or vector4; for vector4, the heading component is ignored. Source-based checks require a valid positive integer server ID and a live player ped. Entity checks also validate that the entity handle is positive and exists.

### Functions

Each function returns a boolean and throws an assertion error for invalid input. player, entity, x, y, and xy take src as their first argument. coords takes only two coordinate tables and an optional radius.

**Parameters (all functions):** See each function for its parameters. The optional distance is a finite, non-negative radius in game units and defaults to 5.0 when omitted.

**Returns (all functions):** true when the measured distance is less than or equal to the radius (including its boundary). false when it is greater than the radius.

#### `Kora.distance.player(src, coords, distance?)`

Checks the player identified by src against a supplied coordinate in full 3D.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | positive integer FiveM player server ID. |
| `coords` | vector3 \| vector4 | vector3 or vector4 target position. |
| `distance?` | number | optional finite, non-negative radius in game units; defaults to 5.0. |

**Returns**

boolean. true when the server-observed player position is within or exactly on the radius of coords; false when farther away.

**Example**

```lua
RegisterNetEvent('shop:purchase', function(itemName)
    local src = source
    if not Kora.distance.player(src, shopCoords, 2.5) then
        return
    end

    -- Validate item, funds, and server-side state before granting.
    processPurchase(src, itemName)
end)
```

**Representative console output**

```text
Within 2.5 units using server-observed coordinates: true
Farther than 2.5 units: false
```

#### `Kora.distance.coords(coords1, coords2, distance?)`

Compares two supplied points in 3D. This is the same pure point-to-point function available on the client and does not take src.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `coords1` | vector3 \| vector4 | first vector3 or vector4 position. coords2 — second vector3 or vector4 position. |
| `distance?` | number | optional finite, non-negative radius in game units; defaults to 5.0. |

**Returns**

boolean. true when the Euclidean distance between the points is less than or equal to distance; false otherwise.

**Example**

```lua
local within = Kora.distance.coords(storageCoords, deliveryCoords, 10.0)
print(within)
```

**Representative console output**

```text
true or false depending on 3D point-to-point distance
```

#### `Kora.distance.entity(src, entity, distance?)`

Checks the server-observed position of the player source against the current position of an entity, in full 3D.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | positive integer FiveM player server ID. |
| `entity` | entity handle | positive integer handle for an existing entity. |
| `distance?` | number | optional finite non-negative radius; defaults to 5.0. |

**Returns**

boolean — true when the source player is within the radius of the entity.

**Example**

```lua
if Kora.distance.entity(source, targetVehicle, 4.0) then
    handleNearbyVehicleAction(source)
end
```

**Representative console output**

```text
true when server-observed player-to-entity distance is at most 4.0; otherwise false
```

#### `Kora.distance.x(src, point, distance?)`

Compares only the source player’s X-axis position with the position component of point. The other coordinate axes do not affect the result.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | positive integer FiveM player server ID. |
| `point` | vector3 \| vector4 | vector3 or vector4 reference position; only its X component is used. |
| `distance?` | number | optional finite, non-negative radius in game units; defaults to 5.0. |

**Returns**

boolean. true when the absolute difference on the X axis is less than or equal to distance; false otherwise.

**Example**

```lua
if Kora.distance.x(source, checkpoint, 2.0) then
    checkCheckpointProgress(source)
end
```

**Representative console output**

```text
true when server-observed X-axis separation is at most 2.0 units
```

#### `Kora.distance.y(src, point, distance?)`

Compares only the source player’s Y-axis position with the position component of point. The other coordinate axes do not affect the result.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | positive integer FiveM player server ID. |
| `point` | vector3 \| vector4 | vector3 or vector4 reference position; only its Y component is used. |
| `distance?` | number | optional finite, non-negative radius in game units; defaults to 5.0. |

**Returns**

boolean. true when the absolute difference on the Y axis is less than or equal to distance; false otherwise.

**Example**

```lua
if Kora.distance.y(source, boundary, 1.5) then
    updateBoundaryState(source)
end
```

**Representative console output**

```text
true when server-observed Y-axis separation is at most 1.5 units
```

#### `Kora.distance.xy(src, point, distance?)`

Checks the source player against a point on the horizontal plane. Height is ignored; both horizontal axes contribute to the 2D distance.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | positive integer FiveM player server ID. |
| `point` | vector3 \| vector4 | vector3 or vector4 reference position. |
| `distance?` | number | optional finite, non-negative radius in game units; defaults to 5.0. |

**Returns**

boolean. true when the 2D distance on the horizontal plane is less than or equal to distance; false otherwise.

**Example**

```lua
if Kora.distance.xy(source, interiorMarker, 3.0) then
    handleFloorIndependentAction(source)
end
```

**Representative console output**

```text
true or false based on horizontal distance; height does not change the result
```

#### `Kora.distance.playerNearAny(src, list, opts)`

Checks whether a player is within a radius of any entry in a list of locations, and returns the nearest matching entry. This replaces the hand-rolled "is the player near any of these configured locations" loop used for door, vendor and pickup-spot lists.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id; the player needs a live ped. |
| `list` | any[] | The entries to test, for example `Config.locations`. |
| `opts.coordsOf` | fun(entry: any): vector3 | Reads one entry's coordinates. Required. |
| `opts.radius?` | number | Search radius in metres. Defaults to `5.0`, like every other `Kora.distance` check. |

**Returns**

- **found** — `true` when any entry is within `opts.radius` of the player.
- **entry** — the nearest matching entry, or `nil` when nothing matched.

**Example**

```lua
local found, location = Kora.distance.playerNearAny(src, Config.locations, {
    radius = 2.5,
    coordsOf = function(entry) return entry.coords end,
})
```

**Representative console output**

```text
`found` is `true` and `location` is the closest `Config.locations` entry within 2.5 metres of the player; with nothing in range it returns `false, nil`. Raises an error when `list` is not a table or `opts.coordsOf` is missing.
```

### Common use cases

- Validate that a player is near a server-controlled interaction before applying an action.
- Check proximity to a server entity using authoritative entity coordinates.
- Use xy where vertical floors should not affect proximity, while still validating the player on the server.
- Compare two coordinates directly with coords when no player source is involved.

### Limits and related APIs

Server coordinates require OneSync to provide a valid player ped position. A source that does not resolve to a live ped fails validation. Entity checks fail for non-integer, non-positive, or non-existent handles. Use these checks as one part of server validation: also validate ownership, permissions, requested values, and current server state. Do not let a client choose the source identity, target position, or radius used to authorize its own request.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/distancecheck/docs.md` or `local/distancecheck/docs.md`) that the reference above does not state.

Cheap radius checks between the local player, arbitrary coordinates, and
entities. Every function returns a boolean: `true` when the measured distance is
within `distance` (default `5.0`). Client functions measure from the local
player (`Kora.cache.get('coords')`); server functions take `src` first and measure
from that player's ped (requires OneSync for a valid server-side ped position).

### Server

Same functions, but each takes `src` first and measures from that player:
```lua
Kora.distance.player(src, coords, distance?)
Kora.distance.entity(src, entity, distance?)
Kora.distance.x(src, point, distance?)   -- and y / xy
Kora.distance.coords(coords1, coords2, distance?)   -- no src; pure point-to-point
```
