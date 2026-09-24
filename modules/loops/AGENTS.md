# loops module guide

## Purpose
This module provides a generic polling/retry loop for waiting on a condition to become true, without hand-rolling a `while`/`Wait` loop at every call site.

## Public API
- `QB.loops.controlled(call, tries, timeout, backoff)`
  - Repeatedly invokes `call` until it returns a truthy value, or the try count / timeout is exhausted.
  - Returns the truthy value from `call`, or `false, error` on failure.

## Implementation notes
- `tries` defaults to 10, `timeout` defaults to 10000ms; either can be disabled by passing `false`.
- `backoff` is deliberately overloaded on type rather than split into separate parameters: `false`/omitted waits a single frame (`Wait(0)`), `true` backs off 25ms -> 1s (`min(1000, 2^(attempt-1) * 25)`), and a number waits that many ms flat. The boolean cases predate the numeric one and keep working unchanged, so this stayed backwards-compatible with every existing call site.
- Every wait (exponential or fixed) is clamped to the remaining timeout budget — without that, a long fixed interval could sleep well past the deadline before the check at the top of the next iteration ran.
- The timeout comparison is inclusive after an unsuccessful predicate call, so a zero timeout makes exactly one attempt and no extra frame poll occurs at the deadline.
- `math.pow` was removed in Lua 5.3, so backoff uses the `^` operator, which is version-agnostic.
- `min()` runs before `floor()` so an overflowed `2^n` (`inf`) clamps to `1000` rather than blowing up on the float-to-integer conversion.

## Best practices
- Keep `call` cheap and side-effect-free where possible — it may run many times.
- Prefer a `backoff` of `true` (exponential) for polling native/game state (e.g. asset loading) to avoid busy-waiting every frame, or a fixed numeric interval when the thing you're waiting on changes on its own cadence.
- Always check the second return value when the first is `false` to distinguish a timeout from a try-count exhaustion.
- Don't disable both `tries` and `timeout` unless `call` is guaranteed to eventually return truthy — doing so removes the only loop exit conditions.
