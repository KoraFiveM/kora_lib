---
title: "Util"
sidebar_position: 53
---


# Util

## Shared

A collection of small dependency-free helpers shared by client and server code. Functions cover safe text/number handling, JSON parsing, weighted choice, vector math, nearest plain-data entries, and sliding-window rate limits. Vector helpers return ordinary Lua tables so their results survive JSON and cross-resource calls.

Namespace: `Kora.util` · Source: `modules/util/shared.lua`

### cleanText options

Pass an options table to make text-cleaning behavior explicit. Omitted fields use the safe defaults. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `maxLength?` | integer | Maximum allowed character count. |
| `whitespace?` | string | Whitespace normalization mode supported by cleanText. |
| `controlCharacters?` | boolean | Whether to strip ASCII control characters. |
| `empty?` | boolean | Whether an empty cleaned result is accepted. |

### Plain vector results

Vector helpers accept vector2, vector3, vector4, or coordinate tables, but they return a plain &#123; x, y, z &#125; table. This keeps values safe for JSON encoding and resource exports. For vector4 input, w is heading and is ignored by spatial calculations.

### Nearest data vs. game entities

Kora.util.nearest works on plain Lua data and needs a coordsOf callback to locate each entry. Use Kora.world or Kora.closest for live game entities.

### Sliding-window limiter

Each key has an independent bucket. consume(key, now) returns true when allowed; otherwise it returns false and milliseconds until another call is allowed. The caller should use a monotonic timer such as GetGameTimer.

### Functions

Choose a helper for one bounded operation. Each function validates the values it needs and returns data without imposing a logging or fallback policy on the caller.

#### `Kora.util.deepClone(value)`

Recursively copies plain tables while preserving shared references and cycles. Metatables are not copied.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | any | Value to copy. Tables are traversed recursively. |

**Returns**

- **copy** — cloned value.

**Example**

```lua
local copy = Kora.util.deepClone(config)
copy.settings.enabled = false
```

**Representative console output**

```text
Changes to copy do not change the corresponding plain tables in config.
```

#### `Kora.util.fnv1a(value)`

Calculates a stable eight-character hexadecimal FNV-1a checksum for change detection or migration fingerprints.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | string | Text to hash. |

**Returns**

- **hash** — eight-character lowercase hexadecimal string.

**Example**

```lua
local fingerprint = Kora.util.fnv1a('config-v1')
print(fingerprint)
```

**Representative console output**

```text
Prints a stable checksum for the input string.
```

#### `Kora.util.isCallable(value)`

Checks whether a value can be called as a function, including tables with callable metatables and FiveM function-reference proxies.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | any | Value to inspect. |

**Returns**

- **callable** — boolean.

**Example**

```lua
if Kora.util.isCallable(callback) then callback() end
```

**Representative console output**

```text
Calls callback only when the value is callable.
```

#### `Kora.util.trim(value)`

Removes leading and trailing whitespace from strings. Non-string values pass through unchanged.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | any | Value to trim. |

**Returns**

- **trimmed** — string with surrounding whitespace removed, or the original non-string value.

**Example**

```lua
print(Kora.util.trim('  hello  '))
```

**Representative console output**

```text
Prints hello without surrounding spaces.
```

#### `Kora.util.cleanText(value, options?)`

Validates and normalizes external text. By default it removes ASCII controls, collapses whitespace, trims, and rejects empty or invalid UTF-8 strings.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | string | Text to validate. |
| `options?` | table | Optional maxLength, whitespace, controlCharacters, and empty rules. See the options table above. |

**Returns**

- **text** — cleaned text.
- **nil, reason** — when input is invalid or rejected.

**Example**

```lua
local clean, err = Kora.util.cleanText(userInput, { maxLength = 80 })
if not clean then return print(err) end
print(clean)
```

**Representative console output**

```text
Prints cleaned input or a reason when the text is invalid.
```

#### `Kora.util.truncateUtf8(value, maximum)`

Limits a string by Unicode characters without cutting a multi-byte character in half.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | string | UTF-8 text. |
| `maximum` | integer | Maximum number of Unicode characters. |

**Returns**

- **text** — truncated UTF-8 string.
- **nil, "invalid_utf8"** — when the input is malformed UTF-8.

**Example**

```lua
local short = Kora.util.truncateUtf8('こんにちは', 3)
print(short)
```

**Representative console output**

```text
Prints the first three complete characters.
```

#### `Kora.util.isFiniteNumber(value)`

