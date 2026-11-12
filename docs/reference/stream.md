---
title: "Streaming module"
sidebar_position: 9
---

# Streaming module

## Overview
The streaming module centralizes model loading operations. It is intended for cases where a script needs to ensure a game asset is available before continuing.

## API

### `Kora.stream.loadModel(model, cb, options?)`
Loads a model and optionally executes a callback once it is ready.

#### Parameters
- `model: string | number` — The model name or hash to load.
- `cb: function | callable table | nil` — Optional callback invoked after the model loads.
- `options.timeout: integer | nil` — Override the default 10-second timeout.
- `options.shouldContinue: function | nil` — Cancel the wait when it returns false.

#### Returns
- `number | false` — The loaded model hash, or `false` if the model never loaded.
- `string | nil` — The reason the load failed, when the first value is `false`.

#### Behavior
1. If `model` is a string, it is converted using `joaat(model)`.
2. The model is validated with `IsModelValid(model)`.
3. If the model is already loaded, the wait is skipped entirely.
4. Otherwise `RequestModel` is issued once and the script polls `HasModelLoaded`
   once per game frame for at most 10 seconds. This avoids adding a long
   backoff delay after the asset has already become ready.
5. On timeout the request is released and `false, error` is returned — the
   callback is not run.
6. If a callback is supplied, it is executed and the model is then marked as no
   longer needed, even if the callback errors.
7. Without a callback the model stays loaded and the caller owns cleanup via the
   returned hash.

#### Example
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

### Other asset loaders
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

### `Kora.stream.loadCollision(coords, cb, entity)`
Waits for world collision to stream in around `coords`, so a freshly teleported or spawned entity doesn't fall through unloaded map geometry.

#### Parameters
- `coords: vector3 | {x, y, z}` — Finite point to stream collision around.
- `cb: function | callable table | nil` — Optional callback run once collision is ready.
- `entity: integer | nil` — Entity whose surroundings are checked (`HasCollisionLoadedAroundEntity`). Defaults to the local player's ped — the usual case, where the ped has just been moved to `coords`.

#### Returns
- `boolean` — `false` if collision never finished loading.
- `string | nil` — The reason, when the first value is `false`.

#### Behavior
This one is **not** built on the shared request → poll → release driver, because collision doesn't fit it: `RequestCollisionAtCoord` has to be re-issued on every poll (a single call isn't sticky), readiness is reported for an *entity* rather than for the requested point, and there's no release native at all — collision unloads on its own as the streamer moves on. So there's nothing to clean up and no callback-scoped asset lifetime here, unlike every loader above.

```lua
SetEntityCoords(PlayerPedId(), x, y, z, false, false, false, false)

Kora.stream.loadCollision(vector3(x, y, z), function()
    FreezeEntityPosition(PlayerPedId(), false) -- safe to drop now, ground exists
end)
```

#### Example
```lua
Kora.stream.loadAnimDict('missfbi3_party', function(dict)
    TaskPlayAnim(PlayerPedId(), dict, 'dance_solo', 8.0, -8.0, -1, 1, 0, false, false, false)
end)
```

```lua
local handle, err = Kora.stream.loadScaleformMovie('mp_big_message_freemode')
if not handle then return print('scaleform failed:', err) end
```

## Notes
- This module expects the FiveM/RedM scripting runtime functions to be available.
- Asset names must be non-empty strings. Model and weapon names should be passed
  exactly as they are used in the game assets.
- When using callbacks, keep the callback logic lightweight so the load cycle stays predictable.
- Every loader (not just `loadModel`) releases its asset immediately after its callback returns — anims, clip sets, ptfx, etc. that need to keep playing beyond the callback's synchronous scope should not be requested this way.
- All callbacks, option tables, native flags, and numeric model/weapon/entity handles are validated before kora_lib calls a streaming native.
