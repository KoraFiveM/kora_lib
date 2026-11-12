---
title: "Timers module"
sidebar_position: 52
---

# Timers module

## Overview
Owner-tracked repeating and deferred callbacks, plus the two rate shapers most
consumers otherwise hand-roll. Everything here is tracked against
`GetInvokingResource()` and cancelled automatically when that resource stops.

`modules/loops` is the sibling to reach for when you want to *poll until a
condition becomes true and then stop* — `Kora.loops.controlled` has no answer for
"run this every N ms until I say stop", which is what a heartbeat, a decay tick,
or a periodic refresh needs.

Shared realm: the same API exists on client and server.

## API

### `Kora.timers.setInterval(fn, interval)`
Runs `fn` every `interval` ms until cancelled or the owning resource stops. The
first run happens one full interval from now, not immediately.

#### Parameters
- `fn: fun()` — any callable, including one that crossed an exports boundary.
- `interval: finite integer` — milliseconds, `>= 0`.

#### Returns
- `integer` — the timer id, for `clearInterval`.

#### Example
```lua
local heartbeat = Kora.timers.setInterval(function()
    broadcastUnitPositions()
end, 3000)

-- later
Kora.timers.clearInterval(heartbeat)
```

### `Kora.timers.setTimeout(fn, delay)`
Runs `fn` once after a finite, non-negative integer `delay` in ms. Unlike bare `SetTimeout` this is cancellable
and dies with its owning resource.

#### Parameters
- `fn: fun()` — any callable, including one that crossed an exports boundary.
- `delay: finite integer` — milliseconds, `>= 0`.

#### Returns
- `integer` — the timer id, for `clearTimeout`.

### `Kora.timers.clearInterval(id)` / `Kora.timers.clearTimeout(id)`
Cancels a timer. Both names operate on the same id space; `clearTimeout` exists
purely so the call site reads correctly. Only the resource that created a timer
can cancel it through its id; internal debounce cleanup retains its captured
owner across the asynchronous gap.

#### Parameters
- `id: integer` — a live timer ID returned by either scheduler.

#### Returns
- `boolean` — `false` for an id that was never live, already cancelled, or
  already fired.

### `Kora.timers.debounce(fn, wait)`
Wraps `fn` so it only runs once calls have stopped arriving for `wait` ms. Each
call restarts the clock; the **last** call's arguments are the ones used.
Trailing-edge only.

#### Returns
- `table` — a **callable table**, not a bare function (Lua functions can't carry
  fields). Call it like a function. It also exposes:
  - `.run(...)` — schedules a run; the form to use from another resource. See
    [Calling the handle from another resource](#calling-the-handle-from-another-resource).
  - `.cancel()` → `boolean` — drops a pending run without firing it.
  - `.isPending()` → `boolean`

#### Example
```lua
local save = Kora.timers.debounce(function(slot) persist(slot) end, 500)

save.run(3) save.run(3) save.run(3)  -- one persist(3), 500ms after the last call
```

### `Kora.timers.throttle(fn, interval)`
Wraps `fn` so it runs at most once per `interval` ms. **Leading-edge**: the
first call passes through immediately and calls inside the cooldown are
*dropped*, not queued for a trailing run.

That choice matters for alerts: a queued trailing call would fire a dispatch
about a moment that has already passed, at coordinates the suspect has left.

#### Returns
- `table` — a callable table returning `boolean` (whether the call actually
  ran). It also exposes:
  - `.run(...)` → `boolean` — runs if the cooldown elapsed; the form to use from
    another resource. See
    [Calling the handle from another resource](#calling-the-handle-from-another-resource).
  - `.reset()` — clears the cooldown so the next call passes through.
  - `.remaining()` → `integer` — ms until the next call would be allowed; `0`
    when ready.

#### Example
```lua
local alertShotsFired = Kora.timers.throttle(function(coords)
    TriggerServerEvent('kora_police:server:shotsFired', coords)
end, 15000)

-- in a per-frame detector loop; only one alert every 15s gets through
if IsPedShooting(ped) then alertShotsFired.run(GetEntityCoords(ped)) end
```

### Calling the handle from another resource

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

### `Kora.timers.cooldown(interval)`

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

### `Kora.timers.count()`
Live timer count, for diagnostics and tests. Debounce/throttle wrappers are not
timers themselves; a debouncer with a pending run contributes one.

## Notes
- An interval of `0` runs once per game frame. Use it only for engine work that
  must be reasserted every frame (for example, a transient control disable);
  ordinary polling should use the slowest interval that still feels responsive.
- All timer delays are integer milliseconds. Fractional values are rejected
  rather than rounded down into a potentially accidental per-frame timer.
- **The ownership registry is created lazily, not at load time.** `fxmanifest.lua`
  loads every `modules/**/shared.lua` *before* any `local/resources/{client,server}.lua`,
  so `Kora.resources.registry`/`serverRegistry` do not exist yet while this chunk
  runs. It is resolved on the first timer creation instead.
- **An erroring interval keeps running.** `fn` is `pcall`'d and a failure is
  printed. A heartbeat that dies permanently because one tick hit a transient
  `nil` is a worse failure than a noisy console — the same containment
  `Kora.keybind` and `Kora.state` apply to their handlers.
- **Cancellation is observed on the next wake.** FiveM has no native to kill a
  coroutine, so cancelling sets a flag the parked loop checks immediately after
  its `Wait`. `clearInterval` therefore never fires one extra tick.
- **`debounce` attributes its pending run to the resource that created it**, not
  to kora_lib. `GetInvokingResource()` inside a deferred closure is always `nil`
  (there is no in-progress `exports()` call at that point), so the owner is
  captured at registration time and carried down.
