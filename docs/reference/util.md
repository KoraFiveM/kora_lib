---
title: "Utility module"
sidebar_position: 53
---

# Utility module

Small shared, dependency-free helpers:

- `Kora.util.deepClone(value)` recursively copies plain tables, including shared
  references and cycles. It intentionally does not copy metatables.
- `Kora.util.fnv1a(value)` returns a stable eight-character hexadecimal FNV-1a
  checksum for change detection and migration fingerprints.
- `Kora.util.isCallable(value)` recognizes functions and tables with callable
  metatables, including FiveM funcrefs.
- `Kora.util.trim(value)` removes leading and trailing whitespace from strings;
  non-strings pass through unchanged.
- `Kora.util.cleanText(value, options?)` validates and cleans external text. By
  default it removes ASCII control characters, collapses whitespace, trims,
  and rejects empty or invalid UTF-8 values. `maxLength`, `whitespace`,
  `controlCharacters`, and `empty` make deviations explicit. Options default
  only when omitted; an explicit non-table value is rejected.
- `Kora.util.truncateUtf8(value, maximum)` bounds text by Unicode characters
  without splitting a codepoint. Invalid UTF-8 returns `nil, "invalid_utf8"`.
- `Kora.util.isFiniteNumber(value)` accepts only real finite numbers, rejecting
  strings, NaN, and positive/negative infinity.
- `Kora.util.isInteger(value)` accepts only finite whole numbers.
- `Kora.util.decodeJson(value)` decodes JSON without throwing on malformed
  external data; failures return `nil, "invalid_json"`. It deliberately does
  not choose a fallback value or log policy for the caller.
- `Kora.util.clamp(value, min, max)` bounds a finite number between finite,
  ordered bounds.
- `Kora.util.round(value, decimals?)` rounds a finite value to integer decimal
  places when the calculation is representable. `decimals` defaults to `0`
  only when omitted; explicit values must be integers.
- `Kora.util.randomFloat(min, max)` returns a uniform float in the inclusive
  finite range, including finite bounds whose difference would overflow; `min`
  must not exceed `max`.
- `Kora.util.weightedChoice(list)` selects from `{ value, positiveWeight }`
  pairs in a non-empty dense array; each weight and their accumulated total
  must be finite. Weights are relative and need not sum to 1 or 100.
- `Kora.util.tableContains(table, value)` scans values for equality.
- `Kora.util.lerp(a, b, t)` finite-number linear interpolation; `t` is **not**
  clamped, but an extrapolation that cannot stay finite is rejected.

## Vector helpers (shared)

These accept `vector2`/`vector3`/`vector4` and coordinate tables interchangeably
and always **return a plain `{x, y, z}` table**, never a CfxLua `vector3`. Two
reasons: this file is shared and loads in the plain-Lua smoke-test harness where
`vector3` doesn't exist, and a plain table survives `json.encode` and the
exports boundary unchanged, which a `vector3` does not.
All coordinate components, scale values, and headings must be finite numbers.

Names are flat (`vecAdd`, not `vec.add`) because `build/finalise.lua` only
exports functions sitting directly on the module table — a nested sub-table
would be invisible to every other resource.

- `Kora.util.vecAdd(a, b)`, `Kora.util.vecSub(a, b)`, `Kora.util.vecScale(v, scalar)`
- `Kora.util.vecLength(v)` — uses stable arithmetic for large finite coordinates.
- `Kora.util.vecDistance(a, b)` — compares every spatial component available on
  both inputs. It is 2D when either input is a `vector2`, otherwise 3D; a
  `vector4`'s `w` heading is always ignored.
- `Kora.util.vecDistance2d(a, b)` — ground-plane, ignoring `z`. The right measure
  for "how far away is that call": a caller three storeys up isn't 30 metres of
  driving away.
- `Kora.util.vecNormalize(v)` — a zero-length vector returns `{0, 0, 0}` rather
  than producing NaNs.
- `Kora.util.headingToDirection(heading)` / `Kora.util.directionToHeading(v)` — GTA
  heading convention (degrees, `0` = north, increasing counter-clockwise).
- `Kora.util.bearing(origin, target)` — compass bearing from one point to another.
  Pair it with `Kora.world.getCardinalDirection(heading)` for an `"N"`/`"NE"`/…
  label; there is no compass-point helper here because that one already exists.
- `Kora.util.nearest(list, position, opts)` — finds the entry in a plain-data
  `list` (not live entities — see `Kora.world`/`Kora.closest` for those) whose
  `opts.coordsOf(entry)` is closest to `position`, optionally bounded by
  `opts.radius` and filtered to entries whose `opts.bucketOf(entry)` matches
  `opts.bucket`. Returns `entry, distance`, or `nil` if nothing qualifies.

## Rate limiting (shared)

- `Kora.util.rateLimiter(max, window)` returns a bounded ring-buffer
  sliding-window limiter. Call `limiter:consume(key, now)` — `now` is supplied
  by the caller (typically `GetGameTimer()`) rather than read internally, so
  the same limiter code runs identically client-side, server-side, and inside
  the plain-Lua test harness. Returns `true` when the call is allowed, or
  `false, retryAfter` (milliseconds) when `key` has hit `max` within the last
  `window`. Each `key` gets its own independent bucket.

## Screen projection (client only)

Lives in `modules/util/client.lua`; both files populate the same `Kora.util`
table.

- `Kora.util.worldToScreen(coords)` → `x, y, onScreen`. Normalised `0..1`, the
  range FiveM's own draw natives use — **not** pixels. `x`/`y` are meaningless
  when `onScreen` is false, so always gate on it.
- `Kora.util.worldToScreenPixels(coords)` → `x, y, onScreen`, using the client's
  current resolution.
