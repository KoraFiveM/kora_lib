---
title: "Stream"
sidebar_position: 9
---


# Stream

Use Stream when a script needs a game asset before it can show or use it. A ped model must be loaded before creating the ped; an animation dictionary must be loaded before playing a clip. The loader waits for the asset, calls your function when ready, then releases the asset after the callback finishes.

Namespace: `Kora.stream` · Source: `modules/stream/client.lua`

## Common asset-loading options

Loaders that accept an options table use these optional settings. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `timeout?` | integer | Maximum wait in milliseconds; defaults to 10000. |
| `shouldContinue?` | function | Checked while waiting; return false to stop the wait. |

## How asset loading works

A string model/weapon name is converted to its game hash. The loader checks validity, skips waiting if already loaded, otherwise requests the asset and checks once per frame for up to ten seconds by default. A timed-out request is released and the callback does not run.

## Who releases the asset?

When you pass a callback, kora_lib releases the asset after your callback returns, even if the callback errors. Without a callback, you keep the asset and must call the matching release native yourself. Do not use callback form for an animation or texture that must remain loaded after the callback ends.

## Functions

Each loader returns the asset identifier on success. On failure it returns false and a reason. When a callback is supplied, use the asset inside that callback; it is released immediately afterward.

### `Kora.stream.loadModel(model, cb?, options?)`

Loads a ped, vehicle, or object model so a game native can create an entity from it.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `model` | string \| integer | Model name, such as a_m_y_beach_01, or its hash. |
| `cb?` | function | Optional function called with the loaded model hash. |
| `options?` | table | Optional timeout/cancellation settings. |

**Returns**

- **modelHash** — loaded hash, or false.
- **reason** — failure detail when false.

**Example**

```lua
local model, err = Kora.stream.loadModel('a_m_y_beach_01')
if not model then print('Model failed:', err) return end
local ped = CreatePed(4, model, 100.0, 200.0, 30.0, 90.0, false, false)
SetModelAsNoLongerNeeded(model)
```

**Representative console output**

```text
Without a callback, release the model yourself with SetModelAsNoLongerNeeded when finished.
```

### `Kora.stream.loadPtfx(fxName, cb?, options?)`

Loads a named particle-effects asset before a particle effect starts.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `fxName` | string | Non-empty particle asset name. |
| `cb?` | function | Optional callback called with the loaded name. |
| `options?` | table | Optional wait settings. |

**Returns**

- **fxName** — loaded asset name, or false.
- **reason** — failure detail.

**Example**

```lua
Kora.stream.loadPtfx('core', function(asset)
    UseParticleFxAssetNextCall(asset)
    StartParticleFxNonLoopedAtCoord('ent_sht_steam', 100.0, 200.0, 30.0, 0.0, 0.0, 0.0, 1.0, false, false, false)
end)
```

**Representative console output**

```text
The callback runs only once the asset is ready; it is released when the callback returns.
```

### `Kora.stream.loadAnimDict(animDict, cb?, options?)`

Loads an animation dictionary before an animation task uses it.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `animDict` | string | Dictionary name. |
| `cb?` | function | Optional callback receiving the ready dictionary. |
| `options?` | table | Optional wait settings. |

**Returns**

- **animDict** — loaded name, or false.
- **reason** — failure detail.

**Example**

```lua
Kora.stream.loadAnimDict('missfbi3_party', function(dict)
    TaskPlayAnim(PlayerPedId(), dict, 'dance_solo', 8.0, -8.0, -1, 1, 0.0, false, false, false)
end)
```

**Representative console output**

```text
The callback can start the animation. The dictionary is released afterward.
```

### `Kora.stream.loadAnimSet(animSet, cb?, options?)`

Loads an animation set before a ped uses it for movement.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `animSet` | string | Animation set name. |
| `cb?` | function | Optional ready callback. |
| `options?` | table | Optional wait settings. |

**Returns**

- **animSet** — loaded name, or false.
- **reason** — failure detail.

**Example**

```lua
Kora.stream.loadAnimSet('move_m@brave', function(set)
    SetPedMovementClipset(PlayerPedId(), set, 1.0)
end)
```

**Representative console output**

```text
The set is available in the callback and released afterward.
```

### `Kora.stream.loadClipSet(clipSet, cb?, options?)`

Loads a clip set for a ped movement/animation native.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `clipSet` | string | Clip set name. |
| `cb?` | function | Optional ready callback. |
| `options?` | table | Optional wait settings. |

**Returns**

