---
title: "Controls"
sidebar_position: 10
---


# Controls

Disables selected game inputs every frame while a lease is active. A lease is an ownership record: if two systems disable the same control, releasing one lease does not re-enable it while the other system still needs it. kora_lib also releases a resource’s leases when that resource stops.

Namespace: `Kora.controls` · Source: `modules/controls/client.lua`

## acquire options

Pass these settings as the second argument. If omitted, the input group defaults to 0 and the extra suppression actions are disabled. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `inputGroup?` | integer | Non-negative game input group passed to DisableControlAction. Defaults to 0. |
| `disablePlayerFiring?` | boolean | Calls DisablePlayerFiring for the local player every frame while the lease is active. Defaults false. |
| `ignoreWeaponWheel?` | boolean | Calls HudWeaponWheelIgnoreSelection every frame while active. Defaults false. |

## Why leases can overlap

Imagine an interaction menu and a progress bar both suppressing movement. Each receives its own lease. When the menu closes, movement remains disabled for the bar. It is enabled again only after the last active lease releases it.

## Resource cleanup

Each lease belongs to the resource that requested it. kora_lib releases active leases when that resource stops. The internal Kora.compat bridge is not a consumer API; use Kora.controls.acquire and release from your resource.

## Functions

Acquire a lease with the controls or suppression actions you need, then release the returned lease ID when the interaction is finished.

### `Kora.controls.acquire(controlIds, options?)`

Starts a reference-counted control lease. Controls are disabled immediately before this function returns and once per frame afterward, so disabled-control input reads can be used during the same tick.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `controlIds` | integer[] | Dense array of non-negative integer game control IDs. Duplicate IDs are ignored. An empty array is allowed only if an option enables another suppression action. |
| `options?` | table | Optional input group and additional suppression settings. See the options table above. |

**Returns**

- **leaseId** — positive integer identifying this caller-owned lease.

**Example**

```lua
local lease = Kora.controls.acquire({ 24, 25 }, {
    inputGroup = 0,
    disablePlayerFiring = true,
})
-- Later, when aiming is allowed again:
Kora.controls.release(lease)
```

**Representative console output**

```text
Controls 24 and 25 and player firing are disabled while this lease exists.
```

### `Kora.controls.release(leaseId)`

Releases one lease owned by the calling resource. It is safe to call during cleanup even if the lease was already released.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `leaseId` | integer | Lease ID returned by Kora.controls.acquire. Another resource cannot release this lease. |

**Returns**

- **released** — true if the lease was active and removed; false if unknown, already released, or owned by another resource.

**Example**

```lua
if lease then
    Kora.controls.release(lease)
    lease = nil
end
```

**Representative console output**

```text
Returns true the first time this active lease is released.
```

## Limits and related APIs

At least one control ID or active suppression option is required. The input-group and control IDs must be non-negative integers; options must be a table when supplied.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/controls/docs.md` or `local/controls/docs.md`) that the reference above does not state.

`Kora.controls` owns the every-frame native calls required to suppress game input. Its leases are reference-counted, so independent systems can disable the same control without one system's cleanup re-enabling it for another.

### `Kora.controls.acquire(controlIds, options?)`

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

### `Kora.controls.release(leaseId)`

Releases one of the calling resource's leases and returns `true`. Unknown,
already-released, or another resource's IDs return `false`, making cleanup safe
to repeat. A control remains disabled until every lease containing it has been
released.
