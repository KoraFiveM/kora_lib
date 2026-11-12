---
title: "Anim"
sidebar_position: 20
---


# Anim

Loads animation dictionaries and prop models, starts tracked entity animations, and attaches caller-owned local props to entity bones. The module releases streamed assets and cleans tracked animations/props when their owning resource stops.

Namespace: `Kora.anim` · Source: `modules/anim/client.lua`

## How it works

Only one Kora animation is tracked per entity. A resource may replace or stop its own animation, while another resource cannot take over or stop it. Handles prevent stale delayed work from stopping a newer animation. Attached props are local and non-networked.

## play opts table

Fields accepted by play as its fourth argument. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `duration??` | integer | Defaults to -1. Use -1 for native indefinite/natural behavior or a non-negative millisecond duration; a positive duration schedules cleanup. |
| `flag??` | integer | FiveM animation flag bitmask; defaults to 1. |
| `blendInSpeed??` | number | Finite blend-in speed; defaults to 8.0. |
| `blendOutSpeed??` | number | Finite blend-out speed; defaults to 8.0. |
| `playbackRate??` | number | Finite playback rate; defaults to 0.0. |
| `lockX? / lockY? / lockZ??` | boolean | Movement axis locks; each defaults to false. |
| `onFinish??` | function | Called with entity after positive duration expires and cleanup finishes; not called for cancellation or replacement. |

## attachProp opts

softPin and collision default false. fixedRot defaults true. vertexIndex is the native rotation order, an integer from 0 through 5. Offsets and rotations must have finite vector3 components. Common hand/head/spine bone names fall back to ped bone indices when name lookup does not resolve.

## Functions

Play and stop tracked animations, use scenarios for native ambient tasks, and attach/detach temporary local props.

### `Kora.anim.play(entity, dict, clip, opts?)`

Loads dict and plays clip on entity, returning a handle. Invalid entity/dict/clip inputs assert; dictionary load failure returns false and a reason.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entity` | number | Existing game entity handle. |
| `dict` | string | Animation dictionary name to stream. |
| `clip` | string | Animation clip within dict. |
| `opts?` | table | Optional playback timing and native flags. |

**Returns**

- **handle** — animation handle on success, or false on load failure.
- **reason** — failure detail when false is returned.

**Example**

```lua
local handle, err = Kora.anim.play(PlayerPedId(), 'amb@world_human_hang_out_street@male_c@idle_a', 'idle_b', {
    duration = 3000,
    flag = 49,
})
if not handle then print(err) end
```

**Representative console output**

```text
Starts the idle animation, then stops/releases it after three seconds.
```

### `Kora.anim.stop(entity, blendOutSpeed?)`

Stops the current animation tracked for entity, releases its dictionary, and reports whether an animation was active.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entity` | number | Entity whose tracked animation should stop. |
| `blendOutSpeed?` | number | Optional finite blend-out speed. |

**Returns**

- **stopped** — boolean.

**Example**

```lua
if Kora.anim.isPlaying(PlayerPedId()) then
    Kora.anim.stop(PlayerPedId(), 4.0)
end
```

**Representative console output**

```text
Returns false when there was no tracked animation to stop.
```

### `Kora.anim.stopHandle(handle, blendOutSpeed?)`

Stops only if handle is still the current animation handle for its entity.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `handle` | table | Handle returned by play. |
| `blendOutSpeed?` | number | Optional finite blend-out speed. |

**Returns**

- **stopped** — boolean; false for stale or invalid handles.

**Example**

```lua
local handle = Kora.anim.play(PlayerPedId(), dict, clip)
-- Later, only this exact animation instance is stopped.
Kora.anim.stopHandle(handle)
```

**Representative console output**

```text
A stale handle cannot stop a replacement animation.
```

### `Kora.anim.isPlaying(entity)`

