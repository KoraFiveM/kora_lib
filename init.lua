local library = exports.kora_lib
local requireModule
local configModule
local compatModule

-- These modules are intentionally instantiated inside each consumer. They
-- contain no shared registry or long-lived ownership state, and their native
-- calls should be attributed to the script that uses them. Everything else
-- stays behind kora_lib's exports so there remains one authoritative instance.
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

    -- Install the table before executing the files: module chunks populate it
    -- through Kora.<name>, which must resolve back here rather than recurse into
    -- this loader.
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

-- Requiring Lua files is deliberately consumer-local. Running this through a
-- kora_lib export would execute the required chunk in kora_lib's Lua environment,
-- leaking globals between resources and making the cache survive a consumer
-- restart. Load the factory into this resource's environment instead.
local function getRequireModule()
    if requireModule then return requireModule end

    local path = 'modules/require/loader.lua'
    local createRequire = compileKoraFile(path)()
    assert(type(createRequire) == 'function', ('@kora_lib/%s must return a factory function'):format(path))

    requireModule = createRequire(GetCurrentResourceName())
    return requireModule
end

-- Configuration has to run inside the CONSUMING resource: its Config table,
-- override file, and live handlers are all local to that resource. The normal
-- exported-module path deliberately routes calls into kora_lib instead, so config
-- uses its own consumer factory rather than the module loader above.
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

-- FXServer export dispatch bug (citizenfx/fivem#2408): dot-style `t[k](t, ...)` can
-- drop/shift arguments, while colon-call syntax (SELF opcode) works. Colon sugar needs a
-- literal name, so load() compiles a chunk with a literal `lib:name(...)` call instead.
-- `name` is validated because it is spliced into load()'s source string.
local function makeColonCall(name)
    assert(name:match("^[%a_][%w_]*$"), ("Invalid Kora export name: %s"):format(name))

    -- select(1, ...) in parens = receiver only; select(2, ...) in the last slot expands to every call argument.
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

        -- __call always receives the proxy as self; strip it before forwarding.
        local moduleCall = makeColonCall(k)

        -- Memoized via rawset so __index only fires once per module.
        local proxy = setmetatable({}, {
            -- Bare function: Kora.foo(...) -> exports.kora_lib:foo(...)
            __call = function(_, ...) return moduleCall(...) end,
            -- Module function: Kora.notify.send(...) -> exports.kora_lib:notify_send(...); memoized so load() runs once.
            __index = function(subProxy, k2)
                local wrapper = makeColonCall(("%s_%s"):format(k, k2))
                rawset(subProxy, k2, wrapper)
                return wrapper
            end,
        })

        rawset(t, k, proxy)
        return proxy
    end,
})

-- Keep the original global name so resources written before the Kora rename
-- (QB.notify.send, QB.sql.query, ...) keep working. It is the same table.
QB = Kora

-- kora_lib emits this after rebuilding its exports. Refresh only modules this
-- consumer already touched; untouched modules remain lazy. Copying into the
-- original table also keeps `local stream = Kora.stream` references current.
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
