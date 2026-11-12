---
title: "Timers"
sidebar_position: 52
---


# Timers

Owner-tracked timers and rate-shaping helpers shared by client and server code. Scheduled work is associated with the resource that created it and cancelled automatically when that resource stops.

Namespace: `Kora.timers` · Source: `modules/timers/shared.lua`

## How it works

All delays and intervals are finite non-negative integers in milliseconds. setInterval waits one full interval before its first call. debounce is trailing-edge; throttle is leading-edge and drops calls during its cooldown. The returned debounce/throttle handles are callable tables inside kora_lib; across resource exports, call their .run method because Lua metatables do not cross the export boundary.

## Functions

The shared API includes timeout and interval scheduling, cancellation, debounce and throttle wrappers, keyed cooldowns, and a live timer count.

### `Kora.timers.setInterval(fn, interval)`

Schedules a repeating callback. The first invocation occurs after one complete interval.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `fn` | number | callable callback. |
| `interval` | number | finite integer milliseconds, greater than or equal to 0. |

**Returns**

- **id** — integer timer ID accepted by clearInterval or clearTimeout.

**Example**

```lua
local timerId = Kora.timers.setInterval(function()
    refreshStatus()
end, 3000)
```

**Representative console output**

```text
refreshStatus runs first after 3000 ms, then every 3000 ms until cancelled or its owner stops.
```

### `Kora.timers.setTimeout(fn, delay)`

Schedules a callback once after delay milliseconds. The scheduled work can be cancelled and is tied to its owning resource.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `fn` | number | callable callback. |
| `delay` | number | finite non-negative integer milliseconds. |

**Returns**

- **id** — integer timer ID accepted by clearTimeout or clearInterval.

**Example**

```lua
local timerId = Kora.timers.setTimeout(function()
    closePrompt()
end, 1500)
```

**Representative console output**

```text
closePrompt runs once after 1500 ms unless cancelled or its owner stops.
```

### `Kora.timers.clearInterval(id)`

Cancels a live interval. Cancellation is observed immediately after the timer’s next wake.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | integer | integer ID returned by setInterval or setTimeout and owned by the calling resource. |

**Returns**

- **cancelled** — boolean; false when the ID was not live or was already cancelled/fired.

**Example**

```lua
local cancelled = Kora.timers.clearInterval(timerId)
```

**Representative console output**

```text
true when the timer was cancelled; false for an inactive or unknown ID.
```

### `Kora.timers.clearTimeout(id)`

Cancels a live timeout. It shares the same timer ID space as clearInterval.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | integer | integer ID returned by setTimeout or setInterval and owned by the calling resource. |

**Returns**

- **cancelled** — boolean; false when the ID was not live or was already cancelled/fired.

**Example**

```lua
Kora.timers.clearTimeout(timerId)
```

**Representative console output**

```text
true when the timer was cancelled.
```

### `Kora.timers.debounce(fn, wait)`

Creates a trailing-edge debouncer. Each call restarts the quiet-period timer; only the last call’s arguments are passed to fn.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `fn` | number | callable callback. |
| `wait` | number | finite non-negative integer milliseconds without a call before execution. |

**Returns**

- **handle** — callable table with run(...), cancel(), and isPending() methods. Use .run(...) across resource exports.
- **cancel()** — boolean; drops a pending call.
- **isPending()** — boolean; whether a run is waiting.

**Example**

```lua
local saveSoon = Kora.timers.debounce(function(slot)
    persist(slot)
end, 500)
saveSoon.run(3)
saveSoon.run(3) -- one persist(3), 500 ms after the last call
```

**Representative console output**

```text
Calls inside the wait window collapse into one trailing invocation.
```

### `Kora.timers.throttle(fn, interval)`

Creates a leading-edge throttle. The first call runs immediately; calls during the interval are dropped rather than queued.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `fn` | number | callable callback. |
| `interval` | number | finite non-negative integer milliseconds between accepted calls. |

**Returns**

- **handle** — callable table with run(...), reset(), and remaining() methods. The call and .run return whether fn ran.
- **reset()** — clears the cooldown.
- **remaining()** — integer milliseconds until ready, or 0.

**Example**