Checks tracked animation state against the native playing state.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entity` | number | Entity to inspect. |

**Returns**

- **playing** — boolean.

**Example**

```lua
print(Kora.anim.isPlaying(PlayerPedId()))
```

**Representative console output**

```text
Returns whether the tracked dictionary and clip are playing.
```

### `Kora.anim.clear(entity, immediate?)`

Stops this module’s tracked animation and clears all ped tasks on the entity.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entity` | number | Ped/entity to clear. |
| `immediate?` | boolean | When true, use immediate task clearing. |

**Returns**

- **return** — no value.

**Example**

```lua
Kora.anim.clear(PlayerPedId(), true)
```

**Representative console output**

```text
Clears the animation and ped task queue immediately.
```

### `Kora.anim.playScenario(entity, scenario, enterVehicle?)`

Starts a named scenario in place, or uses the vehicle-entry scenario task when enterVehicle is true.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entity` | number | Entity to run the scenario on. |
| `scenario` | string | Scenario name understood by the game. |
| `enterVehicle?` | boolean | Selects the vehicle-entry scenario task. |

**Returns**

- **return** — no value.

**Example**

```lua
Kora.anim.playScenario(PlayerPedId(), 'WORLD_HUMAN_CLIPBOARD')
```

**Representative console output**

```text
Starts the clipboard scenario on the player ped.
```

### `Kora.anim.attachProp(entity, model, bone, offset?, rotation?, opts?)`

Streams and creates a local object, then attaches it to a named bone or ped bone id.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `entity` | number | Entity to attach the object to. |
| `model` | string \| number | Prop model name or hash. |
| `bone` | string \| number | Bone name; numeric ped bone id is supported only for peds. |
| `offset?` | vector3 | Position offset; defaults to vector3(0, 0, 0). |
| `rotation?` | vector3 | Rotation offset; defaults to vector3(0, 0, 0). |
| `opts?` | table | Optional attachment flags. |

**Returns**

- **prop** — created entity handle, or false on failure.
- **reason** — failure detail when false is returned.

**Example**

```lua
local prop, err = Kora.anim.attachProp(PlayerPedId(), 'prop_cs_tablet', 'IK_R_Hand',
    vector3(0.03, 0.002, -0.01), vector3(10.0, 160.0, 0.0))
if not prop then print(err) end
```

**Representative console output**

```text
Creates and attaches a local tablet prop to the right hand.
```

### `Kora.anim.detachProp(prop)`

Detaches, deletes, and untracks a prop created by this module for the calling resource.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `prop` | number | Prop entity handle returned by attachProp. |

**Returns**

- **detached** — boolean.
- **reason** — set when the prop is missing, foreign, or untracked.

**Example**

```lua
local prop = Kora.anim.attachProp(PlayerPedId(), 'prop_cs_tablet', 'IK_R_Hand')
-- When the interaction ends:
local ok, err = Kora.anim.detachProp(prop)
```

**Representative console output**

```text
Returns true after removing an owned attached prop.
```

## Limits and related APIs

An animation dictionary load failure and prop model/bone/object failure return false plus a reason. Invalid handles, dictionaries, clips, and malformed numeric options are programmer errors and assert before changing the active animation or creating props.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/anim/docs.md` or `local/anim/docs.md`) that the reference above does not state.

Client-side, resource-owned animation and attached-prop helpers. Animation dictionaries and prop models are streamed automatically. kora_lib releases loaded dictionaries, stops tracked animations, and deletes attached props when their owning resource stops.

Only one kora_lib animation is tracked per entity. The owning resource may replace
its own tracked handle; another resource cannot replace or stop it.
`Kora.anim.stopHandle` prevents an older system from stopping a newer animation.

### `Kora.anim.play(entity, dict, clip, opts?)`

Streams `dict`, starts `clip` on `entity`, and returns an animation handle. It returns `false, reason` when the dictionary cannot be loaded. An invalid entity, dictionary, or clip is a programmer error and raises an assertion.

Options:

