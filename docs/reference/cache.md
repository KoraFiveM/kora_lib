---
title: "Cache module"
sidebar_position: 1
---

# Cache module

## Overview
A cheap, continuously-refreshed cache of local-player state — player id, server id, current ped, vehicle/seat, vehicle-entry attempt/seat, weapon, health, fatal-injury state, armour, and stamina — plus a general `get`/`set`/`onChange` store any module or resource can use for its own local values. Reading `Kora.cache.ped()` is a plain table lookup; it never calls a native itself.

## API

### `Kora.cache.get(key)`
Returns the cached value for `key`, or `nil` if nothing has set it yet.
`key` must be a non-empty string up to 256 bytes, matching `set`, `onChange`,
and `offChange`.

#### Parameters
- `key: string` (1–256 bytes)

### `Kora.cache.set(key, value)`
Sets a cached value, firing any `Kora.cache.onChange` handlers registered for `key` if the value actually changed. Writing one of the built-in keys (`playerId`/`serverId`/`ped`/`vehicle`/`seat`/`enteringVehicle`/`enteringSeat`/`weapon`/`health`/`isDead`/`armour`/`stamina`/`coords`) is rejected outright — logged and ignored — rather than applied and then overwritten on the next refresh tick.

#### Parameters
- `key: string`
- `value: any`

#### Example
```lua
Kora.cache.set('nearestShop', shopId)
```

### `Kora.cache.onChange(key, handler)`
Registers `handler(newValue, oldValue)` to run whenever `key`'s cached value changes — whether from `Kora.cache.set` or the module's own per-tick refresh of a built-in value (`ped`, `coords`, `vehicle`, `seat`, `enteringVehicle`, `enteringSeat`, `weapon`, `health`, `isDead`, `armour`, or `stamina`).

#### Parameters
- `key: string`
- `handler: fun(newValue: any, oldValue: any)`

#### Example
```lua
Kora.cache.onChange('vehicle', function(vehicle, previousVehicle)
    if vehicle then
        print('entered vehicle', vehicle)
    elseif previousVehicle then
        print('left vehicle', previousVehicle)
    end
end)
```

### `Kora.cache.offChange(key)`
Removes every `onChange` handler the calling resource registered for `key`. Rarely needed directly — handlers are swept automatically when their registering resource stops.

#### Parameters
- `key: string`

### `Kora.cache.playerId()`
Returns `PlayerId()`. It is resolved once because the player index is stable for the whole session.

### `Kora.cache.serverId()`
Returns `GetPlayerServerId(PlayerId())`. It is resolved once when valid because the server id is stable for the whole session; an early `-1` startup sentinel is replaced as soon as the network session is ready.

### `Kora.cache.ped()`
Returns the local player's current ped handle, refreshed every tick — safe to use across a death/respawn without re-fetching `PlayerPedId()` yourself.

### `Kora.cache.coords()`
Returns the local player's current coordinates.

### `Kora.cache.vehicle()`
Returns the vehicle the local player is currently in, or `false` if on foot.

### `Kora.cache.seat()`
Returns the seat the local player currently occupies (`-1` = driver, `0+` = passenger), or `false` if not in a vehicle.

### `Kora.cache.enteringVehicle()`
Returns the vehicle the local player is currently trying to enter, or `false`. Pair this with `onChange('enteringVehicle', ...)` to react once per entry attempt instead of polling.

### `Kora.cache.enteringSeat()`
Returns the seat the local player is currently trying to enter, or `false`.

### `Kora.cache.weapon()`
Returns the local player's currently selected weapon hash. Always a hash — when holding nothing this is `WEAPON_UNARMED`'s hash (`GetSelectedPedWeapon` never reports a false/nil sentinel).

### `Kora.cache.health()`
Returns the local player's current health (`GetEntityHealth(ped)`). GTA's death threshold is commonly 100, not 0 — don't assume 0 is reachable when checking for death.

### `Kora.cache.isDead()`
Returns whether `IsPedFatallyInjured(ped)` is true. Use `Kora.cache.onChange('isDead', handler)` to react once when the local player becomes fatally injured; do not infer death from a health threshold.

### `Kora.cache.armour()`
Returns the local player's current armour (`GetPedArmour(ped)`). `0` when no armour is equipped.

### `Kora.cache.stamina()`
Returns the current player stamina value from `GetPlayerStamina(PlayerId())`.

#### Example
```lua
CreateThread(function()
    while true do
        if Kora.cache.vehicle() and Kora.cache.seat() == -1 then
            -- driving
        end
        Wait(500)
    end
end)
```

## Notes
- Built-in telemetry refreshes every `Config.cache.tickInterval` ms (200ms by default). It must be a positive finite integer and is captured at startup. The cache is intentionally a bounded shared poll rather than a frame loop; use direct per-frame natives only for controls that the engine requires to be reasserted every frame.
- `playerId`/`serverId` are session constants and are not re-read by that telemetry tick. A cached vehicle seat is validated directly; the cache only scans every seat when the cached slot no longer contains the player ped.
- If kora_lib starts before networking assigns a server ID, its small retry worker
  checks every 250ms until the `-1` startup sentinel becomes a real ID; it is
  not a frame loop.
- `Kora.cache.set` rejects writes to any built-in key outright (logged, ignored) — it isn't just that the next refresh tick would overwrite a bogus value back, the write never lands in the first place.
- `onChange` handlers only fire when a value actually changes, not on every refresh tick. Coordinates compare `x`/`y`/`z` components so a fresh native vector at a stationary position does not notify.
- A handler may safely remove its own listeners while it runs; remaining
  listeners still receive that update. A listener added during an update begins
  receiving the next one.
- `onChange` handlers are removed automatically when the resource that registered them stops.
- `Kora.cache.set`/`get`/`onChange` aren't limited to the built-in keys — use them for your own resource's local state if you want the same change-notification pattern without building it yourself. Namespace your own keys (e.g. `"myresource:something"`) to avoid colliding with another resource's.
