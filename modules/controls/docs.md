# Controls

`QB.controls` owns the every-frame native calls required to suppress game input. Its leases are reference-counted, so independent systems can disable the same control without one system's cleanup re-enabling it for another.

## `QB.controls.acquire(controlIds, options?)`

```lua
local lease = QB.controls.acquire({ 24, 25 }, {
    inputGroup = 0,
    disablePlayerFiring = true,
    ignoreWeaponWheel = true,
})
```

- `controlIds` is a dense array of non-negative integer control IDs. Duplicate IDs are ignored.
- `options.inputGroup` defaults to `0` and is passed to `DisableControlAction`.
- `options.disablePlayerFiring` defaults to `false`. When enabled, `DisablePlayerFiring(PlayerId(), true)` is also applied every frame.
- `options.ignoreWeaponWheel` defaults to `false`. When enabled, `HudWeaponWheelIgnoreSelection()` is applied every frame.
- At least one control ID or active suppression option is required.
- Returns an opaque integer lease ID. The calling resource owns the lease, and qblib releases it automatically if that resource stops.

The controls are applied immediately before `acquire` returns and then once per frame. That makes disabled-input reads such as `IsDisabledControlJustPressed` and `GetDisabledControlNormal` safe in the same tick.

## `QB.controls.release(leaseId)`

Releases one lease and returns `true`. Unknown or already-released IDs return `false`, making cleanup safe to repeat. A control remains disabled until every lease containing it has been released.
