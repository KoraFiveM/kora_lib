-- qblib's server-side configuration catalog. The catalog intentionally owns
-- no resource configuration files: commits are sent back to the target
-- resource's consumer-local bridge, where SaveResourceFile is permitted.

local registry = {}
local discoverRegistrations

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
    if not entry and discoverRegistrations then
        discoverRegistrations()
        entry = registry[resource]
    end
    assert(entry, ('Resource %q has not registered a qblib configuration.'):format(resource))
    return entry
end

local function isRegistrationFrom(resource, definition)
    return type(definition) == 'table'
        and definition.resource == resource
        and validResource(resource)
        and type(definition.schema) == 'table'
        and type(definition.configured) == 'table'
        and type(definition.client) == 'table'
        and type(definition.revision) == 'number'
end

-- A resource normally announces its schema while starting. Catalog discovery
-- also reads the owner-local bridge directly, so a transient startup/export
-- race cannot leave the in-game editor permanently empty. The bridge cannot
-- forge another resource's entry because the returned owner must match the
-- resource whose export was queried. Probe every started resource: an
-- `@qblib/init.lua` import is a valid consumer even when the manifest does not
-- repeat qblib as an explicit dependency metadata entry.
discoverRegistrations = function()
    if type(GetNumResources) ~= 'function' or type(GetResourceByFindIndex) ~= 'function'
        or type(GetResourceState) ~= 'function' then return end

    for index = 0, GetNumResources() - 1 do
        local resource = GetResourceByFindIndex(index)
        if resource and not registry[resource] and GetResourceState(resource) == 'started' then
            local target = exports[resource]
            if target then
                local ok, definition = pcall(function() return target:qblib_configRead() end)
                if ok and isRegistrationFrom(resource, definition) then registry[resource] = copy(definition) end
            end
        end
    end
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
    discoverRegistrations()
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
        entry.client = copy(fresh.client or entry.client)
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
        entry.values = copy(result.values or entry.values)
        -- This is a local server event, so every subscribing resource can
        -- refresh its in-memory copy without a cross-resource export call in
        -- a gameplay loop. The target resource has already applied its own
        -- handler before returning success.
        TriggerEvent('qblib:server:configChanged', resource, copy(entry.values), entry.revision)
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
        entry.values = copy(result.values or entry.values)
        TriggerEvent('qblib:server:configChanged', resource, copy(entry.values), entry.revision)
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
    if type(Config.notify) == 'table' then
        Config.notify.defaultType = bridge.enum(Config.notify.defaultType, {
            live = true,
            label = 'Default notification type',
            description = 'Selects the semantic style used when a notification caller does not provide a type. The choice controls its icon, status colour, and accessibility wording without changing explicitly typed notifications.',
            options = { 'info', 'success', 'warning', 'error' },
        })
        Config.notify.defaultPosition = bridge.enum(Config.notify.defaultPosition, {
            live = true,
            label = 'Default notification position',
            description = 'Selects where notifications appear when a caller does not request a position. Choose an area that does not overlap the server HUD, inventory, phone, or dispatch feed.',
            options = { 'top-left', 'top-center', 'top-right', 'bottom-left', 'bottom-center', 'bottom-right' },
        })
    end
    Config = bridge.adopt(Config)
    if type(discord) == 'table' then
        Config.discord = discord
        bridge.extend({ discord = discord }, { scope = 'server' })
    end
end

registerQblibConfig()
