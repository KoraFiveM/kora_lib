---
title: "Sound"
sidebar_position: 32
---


# Sound

Client-side frontend, positional, and entity-following audio helpers. Each play call claims a managed GTA sound ID and returns it so the calling resource can stop playback later. Kora also auto-releases IDs after a configurable timeout and cleans up sounds when their owning resource stops.

Namespace: `Kora.sound` · Source: `modules/sound/client.lua`

## How it works

The module is client-only. There is no Sound server or shared page because those files do not exist. A successful play call returns a numeric sound ID; a failure returns false and an error string. If an audio bank is requested, the call waits for the bank to load before claiming and playing a sound.

## Options

Pass an options table as the final argument to a play function. Omit the table or any field to use its default. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `network?` | boolean | Defaults to false. Set true to request playback for nearby players as well as locally. The underlying native determines how the sound is networked. |
| `range?` | number | Used by playFromCoords only. Finite non-negative audible range in metres; defaults to Config.sound.defaultRange (30.0). The value is floored before it is passed to the native. |
| `bank?` | string | Non-empty audio bank name to load before playback. The call waits for Kora.stream.loadAudioBank. If loading fails, the play function returns false and an error string. |
| `releaseAfter?` | number | Finite, non-negative milliseconds before automatic stop and ID release. Defaults to Config.sound.defaultReleaseAfter (10000). Set to 0 to disable the timer; the caller must then stop the sound or wait for resource-stop cleanup. |

## Functions

All play functions accept the same optional options table. The returned sound ID is managed by Kora and can be passed to Kora.sound.stop. Frontend sounds are 2D, coordinate sounds have a world position and audible range, and entity sounds follow an entity.

**Parameters (all functions):** Each function lists its arguments separately. Optional arguments are marked with ?.

**Returns (all functions):** See each function for its exact return contract.

### `Kora.sound.playFrontend(name, set, options?)`

Plays a 2D frontend/UI sound such as a menu click, notification tone, or dispatch beep.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | non-empty string identifying the sound within its sound set. |
| `set` | string | non-empty string identifying the sound set/ref. |
| `options?` | table | optional table of playback options; see Options below. |

**Returns**

- **soundId** — integer sound handle on success; pass it to Kora.sound.stop.
- **failure** — false, error string when the audio bank cannot load or no sound ID is available.

**Example**

```lua
local soundId, err = Kora.sound.playFrontend(
    'Lose_1st',
    'GTAO_FM_Events_Soundset'
)

if not soundId then
    print(('Could not play UI sound: %s'):format(err))
end
```

**Representative console output**

```text
Success: soundId is an integer handle, for example 12
Failure: false, "No free sound id available."
```

### `Kora.sound.playFromCoords(coords, name, set, options?)`

Plays a sound at a fixed world position. The optional range controls the audible radius in metres.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `coords` | vector3 \| vector4 | vector3 or vector4 world position; the heading component of vector4 is ignored. |
| `name` | string | non-empty sound name. |
| `set` | string | non-empty sound set/ref. |
| `options?` | table | optional table of playback options; range applies to this function. |

**Returns**

- **soundId** — integer sound handle on success; pass it to Kora.sound.stop.
- **failure** — false, error string when the audio bank cannot load or no sound ID is available.

**Example**

```lua
local ping, err = Kora.sound.playFromCoords(
    vector3(215.0, -810.0, 30.7),
    'Beep_Red',
    'DLC_HEIST_HACKING_SNAKE_SOUNDS',
    { range = 20.0 }
)

if not ping then
    print(('Could not play positional sound: %s'):format(err))
end
```

**Representative console output**

```text
Success: integer sound ID; sound is positioned at the supplied vector3
Failure: false plus an error string
```

### `Kora.sound.playFromEntity(entity, name, set, options?)`

Plays a sound attached to an entity so the audio follows that entity.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entity` | entity handle | integer handle for an existing entity. |
| `name` | string | non-empty sound name. |
| `set` | string | non-empty sound set/ref. |
| `options?` | table | optional table of playback options. |

**Returns**

- **soundId** — integer sound handle on success; pass it to Kora.sound.stop.
- **failure** — false, error string when the audio bank cannot load or no sound ID is available.

**Example**

```lua
local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
if vehicle ~= 0 then
    local engineSound, err = Kora.sound.playFromEntity(
        vehicle,
        'Engine_Start',
        'DLC_HEIST_HACKING_SNAKE_SOUNDS'
    )
