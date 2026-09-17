-- qblib owns the configuration editor boundary so an administrator can swap
-- qbadmin without also replacing configuration authorization or transport.

local ACE = 'qblib.config.edit'

local function validResource(resource)
    return type(resource) == 'string' and resource:match('^[%w_%-]+$') ~= nil
end

local function objectTableKey(schema, key)
    return schema.fieldKeys and schema.fieldKeys[key] or key
end

local function listChildSchema(schema, index)
    if schema.item then return schema.item end
    local items = schema.items or {}
    return items[index] or items[1]
end

local function containsSensitive(schema)
    if type(schema) ~= 'table' then return false end
    if schema.sensitive == true then return true end
    if containsSensitive(schema.inner) or containsSensitive(schema.item) then return true end
    for _, branch in pairs(schema.fields or {}) do
        if containsSensitive(branch) then return true end
    end
    for _, branch in pairs(schema.items or {}) do
        if containsSensitive(branch) then return true end
    end
    for _, branch in pairs(schema.values or {}) do
        if containsSensitive(branch) then return true end
    end
    return false
end

local function allowed(source)
    if source == 0 then return true end
    if type(IsPlayerAceAllowed) == 'function' and IsPlayerAceAllowed(source, ACE) == true then return true end
    return QB.permissions and QB.permissions.hasPermission
        and QB.permissions.hasPermission(source, 'admin') == true
end

local function sanitize(schema, value)
    if type(schema) ~= 'table' or schema.sensitive == true
        or (schema.kind ~= 'object' and containsSensitive(schema)) then return nil end
    if type(value) ~= 'table' then return value end

    if schema.kind == 'list' then
        local out = {}
        for index, child in pairs(value) do
            local sanitized = sanitize(listChildSchema(schema, index), child)
            if sanitized ~= nil then out[index] = sanitized end
        end
        return out
    end

    if schema.kind == 'map' then
        local out = {}
        for key, child in pairs(value) do
            local sanitized = sanitize(schema.item or (schema.values or {})[key], child)
            if sanitized ~= nil then out[key] = sanitized end
        end
        return out
    end

    if schema.kind == 'optional' then return sanitize(schema.inner, value) end

    if schema.kind == 'vector2' or schema.kind == 'vector3' or schema.kind == 'vector4' then
        local out = { x = value.x, y = value.y }
        if schema.kind ~= 'vector2' then out.z = value.z end
        if schema.kind == 'vector4' then out.w = value.w end
        return out
    end

    if schema.kind ~= 'object' then return value end

    local out = {}
    for key, child in pairs(schema.fields or {}) do
        local tableKey = objectTableKey(schema, key)
        local sanitized = sanitize(child, value[tableKey])
        if sanitized ~= nil then out[tableKey] = sanitized end
    end
    return out
end

local function sanitizeSchema(schema)
    if type(schema) ~= 'table' or schema.sensitive == true
        or (schema.kind ~= 'object' and containsSensitive(schema)) then return nil end
    local out = {}
    for key, value in pairs(schema) do
        if key ~= 'fields' and key ~= 'items' and key ~= 'values' and key ~= 'item'
            and key ~= 'inner' and key ~= 'innerDefault' and key ~= 'fieldKeys' then out[key] = value end
    end
    for _, key in ipairs({ 'fields', 'items', 'values' }) do
        if schema[key] then
            out[key] = {}
            for childKey, child in pairs(schema[key]) do
                local sanitized = sanitizeSchema(child)
                if sanitized then out[key][childKey] = sanitized end
            end
        end
    end
    if out.fields and schema.fieldKeys then
        out.fieldKeys = {}
        for key in pairs(out.fields) do out.fieldKeys[key] = schema.fieldKeys[key] end
    end
    if schema.item then out.item = sanitizeSchema(schema.item) end
    if schema.inner then out.inner = sanitizeSchema(schema.inner) end
    if schema.innerDefault ~= nil and out.inner then
        out.innerDefault = sanitize(schema.inner, schema.innerDefault)
    end
    return out
end

local function sanitizeEntry(entry)
    local schema = entry.schema
    entry.configured = sanitize(schema, entry.configured)
    entry.values = sanitize(schema, entry.values)
    entry.schema = sanitizeSchema(schema)
    entry.loaded = true
    return entry
end

local function validRequest(request)
    if type(request) ~= 'table' or type(request.resource) ~= 'string' or type(request.path) ~= 'table'
        or type(request.revision) ~= 'number' or not validResource(request.resource) then return false end
    if #request.path < 1 or #request.path > 32 then return false end
    for _, key in ipairs(request.path) do
        if type(key) ~= 'string' and type(key) ~= 'number' then return false end
    end
    return true
end

