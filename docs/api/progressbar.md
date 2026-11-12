---
title: "Progressbar"
sidebar_position: 17
---


# Progressbar

Shows the player a timed activity bar, such as picking a lock or repairing a car. The bar can block controls, play an animation or scenario, and show temporary cosmetic props. Lua owns the timer and completion result; the browser only draws the bar.

Namespace: `Kora.progressbar` · Source: `modules/progressbar/client.lua`

## Progress bar payload fields

Pass one table to start or validate. Required fields have no ?. Omitted optional fields use defaults. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `label` | string | Required. Text shown above the bar. |
| `duration` | integer | Required positive whole milliseconds; maximum is Config.progressbar.maxDuration (10 minutes by default). |
| `canCancel?` | boolean | Allow X/Escape cancellation; defaults false. |
| `maxDuration?` | integer \| false | Compatibility override for the configured maximum; false removes the cap. Ordinary resource calls should use the configured maximum. |
| `cancelControls?` | integer[] \| false | Compatibility override for cancel control ids; false lets a compatibility provider handle its remappable cancel command. |
| `presentation?` | string | bar or circle; defaults bar. |
| `position?` | string | middle or bottom; controls circle placement. |
| `useWhileDead? / allowRagdoll? / allowCuffed? / allowFalling? / allowSwimming?` | boolean | Allow the bar during that player state; each defaults false. |
| `strictAnim?` | boolean | Compatibility switch: raise if animation dictionary fails. Normal calls continue the bar without animation. |
| `emote?` | string | Optional kora_emotemenu emote; ignored when anim or scenario is supplied. |
| `maxProps?` | integer \| false | Overrides the local props limit. Defaults to Config.progressbar.maxProps (2); false removes this limit. |

### disable? table

Each field controls one kind of input suppression. The table itself is optional; every field defaults to false unless stated otherwise.

| Option | Type | Description |
| --- | --- | --- |
| `move?` | boolean | Blocks movement input while the bar runs. Defaults false. |
| `moveMode?` | 'controls' \| 'freeze' | How move=true works. controls disables movement input but leaves the ped unfrozen (default); freeze also freezes the ped when safe. |
| `controlProfile?` | 'kora_lib' \| 'ox' | Selects which control set is disabled for combat and vehicle controls. Defaults to kora_lib. |
| `sprint?` | boolean | Blocks sprint input. Defaults false. |
| `combat?` | boolean | Blocks attacking, aiming, weapon switching, and melee. Defaults false. |
| `car?` | boolean | Blocks vehicle driving controls while the player is in a vehicle. Defaults false. |
| `mouse?` | boolean | Blocks look input. Defaults false. |

### anim? table

Play an animation while the progress bar runs. Supply both required strings. The dictionary is requested automatically and cleaned up after the bar.

| Option | Type | Description |
| --- | --- | --- |
| `dict` | string | Required animation dictionary name, for example anim@amb@clubhouse@tutorial@bkr_tut_ig3@. |
| `clip` | string | Required animation clip name inside the dictionary. |
| `flag?` | integer | TaskPlayAnim animation flags. Defaults to 1 (loop). |
| `blendIn?` | number | Blend-in speed when starting the animation. Defaults to 8.0. |
| `blendOut?` | number | Blend-out speed. Defaults to 8.0 and is also used during cleanup unless stopBlendOut is set. |
| `stopBlendOut?` | number | Cleanup blend-out override. Usually leave unset; compatibility calls may use this. |
| `duration?` | integer | Animation task duration in milliseconds. Defaults to -1, allowing the progress bar to own when it stops. |
| `playbackRate?` | number | Playback speed passed to TaskPlayAnim. Defaults to 0. |
| `lockX? / lockY? / lockZ?` | boolean | Whether the animation task locks movement on each axis. Each defaults false. |

### scenario? table

Use a game scenario instead of anim. You cannot set both scenario and anim on the same progress bar.

| Option | Type | Description |
| --- | --- | --- |
| `name` | string | Required scenario name, for example WORLD_HUMAN_HAMMERING. |
| `playEnter?` | boolean | Whether to play the scenario enter animation. Defaults true. |

### props? array

Each array item creates one local cosmetic object attached to the player. Models are loaded before the timer begins; created props are removed when the bar completes, cancels, or errors. The default limit is two.

| Option | Type | Description |
| --- | --- | --- |
| `model` | string \| integer | Required model name or model hash. |
| `bone?` | string \| integer | Ped bone name or ID to attach the object to. Defaults to 60309 (right hand). |
| `offset?` | vector3 | Position offset from the bone, in local coordinates. Defaults to vector3(0, 0, 0). |
| `rotation?` | vector3 | Rotation offset from the bone. Defaults to vector3(0, 0, 0). |
| `softPinning?` | boolean | Whether the attached object uses soft pinning. Defaults true. |
| `collision?` | boolean | Whether the local prop has collision. Defaults false. |
| `rotationOrder?` | integer | Rotation order from 0 through 5. Defaults to 0. |
| `syncRotation?` | boolean | Whether the prop rotation follows the attached bone. Defaults true. |

### prop? and proptwo? legacy tables

These older single-prop fields are still supported. Each takes the same model and attachment settings as props[], with coords used as the attachment offset.

