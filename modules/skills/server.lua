-- Optional server bridge to kora_skills. All writes remain server-only: this
-- module merely keeps dependent resources free of resource-state plumbing.

local RESOURCE = 'kora_skills'

local function isStarted()
    return type(GetResourceState) == 'function' and GetResourceState(RESOURCE) == 'started'
end

local function assertSource(src)
    assert(Kora.util.isInteger(src) and src > 0, 'src must be a positive integer player ID.')
end

local function assertSkill(skill)
    assert(type(skill) == 'string' and skill ~= '', 'skill must be a non-empty string.')
end

local function assertLocation(location, distance)
    if location ~= nil then
        assert(location and Kora.util.isFiniteNumber(location.x)
            and Kora.util.isFiniteNumber(location.y) and Kora.util.isFiniteNumber(location.z),
            'location must have finite x, y, and z values.')
    end
    assert(distance == nil or (Kora.util.isFiniteNumber(distance) and distance > 0),
        'distance must be a positive finite number.')
end

---@return boolean
function Kora.skills.isAvailable()
    return isStarted()
end

---@param src integer
---@param skill? string
---@return table|nil
function Kora.skills.get(src, skill)
    assertSource(src)
    if skill ~= nil then assertSkill(skill) end
    if not isStarted() then return nil end
    return exports[RESOURCE]:getRep(src, skill)
end

---@param src integer
---@return table|nil
function Kora.skills.getAll(src)
    assertSource(src)
    if not isStarted() then return nil end
    return exports[RESOURCE]:getAllRep(src)
end

---@param src integer
---@param skill string
---@param level integer
---@return boolean
function Kora.skills.hasLevel(src, skill, level)
    assertSource(src)
    assertSkill(skill)
    assert(Kora.util.isInteger(level) and level > 0, 'level must be a positive integer.')
    if not isStarted() then return false end
    return exports[RESOURCE]:isLevel(src, skill, level) == true
end

---@param src integer
---@param skill string
---@param amount number
---@param location? vector3|table
---@param distance? number
---@return boolean, string|nil
function Kora.skills.add(src, skill, amount, location, distance)
    assertSource(src)
    assertSkill(skill)
    assert(Kora.util.isInteger(amount) and amount > 0, 'amount must be a positive integer.')
    assertLocation(location, distance)
    if not isStarted() then return false, 'qbskills is not started' end
    return exports[RESOURCE]:addRep(src, skill, amount, location, distance)
end

---@param src integer
---@param skill string
---@param gameType string
---@param resolvedOptions table
---@return table, table|nil
function Kora.skills.adjustMinigame(src, skill, gameType, resolvedOptions)
    assertSource(src)
    assertSkill(skill)
    assert(type(gameType) == 'string' and gameType ~= '', 'gameType must be a non-empty string.')
    assert(type(resolvedOptions) == 'table', 'resolvedOptions must be a table.')
    if not isStarted() then return resolvedOptions, nil end

    local adjusted, skillData = exports[RESOURCE]:getSkillCheckOptions(src, skill, gameType, resolvedOptions)
    if type(adjusted) ~= 'table' then return resolvedOptions, skillData end
    return adjusted, skillData
end