- **clipSet** — loaded name, or false.
- **reason** — failure detail.

**Example**

```lua
Kora.stream.loadClipSet('move_m@brave', function(set)
    SetPedMovementClipset(PlayerPedId(), set, 1.0)
end)
```

**Representative console output**

```text
The callback receives the loaded clip set name.
```

### `Kora.stream.loadIpl(iplName, cb?, options?)`

Requests a map/interior IPL and waits until it becomes active.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `iplName` | string | IPL name. |
| `cb?` | function | Optional ready callback. |
| `options?` | table | Optional wait settings. |

**Returns**

- **iplName** — active name, or false.
- **reason** — failure detail.

**Example**

```lua
local ipl, err = Kora.stream.loadIpl('hei_dlc_casino_aircon')
if not ipl then print(err) end
```

**Representative console output**

```text
Readiness uses IsIplActive; IPLs do not use the usual asset release path.
```

### `Kora.stream.loadScaleformMovie(scaleformName, cb?, options?)`

Loads a Scaleform movie and returns its native handle.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `scaleformName` | string | Scaleform movie name. |
| `cb?` | function | Optional callback receiving handle. |
| `options?` | table | Optional wait settings. |

**Returns**

- **handle** — loaded movie handle, or false.
- **reason** — failure detail.

**Example**

```lua
local movie, err = Kora.stream.loadScaleformMovie('mp_big_message_freemode')
if not movie then return print(err) end
```

**Representative console output**

```text
The returned value is a handle, not the name. Use it with Scaleform natives.
```

### `Kora.stream.loadTextureDict(textureDict, cb?, isAdditionalTextures?)`

Loads a texture dictionary for drawing sprites.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `textureDict` | string | Texture dictionary name. |
| `cb?` | function | Optional ready callback. |
| `isAdditionalTextures?` | boolean | Flag passed to RequestStreamedTextureDict; defaults false. |

**Returns**

- **textureDict** — loaded name, or false.
- **reason** — failure detail.

**Example**

```lua
Kora.stream.loadTextureDict('commonmenu', function(dict)
    DrawSprite(dict, 'shop_new_star', 0.5, 0.5, 0.1, 0.1, 0.0, 255, 255, 255, 255)
end)
```

**Representative console output**

```text
The texture is ready inside the callback and released afterward.
```

### `Kora.stream.loadWeaponAsset(weapon, cb?, weaponResourceFlags?, extraWeaponComponentFlags?)`

Loads streamed weapon data such as model and animation assets.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `weapon` | string \| integer | Weapon name or finite integer hash. |
| `cb?` | function | Optional callback receiving weapon hash. |
| `weaponResourceFlags?` | integer | Native flags; defaults 31. |
| `extraWeaponComponentFlags?` | integer | Component flags; defaults 0. |

**Returns**

- **weaponHash** — loaded hash, or false.
- **reason** — failure detail.

**Example**

```lua
local weapon, err = Kora.stream.loadWeaponAsset('weapon_pistol')
if not weapon then print(err) end
```

**Representative console output**

```text
String names are converted to hashes and validated before waiting.
```

### `Kora.stream.loadAudioBank(audioBank, cb?)`

Requests a script audio bank before playing sounds from it.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `audioBank` | string | Audio bank name. |
| `cb?` | function | Optional ready callback. |

**Returns**

- **audioBank** — loaded name, or false.
- **reason** — failure detail.

**Example**

```lua
Kora.stream.loadAudioBank('DLC_HEIST_HACKING_SNAKE_SOUNDS', function(bank)
    PlaySoundFrontend(-1, 'Start', bank, true)
end)
```

**Representative console output**

```text
The audio bank is released after the callback.
```

### `Kora.stream.loadCollision(coords, cb?, entity?)`

Waits for world collision around a position, commonly after teleporting a player.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `coords` | vector3 | Finite point to load around. |
| `cb?` | function | Optional function called when collision is ready. |
| `entity?` | integer | Entity checked for loaded collision; defaults to local player ped. |

**Returns**

- **loaded** — boolean.
- **reason** — failure detail if not loaded.

**Example**

```lua
local destination = vector3(100.0, 200.0, 30.0)
SetEntityCoords(PlayerPedId(), destination.x, destination.y, destination.z)
local loaded, err = Kora.stream.loadCollision(destination)
if loaded then FreezeEntityPosition(PlayerPedId(), false) end
```

**Representative console output**

```text
Returns true when collision is ready, or false plus a timeout reason.
```