Checks that a value is a real finite Lua number. Numeric strings, NaN, and infinities are rejected.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | any | Value to check. |

**Returns**

- **finite** — boolean.

**Example**

```lua
if Kora.util.isFiniteNumber(distance) then print('Distance is numeric') end
```

**Representative console output**

```text
Prints only when distance is a finite number.
```

#### `Kora.util.isInteger(value)`

Checks whether a value is a finite whole number.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | any | Value to check. |

**Returns**

- **integer** — boolean.

**Example**

```lua
print(Kora.util.isInteger(3.0), Kora.util.isInteger(3.5))
```

**Representative console output**

```text
Prints true then false.
```

#### `Kora.util.decodeJson(value)`

Decodes JSON without throwing on malformed external input. It leaves the error policy to the caller.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | string | JSON text to decode. |

**Returns**

- **decoded** — decoded Lua value on success.
- **nil, "invalid_json"** — when decoding fails.

**Example**

```lua
local data, err = Kora.util.decodeJson(jsonText)
if not data then print('Bad JSON:', err) end
```

**Representative console output**

```text
Prints a safe error result instead of raising on malformed JSON.
```

#### `Kora.util.clamp(value, min, max)`

Bounds a finite number to an inclusive finite range.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | number | Finite value to bound. |
| `min` | number | Finite lower bound. |
| `max` | number | Finite upper bound; must be at least min. |

**Returns**

- **number** — value no lower than min and no higher than max.

**Example**

```lua
local volume = Kora.util.clamp(requestedVolume, 0.0, 1.0)
```

**Representative console output**

```text
volume stays between 0 and 1.
```

#### `Kora.util.round(value, decimals?)`

Rounds a finite number to the requested number of decimal places.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `value` | number | Finite number to round. |
| `decimals?` | integer | Decimal places; defaults to 0 only when omitted. |

**Returns**

- **number** — rounded result, if representable.

**Example**

```lua
print(Kora.util.round(12.345, 2))
```

**Representative console output**

```text
Prints 12.35.
```

#### `Kora.util.randomFloat(min, max)`

Returns a uniformly selected finite floating-point value between the inclusive bounds.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `min` | number | Finite lower bound. |
| `max` | number | Finite upper bound; must be greater than or equal to min. |

**Returns**

- **number** — random value within the requested range.

**Example**

```lua
local offset = Kora.util.randomFloat(-1.0, 1.0)
```

**Representative console output**

```text
offset is between -1 and 1.
```

#### `Kora.util.weightedChoice(list)`

Selects one value from a weighted list. Weights are relative; they do not need to total 1 or 100.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `list` | table[] | Non-empty dense array of &#123; value, positiveWeight &#125; pairs. Weights and their total must be finite. |

**Returns**

- **value** — selected pair value.

**Example**

```lua
local item = Kora.util.weightedChoice({
    { 'bread', 60 }, { 'watch', 5 }, { 'water', 20 },
})
print(item)
```

**Representative console output**

```text
Returns one item, with bread six times as likely as a weight-10 item.
```

#### `Kora.util.tableContains(t, value)`

Searches a table’s values for an equal value.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `t` | table | Table to search. |
| `value` | any | Value to compare against each entry. |

**Returns**

- **contains** — boolean.

**Example**

```lua
if Kora.util.tableContains(allowedJobs, jobName) then print('Allowed') end
```

**Representative console output**

```text
Prints when jobName exists among the table values.
```

#### `Kora.util.lerp(a, b, t)`

Linearly interpolates between a and b. t is not clamped, so values outside 0–1 extrapolate.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `a` | number | Finite start value. |
| `b` | number | Finite end value. |
| `t` | number | Finite interpolation fraction. |

**Returns**

- **number** — interpolated or extrapolated value, when finite.

**Example**

```lua
local midpoint = Kora.util.lerp(10, 20, 0.5)
print(midpoint)
```

**Representative console output**

```text
Prints 15.
```

#### `Kora.util.vecAdd(a, b)`

Adds two vectors component by component.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `a` | vector2 \| vector3 \| vector4 \| table | First vector-like value with finite components. |
| `b` | vector2 \| vector3 \| vector4 \| table | Second vector-like value. |

**Returns**

- **table** — plain &#123; x, y, z &#125; result.

**Example**

```lua
local sum = Kora.util.vecAdd(vector3(1, 2, 3), vector3(4, 5, 6))
print(sum.x, sum.y, sum.z)
```

**Representative console output**

