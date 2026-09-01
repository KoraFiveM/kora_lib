# Timers module

## Overview
Owner-tracked repeating and deferred callbacks, plus the two rate shapers most
consumers otherwise hand-roll. Everything here is tracked against
`GetInvokingResource()` and cancelled automatically when that resource stops.

`modules/loops` is the sibling to reach for when you want to *poll until a
condition becomes true and then stop* — `QB.loops.controlled` has no answer for
"run this every N ms until I say stop", which is what a heartbeat, a decay tick,
or a periodic refresh needs.

Shared realm: the same API exists on client and server.

## API

### `QB.timers.setInterval(fn, interval)`
Runs `fn` every `interval` ms until cancelled or the owning resource stops. The
first run happens one full interval from now, not immediately.

#### Parameters
- `fn: fun()` — any callable, including one that crossed an exports boundary.
- `interval: number` — milliseconds, `>= 0`.

#### Returns
- `integer` — the timer id, for `clearInterval`.

#### Example
```lua
local heartbeat = QB.timers.setInterval(function()
    broadcastUnitPositions()
end, 3000)

-- later
QB.timers.clearInterval(heartbeat)
```

### `QB.timers.setTimeout(fn, delay)`
Runs `fn` once after `delay` ms. Unlike bare `SetTimeout` this is cancellable
and dies with its owning resource.

#### Returns
- `integer` — the timer id, for `clearTimeout`.

### `QB.timers.clearInterval(id)` / `QB.timers.clearTimeout(id)`
Cancels a timer. Both names operate on the same id space; `clearTimeout` exists
purely so the call site reads correctly.

#### Returns
- `boolean` — `false` for an id that was never live, already cancelled, or
  already fired.

### `QB.timers.debounce(fn, wait)`
Wraps `fn` so it only runs once calls have stopped arriving for `wait` ms. Each
call restarts the clock; the **last** call's arguments are the ones used.
Trailing-edge only.

#### Returns
- `table` — a **callable table**, not a bare function (Lua functions can't carry
  fields). Call it like a function. It also exposes:
  - `.cancel()` → `boolean` — drops a pending run without firing it.
  - `.isPending()` → `boolean`

#### Example
```lua
local save = QB.timers.debounce(function(slot) persist(slot) end, 500)

save(3) save(3) save(3)  -- one persist(3), 500ms after the last call
```

### `QB.timers.throttle(fn, interval)`
Wraps `fn` so it runs at most once per `interval` ms. **Leading-edge**: the
first call passes through immediately and calls inside the cooldown are
*dropped*, not queued for a trailing run.

That choice matters for alerts: a queued trailing call would fire a dispatch
about a moment that has already passed, at coordinates the suspect has left.

#### Returns
- `table` — a callable table returning `boolean` (whether the call actually
  ran). It also exposes:
  - `.reset()` — clears the cooldown so the next call passes through.
  - `.remaining()` → `integer` — ms until the next call would be allowed; `0`
    when ready.

#### Example
```lua
local alertShotsFired = QB.timers.throttle(function(coords)
    TriggerServerEvent('qbpolice:server:shotsFired', coords)
end, 15000)

-- in a per-frame detector loop; only one alert every 15s gets through
if IsPedShooting(ped) then alertShotsFired(GetEntityCoords(ped)) end
```

### `QB.timers.count()`
Live timer count, for diagnostics and tests. Debounce/throttle wrappers are not
timers themselves; a debouncer with a pending run contributes one.

## Notes
- **The ownership registry is created lazily, not at load time.** `fxmanifest.lua`
  loads every `modules/**/shared.lua` *before* any `local/resources/{client,server}.lua`,
  so `QB.resources.registry`/`serverRegistry` do not exist yet while this chunk
  runs. It is resolved on the first timer creation instead.
- **An erroring interval keeps running.** `fn` is `pcall`'d and a failure is
  printed. A heartbeat that dies permanently because one tick hit a transient
  `nil` is a worse failure than a noisy console — the same containment
  `QB.keybind` and `QB.state` apply to their handlers.
- **Cancellation is observed on the next wake.** FiveM has no native to kill a
  coroutine, so cancelling sets a flag the parked loop checks immediately after
  its `Wait`. `clearInterval` therefore never fires one extra tick.
- **`debounce` attributes its pending run to the resource that created it**, not
  to qblib. `GetInvokingResource()` inside a deferred closure is always `nil`
  (there is no in-progress `exports()` call at that point), so the owner is
  captured at registration time and carried down.
