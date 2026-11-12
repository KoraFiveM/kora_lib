---
title: "Progress bar module"
sidebar_position: 17
---

# Progress bar module

## Overview
Shows a filling progress bar to the local player for a fixed duration, optionally playing an animation or scenario, attaching local cosmetic props, and disabling controls. Client-only — there is no server API, and no round trip to the NUI: Lua owns the timing and the completion decision, while the NUI is purely visual.

## API

### `Kora.progressbar.validate(payload)`
Validates the same payload accepted by `start` without displaying a bar or
changing active state. It returns `true` or raises for invalid input. Use it
when a resource must validate a future progress payload before beginning a
server-authorized flow; `Kora.actions.run` uses it for that purpose.

### `Kora.progressbar.start(payload)`
Runs a progress bar for `payload.duration` ms.

#### Parameters
- `payload: KoraProgressBarPayload`
  - `label: string` — Text shown above the bar. Required.
  - `duration: finite integer` — Milliseconds the bar takes to fill. Must be `> 0` and `<= Config.progressbar.maxDuration` (10 minutes by default).
  - `maxDuration?: finite integer|false` — Internal compatibility override for a different positive limit; `false` removes the cap. Normal kora_lib calls should keep the configured default.
  - `canCancel?: boolean` — Lets the player abort early with `Config.progressbar.cancelControls` (`73` / X or `322` / Escape by default). Defaults to `false`.
  - `cancelControls?: integer[]|false` — Internal compatibility override for the controls polled by kora_lib; `false` delegates cancellation to a compatibility resource's remappable command.
  - `presentation?: "bar" | "circle"` and `position?: "middle" | "bottom"` — Select the visual used by ox-compatible progress-circle calls.
    The bar (and a circle at `"bottom"`) sits `Config.progressbar.bottomOffset` rem (default `10`) above the screen bottom, clear of kora_hud's vitals.
  - `useWhileDead?`, `allowRagdoll?`, `allowCuffed?`, `allowFalling?`, `allowSwimming?` — State-specific interruption overrides; all default to `false`.
  - `disable?: table`
    - `move?: boolean` — Blocks the player's movement controls for the duration. Defaults to `false`. By default (`Config.progressbar.defaultMoveMode = 'controls'`) the ped is **not** frozen, so a bar started from a target option while walking does not lock the character like an admin freeze. Set `moveMode = 'freeze'` (or change the config default) to also `FreezeEntityPosition`; the freeze is skipped while the ped is falling, jumping, ragdolling or airborne and is always undone on finish, cancel, death and resource stop.
    - `moveMode?: 'freeze'|'controls'` — Per-bar override of `Config.progressbar.defaultMoveMode`.
    - `sprint?: boolean` — Disables sprinting.
    - `combat?: boolean` — Disables attack/aim/weapon-switch/melee controls for the duration. Defaults to `false`.
    - `car?: boolean` — Disables vehicle driving controls while the ped is in a vehicle. Defaults to `false`.
    - `mouse?: boolean` — Disables look input.
  - `anim?: table` — Played for the duration, stopped and released automatically when the bar ends.
  - `strictAnim?: boolean` — Internal compatibility switch that raises if `anim.dict` cannot load. Normal kora_lib calls retain the graceful fallback below.
    - `dict: string`, `clip: string` — Animation dictionary/clip.
    - `flag?: number` — `TaskPlayAnim` AnimFlags bitmask. Defaults to `1` (loop).
    - `blendIn?: number`, `blendOut?: number` — Default `8.0` each.
    - `duration?: integer`, `playbackRate?: finite number`, `lockX?`, `lockY?`, `lockZ?` — Forwarded to `TaskPlayAnim`.
    - `stopBlendOut?: finite number` — Internal compatibility override for the cleanup blend-out; normal calls reuse `blendOut`.
  - `scenario?: table` — Alternative to `anim`; the two cannot be combined.
    - `name: string` — Scenario name, such as `WORLD_HUMAN_HAMMERING`.
    - `playEnter?: boolean` — Whether to play its enter animation. Defaults to `true`.
  - `emote?: string` — Plays `exports.kora_emotemenu:playEmote(emote)` for the duration and cancels it during cleanup. Ignored when `anim` or `scenario` is supplied.
  - `prop?: table`, `proptwo?: table` — Legacy singular local cosmetic props. Each requires `model: string|integer`, `coords: vector3`, `bone: integer`, and `rotation: vector3`. Both may be supplied and are attached and deleted with the same lifecycle as `props`.
  - `props?: table[]` — Up to `Config.progressbar.maxProps` local cosmetic objects (2 by default), with finite transform components, created before the timer begins and deleted when it ends.
    - `model: string | integer` — Model name or hash. Required.
    - `bone?: string | integer` — Ped bone name or ID. Defaults to `60309`.
    - `offset?: vector3 | {x, y, z}` and `rotation?: vector3 | {x, y, z}` — Default to zero.
    - `softPinning?: boolean` — Defaults to `true`.
    - `collision?: boolean` — Defaults to `false`.
    - `rotationOrder?: integer` — `0` through `5`; defaults to `0`.
    - `syncRotation?: boolean` — Defaults to `true`.

