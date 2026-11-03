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
    -- A sites index is consumer data; keeping it here means validate() never
    -- re-serialises it across the exports boundary.
    sites = { 'modules/sites/shared.lua' },
}

local isServer = type(IsDuplicityVersion) == 'function' and IsDuplicityVersion()
if not isServer then
    consumerModuleFiles.stream = { 'modules/stream/client.lua' }
    consumerModuleFiles.util[#consumerModuleFiles.util + 1] = 'modules/util/client.lua'
end
consumerModuleFiles.sites[2] = isServer and 'modules/sites/server.lua' or 'modules/sites/client.lua'

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

-- Registrations made through kora_lib exports (server callbacks and events,
-- cache listeners, zones, keybinds, ...) are stored inside kora_lib, so a
-- kora_lib restart drops them while this consumer keeps running. Handlers in
-- this list re-run after every restart so the consumer can put them back.
local readyHandlers = {}
local nextReadyId = 0

---Runs `fn` now, then again every time kora_lib restarts while this resource
---keeps running. `fn` must be safe to run more than once.
---@param fn fun()
---@return integer id Pass to Kora.offReady to stop the re-runs.
function Kora.onReady(fn)
    assert(type(fn) == 'function', 'Kora.onReady requires a function.')

    nextReadyId = nextReadyId + 1
    local id = nextReadyId
    readyHandlers[#readyHandlers + 1] = { id = id, fn = fn }

    fn()
    return id
end

---Stops a Kora.onReady handler from running after later kora_lib restarts.
---@param id integer
---@return boolean removed
function Kora.offReady(id)
    for index = 1, #readyHandlers do
        if readyHandlers[index].id == id then
            table.remove(readyHandlers, index).removed = true
            return true
        end
    end
    return false
end

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

    -- One thread per handler, so one that waits (or errors) cannot hold up the
    -- others. A snapshot keeps Kora.offReady inside a handler safe.
    local handlers = table.move(readyHandlers, 1, #readyHandlers, 1, {})
    for index = 1, #handlers do
        local handler = handlers[index]
        CreateThread(function()
            if handler.removed then return end
            local ok, err = pcall(handler.fn)
            if not ok then
                print(('[kora_lib] Kora.onReady handler %d in %s errored: %s')
                    :format(handler.id, GetCurrentResourceName(), tostring(err)))
            end
        end)
    end
end)
