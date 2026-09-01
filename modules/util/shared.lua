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
    for _, entry in ipairs(list) do
        assert(type(entry[2]) == "number" and entry[2] > 0, "Every weightedChoice entry needs a positive weight.")
        total = total + entry[2]
    end

    local roll = math.random() * total
    local cumulative = 0

    for _, entry in ipairs(list) do
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
-- These accept vector3/vector4/{x,y,z} interchangeably and always RETURN a
-- plain `{x, y, z}` table, never a CfxLua `vector3`. Two reasons: this file is
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
        ("%s expects a vector3/vector4 or {x, y, z} table."):format(label or "QB.util"))
    return v.x, v.y, v.z or 0.0
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

---3D distance between two points.
---@param a vector3 | {x: number, y: number, z: number}
---@param b vector3 | {x: number, y: number, z: number}
---@return number
function QB.util.vecDistance(a, b)
    return QB.util.vecLength(QB.util.vecSub(a, b))
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