```text
Prints 5, 7, 9; the result is a plain table.
```

#### `Kora.util.vecSub(a, b)`

Subtracts the second vector from the first component by component.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `a` | vector2 \| vector3 \| vector4 \| table | Vector to subtract from. |
| `b` | vector2 \| vector3 \| vector4 \| table | Vector to subtract. |

**Returns**

- **table** — plain &#123; x, y, z &#125; result.

**Example**

```lua
local delta = Kora.util.vecSub(vector3(10, 8, 6), vector3(1, 2, 3))
print(delta.x, delta.y, delta.z)
```

**Representative console output**

```text
Prints 9, 6, 3.
```

#### `Kora.util.vecScale(v, scalar)`

Multiplies each spatial component by the same finite scalar.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `v` | vector2 \| vector3 \| vector4 \| table | Input vector-like value. |
| `scalar` | number | Finite multiplier. |

**Returns**

- **table** — plain &#123; x, y, z &#125; scaled result.

**Example**

```lua
local doubled = Kora.util.vecScale(vector3(1, 2, 3), 2)
```

**Representative console output**

```text
Returns a plain table containing twice the spatial values.
```

#### `Kora.util.vecLength(v)`

Calculates the vector magnitude using stable arithmetic for large finite values.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `v` | vector2 \| vector3 \| vector4 \| table | Vector-like value. |

**Returns**

- **length** — finite number.

**Example**

```lua
print(Kora.util.vecLength(vector3(3, 4, 0)))
```

**Representative console output**

```text
Prints 5.
```

#### `Kora.util.vecDistance(a, b)`

Measures distance using components available on both inputs. It is 2D when either input is vector2; otherwise it is 3D. A vector4 heading is ignored.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `a` | vector2 \| vector3 \| vector4 \| table | First position. |
| `b` | vector2 \| vector3 \| vector4 \| table | Second position. |

**Returns**

- **distance** — finite spatial distance.

**Example**

```lua
local distance = Kora.util.vecDistance(vector3(0, 0, 0), vector3(3, 4, 0))
print(distance)
```

**Representative console output**

```text
Prints 5 metres.
```

#### `Kora.util.vecDistance2d(a, b)`

Measures ground-plane distance while ignoring elevation.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `a` | vector3 \| vector4 \| table | First position. |
| `b` | vector3 \| vector4 \| table | Second position. |

**Returns**

- **distance** — finite 2D distance.

**Example**

```lua
local roadDistance = Kora.util.vecDistance2d(vector3(0, 0, 0), vector3(3, 4, 100))
```

**Representative console output**

```text
Returns 5 even though the positions differ greatly in height.
```

#### `Kora.util.vecNormalize(v)`

Returns a unit-length direction vector. A zero-length vector returns zero components instead of NaN.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `v` | vector2 \| vector3 \| vector4 \| table | Input vector-like value. |

**Returns**

- **table** — plain normalized &#123; x, y, z &#125; result.

**Example**

```lua
local direction = Kora.util.vecNormalize(vector3(0, 3, 4))
print(direction.x, direction.y, direction.z)
```

**Representative console output**

```text
Returns a direction with length 1.
```

#### `Kora.util.headingToDirection(heading)`

Converts a GTA heading in degrees into a normalized direction vector. GTA heading 0 points north and increases counter-clockwise.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `heading` | number | Finite heading in degrees. |

**Returns**

- **table** — plain &#123; x, y, z &#125; direction vector.

**Example**

```lua
local forward = Kora.util.headingToDirection(0)
print(forward)
```

**Representative console output**

```text
Returns the north-facing direction.
```

#### `Kora.util.directionToHeading(v)`

Converts a direction vector to GTA heading degrees.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `v` | vector2 \| vector3 \| vector4 \| table | Finite direction vector. |

**Returns**

- **heading** — degrees using GTA convention.

**Example**

```lua
local heading = Kora.util.directionToHeading(vector3(0, 1, 0))
print(heading)
```

**Representative console output**

```text
Prints the heading for the supplied northward direction.
```

#### `Kora.util.bearing(origin, target)`

Returns the compass bearing from one point to another. Use Kora.world.getCardinalDirection for a cardinal text label.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `origin` | vector3 \| vector4 \| table | Starting position. |
| `target` | vector3 \| vector4 \| table | Destination position. |

**Returns**

- **bearing** — finite angle in degrees.

**Example**

```lua
local bearing = Kora.util.bearing(vector3(0, 0, 0), vector3(10, 0, 0))
print(bearing)
```

