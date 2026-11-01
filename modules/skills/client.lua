-- Optional client bridge to kora_skills; without it callers get no skill data or modifier.

local RESOURCE = 'kora_skills'

local function isStarted()
    return type(GetResourceState) == 'function' and GetResourceState(RESOURCE) == 'started'
end

local function assertSkill(skill)
    assert(type(skill) == 'string' and skill ~= '', 'skill must be a non-empty string.')
end

---@return boolean
function Kora.skills.isAvailable()
    return isStarted()
end

---@param skill? string
---@return table|nil
function Kora.skills.get(skill)
    if skill ~= nil then assertSkill(skill) end
    if not isStarted() then return nil end
    return exports[RESOURCE]:getRep(skill)
end

---@return table|nil
function Kora.skills.getAll()
    if not isStarted() then return nil end
    return exports[RESOURCE]:getAllRep()
end

---@param skill string
---@param level integer
---@return boolean
function Kora.skills.hasLevel(skill, level)
    assertSkill(skill)
    assert(Kora.util.isInteger(level) and level > 0, 'level must be a positive integer.')
    if not isStarted() then return false end
    return exports[RESOURCE]:isLevel(skill, level) == true
end

---@param skill string
---@param gameType string
---@param opts? table
---@return table|nil
function Kora.skills.adjustMinigame(skill, gameType, opts)
    assertSkill(skill)
    assert(type(gameType) == 'string' and gameType ~= '', 'gameType must be a non-empty string.')
    assert(opts == nil or type(opts) == 'table', 'opts must be a table.')
    if not isStarted() then return opts end
    local adjusted = exports[RESOURCE]:getSkillCheckOptions(skill, gameType, opts)
    return type(adjusted) == 'table' and adjusted or opts
end
