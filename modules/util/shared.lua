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
