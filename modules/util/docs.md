# Utility module

Small shared, dependency-free helpers:

- `QB.util.deepClone(value)` recursively copies plain tables.
- `QB.util.fnv1a(value)` returns a stable eight-character hexadecimal FNV-1a
  checksum for change detection and migration fingerprints.
- `QB.util.isCallable(value)` recognizes functions and tables with callable
  metatables, including FiveM funcrefs.
- `QB.util.trim(value)` removes leading and trailing whitespace from strings;
  non-strings pass through unchanged.
- `QB.util.truncateUtf8(value, maximum)` bounds text by Unicode characters
  without splitting a codepoint. Invalid UTF-8 returns `nil, "invalid_utf8"`.
- `QB.util.isFiniteNumber(value)` accepts only real finite numbers, rejecting
  strings, NaN, and positive/negative infinity.
- `QB.util.clamp(value, min, max)` bounds a number.
- `QB.util.round(value, decimals?)` rounds to decimal places.
- `QB.util.randomFloat(min, max)` returns a uniform float in the range.
- `QB.util.weightedChoice(list)` selects from `{ value, positiveWeight }`
  pairs; weights are relative and need not sum to 1 or 100.
- `QB.util.tableContains(table, value)` scans values for equality.
- `QB.util.lerp(a, b, t)` linear interpolation; `t` is **not** clamped.

## Vector helpers (shared)

These accept `vector2`/`vector3`/`vector4` and coordinate tables interchangeably
and always **return a plain `{x, y, z}` table**, never a CfxLua `vector3`. Two
reasons: this file is shared and loads in the plain-Lua smoke-test harness where
`vector3` doesn't exist, and a plain table survives `json.encode` and the
exports boundary unchanged, which a `vector3` does not.

Names are flat (`vecAdd`, not `vec.add`) because `build/finalise.lua` only
exports functions sitting directly on the module table — a nested sub-table
would be invisible to every other resource.

- `QB.util.vecAdd(a, b)`, `QB.util.vecSub(a, b)`, `QB.util.vecScale(v, scalar)`
- `QB.util.vecLength(v)`
- `QB.util.vecDistance(a, b)` — compares every spatial component available on
  both inputs. It is 2D when either input is a `vector2`, otherwise 3D; a
  `vector4`'s `w` heading is always ignored.
- `QB.util.vecDistance2d(a, b)` — ground-plane, ignoring `z`. The right measure
  for "how far away is that call": a caller three storeys up isn't 30 metres of
  driving away.
- `QB.util.vecNormalize(v)` — a zero-length vector returns `{0, 0, 0}` rather
  than producing NaNs.
- `QB.util.headingToDirection(heading)` / `QB.util.directionToHeading(v)` — GTA
  heading convention (degrees, `0` = north, increasing counter-clockwise).
- `QB.util.bearing(origin, target)` — compass bearing from one point to another.
  Pair it with `QB.world.getCardinalDirection(heading)` for an `"N"`/`"NE"`/…
  label; there is no compass-point helper here because that one already exists.

## Screen projection (client only)

Lives in `modules/util/client.lua`; both files populate the same `QB.util`
table.

- `QB.util.worldToScreen(coords)` → `x, y, onScreen`. Normalised `0..1`, the
  range FiveM's own draw natives use — **not** pixels. `x`/`y` are meaningless
  when `onScreen` is false, so always gate on it.
- `QB.util.worldToScreenPixels(coords)` → `x, y, onScreen`, using the client's
  current resolution.
