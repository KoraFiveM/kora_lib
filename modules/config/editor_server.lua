-- qblib owns the configuration editor boundary so an administrator can swap
-- qbadmin without also replacing configuration authorization or transport.

local ACE = 'qblib.config.edit'

local function allowed(source)
    return type(IsPlayerAceAllowed) == 'function' and IsPlayerAceAllowed(source, ACE) == true
end

local function sanitize(schema, value)
    if type(schema) ~= 'table' or schema.sensitive == true then return nil end
    if type(value) ~= 'table' then return value end

    if schema.kind == 'list' then
        local out = {}
        for index, child in pairs(value) do
            local sanitized = sanitize(schema.item or (schema.items or {})[index], child)
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
    if schema.kind ~= 'object' then return value end

    local out = {}
    for key, child in pairs(schema.fields or {}) do
        local sanitized = sanitize(child, value[key])
        if sanitized ~= nil then out[key] = sanitized end
    end
    return out
end

local function sanitizeSchema(schema)
    if type(schema) ~= 'table' or schema.sensitive == true then return nil end
    local out = {}
    for key, value in pairs(schema) do
        if key ~= 'fields' and key ~= 'items' and key ~= 'values' and key ~= 'item' and key ~= 'inner' then out[key] = value end
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
    if schema.item then out.item = sanitizeSchema(schema.item) end
    if schema.inner then out.inner = sanitizeSchema(schema.inner) end
    return out
end

local function validRequest(request)
    if type(request) ~= 'table' or type(request.resource) ~= 'string' or type(request.path) ~= 'table'
        or type(request.revision) ~= 'number' or not request.resource:match('^[%w_%-]+$') then return false end
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
    local catalog = QB.config.catalog()
    for _, entry in ipairs(catalog) do entry.schema = sanitizeSchema(entry.schema) end
    return catalog
end)

QB.callback.register('qblib:configRead', function(source, resource)
    local ok, err = requireEditor(source)
    if not ok then return nil, err end
    if type(resource) ~= 'string' then return nil, 'invalid resource' end
    local readOk, entry = pcall(QB.config.read, resource)
    if not readOk or type(entry) ~= 'table' then return nil, 'configuration is unavailable' end
    entry.configured = sanitize(entry.schema, entry.configured)
    entry.values = sanitize(entry.schema, entry.values)
    entry.schema = sanitizeSchema(entry.schema)
    return entry
end)

QB.callback.register('qblib:configCommit', function(source, request)
    local ok, err = requireEditor(source)
    if not ok then return nil, err end
    if not validRequest(request) then return nil, 'invalid configuration request' end
    local result = QB.config.commit(request.resource, { path = request.path, value = request.value, revision = request.revision })
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
    local result = QB.config.reset(request.resource, { path = request.path, revision = request.revision })
    if type(result) ~= 'table' then return result end
    local readOk, entry = pcall(QB.config.read, request.resource)
    if readOk and type(entry) == 'table' then
        result.configured = sanitize(entry.schema, entry.configured)
        result.values = sanitize(entry.schema, entry.values)
    end
    return result
end)

RegisterCommand('config', function(source, args)
    if not allowed(source) then return end
    local resource = type(args[1]) == 'string' and args[1] or nil
    TriggerClientEvent('qblib:client:configOpened', source, resource)
end, false)
