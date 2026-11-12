---
title: "Cache"
sidebar_position: 1
---


# Cache

Provides quick access to recently sampled local-player information and a small change-notification store. It refreshes player state on one shared timer, so many resources can reuse the same values instead of each starting its own polling loop. Values such as the player ped, current vehicle, health, and position are snapshots from the latest cache tick, not live native calls.

Namespace: `Kora.cache` · Source: `modules/cache/client.lua`

## Built-in values are read-only

The cache owns playerId, serverId, ped, vehicle, seat, enteringVehicle, enteringSeat, weapon, health, isDead, armour, stamina, and coords. Kora.cache.set ignores attempts to write those names. Use a namespaced key for your own value, such as myresource:currentShop.

## When change handlers run

Handlers run only when a value changes, not on every refresh. The configured cache tick defaults to 200 milliseconds. A handler registered by a resource is removed automatically when that resource stops; offChange is useful when you need to remove it earlier.

## What to use it for

Use cached reads for menus, HUDs, and interval checks. Do not use a cached position or vehicle handle as proof that a server action is allowed. The server must validate important actions against its own current state.

## Functions

Read or write cache values, subscribe to changes, or use the named helpers for common local-player information.

### `Kora.cache.get(key)`

Reads a value from the cache. This works for built-in values and for keys your own resource has stored.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `key` | string | Non-empty cache key, up to 256 bytes. Use a resource prefix for your own keys, such as myresource:target. |

**Returns**

- **value** — cached value, or nil if no value has been stored.

**Example**

```lua
local selectedShop = Kora.cache.get('myshop:selected')
```

**Representative console output**

```text
If nothing stored that key, selectedShop is nil.
```

### `Kora.cache.set(key, value)`

Stores a value under your own key and notifies listeners if the value changes. Built-in player keys are read-only and are ignored with a console message.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `key` | string | Non-empty cache key, up to 256 bytes. Do not use reserved player-state names. |
| `value` | any | Any Lua value to store. |

**Returns**

- **return** — no value.

**Example**

```lua
Kora.cache.set('myshop:selected', 'hardware')
```

**Representative console output**

```text
A listener for myshop:selected runs if the stored value was different.
```

### `Kora.cache.onChange(key, handler)`

Subscribes to value changes. The callback receives the new value first and the previous value second. A handler error is logged and does not prevent other handlers from running.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `key` | string | Cache key to watch. |
| `handler` | function | Callable function receiving (newValue, oldValue). |

**Returns**

- **return** — no value.

**Example**

```lua
Kora.cache.onChange('vehicle', function(vehicle, previousVehicle)
    if vehicle then
        print('Entered vehicle', vehicle)
    elseif previousVehicle then
        print('Left vehicle', previousVehicle)
    end
end)
```

**Representative console output**

```text
Entering a vehicle prints its handle; leaving prints the prior handle.
```

### `Kora.cache.offChange(key)`

Removes every change handler for this key that was registered by the calling resource. Other resources’ handlers remain registered.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `key` | string | The key whose handlers should be removed. |

**Returns**

- **return** — no value.

**Example**

```lua
Kora.cache.offChange('vehicle')
```

**Representative console output**

```text
This resource no longer receives vehicle change notifications.
```

### `Kora.cache.playerId()`

Returns the local player index. It is stable for the whole session and resolved once.

**Parameters**



**Returns**

- **playerId** — integer player index.

**Example**

```lua
local player = Kora.cache.playerId()
```

**Representative console output**

```text
Returns the same local player index for the session.
```

### `Kora.cache.serverId()`

Returns the local player’s server ID. If networking has not assigned it during startup, the cache retries until the ID becomes available.

**Parameters**



**Returns**

- **serverId** — integer server ID.

**Example**

```lua
local serverId = Kora.cache.serverId()
```

**Representative console output**

```text
Returns the assigned server ID when available.
```

### `Kora.cache.ped()`

Returns the current local-player ped handle. The cache refreshes it so code can read the replacement ped after death or respawn.

**Parameters**



**Returns**

- **ped** — integer entity handle.

**Example**

```lua
local ped = Kora.cache.ped()
if DoesEntityExist(ped) then print('Player ped is ready') end
```

