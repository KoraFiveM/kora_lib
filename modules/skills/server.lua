-- Optional server bridge to qbskills. All writes remain server-only: this
-- module merely keeps dependent resources free of resource-state plumbing.

local RESOURCE = 'qbskills'

local function isStarted()
    return type(GetResourceState) == 'function' and GetResourceState(RESOURCE) == 'started'
end

---@return boolean
function QB.skills.isAvailable()
    return isStarted()
end

---@param src integer
---@param skill? string
---@return table|nil
function QB.skills.get(src, skill)
    if not isStarted() then return nil end
    return exports[RESOURCE]:getRep(src, skill)
end

---@param src integer
---@return table|nil
function QB.skills.getAll(src)
    if not isStarted() then return nil end
    return exports[RESOURCE]:getAllRep(src)
end

---@param src integer
---@param skill string
---@param level integer
---@return boolean
function QB.skills.hasLevel(src, skill, level)
    if not isStarted() then return false end
    return exports[RESOURCE]:isLevel(src, skill, level) == true
end

---@param src integer
---@param skill string
---@param amount number
---@param location? vector3|table
---@param distance? number
---@return boolean, string|nil
function QB.skills.add(src, skill, amount, location, distance)
    if not isStarted() then return false, 'qbskills is not started' end
    return exports[RESOURCE]:addRep(src, skill, amount, location, distance)
end

---@param src integer
---@param skill string
---@param gameType string
---@param resolvedOptions table
---@return table, table|nil
function QB.skills.adjustMinigame(src, skill, gameType, resolvedOptions)
    assert(type(resolvedOptions) == 'table', 'resolvedOptions must be a table.')
    if not isStarted() then return resolvedOptions, nil end

    local adjusted, skillData = exports[RESOURCE]:getSkillCheckOptions(src, skill, gameType, resolvedOptions)
    if type(adjusted) ~= 'table' then return resolvedOptions, skillData end
    return adjusted, skillData
end
