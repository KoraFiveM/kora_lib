-- QB.permissions (server realm) -- one permission gateway over FiveM ACEs and,
-- when a caller opts in, QB.discord's fail-closed role cache. ACE checks are
-- always evaluated and win immediately; Discord roles can add a grant but can
-- never disable an ACE grant such as group.admin.

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

local function aceAllows(src, permission, prefix, includeCommand)
    return (prefix ~= nil and IsPlayerAceAllowed(src, prefix .. '.' .. permission))
        or IsPlayerAceAllowed(src, 'group.' .. permission)
        or (includeCommand and IsPlayerAceAllowed(src, 'command.' .. permission))
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
        assert(#roles > 0, ('Discord roles for permission %q cannot be empty.'):format(permission))
    end

    -- hasAnyRole rejects disabled bots and missing/stale member snapshots. A
    -- role lookup failure must fail closed without disturbing the ACE result.
    local hasAnyRole = QB.discord and QB.discord.hasAnyRole
    if type(hasAnyRole) ~= 'function' then return false end
    local ok, allowed = pcall(hasAnyRole, src, roles)
    return ok and allowed == true
end

---Resolve the highest privilege level a player holds.
---@param src integer
---@param levels string[] -- ordered most-privileged first; 'user' always matches
---@param prefixOrOptions string|table|nil -- prefix, or { prefix?, discordRoles? }
---@return string
function QB.permissions.getLevel(src, levels, prefixOrOptions)
    assert(type(levels) == 'table' and #levels > 0, 'Permission levels must be a non-empty array.')
    local prefix, discordRoles = resolveOptions(prefixOrOptions)

    for _, level in ipairs(levels) do
        assert(type(level) == 'string' and level ~= '', 'Each permission level must be a non-empty string.')
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
function QB.permissions.hasLevel(src, required, levels, prefixOrOptions)
    assert(type(required) == 'string' and required ~= '', 'Required permission level must be a non-empty string.')
    assert(type(levels) == 'table' and #levels > 0, 'Permission levels must be a non-empty array.')

    local held = QB.permissions.getLevel(src, levels, prefixOrOptions)
    local heldIndex, requiredIndex
    for index, level in ipairs(levels) do
        if level == held then heldIndex = index end
        if level == required then requiredIndex = index end
    end
    return heldIndex ~= nil and requiredIndex ~= nil and heldIndex <= requiredIndex
end

---@param src integer
---@param permission string
---@param prefixOrOptions string|table|nil -- prefix, or { prefix?, discordRoles? }
---@return boolean
function QB.permissions.hasPermission(src, permission, prefixOrOptions)
    assert(type(permission) == 'string' and permission ~= '', 'Permission must be a non-empty string.')
    if permission == 'user' then return true end
    local prefix, discordRoles = resolveOptions(prefixOrOptions)
    return aceAllows(src, permission, prefix, true) or discordAllows(src, permission, discordRoles)
end
