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

-- Normalizes whatever IsPlayerAceAllowed hands back into a real boolean.
--
-- The native is declared BOOL and the Lua runtime does return true/false, so
-- this is belt-and-braces rather than a fix for an observed miscount. It is
-- worth having anyway for two reasons. First, `aceAllows` and `hasPermission`
-- below used to return the native's value straight through, and hasPermission
-- is a cross-resource export -- any consumer writing `== true` against a
-- non-boolean would silently deny. Second, note that a hypothetical numeric
-- return could NOT cause a denial in the first place: 0 is truthy in Lua, so a
-- 1/0 native would make getLevel return the FIRST level it tests ('god') for
-- everybody. Over-permission, not under. Anyone debugging a "no permissions"
-- report should look at identifiers and principals, not here.
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

    for levelIndex = 1, #levels do
        local level = levels[levelIndex]
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
function QB.permissions.hasPermission(src, permission, prefixOrOptions)
    assert(type(permission) == 'string' and permission ~= '', 'Permission must be a non-empty string.')
    if permission == 'user' then return true end
    local prefix, discordRoles = resolveOptions(prefixOrOptions)
    -- Explicitly a boolean: this is an export, and a caller comparing the
    -- result with `== true` must not be defeated by a truthy non-boolean.
    return aceAllows(src, permission, prefix, true) == true
        or discordAllows(src, permission, discordRoles) == true
end

---Explains how a permission level was resolved for one player: every ACE
---object consulted, in order, with the raw value the native returned for it.
---Diagnostics only -- nothing gates on this. It exists so a "my ACEs are right
---but I have no permissions" report can be answered with evidence instead of
---inference.
---@param src integer
---@param levels string[]
---@param prefixOrOptions string|table|nil
---@return table checks array of { level, object, raw, type, allowed }
---@return string resolved
function QB.permissions.explain(src, levels, prefixOrOptions)
    assert(type(levels) == 'table' and #levels > 0, 'Permission levels must be a non-empty array.')
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

    return checks, QB.permissions.getLevel(src, levels, prefixOrOptions)
end
