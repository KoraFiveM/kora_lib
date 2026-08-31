# Progress bar module

## Overview
Shows a filling progress bar to the local player for a fixed duration, optionally playing an animation or scenario, attaching network-visible props, and disabling controls. Client-only — there is no server API, and no round trip to the NUI: Lua owns the timing and the completion decision, while the NUI is purely visual.

## API

### `QB.progressbar.start(payload)`
Runs a progress bar for `payload.duration` ms.

#### Parameters
- `payload: QBProgressBarPayload`
  - `label: string` — Text shown above the bar. Required.
  - `duration: integer` — Milliseconds the bar takes to fill. Must be `> 0` and `<= Config.progressbar.maxDuration` (10 minutes by default).
  - `canCancel?: boolean` — Lets the player abort early by pressing `Config.progressbar.cancelControl` (`73` / "X" by default). Defaults to `false`.
  - `disable?: table`
    - `move?: boolean` — Freezes the ped in place for the duration (`FreezeEntityPosition`). Defaults to `false`.
    - `combat?: boolean` — Disables attack/aim/weapon-switch/melee controls for the duration. Defaults to `false`.
    - `car?: boolean` — Disables vehicle driving controls while the ped is in a vehicle. Defaults to `false`.
  - `anim?: table` — Played for the duration, stopped and released automatically when the bar ends.
    - `dict: string`, `clip: string` — Animation dictionary/clip.
    - `flag?: number` — `TaskPlayAnim` AnimFlags bitmask. Defaults to `1` (loop).
    - `blendIn?: number`, `blendOut?: number` — Default `8.0` each.
  - `scenario?: table` — Alternative to `anim`; the two cannot be combined.
    - `name: string` — Scenario name, such as `WORLD_HUMAN_HAMMERING`.
    - `playEnter?: boolean` — Whether to play its enter animation. Defaults to `true`.
  - `props?: table[]` — Up to `Config.progressbar.maxProps` network-visible objects (2 by default), created before the timer begins and deleted when it ends.
    - `model: string | integer` — Model name or hash. Required.
    - `bone?: string | integer` — Ped bone name or ID. Defaults to `60309`.
    - `offset?: vector3 | {x, y, z}` and `rotation?: vector3 | {x, y, z}` — Default to zero.
    - `softPinning?: boolean` — Defaults to `true`.
    - `collision?: boolean` — Defaults to `false`.
    - `rotationOrder?: integer` — `0` through `5`; defaults to `0`.
    - `syncRotation?: boolean` — Defaults to `true`.

#### Returns
- `boolean completed` — `false` if the bar never started, or was cancelled (death, the cancel key, `QB.progressbar.cancel()`, or an internal error) before `duration` elapsed.
- `string | nil error` — Set only when the bar never started at all (another one is already active).

#### Example
```lua
local completed = QB.progressbar.start({
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

### `QB.progressbar.cancel()`
Cancels the currently active progress bar, if any. The active `QB.progressbar.start` call notices on its next tick (at most one frame later) and returns `completed = false` — this does not interrupt it synchronously.

#### Returns
- `boolean` — `true` if a bar was actually running and got cancelled; `false` if none was active.

### `QB.progressbar.isActive()`
Returns `true` while a progress bar started by this module is currently running.

## Notes
- Only one bar can be active at a time. Calling `start` while one is already running does not queue or interrupt it — it fails immediately with `completed = false, error = "A progress bar is already active."` — a progress bar represents "the player is busy doing one specific thing right now", and silently stacking a second one on top would make both visually and mechanically incoherent (which anim plays, whose controls win).
- Dying always cancels the bar, regardless of `disable`/`canCancel`.
- If `anim.dict` fails to load within 5 seconds, the bar still runs (and can still complete) — it just runs without the animation, and a warning is printed to the client console.
- Prop models are streamed before the progress timer and NUI animation start. A malformed descriptor is rejected up front; a runtime streaming/object/attachment failure logs a warning and lets the action continue without that prop.
- Props are networked mission entities configured for visibility on all machines and stable creator ownership. They are detached and deleted on completion, cancellation, internal errors, or resource shutdown.
- Combat and vehicle suppression use reference-counted `QB.controls` leases, so they can overlap other qblib input owners without releasing those owners' controls.
- The NUI side (`web/src/components/progressbar/ProgressBar.tsx`) is fire-and-forget: `QB.nui.send("progressStart", { label, duration })` starts its own CSS fill animation timed to `duration` and hides itself when that finishes; `QB.nui.send("progressCancel")` (no payload) hides it immediately for every early-exit path. Lua's own timing is authoritative either way — the NUI never reports back.