end
```

**Representative console output**

```text
Success: integer sound ID; playback follows the vehicle
Invalid or non-existent entity: assertion error
```

### `Kora.sound.stop(soundId)`

Stops a sound managed by Kora.sound and releases its GTA sound ID. A caller can stop only sounds owned by its resource.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `soundId` | integer | integer handle returned by a successful play function. Non-integer or untracked IDs are rejected without stopping an unrelated sound. |

**Returns**

- **success** — true when the sound was stopped and its ID released.
- **failure** — false, error string when the ID is not tracked or belongs to another resource.

**Example**

```lua
local soundId = Kora.sound.playFrontend(
    'Lose_1st',
    'GTAO_FM_Events_Soundset',
    { releaseAfter = 0 }
)

-- Stop it when the related UI closes.
if soundId then
    Kora.sound.stop(soundId)
end
```

**Representative console output**

```text
true  -- sound stopped and its ID released
false, "Sound id is not tracked by Kora.sound."  -- unknown ID
```

### `Kora.sound.isLive(soundId)`

Checks whether the sound ID is currently held in Kora.sound’s managed registry.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `soundId` | integer | value to check; non-integer values are treated as not live. |

**Returns**

- **live** — true if this module currently holds the integer ID; false otherwise.

**Example**

```lua
local soundId = Kora.sound.playFrontend(
    'Lose_1st',
    'GTAO_FM_Events_Soundset'
)

if soundId and Kora.sound.isLive(soundId) then
    print('Sound is still managed')
end
```

**Representative console output**

```text
true until stopped, auto-released, or cleaned up with the owning resource
```

## Common use cases

- Play a short frontend sound for a local menu, notification, or interaction response.
- Place a beep, alarm, or environmental cue at a world vector3 with a limited audible range.
- Attach a sound to a ped or vehicle so it moves with that entity.
- Use releaseAfter = 0 when the sound lifetime should match a known UI or gameplay event, then call stop explicitly.

## Limits and related APIs

GTA has a finite sound-ID pool. Managed IDs are automatically released after the configured timeout, when stop succeeds, or when the owning resource stops. Auto-release stops playback before releasing the ID. Audio banks are reference-counted across live sounds. Foreign sound IDs are refused by stop, so one resource cannot stop another resource’s sound. Supplying options.bank yields while the bank loads. Invalid option types, empty sound names/sets, invalid ranges or timeouts, and invalid entity handles raise assertion errors before playback starts.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/sound/docs.md` or `local/sound/docs.md`) that the reference above does not state.

### Overview
Frontend, world and entity sound playback with **managed sound ids**. Client
only — the server has no audio realm.

GTA's sound-id pool is small and finite. `GetSoundId()` claims a slot that stays
claimed until `ReleaseSoundId()`, so a script that allocates one per alert and
never releases it will silently stop producing audio partway through a session —
a bug that presents as "the dispatch sound randomly stopped working" and is
near-impossible to trace. Every id allocated here is auto-released on a timer,
released early by `Kora.sound.stop`, and swept when the owning resource stops.

### API

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

#### `Kora.sound.playFrontend(name, set, options?)`
A 2D UI/frontend sound — notification beeps, dispatch tones, menu clicks.

```lua
Kora.sound.playFrontend('Lose_1st', 'GTAO_FM_Events_Soundset')
```

#### `Kora.sound.playFromCoords(coords, name, set, options?)`
A positional sound at finite world coordinates.

```lua
Kora.sound.playFromCoords(coords, 'Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', { range = 20.0 })
```

#### `Kora.sound.stop(soundId)`
Stops a sound created by the calling resource and releases its id.

##### Returns
- `boolean`, `string?` — `false, "Sound id is not tracked by Kora.sound."` for an
  id this module didn't allocate, or `false, "Sound id is owned by another resource."`
  for a handle belonging to another resource.

`soundId` must be a finite integer. `Kora.sound.isLive(soundId)` returns `false`
for any other value.
