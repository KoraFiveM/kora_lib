-- Optional client bridge to qbskills. qblib remains usable on servers that do
-- not run qbskills; callers simply receive no skill data or modifier there.

local RESOURCE = 'qbskills'

local function isStarted()
    return type(GetResourceState) == 'function' and GetResourceState(RESOURCE) == 'started'
end

---@return boolean
function QB.skills.isAvailable()
    return isStarted()
end

---@param skill? string
---@return table|nil
function QB.skills.get(skill)
    if not isStarted() then return nil end
    return exports[RESOURCE]:getRep(skill)
end

---@return table|nil
function QB.skills.getAll()
    if not isStarted() then return nil end
    return exports[RESOURCE]:getAllRep()
end

---@param skill string
---@param level integer
---@return boolean
function QB.skills.hasLevel(skill, level)
    if not isStarted() then return false end
    return exports[RESOURCE]:isLevel(skill, level) == true
end

---@param skill string
---@param gameType string
---@param opts? table
---@return table|nil
function QB.skills.adjustMinigame(skill, gameType, opts)
    if not isStarted() then return opts end
    local adjusted = exports[RESOURCE]:getSkillCheckOptions(skill, gameType, opts)
    return type(adjusted) == 'table' and adjusted or opts
end
