---Recursively copies a plain table (nested tables included). Non-table
---values are returned as-is. Shared and circular table references are
---preserved; metatables and function values are not copied specially.
---@param value any
---@return any
function Kora.util.deepClone(value)
    local seen = {}

    local function clone(item)
        if type(item) ~= "table" then return item end
        if seen[item] then return seen[item] end

        local copy = {}
        seen[item] = copy
        for key, nested in pairs(item) do
            copy[clone(key)] = clone(nested)
        end
        return copy
    end

    return clone(value)
end

---Returns the lowercase, eight-character hexadecimal FNV-1a checksum of a
---string. This is a compact change detector, not a cryptographic hash.
---@param value string
---@return string checksum
function Kora.util.fnv1a(value)
    assert(type(value) == "string", "Kora.util.fnv1a requires a string.")

    local hash = 2166136261
    for index = 1, #value do
        hash = ((hash ~ value:byte(index)) * 16777619) & 0xFFFFFFFF
    end

    return ("%08x"):format(hash)
end

---Returns whether a value can be called directly. In addition to functions,
---this accepts tables with a callable metatable and raw FiveM funcrefs.
---@param value any
---@return boolean
Kora.util.isCallable = Kora.compat.isCallable

---Removes leading and trailing whitespace from a string. Non-string values
---are returned unchanged so normalisers can preserve their own type policy.
---@generic T
---@param value T
---@return T
function Kora.util.trim(value)
    if type(value) ~= "string" then return value end
    return value:match("^%s*(.-)%s*$")
end

---Cleans external text using one explicit, reusable policy.
---@param value any
---@param options? KoraCleanTextOptions
---@return string|nil text
---@return string|nil reason
function Kora.util.cleanText(value, options)
    if options == nil then options = {} end

    assert(type(options) == "table", "Kora.util.cleanText options must be a table.")
    assert(options.maxLength == nil or Kora.util.isInteger(options.maxLength) and options.maxLength >= 0,
        "Kora.util.cleanText maxLength must be a non-negative integer.")
    assert(options.whitespace == nil or options.whitespace == "collapse" or options.whitespace == "preserve",
        "Kora.util.cleanText whitespace must be 'collapse' or 'preserve'.")
    assert(options.controlCharacters == nil or options.controlCharacters == "remove"
        or options.controlCharacters == "preserve",
        "Kora.util.cleanText controlCharacters must be 'remove' or 'preserve'.")
    assert(options.empty == nil or options.empty == "nil" or options.empty == "allow",
        "Kora.util.cleanText empty must be 'nil' or 'allow'.")

    if type(value) ~= "string" then return nil, "invalid_type" end

    local text = value
    if (options.controlCharacters or "remove") == "remove" then
        text = text:gsub("[%z\1-\31\127]", " ")
    end
    if (options.whitespace or "collapse") == "collapse" then
        text = text:gsub("%s+", " ")
    end
    text = Kora.util.trim(text)

    local valid, length = pcall(utf8.len, text)
    if not valid or not length then return nil, "invalid_utf8" end
    if options.maxLength and length > options.maxLength then
        text = assert(Kora.util.truncateUtf8(text, options.maxLength))
    end
    if text == "" and (options.empty or "nil") == "nil" then return nil, "empty" end

    return text
end

---Truncates a valid UTF-8 string to at most `maximum` characters without
---splitting a codepoint. Invalid UTF-8 returns nil.
---@param value string
---@param maximum integer
---@return string|nil value
---@return string|nil reason
function Kora.util.truncateUtf8(value, maximum)
    assert(type(value) == "string", "Kora.util.truncateUtf8 requires a string.")
    assert(type(maximum) == "number" and maximum >= 0 and maximum % 1 == 0,
        "Kora.util.truncateUtf8 requires a non-negative integer maximum.")

    local valid, length = pcall(utf8.len, value)
    if not valid or not length then return nil, "invalid_utf8" end
    if length <= maximum then return value end

    local offset = utf8.offset(value, maximum + 1)
    return offset and value:sub(1, offset - 1) or value
end

