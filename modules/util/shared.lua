---Recursively copies a plain table (nested tables included). Non-table
---values are returned as-is. Does not special-case metatables, function
---values, or cyclic references -- callers with data shaped like that need
---their own copy logic.
---@param value any
---@return any
function QB.util.deepClone(value)
    if type(value) ~= "table" then return value end

    local copy = {}
    for k, v in pairs(value) do
        copy[QB.util.deepClone(k)] = QB.util.deepClone(v)
    end

    return copy
end

---Returns the lowercase, eight-character hexadecimal FNV-1a checksum of a
---string. This is a compact change detector, not a cryptographic hash.
---@param value string
---@return string checksum
function QB.util.fnv1a(value)
    assert(type(value) == "string", "QB.util.fnv1a requires a string.")

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
QB.util.isCallable = QB.compat.isCallable

---Removes leading and trailing whitespace from a string. Non-string values
---are returned unchanged so normalisers can preserve their own type policy.
---@generic T
---@param value T
---@return T
function QB.util.trim(value)
    if type(value) ~= "string" then return value end
    return value:match("^%s*(.-)%s*$")
end

---Truncates a valid UTF-8 string to at most `maximum` characters without
---splitting a codepoint. Invalid UTF-8 returns nil.
---@param value string
---@param maximum integer
---@return string|nil value
---@return string|nil reason
function QB.util.truncateUtf8(value, maximum)
    assert(type(value) == "string", "QB.util.truncateUtf8 requires a string.")
    assert(type(maximum) == "number" and maximum >= 0 and maximum % 1 == 0,
        "QB.util.truncateUtf8 requires a non-negative integer maximum.")

    local valid, length = pcall(utf8.len, value)
    if not valid or not length then return nil, "invalid_utf8" end
    if length <= maximum then return value end

    local offset = utf8.offset(value, maximum + 1)
    return offset and value:sub(1, offset - 1) or value
end

