---
title: "Sound module"
sidebar_position: 32
---

# Sound module

## Overview
Frontend, world and entity sound playback with **managed sound ids**. Client
only — the server has no audio realm.

GTA's sound-id pool is small and finite. `GetSoundId()` claims a slot that stays
claimed until `ReleaseSoundId()`, so a script that allocates one per alert and
never releases it will silently stop producing audio partway through a session —
a bug that presents as "the dispatch sound randomly stopped working" and is
near-impossible to trace. Every id allocated here is auto-released on a timer,
released early by `Kora.sound.stop`, and swept when the owning resource stops.

## API

All three `play*` functions share the same options table:

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `network` | `boolean` | `false` | Play for nearby players too, not just locally |
| `range` | `number` | `Config.sound.defaultRange` (30.0) | Finite non-negative audible range in metres — world sounds only |
| `bank` | `string` | — | Audio bank to request and wait for before playing |
| `releaseAfter` | `number` | `Config.sound.defaultReleaseAfter` (10000) | Finite non-negative ms before auto-release; `0` opts out |

Each returns `integer | false` (the sound id, for `Kora.sound.stop`) plus an error
string on failure.

`options` must be a table when supplied. `network` must be boolean and `bank`
must be a non-empty string; explicit invalid values are rejected before kora_lib
claims a sound id or requests an audio bank.

### `Kora.sound.playFrontend(name, set, options?)`
A 2D UI/frontend sound — notification beeps, dispatch tones, menu clicks.

```lua
Kora.sound.playFrontend('Lose_1st', 'GTAO_FM_Events_Soundset')
```

### `Kora.sound.playFromCoords(coords, name, set, options?)`
A positional sound at finite world coordinates.

```lua
Kora.sound.playFromCoords(coords, 'Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', { range = 20.0 })
```

### `Kora.sound.playFromEntity(entity, name, set, options?)`
A sound that follows an entity.

### `Kora.sound.stop(soundId)`
Stops a sound created by the calling resource and releases its id.

#### Returns
- `boolean`, `string?` — `false, "Sound id is not tracked by Kora.sound."` for an
  id this module didn't allocate, or `false, "Sound id is owned by another resource."`
  for a handle belonging to another resource.

`soundId` must be a finite integer. `Kora.sound.isLive(soundId)` returns `false`
for any other value.

### `Kora.sound.isLive(soundId)`
Whether an id allocated by this module is still held.

## Notes
- **Foreign ids are refused.** `exports.kora_lib:sound_stop` is callable from any
  resource, but it can only stop a sound the caller created. This prevents it
  becoming a stop-anything primitive against another resource's audio.
- **Every call gets a stoppable handle.** The usual fire-and-forget idiom
  (passing `-1` as the sound id) needs no bookkeeping but produces a handle you
  can never stop. Managing the id uniformly means no call site can leak and
  every one of them is stoppable.
- **`options.bank` yields.** It goes through `Kora.stream.loadAudioBank` and waits
  for residency. Playing before the bank loads is a silent no-op rather than an
  error — the other classic "the sound sometimes doesn't play" cause.
- **Cleanup stops before it releases.** Releasing an id that is still playing
  leaves the audio running with no handle to stop it, so the resource-stop sweep
  calls `StopSound` first.
- **Audio banks are reference-counted.** A named bank remains resident while
  any managed sound using it is live and is released when the final sound
  stops, times out, or loses its owning resource.
- Auto-release callbacks are tied to one claim generation. If the game reuses
  a numeric sound ID, an older timer cannot stop the newer sound.
