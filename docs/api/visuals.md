---
title: "Visuals"
sidebar_position: 35
---


# Visuals

Provides short screen fade and camera/drug-style visual effects. These are presentation helpers; they do not verify that an item was used or that an action is authorized. Drug-style effects run asynchronously and can overlap.

Namespace: `Kora.visuals` · Source: `modules/visuals/client.lua`

## Screen fade timing

fade waits for the game to report the fade complete. If the native stalls, it waits at most one additional second before continuing so the caller is not stranded. The legacy fade(vector4, duration?) form moves the local ped while the screen is black; new movement code should use Kora.teleport.player or Kora.teleport.entity.

## Duration and overlap

The visual helpers accept a finite, non-negative duration in milliseconds. Some three-stage sequences split that duration across transitions; stamina loops can have their own fixed lifetime. Several effects may overlap, and sprint restoration waits for the final active effect.

## Use as presentation only

A visual effect is client-side feedback. Do not use it as proof that an item was consumed, a reward was earned, or a player is authorized to perform a server action.

## Functions

Fade the screen around a callback or start one of the named visual sequences.

### `Kora.visuals.fade(duration?, fn?)`

Fades to black, calls fn while black, then fades back in. If fn errors, the screen is restored before the original error is re-raised.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `duration?` | number | Finite non-negative fade time in milliseconds. Defaults to 500. |
| `fn?` | function | Optional function to run while the screen is black. |

**Returns**

- **return** — callback results when fn is supplied; otherwise no meaningful value.

**Example**

```lua
Kora.visuals.fade(500, function()
    SetEntityCoords(PlayerPedId(), vector3(100.0, 200.0, 30.0))
end)
```

**Representative console output**

```text
Screen fades out, runs the coordinate change, then fades back in.
```

### `Kora.visuals.trevor(duration?)`

Plays the Trevor clown screen-effect sequence for the requested duration.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `duration?` | number | Optional finite non-negative milliseconds. Omitted or non-numeric values use this effect’s default. |

**Returns**

- **return** — no value; the effect runs asynchronously.

**Example**

```lua
Kora.visuals.trevor(3000)
```

**Representative console output**

```text
Starts the clown visual sequence for about three seconds.
```

### `Kora.visuals.alien(duration?)`

Plays the Michael alien screen-effect sequence.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `duration?` | number | Optional finite non-negative milliseconds; otherwise the helper default is used. |

**Returns**

- **return** — no value; the effect runs asynchronously.

**Example**

```lua
Kora.visuals.alien(3000)
```

**Representative console output**

```text
Starts the alien screen sequence.
```

### `Kora.visuals.meth(duration?)`

Starts a temporary visual sequence with stamina ticks and a sprint multiplier. Concurrent effects are tracked so the default sprint multiplier is restored after the last active effect ends.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `duration?` | number | Optional finite non-negative milliseconds; numeric strings are accepted for legacy calls. |

**Returns**

- **return** — no value; the effect runs asynchronously.

**Example**

```lua
Kora.visuals.meth(5000)
```

**Representative console output**

```text
Starts the effect; its temporary sprint change is removed when the effect ends.
```

### `Kora.visuals.ecstacy(duration?)`

Runs repeated visual flashes, camera shakes, and stamina restoration; a running ped may ragdoll as part of the effect.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `duration?` | number | Optional finite non-negative milliseconds; non-numeric values use the helper default. |

**Returns**

- **return** — no value; the effect runs asynchronously.

**Example**

```lua
Kora.visuals.ecstacy(4000)
```

**Representative console output**

```text
Starts the temporary flash and camera-shake sequence.
```

### `Kora.visuals.crack(duration?)`

Combines an alien-style visual with stamina, sprint, and running ragdoll effects.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `duration?` | number | Optional finite non-negative milliseconds; non-numeric values use the helper default. |

**Returns**

- **return** — no value; the effect runs asynchronously.

**Example**

```lua
Kora.visuals.crack(4000)
```

**Representative console output**

```text
Starts the temporary visual and movement sequence.
```

### `Kora.visuals.coke(duration?)`

Combines a screen effect with stamina and sprint changes, delayed replays, and a possible final running ragdoll.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `duration?` | number | Optional finite non-negative milliseconds; non-numeric values use the helper default. |

**Returns**

- **return** — no value; the effect runs asynchronously.

**Example**

```lua
Kora.visuals.coke(4000)
```

**Representative console output**

```text
Starts the temporary visual sequence.
```

## Limits and related APIs

These APIs are client-only. Numeric strings are accepted only for legacy duration callers; new code should pass a number.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/visuals/docs.md` or `local/visuals/docs.md`) that the reference above does not state.

Client-side screen and drug-effect conveniences. Drug effects start asynchronously and return immediately; multiple effects may overlap. kora_lib restores the default sprint multiplier after the last live effect finishes.

### Screen fade

`Kora.visuals.fade(duration?, fn?)` fades to black over `duration` milliseconds (default `500`), runs `fn` while the screen is fully black, and always fades back in. If the callback raises, the screen is restored before the error is re-raised.
If the game does not report a completed fade, kora_lib waits at most one extra
second before continuing, so a stalled native cannot strand the caller.

```lua
Kora.visuals.fade(500, function()
    SetEntityCoords(PlayerPedId(), destination.x, destination.y, destination.z)
end)
```

The legacy `Kora.visuals.fade(coords, duration?)` form still moves the local ped, including the heading from `coords.w`. New movement code should use `Kora.teleport.player` or `Kora.teleport.entity`, which owns the teleport behavior explicitly.

### Drug and camera effects

All functions take an optional finite, non-negative duration in milliseconds. Numeric strings remain accepted for legacy callers; omitted or non-numeric values use the helper's default:

- `Kora.visuals.trevor(duration?)` plays the Trevor clown screen-effect sequence.
- `Kora.visuals.alien(duration?)` plays the Michael alien screen-effect sequence.
- `Kora.visuals.meth(duration?)` adds a temporary sprint multiplier and stamina ticks, with occasional effect replays.
- `Kora.visuals.ecstacy(duration?)` adds repeated flashes, camera shakes, and stamina restoration, then may ragdoll a running ped.
- `Kora.visuals.crack(duration?)` combines the alien effect with stamina, sprint, and running ragdolls.
- `Kora.visuals.coke(duration?)` combines its screen effect with stamina, sprint, replay delays, and a final running ragdoll.

```lua
Kora.visuals.meth(3000)
```

For the helpers with a three-stage screen effect, the duration is split across the transition waits. Stamina loops have their own fixed or effect-specific lifetime. These functions are visual/gameplay presentation only and must not be used as server-side evidence that an item was consumed.
