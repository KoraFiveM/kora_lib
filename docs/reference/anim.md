---
title: "Animations"
sidebar_position: 20
---

# Animations

Client-side, resource-owned animation and attached-prop helpers. Animation dictionaries and prop models are streamed automatically. kora_lib releases loaded dictionaries, stops tracked animations, and deletes attached props when their owning resource stops.

Only one kora_lib animation is tracked per entity. The owning resource may replace
its own tracked handle; another resource cannot replace or stop it.
`Kora.anim.stopHandle` prevents an older system from stopping a newer animation.

## `Kora.anim.play(entity, dict, clip, opts?)`

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

## Stopping and inspecting

- `Kora.anim.stop(entity, blendOutSpeed?)` stops the currently tracked animation, releases its dictionary, and returns whether one was active. `blendOutSpeed`, when supplied, must be finite. A resource can stop only an animation it started; kora_lib's own delayed cleanup remains internal.
- `Kora.anim.stopHandle(handle, blendOutSpeed?)` stops only when `handle` is still current for its entity. It returns `false` for a stale or invalid handle.
- `Kora.anim.isPlaying(entity)` returns whether the tracked dictionary and clip are currently playing according to the native state.
- `Kora.anim.clear(entity, immediate?)` stops kora_lib's tracked animation and clears all ped tasks. `immediate = true` uses immediate task clearing.

## Scenarios

`Kora.anim.playScenario(entity, scenario, enterVehicle?)` starts a named scenario. When `enterVehicle` is true it uses the vehicle-entry scenario task; otherwise it starts the scenario in place.

## Attached props

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
