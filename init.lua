local library = exports.kora_lib
local requireModule
local configModule
local compatModule

local consumerModuleFiles = {
    loops = { 'modules/loops/shared.lua' },
    util = { 'modules/util/shared.lua' },
}

local isServer = type(IsDuplicityVersion) == 'function' and IsDuplicityVersion()
if not isServer then
    consumerModuleFiles.stream = { 'modules/stream/client.lua' }
    consumerModuleFiles.util[#consumerModuleFiles.util + 1] = 'modules/util/client.lua'
end

local function compileKoraFile(path)
    local source = assert(LoadResourceFile('kora_lib', path), ('Unable to load @kora_lib/%s'):format(path))
    local chunk, compileError = load(source, ('@@kora_lib/%s'):format(path), 't', _ENV)
    assert(chunk, compileError)
    return chunk
end

local function loadConsumerModule(namespace, name, paths)
    local module = {}
    local previous = rawget(namespace, name)

    rawset(namespace, name, module)

    local ok, loadError = pcall(function()
        for index = 1, #paths do
            compileKoraFile(paths[index])()
        end

        assert(next(module), ('Consumer module Kora.%s did not register any functions.'):format(name))
    end)

    if not ok then
        rawset(namespace, name, previous)
        error(loadError, 2)
    end

    return module
end

local function getRequireModule()
    if requireModule then return requireModule end

    local path = 'modules/require/loader.lua'
    local createRequire = compileKoraFile(path)()
    assert(type(createRequire) == 'function', ('@kora_lib/%s must return a factory function'):format(path))

    requireModule = createRequire(GetCurrentResourceName())
    return requireModule
end

local function getConfigModule()
    if configModule then return configModule end

    local path = 'modules/config/consumer.lua'
    local createConfig = compileKoraFile(path)()
    assert(type(createConfig) == 'function', ('@kora_lib/%s must return a factory function'):format(path))
    configModule = createConfig(library)
    return configModule
end

local function getCompatModule()
    if compatModule then return compatModule end
    local path = 'compat/provider.lua'
    compatModule = compileKoraFile(path)()()
    return compatModule
end

local function makeColonCall(name)
    assert(name:match("^[%a_][%w_]*$"), ("Invalid Kora export name: %s"):format(name))

    local chunk = assert(load(("return (select(1, ...)):%s(select(2, ...))"):format(name)))

    return function(...)
        return chunk(library, ...)
    end
end

---@type kora_lib
Kora = setmetatable({}, {
    __index = function(t, k)
        if k == 'require' then
            local module = getRequireModule()
            rawset(t, k, module)
            return module
        end

        if k == 'config' then
            local module = getConfigModule()
            rawset(t, k, module)
            return module
        end
        if k == 'compat' then
            local module = getCompatModule()
            rawset(t, k, module)
            return module
        end

        local consumerFiles = consumerModuleFiles[k]
        if consumerFiles then
            return loadConsumerModule(t, k, consumerFiles)
        end

        local moduleCall = makeColonCall(k)

        local proxy = setmetatable({}, {
            __call = function(_, ...) return moduleCall(...) end,
            __index = function(subProxy, k2)
                local wrapper = makeColonCall(("%s_%s"):format(k, k2))
                if k == 'callback' and k2 == 'trigger' then
                    -- Multiple export return values lose everything after a
                    -- leading nil (`return nil, "reason"`), so ask for one
                    -- envelope and unpack it here, in the caller's own VM.
                    local packedCall = makeColonCall('callback_triggerPacked')
                    wrapper = function(...)
                        local packed = packedCall(...)
                        if type(packed) ~= 'table' then return packed end
                        return table.unpack(packed, 1, tonumber(packed.n) or #packed)
                    end
                end
                rawset(subProxy, k2, wrapper)
                return wrapper
            end,
        })

        rawset(t, k, proxy)
        return proxy
    end,
})


AddEventHandler(isServer and 'kora_lib:server:updated' or 'kora_lib:client:updated', function()
    for name, paths in pairs(consumerModuleFiles) do
        local current = rawget(Kora, name)
        if current then
            local updated = loadConsumerModule(Kora, name, paths)

            for key in pairs(current) do current[key] = nil end
            for key, value in pairs(updated) do current[key] = value end
            rawset(Kora, name, current)
        end
    end
end)