**Representative console output**

```text
Prints only when the cached ped handle currently exists.
```

### `Kora.cache.coords()`

Returns the local player’s position from the most recent cache tick. Use it for ordinary interval work; use a fresh native read for frame-critical aiming, movement, or placement.

**Parameters**



**Returns**

- **coords** — vector3 sampled world position.

**Example**

```lua
local position = Kora.cache.coords()
print(position.x, position.y, position.z)
```

**Representative console output**

```text
Prints the player position sampled by the cache.
```

### `Kora.cache.vehicle()`

Returns the vehicle the player currently occupies, or false while on foot.

**Parameters**



**Returns**

- **vehicle** — integer vehicle handle, or false.

**Example**

```lua
if Kora.cache.vehicle() then print('Player is in a vehicle') end
```

**Representative console output**

```text
Prints while the player is in a vehicle.
```

### `Kora.cache.seat()`

Returns the occupied seat. Seat -1 is the driver seat; 0 and above are passenger seats.

**Parameters**



**Returns**

- **seat** — integer seat index, or false while on foot.

**Example**

```lua
if Kora.cache.seat() == -1 then print('Player is driving') end
```

**Representative console output**

```text
Prints while the player occupies the driver seat.
```

### `Kora.cache.enteringVehicle()`

Returns the vehicle the player is trying to enter, or false when there is no active entry attempt. Subscribe with onChange to react to the attempt without polling.

**Parameters**



**Returns**

- **vehicle** — integer vehicle handle, or false.

**Example**

```lua
Kora.cache.onChange('enteringVehicle', function(vehicle)
    if vehicle then print('Trying to enter', vehicle) end
end)
```

**Representative console output**

```text
Prints when the player begins a vehicle entry attempt.
```

### `Kora.cache.enteringSeat()`

Returns the seat the player is trying to enter, or false when no entry attempt is active.

**Parameters**



**Returns**

- **seat** — integer seat index, or false.

**Example**

```lua
local targetSeat = Kora.cache.enteringSeat()
if targetSeat == -1 then print('Trying to enter the driver seat') end
```

**Representative console output**

```text
Prints when the latest sampled entry attempt targets the driver seat.
```

### `Kora.cache.weapon()`

Returns the selected weapon hash. When the player has no weapon equipped, the game returns the WEAPON_UNARMED hash rather than nil or false.

**Parameters**



**Returns**

- **weaponHash** — integer weapon hash.

**Example**

```lua
local weaponHash = Kora.cache.weapon()
print('Selected weapon hash:', weaponHash)
```

**Representative console output**

```text
Prints the selected weapon hash, including the unarmed hash.
```

### `Kora.cache.health()`

Returns the player ped’s health from the latest cache tick. Do not treat zero as the normal death threshold; use isDead for the game’s fatal-injury check.

**Parameters**



**Returns**

- **health** — integer health value.

**Example**

```lua
print('Health:', Kora.cache.health())
```

**Representative console output**

```text
Prints the cached health value.
```

### `Kora.cache.isDead()`

Returns the game’s IsPedFatallyInjured result for the cached ped. This uses the game death predicate rather than guessing from a health number.

**Parameters**



**Returns**

- **isDead** — boolean.

**Example**

```lua
if Kora.cache.isDead() then print('Player is fatally injured') end
```

**Representative console output**

```text
Prints when the game reports the ped as fatally injured.
```

### `Kora.cache.armour()`

Returns the player’s armour value. It is 0 when no armour is equipped.

**Parameters**



**Returns**

- **armour** — integer armour value.

**Example**

```lua
print('Armour:', Kora.cache.armour())
```

**Representative console output**

```text
Prints the cached armour value.
```

### `Kora.cache.stamina()`

Returns remaining player stamina from the latest cache tick. It can change on most ticks while sprinting.

**Parameters**



**Returns**

- **stamina** — number, normally from 0 to 100.

**Example**

```lua
Kora.cache.onChange('stamina', function(value)
    if value < 20 then print('Low stamina') end
end)
```

**Representative console output**

```text
Prints when a stamina update is below 20.
```

## Limits and related APIs

Cache values may be up to one configured tick old. Coordinates should be read fresh for frame-critical placement or aiming.
