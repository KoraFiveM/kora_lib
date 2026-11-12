---
title: "Visual effects"
sidebar_position: 35
---

# Visual effects

Client-side screen and drug-effect conveniences. Drug effects start asynchronously and return immediately; multiple effects may overlap. kora_lib restores the default sprint multiplier after the last live effect finishes.

## Screen fade

`Kora.visuals.fade(duration?, fn?)` fades to black over `duration` milliseconds (default `500`), runs `fn` while the screen is fully black, and always fades back in. If the callback raises, the screen is restored before the error is re-raised.
If the game does not report a completed fade, kora_lib waits at most one extra
second before continuing, so a stalled native cannot strand the caller.

```lua
Kora.visuals.fade(500, function()
    SetEntityCoords(PlayerPedId(), destination.x, destination.y, destination.z)
end)
```

The legacy `Kora.visuals.fade(coords, duration?)` form still moves the local ped, including the heading from `coords.w`. New movement code should use `Kora.teleport.player` or `Kora.teleport.entity`, which owns the teleport behavior explicitly.

## Drug and camera effects

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
