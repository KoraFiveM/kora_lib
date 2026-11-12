---
title: "Loops"
sidebar_position: 48
---


# Loops

Provides bounded polling/retry behavior for waiting on a condition without hand-writing a while/Wait loop. The same helper is available on client and server.

Namespace: `Kora.loops` · Source: `modules/loops/shared.lua`

## How it works

Each call invokes the predicate first. A truthy value returns immediately. If it is false/nil, the loop checks its attempt/time limits and waits according to backoff before trying again. Waits are clamped to the remaining timeout budget.

## Backoff choices

Omitted/false waits one game frame. true waits exponentially from 25 ms up to 1 second. A number waits that many milliseconds after each unsuccessful attempt. A zero timeout still performs exactly one predicate attempt.

## Functions

Functions exported by this realm.

### `Kora.loops.controlled(call, tries?, timeout?, backoff?)`

Polls call until it returns a truthy value or a configured attempt/time bound is reached.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `call` | number | callable predicate; false/nil means not ready. |
| `tries?` | number | optional positive integer maximum, or false to disable; defaults to 10. |
| `timeout?` | number | optional non-negative integer milliseconds, or false to disable; defaults to 10000. |
| `backoff?` | number | optional false/nil for Wait(0), true for exponential 25 ms to 1000 ms, or non-negative integer fixed delay. |

**Returns**

- **result** — truthy value returned by call, or false on failure.
- **error** — nil on success; Loop timed out. or Loop failed due to exceeding try count. on failure.

**Example**

```lua
local loaded, err = Kora.loops.controlled(function()
    return HasModelLoaded(model) or nil
end, false, 10000, true)
if not loaded then print(err) end
```

**Representative console output**

```text
Exponential retry starts at 25 ms and caps at 1000 ms; timeout bounds every wait.
```

## Limits and related APIs

Predicate should be cheap and preferably side-effect free because it may run repeatedly. Invalid callbacks, try counts, timeout, and numeric backoff values fail before the first call. Disabling both tries and timeout removes the only exit conditions; do so only when the predicate is guaranteed to succeed. Requires GetGameTimer and Wait.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/loops/docs.md` or `local/loops/docs.md`) that the reference above does not state.

### API

#### `Kora.loops.controlled(call, tries, timeout, backoff)`
Repeatedly invokes `call` until it returns a truthy value, or until the try count / timeout is exhausted.

##### Parameters
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

##### Example
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