**Representative console output**

```text
Prints the compass bearing from origin to target.
```

#### `Kora.util.nearest(list, position, opts)`

Finds the nearest plain-data entry using a caller-provided coordinate selector. It can also filter entries by a bucket and stop searching outside a radius.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `list` | table[] | Entries to examine; these are data values, not live game entities. |
| `position` | vector3 \| vector4 \| table | Search position. |
| `opts` | table | Required coordsOf callback; optional radius, bucketOf callback, and bucket filter. |

**Returns**

- **entry, distance** — nearest qualifying entry and its distance.
- **nil** — when no entry qualifies.

**Example**

```lua
local shop, distance = Kora.util.nearest(shops, playerCoords, {
    coordsOf = function(entry) return entry.coords end,
    radius = 100.0,
})
```

**Representative console output**

```text
Returns the closest shop entry within 100 metres, or nil if none qualify.
```

#### `Kora.util.rateLimiter(max, window)`

Creates a sliding-window limiter with a separate history for each key. Supply the current time yourself so the same limiter works in either realm.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `max` | integer | Positive maximum calls allowed in one window. |
| `window` | integer | Positive window size in milliseconds. |

**Returns**

- **limiter** — object with consume(key, now).

**Example**

```lua
local limiter = Kora.util.rateLimiter(5, 10000)
local allowed, retryAfter = limiter:consume(source, GetGameTimer())
if not allowed then print('Try again in', retryAfter, 'ms') end
```

**Representative console output**

```text
Allows the first five calls per player in ten seconds; later calls include the wait time.
```

### Limits and related APIs

Vector components and numeric arguments must be finite. Interpolation does not clamp t. nearest requires plain data; do not use it as a network-entity discovery or authorization API.

## Client

Adds screen-projection helpers to the shared Kora.util table. Coordinates must be in the rendered world; screen coordinates are normalized to the range used by FiveM drawing natives.

Namespace: `Kora.util` · Source: `modules/util/client.lua`

### Always check onScreen

When onScreen is false, the returned x and y values are not meaningful. Gate screen drawing on the boolean. worldToScreen returns normalized values; worldToScreenPixels uses resolution pixels.

### Functions

Project a world position to normalized screen coordinates or pixel coordinates.

#### `Kora.util.worldToScreen(coords)`

Projects a world position to normalized screen coordinates from 0 to 1.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `coords` | vector3 | World position to project. |

**Returns**

- **x** — normalized horizontal screen position.
- **y** — normalized vertical screen position.
- **onScreen** — whether the position is visible.

**Example**

```lua
local x, y, onScreen = Kora.util.worldToScreen(targetCoords)
if onScreen then print(x, y) end
```

**Representative console output**

```text
Prints coordinates only when the target is on screen.
```

#### `Kora.util.worldToScreenPixels(coords)`

Projects a world position using the client’s current screen resolution.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `coords` | vector3 | World position to project. |

**Returns**

- **x** — horizontal pixel coordinate.
- **y** — vertical pixel coordinate.
- **onScreen** — whether the position is visible.

**Example**

```lua
local x, y, onScreen = Kora.util.worldToScreenPixels(targetCoords)
if onScreen then DrawRect(x, y, 4, 4, 255, 255, 255, 255) end
```

**Representative console output**

```text
Draws a small marker at the projected pixel position when visible.
```

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/util/docs.md` or `local/util/docs.md`) that the reference above does not state.

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

### Vector helpers (shared)

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

### Rate limiting (shared)

- `Kora.util.rateLimiter(max, window)` returns a bounded ring-buffer
  sliding-window limiter. Call `limiter:consume(key, now)` — `now` is supplied
  by the caller (typically `GetGameTimer()`) rather than read internally, so
  the same limiter code runs identically client-side, server-side, and inside
  the plain-Lua test harness. Returns `true` when the call is allowed, or
  `false, retryAfter` (milliseconds) when `key` has hit `max` within the last
  `window`. Each `key` gets its own independent bucket.

### Screen projection (client only)

Lives in `modules/util/client.lua`; both files populate the same `Kora.util`
table.

- `Kora.util.worldToScreen(coords)` → `x, y, onScreen`. Normalised `0..1`, the
  range FiveM's own draw natives use — **not** pixels. `x`/`y` are meaningless
  when `onScreen` is false, so always gate on it.
- `Kora.util.worldToScreenPixels(coords)` → `x, y, onScreen`, using the client's
  current resolution.
