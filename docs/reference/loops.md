---
title: "Loops module"
sidebar_position: 48
---

# Loops module

## Overview
The loops module centralizes controlled polling/retry logic. It's for cases where a script needs to wait on some condition to become true, with a bounded number of attempts and/or a bounded amount of time.

## API

### `Kora.loops.controlled(call, tries, timeout, backoff)`
Repeatedly invokes `call` until it returns a truthy value, or until the try count / timeout is exhausted.

#### Parameters
- `call: fun(): any` — Predicate to poll. Signals "not ready yet" by returning `false` or `nil`, and "done" by returning any truthy value.
- `tries: integer | false | nil` — Max attempts, or `false` to disable. Defaults to `10`.
- `timeout: integer | false | nil` — Max milliseconds, or `false` to disable. Defaults to `10000`.
- `backoff: boolean | integer | nil` — How long to wait between attempts:
  | Value | Wait between attempts |
  |---|---|
  | omitted / `false` | A single frame (`Wait(0)`) |
  | `true` | Exponential, 25ms → 1s |
  | a non-negative integer | That many ms, every attempt |

`call` must be callable. `tries` must be a positive finite integer when set;
`timeout` and numeric `backoff` must be finite non-negative integers. Invalid
options fail before the first predicate call, rather than during a later retry.

#### Returns
- `any | false` — The truthy value from `call`, or `false` on failure.
- `string | nil` — The reason the loop gave up, when the first value is `false`.

#### Behavior
1. `call()` is invoked; if it returns a truthy value, that value is returned immediately.
2. If a `timeout` is set and the deadline is reached, the loop returns
   `false, "Loop timed out."` after that attempt.
3. If `tries` is set and exhausted, the loop returns `false, "Loop failed due to exceeding try count."`.
4. Between attempts the loop waits per `backoff` above. Any wait is clamped to the remaining timeout, so a long interval can't overshoot the deadline.

#### Example
```lua
local ped = Kora.loops.controlled(function()
    return DoesEntityExist(PlayerPedId()) and PlayerPedId() or nil
end, 20, 5000)

if not ped then return print('player ped never became available') end
```

Polling with exponential backoff:

```lua
local loaded, err = Kora.loops.controlled(function()
    return HasModelLoaded(model)
end, false, 10000, true)

if not loaded then return print('model load failed:', err) end
```

Polling on a fixed interval — the middle ground between every-frame and exponential, for waiting on something that changes on its own schedule:

```lua
local vehicle = Kora.loops.controlled(function()
    local spawned = GetVehiclePedIsIn(PlayerPedId(), false)
    return spawned ~= 0 and spawned or nil
end, false, 5000, 250) -- check 4x a second for up to 5s
```

## Notes
- This module expects the FiveM/RedM scripting runtime functions `GetGameTimer` and `Wait` to be available.
- Disabling both `tries` and `timeout` removes the loop's only exit conditions — only do this if `call` is guaranteed to eventually return truthy.
