-- qblib's server-side configuration catalog. The catalog intentionally owns
-- no resource configuration files: commits are sent back to the target
-- resource's consumer-local bridge, where SaveResourceFile is permitted.

local registry = {}

local function copy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do out[copy(key, seen)] = copy(child, seen) end
    return out
end

local function validResource(resource)
    return type(resource) == 'string' and resource:match('^[%w_%-]+$') ~= nil
end

local function assertRegistered(resource)
    assert(validResource(resource), 'Configuration resource must be a resource name.')
    local entry = registry[resource]
    assert(entry, ('Resource %q has not registered a qblib configuration.'):format(resource))
    return entry
end

local function callResource(resource, method, request)
    local target = exports[resource]
    assert(target, ('Resource %q is unavailable.'):format(resource))
    -- FXServer export dispatch requires genuine colon bytecode; dynamic
    -- `target[method](target, ...)` can shift arguments (see init.lua).
    if method == 'qblib_configRead' then return target:qblib_configRead() end
    if method == 'qblib_configCommit' then return target:qblib_configCommit(request) end
    if method == 'qblib_configReset' then return target:qblib_configReset(request) end
    error(('Unknown configuration bridge method %q.'):format(method))
end

---@param definition table `{resource, schema, configured, client, revision}`
function QB.config.register(definition)
    assert(type(definition) == 'table', 'Configuration registration must be a table.')
    assert(validResource(definition.resource), 'Configuration registration needs a valid resource name.')
    assert(type(definition.schema) == 'table', 'Configuration registration needs a schema.')
    assert(type(definition.configured) == 'table', 'Configuration registration needs configured values.')
    assert(type(definition.client) == 'table', 'Configuration registration needs client values.')
    assert(type(definition.revision) == 'number', 'Configuration registration needs a revision.')

    local caller = GetInvokingResource()
    local selfRegistration = caller == nil and definition.resource == GetCurrentResourceName()
    assert(caller == definition.resource or selfRegistration,
        ('Resource %q cannot register configuration for %q.'):format(tostring(caller), definition.resource))

    registry[definition.resource] = copy(definition)
    return true
end

---@return table[]
function QB.config.catalog()
    local out = {}
    for resource, entry in pairs(registry) do
        out[#out + 1] = { resource = resource, schema = copy(entry.schema), revision = entry.revision }
    end
    table.sort(out, function(a, b) return a.resource < b.resource end)
    return out
end

---@param resource string
---@return table|nil
function QB.config.read(resource)
    local entry = assertRegistered(resource)
    local fresh = callResource(resource, 'qblib_configRead')
    if type(fresh) == 'table' then
        entry.schema = copy(fresh.schema or entry.schema)
        entry.configured = copy(fresh.configured or entry.configured)
        entry.values = copy(fresh.values or entry.values)
        entry.revision = fresh.revision or entry.revision
    end
    return copy({ resource = resource, schema = entry.schema, configured = entry.configured,
        values = entry.values, revision = entry.revision })
end

---@param resource string
---@param request table `{path: string[], value: any, revision: integer}`
---@return table
function QB.config.commit(resource, request)
    local entry = assertRegistered(resource)
    assert(type(request) == 'table', 'Configuration commit must be a table.')
    local result = callResource(resource, 'qblib_configCommit', request)
    if type(result) ~= 'table' then return { ok = false, error = 'The resource returned an invalid configuration response.' } end

    if result.ok then
        entry.revision = result.revision or entry.revision
        entry.configured = copy(result.configured or entry.configured)
    end
    return copy(result)
end

---@param resource string
---@param request table `{path: string[], revision: integer}`
---@return table
function QB.config.reset(resource, request)
    local entry = assertRegistered(resource)
    assert(type(request) == 'table', 'Configuration reset must be a table.')
    local result = callResource(resource, 'qblib_configReset', request)
    if type(result) ~= 'table' then return { ok = false, error = 'The resource returned an invalid configuration response.' } end

    if result.ok then
        entry.revision = result.revision or entry.revision
        entry.configured = copy(result.configured or entry.configured)
    end
    return copy(result)
end

RegisterNetEvent('qblib:server:configRequested', function(resource)
    if not validResource(resource) then return end
    local entry = registry[resource]
    if not entry then return end
    TriggerClientEvent('qblib:client:configSnapshot', source, resource, copy(entry.client), entry.revision)
end)

AddEventHandler('onResourceStop', function(resource)
    registry[resource] = nil
end)

-- qblib uses the same consumer-local bridge as every adopting resource. It
-- cannot import @qblib/init.lua into itself because that file is the external
-- proxy, so it loads the bridge factory directly during its own bootstrap.
-- Config.discord is declared by server/config.lua and is deliberately added
-- after the shared table so it never enters the client snapshot.
local function registerQblibConfig()
    if type(Config) ~= 'table' or type(GetCurrentResourceName) ~= 'function' or GetCurrentResourceName() ~= 'qblib' then return end

    local source = assert(LoadResourceFile('qblib', 'modules/config/consumer.lua'))
    local factory = assert(load(source, '@@qblib/modules/config/consumer.lua', 't', _ENV))()
    local bridge = factory({
        config_register = function(_, definition)
            return QB.config.register(definition)
        end,
    })
    local discord = Config.discord
    Config.discord = nil
    Config = bridge.adopt(Config)
    if type(discord) == 'table' then
        Config.discord = discord
        bridge.extend({ discord = discord }, { scope = 'server' })
    end
end

registerQblibConfig()