---Returns whether `value` is a real finite number (not NaN or either infinity).
---@param value any
---@return boolean
function QB.util.isFiniteNumber(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

---Returns whether a value is a finite integer.
---@param value any
---@return boolean
function QB.util.isInteger(value)
    return QB.util.isFiniteNumber(value) and value % 1 == 0
end

---Decodes JSON without throwing on malformed external data.
---@param value string
---@return any decoded
---@return string? reason
function QB.util.decodeJson(value)
    assert(type(value) == 'string', 'QB.util.decodeJson requires a string.')
    local ok, decoded = pcall(json.decode, value)
    if not ok then return nil, 'invalid_json' end
    return decoded
end

---@param value number
---@param min number
---@param max number
---@return number
function QB.util.clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

---@param value number
---@param decimals? integer Defaults to 0.
---@return number
function QB.util.round(value, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor(value * mult + 0.5) / mult
end

---@param min number
---@param max number
---@return number
function QB.util.randomFloat(min, max)
    return min + math.random() * (max - min)
end

---Picks one entry from a weighted list. Weights don't need to sum to any
---particular total -- each is just relative to the others.
---@param list {[1]: any, [2]: number}[] Array of `{value, weight}` pairs. Every weight must be > 0.
---@return any value
function QB.util.weightedChoice(list)
    assert(type(list) == "table" and #list > 0, "QB.util.weightedChoice requires a non-empty list.")

    local total = 0
    for entryIndex = 1, #list do
        local entry = list[entryIndex]
        assert(type(entry[2]) == "number" and entry[2] > 0, "Every weightedChoice entry needs a positive weight.")
        total = total + entry[2]
    end

    local roll = math.random() * total
    local cumulative = 0

    for entryIndex = 1, #list do
        local entry = list[entryIndex]
        cumulative = cumulative + entry[2]
        if roll <= cumulative then return entry[1] end
    end

    return list[#list][1] -- floating-point fallback, should only trigger on a roll == total edge case
end

---@param t table
---@param value any
---@return boolean
function QB.util.tableContains(t, value)
    for _, v in pairs(t) do
        if v == value then return true end
    end
    return false
end

-- --- vector helpers -------------------------------------------------------
--
-- These accept vector2/vector3/vector4 and coordinate tables interchangeably
-- and always RETURN a plain `{x, y, z}` table, never a CfxLua `vector3`. Two reasons: this file is
-- shared and loads in the plain-Lua smoke-test harness where `vector3` doesn't
-- exist, and a plain table survives json.encode and the exports boundary
-- unchanged, which a vector3 does not. Callers that want a real vector3 can
-- wrap the result themselves.
--
-- Deliberately flat names (`vecAdd`, not `vec.add`): build/finalise.lua only
-- exports functions sitting directly on the module table, so a nested `vec`
-- sub-table would be invisible to every other resource.

---@param v any
---@param label? string
---@return number x, number y, number z
local function xyz(v, label)
    assert(v and type(v.x) == "number" and type(v.y) == "number",
        ("%s expects a vector2/vector3/vector4 or coordinate table."):format(label or "QB.util"))

    local z = type(v) == "vector2" and 0.0 or v.z or 0.0
    return v.x, v.y, z
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
function QB.util.lerp(a, b, t)
    return a + (b - a) * t
end

---@param a vector3 | {x: number, y: number, z: number}
---@param b vector3 | {x: number, y: number, z: number}
---@return {x: number, y: number, z: number}
function QB.util.vecAdd(a, b)
    local ax, ay, az = xyz(a, "QB.util.vecAdd")
    local bx, by, bz = xyz(b, "QB.util.vecAdd")
    return { x = ax + bx, y = ay + by, z = az + bz }
end

---@param a vector3 | {x: number, y: number, z: number}
---@param b vector3 | {x: number, y: number, z: number}
---@return {x: number, y: number, z: number} a minus b
function QB.util.vecSub(a, b)
    local ax, ay, az = xyz(a, "QB.util.vecSub")
    local bx, by, bz = xyz(b, "QB.util.vecSub")
    return { x = ax - bx, y = ay - by, z = az - bz }
end

---@param v vector3 | {x: number, y: number, z: number}
---@param scalar number
---@return {x: number, y: number, z: number}
function QB.util.vecScale(v, scalar)
    local x, y, z = xyz(v, "QB.util.vecScale")
    assert(type(scalar) == "number", "QB.util.vecScale requires a numeric scalar.")
    return { x = x * scalar, y = y * scalar, z = z * scalar }
end

---@param v vector3 | {x: number, y: number, z: number}
---@return number
function QB.util.vecLength(v)
    local x, y, z = xyz(v, "QB.util.vecLength")
    return math.sqrt(x * x + y * y + z * z)
end

---Distance between two points using the dimensions available on both. This is
---2D if either point has no `z`, otherwise it is 3D. A vector4's `w` heading is
---never part of the distance.
---@param a vector2 | vector3 | vector4 | {x: number, y: number, z?: number, w?: number}
---@param b vector2 | vector3 | vector4 | {x: number, y: number, z?: number, w?: number}
---@return number
function QB.util.vecDistance(a, b)
    local ax, ay, az = xyz(a, "QB.util.vecDistance")
    local bx, by, bz = xyz(b, "QB.util.vecDistance")
    local dx, dy = ax - bx, ay - by

    if not hasZ(a) or not hasZ(b) then
        return math.sqrt(dx * dx + dy * dy)
    end

    local dz = az - bz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---2D (ground-plane) distance, ignoring z. This is the right measure for
---"how far away is that dispatch call" -- a caller three storeys up in a
---tower is not 30 metres of driving away.
---@param a vector3 | {x: number, y: number, z: number}
---@param b vector3 | {x: number, y: number, z: number}
---@return number
function QB.util.vecDistance2d(a, b)
    local ax, ay = xyz(a, "QB.util.vecDistance2d")
    local bx, by = xyz(b, "QB.util.vecDistance2d")
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

---Unit vector in the same direction. A zero-length vector is returned as
---`{0, 0, 0}` rather than producing NaNs.
---@param v vector3 | {x: number, y: number, z: number}
---@return {x: number, y: number, z: number}
function QB.util.vecNormalize(v)
    local length = QB.util.vecLength(v)
    if length == 0 then return { x = 0.0, y = 0.0, z = 0.0 } end
    return QB.util.vecScale(v, 1 / length)
end

---GTA heading (degrees, 0 = north / +Y, increasing counter-clockwise) to a
---unit direction vector on the ground plane.
---@param heading number
---@return {x: number, y: number, z: number}
function QB.util.headingToDirection(heading)
    assert(type(heading) == "number", "QB.util.headingToDirection requires a numeric heading.")
    local radians = math.rad(heading)
    return { x = -math.sin(radians), y = math.cos(radians), z = 0.0 }
end

---Inverse of headingToDirection: the GTA heading pointing along `v`,
---normalised into [0, 360).
---@param v vector3 | {x: number, y: number, z: number}
---@return number heading
function QB.util.directionToHeading(v)
    local x, y = xyz(v, "QB.util.directionToHeading")
    local heading = math.deg(math.atan(-x, y))
    return (heading + 360) % 360
end

---Compass bearing FROM `origin` TO `target`, in the same heading convention.
---Useful for "call is 240m north-east of you" style readouts.
---@param origin vector3 | {x: number, y: number, z: number}
---@param target vector3 | {x: number, y: number, z: number}
---@return number heading
function QB.util.bearing(origin, target)
    return QB.util.directionToHeading(QB.util.vecSub(target, origin))
end

-- There is deliberately no compass-point helper here: QB.world.getCardinalDirection
-- already turns a heading (or an entity, or the cached player ped) into
-- "N"/"NE"/"E"/... with exactly these semantics. Pair it with QB.util.bearing
-- when you need the direction TO something rather than the direction something
-- is facing.