## Limits and related APIs

Names, callbacks, native flags, handles, and options are validated before streaming calls. Cancellation through shouldContinue returns false and a reason.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/stream/docs.md` or `local/stream/docs.md`) that the reference above does not state.

### API

#### `Kora.stream.loadModel(model, cb, options?)`
Loads a model and optionally executes a callback once it is ready.

##### Example
```lua
Kora.stream.loadModel('a_m_y_beach_01', function(model)
    print('Loaded model:', model)
end)
```

Handling a failed load:

```lua
local model, err = Kora.stream.loadModel('a_m_y_beach_01')
if not model then return print('load failed:', err) end

-- caller owns cleanup when no callback is passed
SetModelAsNoLongerNeeded(model)
```

#### Other asset loaders
All follow the same request → poll-until-loaded → run callback → release lifecycle as `loadModel` above (an already-loaded asset short-circuits the request; a timed-out load releases and returns `false, error` without running `cb`; the callback runs under `pcall` and the asset is released right after it returns, even on error).

| Function | Loads | Returns |
|---|---|---|
| `Kora.stream.loadPtfx(fxName, cb, options?)` | A named particle effect (ptfx) asset. | `fxName \| false`, `error?` |
| `Kora.stream.loadAnimDict(animDict, cb, options?)` | An animation dictionary (validated with `DoesAnimDictExist`). | `animDict \| false`, `error?` |
| `Kora.stream.loadAnimSet(animSet, cb, options?)` | An animation set. | `animSet \| false`, `error?` |
| `Kora.stream.loadClipSet(clipSet, cb, options?)` | A clip set. | `clipSet \| false`, `error?` |
| `Kora.stream.loadIpl(iplName, cb, options?)` | An interior proplist (checked via `IsIplActive`, not `Has...Loaded`). | `iplName \| false`, `error?` |
| `Kora.stream.loadScaleformMovie(scaleformName, cb, options?)` | A scaleform movie. `cb` and the return value receive the **scaleform handle**, not the name — `HasScaleformMovieLoaded`/`SetScaleformMovieAsNoLongerNeeded` are keyed by that handle. | `handle \| false`, `error?` |
| `Kora.stream.loadTextureDict(textureDict, cb, isAdditionalTextures?)` | A streamed texture dictionary. `isAdditionalTextures` must be boolean and is forwarded as `RequestStreamedTextureDict`'s undocumented second argument (defaults `false`). | `textureDict \| false`, `error?` |
| `Kora.stream.loadWeaponAsset(weapon, cb, weaponResourceFlags?, extraWeaponComponentFlags?)` | A weapon's streaming asset (model/anims/etc). `weapon` accepts a name or finite integer hash (joaat-converted like `loadModel`), validated with `IsWeaponValid`. Flags are finite integers and default to `31`/`0`, the common values seen in practice (undocumented upstream). | `weaponHash \| false`, `error?` |
| `Kora.stream.loadAudioBank(audioBank, cb)` | A script audio bank. Unlike every other type there's no separate `Has...Loaded` native — `RequestScriptAudioBank` itself reports readiness, so it serves as both request and poll. Released with `ReleaseNamedScriptAudioBank`. | `audioBank \| false`, `error?` |

#### `Kora.stream.loadCollision(coords, cb, entity)`
Waits for world collision to stream in around `coords`, so a freshly teleported or spawned entity doesn't fall through unloaded map geometry.

##### Behavior
This one is **not** built on the shared request → poll → release driver, because collision doesn't fit it: `RequestCollisionAtCoord` has to be re-issued on every poll (a single call isn't sticky), readiness is reported for an *entity* rather than for the requested point, and there's no release native at all — collision unloads on its own as the streamer moves on. So there's nothing to clean up and no callback-scoped asset lifetime here, unlike every loader above.

```lua
SetEntityCoords(PlayerPedId(), x, y, z, false, false, false, false)

Kora.stream.loadCollision(vector3(x, y, z), function()
    FreezeEntityPosition(PlayerPedId(), false) -- safe to drop now, ground exists
end)
```

##### Example
```lua
Kora.stream.loadAnimDict('missfbi3_party', function(dict)
    TaskPlayAnim(PlayerPedId(), dict, 'dance_solo', 8.0, -8.0, -1, 1, 0, false, false, false)
end)
```

```lua
local handle, err = Kora.stream.loadScaleformMovie('mp_big_message_freemode')
if not handle then return print('scaleform failed:', err) end
```