```lua
local report = Kora.timers.throttle(sendAlert, 15000)
if IsPedShooting(ped) then
    report.run(GetEntityCoords(ped))
end
```

**Representative console output**

```text
The first eligible call runs immediately; calls during the 15 second cooldown return false and are discarded.
```

### `Kora.timers.cooldown(interval)`

Creates independent leading-edge cooldowns addressed by scalar keys.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `interval` | boolean | finite non-negative integer milliseconds. Keys passed to the handle must be finite numbers, booleans, or strings up to 256 bytes. |

**Returns**

- **handle** — table with use(key), remaining(key), and reset(key?) methods.
- **use(key)** — boolean; true for the first accepted use after the interval, false during cooldown.
- **remaining(key)** — integer milliseconds until the key is ready.
- **reset(key?)** — clears one key, or all keys when omitted.

**Example**

```lua
local requests = Kora.timers.cooldown(1000)
if not requests.use(source) then return end
processRequest(source)
```

**Representative console output**

```text
Cooldown state is independent for each key. Key lifecycle is caller-managed; reset player keys on playerDropped.
```

### `Kora.timers.count()`

Returns the number of live scheduled timers for diagnostics. A pending debounce contributes one; throttle/debounce wrappers with no pending work do not.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `—` |  | No parameters. |

**Returns**

- **count** — integer number of live timers.

**Example**

```lua
print(('%d timers are live'):format(Kora.timers.count()))
```

**Representative console output**

```text
A non-negative integer.
```

## Limits and related APIs

Callbacks are protected with pcall; an interval that errors is logged and continues running. A zero interval repeats once per game frame and should be reserved for engine work that must be reasserted each frame. Debounce captures the creating resource as owner before its asynchronous delay.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/timers/docs.md` or `local/timers/docs.md`) that the reference above does not state.

### Overview
Owner-tracked repeating and deferred callbacks, plus the two rate shapers most
consumers otherwise hand-roll. Everything here is tracked against
`GetInvokingResource()` and cancelled automatically when that resource stops.

`modules/loops` is the sibling to reach for when you want to *poll until a
condition becomes true and then stop* — `Kora.loops.controlled` has no answer for
"run this every N ms until I say stop", which is what a heartbeat, a decay tick,
or a periodic refresh needs.

Shared realm: the same API exists on client and server.

### API

#### `Kora.timers.throttle(fn, interval)`
Wraps `fn` so it runs at most once per `interval` ms. **Leading-edge**: the
first call passes through immediately and calls inside the cooldown are
*dropped*, not queued for a trailing run.

That choice matters for alerts: a queued trailing call would fire a dispatch
about a moment that has already passed, at coordinates the suspect has left.

#### Calling the handle from another resource

Both handles are callable tables, made callable by a `__call` metamethod. **That
metamethod does not survive the export boundary.** Any resource other than kora_lib
reaches these through the `Kora` proxy, which compiles `Kora.timers.throttle(...)`
into `exports.kora_lib:timers_throttle(...)`; the returned table's *fields* cross
fine as funcrefs, but its metatable is not carried across. Calling the handle
directly there fails with:

```text
attempt to call a table value (upvalue 'reportMelee')
```

So from outside kora_lib, always use `.run(...)`:

```lua
local reportMelee = Kora.timers.throttle(function() ... end, 30000)

reportMelee()      -- works only inside kora_lib itself
reportMelee.run()  -- correct everywhere
```

`.run()` is the same code path `__call` delegates to, so behaviour and return
value are identical. Test mocks must mirror the shape — returning a bare
function from a mocked `throttle` hides this class of bug.

#### `Kora.timers.cooldown(interval)`

Creates independent leading-edge cooldowns within one handle. Use a player
source, action name, or composite scalar as the key. Keys must be finite
numbers, booleans, or strings up to 256 bytes; tables are rejected so a
long-lived cooldown cannot retain arbitrary object graphs.

- `.use(key)` → `boolean` accepts the first use after the interval.
- `.remaining(key)` → `integer` returns milliseconds until ready.
- `.reset(key?)` clears one key, or every key when omitted.

The handle deliberately does not guess key lifecycle. Long-lived server code
using player sources should reset that source from `playerDropped`.

```lua
local requests = Kora.timers.cooldown(1000)
if not requests.use(source) then return end
```