#### Returns
- `boolean completed` — `false` if the bar never started, or was cancelled (death, the cancel key, `Kora.progressbar.cancel()`, or an internal error) before `duration` elapsed.
- `string | nil error` — Set only when the bar never started at all (another one is already active).

#### Example
```lua
local completed = Kora.progressbar.start({
    label = "Picking lock...",
    duration = 8000,
    canCancel = true,
    disable = { move = true, combat = true, car = true },
    anim = { dict = "anim@amb@clubhouse@tutorial@bkr_tut_ig3@", clip = "machinic_loop_mechandplayer" },
    props = {
        {
            model = "prop_tool_screwdvr01",
            bone = 60309,
            offset = vector3(0.05, 0.0, 0.0),
            rotation = vector3(0.0, 0.0, 0.0),
        },
    },
})

if completed then
    print("Lock picked.")
else
    print("Lockpicking interrupted.")
end
```

### `Kora.progressbar.cancel()`
Cancels the caller's currently active progress bar, if any. A resource cannot
cancel a bar started by another resource; compatibility providers may pass
their captured internal owner. The active `Kora.progressbar.start` call notices
on its next tick (at most one frame later) and returns `completed = false` —
this does not interrupt it synchronously.

#### Returns
- `boolean` — `true` if a bar was actually running and got cancelled; `false` if none was active.

### `Kora.progressbar.isActive()`
Returns `true` while a progress bar started by this module is currently running.

## Notes
- Only one bar can be active at a time. Calling `start` while one is already running does not queue or interrupt it — it fails immediately with `completed = false, error = "A progress bar is already active."` — a progress bar represents "the player is busy doing one specific thing right now", and silently stacking a second one on top would make both visually and mechanically incoherent (which anim plays, whose controls win).
- Death, ragdoll, cuffed, falling, and swimming states cancel by default; their explicit allow flags opt into continuing.
- If `anim.dict` fails to load within 5 seconds, the bar still runs (and can still complete) — it just runs without the animation, and a warning is printed to the client console.
- Prop models are streamed before the progress timer and NUI animation start. A malformed descriptor is rejected up front; a runtime streaming/object/attachment failure logs a warning and lets the action continue without that prop.
- Props are non-networked local entities, so they work under strict entity lockdown and cannot become shared world state. They are detached and deleted on completion, cancellation, internal errors, or resource shutdown. If nearby players must see a gameplay prop, its owning server resource must create and lifecycle-manage it separately.
- Combat and vehicle suppression use reference-counted `Kora.controls` leases, so they can overlap other kora_lib input owners without releasing those owners' controls.
- The NUI side (`web/src/components/progressbar/ProgressBar.tsx`) is fire-and-forget: `Kora.nui.send("progressStart", { label, duration })` starts its own CSS fill animation timed to `duration` and hides itself when that finishes; `Kora.nui.send("progressCancel")` (no payload) hides it immediately for every early-exit path. Lua's own timing is authoritative either way — the NUI never reports back.


## Legacy `progressbar` resource

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