local function requireEditor(source)
    if not allowed(source) then return nil, 'permission denied' end
    return true
end

QB.callback.register('qblib:configCatalog', function(source)
    local ok, err = requireEditor(source)
    if not ok then return nil, err end
    local catalogOk, summaries = pcall(QB.config.catalog)
    if not catalogOk or type(summaries) ~= 'table' then return nil, 'configuration catalog is unavailable' end
    local catalog = {}
    for _, summary in ipairs(summaries) do
        summary.schema = sanitizeSchema(summary.schema)
        summary.loaded = false
        catalog[#catalog + 1] = summary
    end
    return catalog
end)

QB.callback.register('qblib:configRead', function(source, resource)
    local ok, err = requireEditor(source)
    if not ok then return nil, err end
    if not validResource(resource) then return nil, 'invalid resource' end
    local readOk, entry = pcall(QB.config.read, resource)
    if not readOk or type(entry) ~= 'table' then return nil, 'configuration is unavailable' end
    return sanitizeEntry(entry)
end)

local function isRegistered(resource)
    local ok, summaries = pcall(QB.config.catalog)
    if not ok or type(summaries) ~= 'table' then return false end
    for _, summary in ipairs(summaries) do
        if summary.resource == resource then return true end
    end
    return false
end

QB.callback.register('qblib:configRestart', function(source, resource)
    local ok, err = requireEditor(source)
    if not ok then return nil, err end
    if not validResource(resource) or not isRegistered(resource) then return nil, 'invalid resource' end
    if resource == GetCurrentResourceName() then
        return { ok = false, error = 'qblib cannot restart itself from its own configuration editor.' }
    end
    if type(GetResourceState) ~= 'function' or GetResourceState(resource) ~= 'started' then
        return { ok = false, error = 'The resource is not currently running.' }
    end
    if type(StopResource) ~= 'function' or type(StartResource) ~= 'function' then
        return { ok = false, error = 'Resource restart controls are unavailable on this server.' }
    end

    local stopped = StopResource(resource)
    if stopped == false then return { ok = false, error = 'The resource could not be stopped.' } end
    local started = StartResource(resource)
    if started == false then
        return { ok = false, error = 'The resource stopped but could not be started again. Start it from the server console.' }
    end
    return { ok = true }
end)

QB.callback.register('qblib:configCommit', function(source, request)
    local ok, err = requireEditor(source)
    if not ok then return nil, err end
    if not validRequest(request) then return nil, 'invalid configuration request' end
    local commitOk, result = pcall(QB.config.commit, request.resource,
        { path = request.path, value = request.value, revision = request.revision })
    if not commitOk then return nil, 'configuration is unavailable' end
    if type(result) ~= 'table' then return result end
    local readOk, entry = pcall(QB.config.read, request.resource)
    if readOk and type(entry) == 'table' then
        result.configured = sanitize(entry.schema, entry.configured)
        result.values = sanitize(entry.schema, entry.values)
    end
    return result
end)

QB.callback.register('qblib:configReset', function(source, request)
    local ok, err = requireEditor(source)
    if not ok then return nil, err end
    if not validRequest(request) then return nil, 'invalid configuration request' end
    local resetOk, result = pcall(QB.config.reset, request.resource,
        { path = request.path, revision = request.revision })
    if not resetOk then return nil, 'configuration is unavailable' end
    if type(result) ~= 'table' then return result end
    local readOk, entry = pcall(QB.config.read, request.resource)
    if readOk and type(entry) == 'table' then
        result.configured = sanitize(entry.schema, entry.configured)
        result.values = sanitize(entry.schema, entry.values)
    end
    return result
end)

-- qbadmin provides the server's owner-gated `/config` presentation layer. Do
-- not re-register the same command when it is running: qblib resources can
-- restart independently, and taking the name back would route the command
-- through qblib's different ACE boundary and editor callbacks.
local function registerFallbackCommand()
    if type(GetResourceState) == 'function' and GetResourceState('qbadmin') == 'started' then return end

    QB.commands.add('config', 'Open the qblib configuration editor', nil, false, function(source, args)
        local resource = type(args[1]) == 'string' and args[1] or nil
        TriggerClientEvent('qblib:client:configOpened', source, resource)
    end, {
        permission = ACE,
        checkPermission = function(source) return source == 0 or allowed(source) end,
        resource = 'qblib',
    })
end

registerFallbackCommand()

-- If qbadmin is stopped after qblib, restore the standalone fallback. The
-- deferred registration lets qbadmin finish releasing its command ownership.
if type(AddEventHandler) == 'function' then
    AddEventHandler('onResourceStop', function(resource)
        if resource ~= 'qbadmin' or type(SetTimeout) ~= 'function' then return end
        SetTimeout(0, registerFallbackCommand)
    end)
end