| Option | Type | Description |
| --- | --- | --- |
| `model` | string \| integer | Required model name or hash. |
| `coords` | vector3 | Required legacy position offset from the attachment bone. |
| `bone` | integer | Required ped bone ID. |
| `rotation` | vector3 | Required rotation offset. |

## What can end the bar?

Only one bar can run at a time. Starting another does not replace or queue it; it returns false and an error. Death, ragdoll, cuffs, falling, swimming, cancel key, explicit cancel, internal error, or resource shutdown can interrupt it. Allow flags opt into continuing through specific states.

## What happens to animations and props?

Models and dictionaries are loaded before the bar begins. If a cosmetic animation or prop cannot load, the bar can still run without it. Props are local to this client and are deleted when the bar completes, cancels, errors, or its resource stops.

## Movement and server actions

Movement suppression blocks controls by default; it does not freeze the ped unless moveMode is freeze. Even freeze is skipped while airborne, jumping, falling, or ragdolling. The progress bar is only feedback: your server must authorize the action before and validate it again after the bar.

## Functions

Validate a payload before starting, run the bar, cancel your own bar, or check whether one is running.

### `Kora.progressbar.validate(payload)`

Checks bar settings without showing a bar. This is useful before asking a server to create an action token, because invalid display settings are caught first.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `payload` | KoraProgressBarPayload | Same table shape accepted by start; see shared options above. |

**Returns**

- **true** — settings are valid.
- **invalid settings** — raises an assertion naming the invalid value.

**Example**

```lua
local valid = pcall(function()
    Kora.progressbar.validate({ label = 'Repairing', duration = 5000 })
end)
if not valid then return end
```

**Representative console output**

```text
A valid payload passes without showing anything. An invalid payload raises before an action begins.
```

### `Kora.progressbar.start(payload)`

Starts a progress bar and waits until its time completes or something cancels it.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `payload` | KoraProgressBarPayload | Required label and duration plus optional presentation/behavior settings. |

**Returns**

- **completed** — boolean; true only after the full duration.
- **error** — returned when another progress bar was already active.

**Example**

```lua
local completed = Kora.progressbar.start({
    label = 'Picking lock...',
    duration = 8000,
    canCancel = true,
    disable = { move = true, combat = true, car = true },
    anim = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer' },
})
if completed then
    print('Lock picked.')
else
    print('Lockpicking interrupted.')
end
```

**Representative console output**

```text
After eight seconds it prints Lock picked. If the player cancels or is interrupted, it prints Lockpicking interrupted.
```

### `Kora.progressbar.cancel()`

Requests cancellation of a progress bar owned by the calling resource.

**Parameters**



**Returns**

- **cancelled** — true if a bar was running; otherwise false.

**Example**

```lua
if shouldAbortRepair then
    Kora.progressbar.cancel()
end
```

**Representative console output**

```text
The active start call sees cancellation on its next frame and returns false.
```

### `Kora.progressbar.isActive()`

Checks whether a progress bar is running now.

**Parameters**



**Returns**

- **active** — boolean.

**Example**

```lua
if Kora.progressbar.isActive() then print("Player is busy") end
```

**Representative console output**

```text
Prints Player is busy while a bar is active.
```

## Limits and related APIs

The browser animation does not decide success; Lua timer does. Do not run the original standalone progressbar resource alongside kora_lib compatibility exports.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/progressbar/docs.md` or `local/progressbar/docs.md`) that the reference above does not state.

### Legacy `progressbar` resource

kora_lib provides the five exports and six events from
`qbcore-framework/progressbar` commit `6e9381de6637bd443a8eaf1a6da0d339d8cebb15`:
`Progress`, `ProgressWithStartEvent`, `ProgressWithTickEvent`,
`ProgressWithStartAndTick`, and `isDoingSomething`. The four start variants also
accept their `progressbar:client:*` events (`progress` is lowercase).
`progressbar:client:cancel` cancels the current legacy bar;
`progressbar:client:ToggleBusyness` gates starts and can end a running bar.
Finish callbacks receive `cancelled`, and can start the next bar. Busy/dead
starts do not call callbacks. No sequence export exists at this pinned version.

Animation/task, both props, all four control-disable groups, Escape cancellation,
and `inv_busy` are translated. Resource shutdown releases owned state and does
not call callbacks into the stopped resource. Existing `inv_busy=true` is restored.
Native timing owns completion; the old `FinishAction` NUI callback is not exposed.
Legacy props opt into upstream's networked creation/visibility flags and disable
owner migration; the same session owns deletion on completion, cancellation,
failure and resource stop. Native calls still create local props by default.
Do not run the original progressbar resource alongside kora_lib's provider.

`Kora.progressbar.start(payload, owner?, hooks?)` accepts internal compatibility
hooks `onStart`, `onTick`, and `isFinished`, plus `networkedProps`; hooks run in the existing native
session and all cleanup/error handling remains in that session.

For core forwarding only, `Progress(action, finish, owner?)` accepts the captured
original resource name as its third argument, honoured only when the actual
invoking resource is `kora_core`. A core adapter must capture that
name before crossing the kora_lib export boundary so stop/cancel cleanup belongs to
the actual caller. Ordinary legacy callers omit it.