| Field | Default | Meaning |
| --- | --- | --- |
| `duration` | `-1` | `-1` or a non-negative finite integer in milliseconds passed to `TaskPlayAnim`. `-1` retains the native's indefinite/natural-length behavior; a positive value also schedules kora_lib cleanup. |
| `flag` | `1` | FiveM animation flag bitmask. |
| `blendInSpeed` | `8.0` | Animation blend-in speed. |
| `blendOutSpeed` | `8.0` | Animation blend-out speed. |
| `playbackRate` | `0.0` | Playback rate passed to the native. |
| `lockX`, `lockY`, `lockZ` | `false` | Lock the corresponding movement axis. |
| `onFinish` | none | Callable invoked with `entity` after a positive duration expires. It is not called after explicit cancellation or replacement. |

Every supplied numeric option must be finite (`duration` and `flag` are
integers); axis locks must be booleans. kora_lib validates these before streaming
the dictionary or changing the entity's active animation. `onFinish` runs only
after kora_lib has stopped and released the animation; an error is logged without
leaving the animation active.

```lua
local handle, reason = Kora.anim.play(PlayerPedId(), 'amb@world_human_hang_out_street@male_c@idle_a', 'idle_b', {
    duration = 3000,
    flag = 49,
})

if not handle then
    print(reason)
end
```

### Stopping and inspecting

- `Kora.anim.stop(entity, blendOutSpeed?)` stops the currently tracked animation, releases its dictionary, and returns whether one was active. `blendOutSpeed`, when supplied, must be finite. A resource can stop only an animation it started; kora_lib's own delayed cleanup remains internal.
- `Kora.anim.stopHandle(handle, blendOutSpeed?)` stops only when `handle` is still current for its entity. It returns `false` for a stale or invalid handle.
- `Kora.anim.isPlaying(entity)` returns whether the tracked dictionary and clip are currently playing according to the native state.
- `Kora.anim.clear(entity, immediate?)` stops kora_lib's tracked animation and clears all ped tasks. `immediate = true` uses immediate task clearing.

### Scenarios

`Kora.anim.playScenario(entity, scenario, enterVehicle?)` starts a named scenario. When `enterVehicle` is true it uses the vehicle-entry scenario task; otherwise it starts the scenario in place.

### Attached props

`Kora.anim.attachProp(entity, model, bone, offset?, rotation?, opts?)` creates a local, non-networked object and attaches it to the named bone. It returns the prop entity, or `false, reason` if the model cannot load, the bone is absent, or object creation fails.

`bone` is a bone name (`'PH_R_Hand'`, resolved with `GetEntityBoneIndexByName` on any entity) or, on a ped, a ped bone id (`28422`, resolved with `GetPedBoneIndex`). Name lookups do not always resolve on MP freemode peds, so common ped bone names (`SKEL_*_Hand`, `PH_*_Hand`, `IK_*_Hand`, `SKEL_Head`, `IK_Head`, `SKEL_Neck_1`, `SKEL_Spine2/3`, `SKEL_Pelvis`, `SKEL_ROOT`) fall back to their ped bone id. A numeric bone on a non-ped entity returns `false, reason`.

`offset` and `rotation` default to zero vectors. Options map to `AttachEntityToEntity`:

- `softPin` defaults to `false`.
- `collision` defaults to `false`.
- `vertexIndex` is the legacy option name for the native's rotation order and defaults to `0`.
- `fixedRot` controls rotation synchronization and defaults to `true`.

Offsets and rotations require finite `x`/`y`/`z` components. Attachment flags
must be booleans and `vertexIndex` is an integer from `0` to `5`; kora_lib checks
all of them before streaming a model or creating a local prop.

```lua
local prop, reason = Kora.anim.attachProp(PlayerPedId(), 'prop_cs_tablet', 'IK_R_Hand',
    vector3(0.03, 0.002, -0.01),
    vector3(10.0, 160.0, 0.0))
```

`Kora.anim.detachProp(prop)` only accepts a prop created by this module and owned by its caller. It detaches, deletes, and untracks the object, returning `true`; an unowned, foreign, or missing prop returns `false, reason`.
