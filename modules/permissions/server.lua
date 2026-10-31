-- Kora.permissions (server realm) -- one permission gateway over FiveM ACEs and,
-- when a caller opts in, Kora.discord's fail-closed role cache. ACE checks are
-- always evaluated and win immediately; Discord roles can add a grant but can
-- never disable an ACE grant such as group.admin.

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

    -- hasAnyRole rejects disabled bots and missing/stale member snapshots. A
    -- role lookup failure must fail closed without disturbing the ACE result.
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
