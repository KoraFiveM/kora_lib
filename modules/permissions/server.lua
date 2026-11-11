local MAX_LEVELS = 32

local function resolveOptions(prefixOrOptions)
    if prefixOrOptions == nil or type(prefixOrOptions) == 'string' then
        return prefixOrOptions, nil
    end

    assert(type(prefixOrOptions) == 'table', 'Permission options must be a prefix string, table, or nil.')
    local prefix = prefixOrOptions.prefix
    local discordRoles = prefixOrOptions.discordRoles
    assert(prefix == nil or (type(prefix) == 'string' and prefix ~= ''),
        'Permission options.prefix must be a non-empty string or nil.')
    assert(discordRoles == nil or type(discordRoles) == 'table',
        'Permission options.discordRoles must be a table or nil.')
    return prefix, discordRoles
end

local function assertPlayerSource(src)
    assert(type(src) == 'number' and src >= 1 and src % 1 == 0 and src == src
        and src ~= math.huge and src ~= -math.huge,
        'Permission source must be a positive finite player server ID.')
end

local function assertLevels(levels)
    assert(type(levels) == 'table' and #levels > 0, 'Permission levels must be a non-empty array.')
    local count = 0
    for index, level in pairs(levels) do
        assert(type(index) == 'number' and index >= 1 and index % 1 == 0
            and index == index and index < math.huge,
            'Permission levels must be a dense array.')
        assert(type(level) == 'string' and level ~= '',
            'Each permission level must be a non-empty string.')
        count = count + 1
        assert(count <= MAX_LEVELS, ('Permission levels cannot exceed %d entries.'):format(MAX_LEVELS))
    end
    assert(count == #levels, 'Permission levels must be a dense array.')
end

local function aceAllowed(src, object)
    local allowed = IsPlayerAceAllowed(src, object)
    return allowed == true or allowed == 1
end

local function aceAllows(src, permission, prefix, includeCommand)
    return (prefix ~= nil and aceAllowed(src, prefix .. '.' .. permission))
        or aceAllowed(src, 'group.' .. permission)
        or (includeCommand and aceAllowed(src, 'command.' .. permission))
        or false
end

local function discordAllows(src, permission, discordRoles)
    if not discordRoles then return false end
    local roles = discordRoles[permission]
    if roles == nil then return false end

    assert(type(roles) == 'string' or type(roles) == 'table',
        ('Discord roles for permission %q must be a role string or array.'):format(permission))
    if type(roles) == 'string' then
        assert(roles ~= '', ('Discord role for permission %q cannot be empty.'):format(permission))
    else
        local count = 0
        for index, role in pairs(roles) do
            assert(type(index) == 'number' and index >= 1 and index % 1 == 0
                and index == index and index < math.huge and type(role) == 'string' and role ~= '',
                ('Discord roles for permission %q must be a dense string array.'):format(permission))
            count = count + 1
        end
        assert(count > 0 and count == #roles,
            ('Discord roles for permission %q must be a non-empty dense string array.'):format(permission))
    end

    local hasAnyRole = Kora.discord and Kora.discord.hasAnyRole
    if type(hasAnyRole) ~= 'function' then return false end
    local ok, allowed = pcall(hasAnyRole, src, roles)
    return ok and allowed == true
end

---Resolve the highest privilege level a player holds.
---@param src integer
---@param levels string[] -- ordered most-privileged first; 'user' always matches
---@param prefixOrOptions string|table|nil -- prefix, or { prefix?, discordRoles? }
---@return string
function Kora.permissions.getLevel(src, levels, prefixOrOptions)
    assertPlayerSource(src)
    assertLevels(levels)
    local prefix, discordRoles = resolveOptions(prefixOrOptions)

    for levelIndex = 1, #levels do
        local level = levels[levelIndex]
        if level == 'user' or aceAllows(src, level, prefix, false) or discordAllows(src, level, discordRoles) then
            return level
        end
    end
    return 'user'
end

---Check a ranked permission. levels must be ordered most-privileged first, so
---a resolved admin level also satisfies a lower mod requirement.
---@param src integer
---@param required string
---@param levels string[]
---@param prefixOrOptions string|table|nil -- prefix, or { prefix?, discordRoles? }
---@return boolean
function Kora.permissions.hasLevel(src, required, levels, prefixOrOptions)
    assertPlayerSource(src)
    assert(type(required) == 'string' and required ~= '', 'Required permission level must be a non-empty string.')
    assertLevels(levels)

    local held = Kora.permissions.getLevel(src, levels, prefixOrOptions)
    local heldIndex, requiredIndex
    for index = 1, #levels do
        local level = levels[index]
        if level == held then heldIndex = index end
        if level == required then requiredIndex = index end
    end
    return heldIndex ~= nil and requiredIndex ~= nil and heldIndex <= requiredIndex
end

---@param src integer
---@param permission string
---@param prefixOrOptions string|table|nil -- prefix, or { prefix?, discordRoles? }
---@return boolean
function Kora.permissions.hasPermission(src, permission, prefixOrOptions)
    assertPlayerSource(src)
    assert(type(permission) == 'string' and permission ~= '', 'Permission must be a non-empty string.')
    if permission == 'user' then return true end
    local prefix, discordRoles = resolveOptions(prefixOrOptions)
    return aceAllows(src, permission, prefix, true) == true
        or discordAllows(src, permission, discordRoles) == true
end

---Explains how a level was resolved: each ACE object consulted, in order, with the native's raw value. Diagnostics only; nothing gates on it.
---@param src integer
---@param levels string[]
---@param prefixOrOptions string|table|nil
---@return table checks array of { level, object, raw, type, allowed }
---@return string resolved
function Kora.permissions.explain(src, levels, prefixOrOptions)
    assertPlayerSource(src)
    assertLevels(levels)
    local prefix = resolveOptions(prefixOrOptions)
    local checks = {}

    for levelIndex = 1, #levels do
        local level = levels[levelIndex]
        local objects = {}
        if prefix ~= nil then objects[#objects + 1] = prefix .. '.' .. level end
        objects[#objects + 1] = 'group.' .. level
        for objectIndex = 1, #objects do
            local object = objects[objectIndex]
            local raw = IsPlayerAceAllowed(src, object)
            checks[#checks + 1] = {
                level = level,
                object = object,
                raw = tostring(raw),
                type = type(raw),
                allowed = raw == true or raw == 1,
            }
        end
    end

    return checks, Kora.permissions.getLevel(src, levels, prefixOrOptions)
end
