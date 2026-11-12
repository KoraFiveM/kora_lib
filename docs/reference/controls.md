---
title: "Controls"
sidebar_position: 10
---

# Controls

`Kora.controls` owns the every-frame native calls required to suppress game input. Its leases are reference-counted, so independent systems can disable the same control without one system's cleanup re-enabling it for another.

## `Kora.controls.acquire(controlIds, options?)`

```lua
local lease = Kora.controls.acquire({ 24, 25 }, {
    inputGroup = 0,
    disablePlayerFiring = true,
    ignoreWeaponWheel = true,
})
```

- `controlIds` is a dense array of finite, non-negative integer control IDs. Duplicate IDs are ignored.
- `options.inputGroup` defaults to `0` only when omitted; it must be a finite, non-negative integer and is passed to `DisableControlAction`.
- `options.disablePlayerFiring` defaults to `false`. When enabled, `DisablePlayerFiring(PlayerId(), true)` is also applied every frame.
- `options.ignoreWeaponWheel` defaults to `false`. When enabled, `HudWeaponWheelIgnoreSelection()` is applied every frame.
- At least one control ID or active suppression option is required.
- Returns an opaque integer lease ID. The calling resource owns the lease, and kora_lib releases it automatically if that resource stops.

The controls are applied immediately before `acquire` returns and then once per frame. That makes disabled-input reads such as `IsDisabledControlJustPressed` and `GetDisabledControlNormal` safe in the same tick.

The lease remains owned by the resource that acquired it even when kora_lib later
finishes an asynchronous progress bar, menu, placement tool, raycast tool, or
zone creator on that resource's behalf. kora_lib uses that captured ownership only
for its own cleanup; it does not make a lease transferable between resources.

## `Kora.controls.release(leaseId)`

Releases one of the calling resource's leases and returns `true`. Unknown,
already-released, or another resource's IDs return `false`, making cleanup safe
to repeat. A control remains disabled until every lease containing it has been
released.