---Returns whether `value` is a real finite number (not NaN or either infinity).
---@param value any
---@return boolean
function Kora.util.isFiniteNumber(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

---Returns whether a value is a finite integer.
---@param value any
---@return boolean
function Kora.util.isInteger(value)
    return Kora.util.isFiniteNumber(value) and value % 1 == 0
end

---Decodes JSON without throwing on malformed external data.
---@param value string
---@return any decoded
---@return string? reason
function Kora.util.decodeJson(value)
    assert(type(value) == 'string', 'Kora.util.decodeJson requires a string.')
    local ok, decoded = pcall(json.decode, value)
    if not ok then return nil, 'invalid_json' end
    return decoded
end

---@param value number
---@param min number
---@param max number
---@return number
function Kora.util.clamp(value, min, max)
    assert(Kora.util.isFiniteNumber(value) and Kora.util.isFiniteNumber(min) and Kora.util.isFiniteNumber(max) and min <= max,
        "Kora.util.clamp requires finite bounds where min is at most max.")
    if value < min then return min end
    if value > max then return max end
    return value
end

---@param value number
---@param decimals? integer Defaults to 0.
---@return number
function Kora.util.round(value, decimals)
    if decimals == nil then decimals = 0 end
    assert(Kora.util.isFiniteNumber(value) and Kora.util.isInteger(decimals),
        "Kora.util.round requires a finite value and integer decimal places.")
    local mult = 10 ^ decimals
    assert(Kora.util.isFiniteNumber(mult) and mult > 0,
        "Kora.util.round decimal places must produce finite precision.")
    local scaled = value * mult
    assert(Kora.util.isFiniteNumber(scaled), "Kora.util.round value and decimal places must stay finite.")
    return math.floor(scaled + 0.5) / mult
end

---@param min number
---@param max number
---@return number
function Kora.util.randomFloat(min, max)
    assert(Kora.util.isFiniteNumber(min) and Kora.util.isFiniteNumber(max) and min <= max,
        "Kora.util.randomFloat requires finite bounds where min is at most max.")
    local ratio = math.random()
    return min * (1 - ratio) + max * ratio
end

---Picks one entry from a weighted list. Weights don't need to sum to any
---particular total -- each is just relative to the others.
---@param list {[1]: any, [2]: number}[] Array of `{value, weight}` pairs. Every weight must be > 0.
---@return any value
function Kora.util.weightedChoice(list)
    assert(type(list) == "table", "Kora.util.weightedChoice requires a non-empty dense array.")
    local entryCount = 0
    for index, entry in pairs(list) do
        assert(Kora.util.isInteger(index) and index >= 1 and type(entry) == 'table',
            'Kora.util.weightedChoice requires a dense array of pairs.')
        entryCount = entryCount + 1
    end
    assert(entryCount > 0 and entryCount == #list,
        'Kora.util.weightedChoice requires a non-empty dense array of pairs.')

    local total = 0
    for entryIndex = 1, #list do
        local entry = list[entryIndex]
        assert(Kora.util.isFiniteNumber(entry[2]) and entry[2] > 0,
            "Every weightedChoice entry needs a positive finite weight.")
        total = total + entry[2]
    end
    assert(Kora.util.isFiniteNumber(total), "weightedChoice total must be finite.")

    local roll = math.random() * total
    local cumulative = 0

    for entryIndex = 1, #list do
        local entry = list[entryIndex]
        cumulative = cumulative + entry[2]
        if roll <= cumulative then return entry[1] end
    end

    return list[#list][1]
end

---@param t table
---@param value any
---@return boolean
function Kora.util.tableContains(t, value)
    for _, v in pairs(t) do
        if v == value then return true end
    end
    return false
end

---@param v any
---@param label? string
---@return number x, number y, number z
local function xyz(v, label)
    local z = v and (type(v) == "vector2" and 0.0 or v.z or 0.0)
    assert(v and Kora.util.isFiniteNumber(v.x) and Kora.util.isFiniteNumber(v.y) and Kora.util.isFiniteNumber(z),
        ("%s expects finite vector2/vector3/vector4 or coordinate-table values."):format(label or "Kora.util"))

    return v.x, v.y, z
end

local function magnitude(x, y, z, label)
    local scale = math.max(math.abs(x), math.abs(y), math.abs(z))
    if scale == 0 then return 0 end

    local value = scale * math.sqrt((x / scale) ^ 2 + (y / scale) ^ 2 + (z / scale) ^ 2)
    assert(Kora.util.isFiniteNumber(value), ("%s result must be finite."):format(label))
    return value
end

---@param v any
---@return boolean
local function hasZ(v)
    local kind = type(v)
    return kind == "vector3" or kind == "vector4" or (kind == "table" and v.z ~= nil)
end

---Linear interpolation. `t` is not clamped -- pass a clamped value if you need
---to stay inside the segment.
---@param a number
---@param b number
---@param t number
---@return number
function Kora.util.lerp(a, b, t)
    assert(Kora.util.isFiniteNumber(a) and Kora.util.isFiniteNumber(b) and Kora.util.isFiniteNumber(t),
        "Kora.util.lerp requires finite numbers.")
    if t >= 0 and t <= 1 then return a * (1 - t) + b * t end

    local value = a + (b - a) * t
    assert(Kora.util.isFiniteNumber(value), "Kora.util.lerp result must be finite.")
    return value
end

---@param a vector3 | {x: number, y: number, z: number}
---@param b vector3 | {x: number, y: number, z: number}
---@return {x: number, y: number, z: number}
function Kora.util.vecAdd(a, b)
    local ax, ay, az = xyz(a, "Kora.util.vecAdd")
    local bx, by, bz = xyz(b, "Kora.util.vecAdd")
    return { x = ax + bx, y = ay + by, z = az + bz }
end

---@param a vector3 | {x: number, y: number, z: number}
---@param b vector3 | {x: number, y: number, z: number}
---@return {x: number, y: number, z: number} a minus b
function Kora.util.vecSub(a, b)
    local ax, ay, az = xyz(a, "Kora.util.vecSub")
    local bx, by, bz = xyz(b, "Kora.util.vecSub")
    return { x = ax - bx, y = ay - by, z = az - bz }
end

---@param v vector3 | {x: number, y: number, z: number}
---@param scalar number
---@return {x: number, y: number, z: number}
function Kora.util.vecScale(v, scalar)
    local x, y, z = xyz(v, "Kora.util.vecScale")
    assert(Kora.util.isFiniteNumber(scalar), "Kora.util.vecScale requires a finite scalar.")
    return { x = x * scalar, y = y * scalar, z = z * scalar }
end

---@param v vector3 | {x: number, y: number, z: number}
---@return number
function Kora.util.vecLength(v)
    local x, y, z = xyz(v, "Kora.util.vecLength")
    return magnitude(x, y, z, "Kora.util.vecLength")
end

---Distance between two points using the dimensions available on both. This is
---2D if either point has no `z`, otherwise it is 3D. A vector4's `w` heading is
---never part of the distance.
---@param a vector2 | vector3 | vector4 | {x: number, y: number, z?: number, w?: number}
---@param b vector2 | vector3 | vector4 | {x: number, y: number, z?: number, w?: number}
---@return number
function Kora.util.vecDistance(a, b)
    local ax, ay, az = xyz(a, "Kora.util.vecDistance")
    local bx, by, bz = xyz(b, "Kora.util.vecDistance")
    local dx, dy = ax - bx, ay - by

    if not hasZ(a) or not hasZ(b) then
        return magnitude(dx, dy, 0, "Kora.util.vecDistance")
    end

    local dz = az - bz
    return magnitude(dx, dy, dz, "Kora.util.vecDistance")
end

---2D (ground-plane) distance, ignoring z: the right measure for "how far away is that dispatch call".
---@param a vector3 | {x: number, y: number, z: number}
---@param b vector3 | {x: number, y: number, z: number}
---@return number
function Kora.util.vecDistance2d(a, b)
    local ax, ay = xyz(a, "Kora.util.vecDistance2d")
    local bx, by = xyz(b, "Kora.util.vecDistance2d")
    local dx, dy = ax - bx, ay - by
    return magnitude(dx, dy, 0, "Kora.util.vecDistance2d")
end

---Finds the entry in a plain-data `list` (not live entities -- see
---`Kora.world`/`Kora.closest` for those) whose coordinates are nearest to
---`position`, optionally bounded by `opts.radius` and filtered to entries
---whose `opts.bucketOf` result matches `opts.bucket`.
---@param list any[]
---@param position vector3 | {x: number, y: number, z: number}
---@param opts KoraNearestOptions
---@return any entry, number? distance
function Kora.util.nearest(list, position, opts)
    assert(type(list) == "table", "Kora.util.nearest requires a list.")
    assert(type(opts) == "table" and Kora.util.isCallable(opts.coordsOf),
        "Kora.util.nearest requires opts.coordsOf.")
    assert(opts.bucketOf == nil or Kora.util.isCallable(opts.bucketOf),
        "Kora.util.nearest opts.bucketOf must be callable when provided.")

    local bestEntry, bestDistance
    for _, entry in pairs(list) do
        if opts.bucketOf == nil or opts.bucketOf(entry) == opts.bucket then
            local distance = Kora.util.vecDistance(position, opts.coordsOf(entry))
            if (opts.radius == nil or distance <= opts.radius)
                and (bestDistance == nil or distance < bestDistance) then
                bestEntry, bestDistance = entry, distance
            end
        end
    end

    return bestEntry, bestDistance
end

---Unit vector in the same direction. A zero-length vector is returned as
---`{0, 0, 0}` rather than producing NaNs.
---@param v vector3 | {x: number, y: number, z: number}
---@return {x: number, y: number, z: number}
function Kora.util.vecNormalize(v)
    local length = Kora.util.vecLength(v)
    if length == 0 then return { x = 0.0, y = 0.0, z = 0.0 } end
    return Kora.util.vecScale(v, 1 / length)
end

---GTA heading (degrees, 0 = north / +Y, increasing counter-clockwise) to a
---unit direction vector on the ground plane.
---@param heading number
---@return {x: number, y: number, z: number}
function Kora.util.headingToDirection(heading)
    assert(Kora.util.isFiniteNumber(heading), "Kora.util.headingToDirection requires a finite heading.")
    local radians = math.rad(heading)
    return { x = -math.sin(radians), y = math.cos(radians), z = 0.0 }
end

---Inverse of headingToDirection: the GTA heading pointing along `v`,
---normalised into [0, 360).
---@param v vector3 | {x: number, y: number, z: number}
---@return number heading
function Kora.util.directionToHeading(v)
    local x, y = xyz(v, "Kora.util.directionToHeading")
    local heading = math.deg(math.atan(-x, y))
    return (heading + 360) % 360
end

---Compass bearing FROM `origin` TO `target`, in the same heading convention.
---Useful for "call is 240m north-east of you" style readouts.
---@param origin vector3 | {x: number, y: number, z: number}
---@param target vector3 | {x: number, y: number, z: number}
---@return number heading
function Kora.util.bearing(origin, target)
    return Kora.util.directionToHeading(Kora.util.vecSub(target, origin))
end

---Returns a bounded ring-buffer sliding-window rate limiter. `max` and
---`window` (same unit as `now`, typically milliseconds) bound how many
---`consume` calls succeed per `key` within any `window`-sized span. `now` is
---supplied by the caller (e.g. `GetGameTimer()`) rather than read internally,
---so the limiter works identically in client, server, and the plain-Lua test
---harness.
---@param max integer
---@param window number
---@return KoraRateLimiter
function Kora.util.rateLimiter(max, window)
    assert(Kora.util.isInteger(max) and max >= 1, "Kora.util.rateLimiter requires a positive integer max.")
    assert(Kora.util.isFiniteNumber(window) and window > 0, "Kora.util.rateLimiter requires a positive finite window.")

    local buckets = {}

    local function prune(bucket, cutoff)
        while bucket.count > 0 and bucket.timestamps[bucket.head] <= cutoff do
            bucket.timestamps[bucket.head] = nil
            bucket.head = bucket.head % bucket.max + 1
            bucket.count = bucket.count - 1
        end
    end

    local limiter = {}

    function limiter:consume(key, now)
        assert(Kora.util.isFiniteNumber(now), "Kora.util.rateLimiter:consume requires a finite now.")

        local bucket = buckets[key]
        if not bucket then
            bucket = { timestamps = {}, head = 1, tail = 0, count = 0, max = max }
            buckets[key] = bucket
        end

        prune(bucket, now - window)

        if bucket.count >= max then
            return false, math.max(0, math.ceil(window - (now - bucket.timestamps[bucket.head])))
        end

        bucket.tail = bucket.tail % bucket.max + 1
        bucket.timestamps[bucket.tail] = now
        bucket.count = bucket.count + 1
        return true
    end

    return limiter
end
