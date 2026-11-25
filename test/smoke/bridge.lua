local scriptDir = debug.getinfo(1, 'S').source:match('^@(.*/)') or 'test/smoke/'
local root = scriptDir .. '../../'

if _VERSION == 'Lua 5.1' then
    _G.load = function(source, name, _, environment)
        local chunk, err = loadstring(source, name)
        if chunk and environment then setfenv(chunk, environment) end
        return chunk, err
    end
end
if not table.pack then
    function table.pack(...) return { n = select('#', ...), ... } end
end
if not table.unpack then table.unpack = unpack end

local config = { bridge = { vehiclekeys = 'auto' } }
local states = { kora_vehiclekeys = 'started', zz_vehiclekeys = 'started' }
local handlers = {}
local events = {}
local loadedPaths = {}
_G.shouldThrow = false

_G.Config = config
_G.IsDuplicityVersion = function() return true end
_G.GetResourceState = function(resource) return states[resource] or 'missing' end
_G.AddEventHandler = function(name, callback) handlers[name] = callback end
_G.LoadResourceFile = function(resource, path)
    assert(resource == 'kora_lib')
    if path == 'modules/bridge/modules/vehiclekeys/kora_vehiclekeys/server.lua' then
        loadedPaths[#loadedPaths + 1] = path
        return [[
            Kora.bridge.giveKeys = function()
                if shouldThrow then error('private provider error') end
                return 'kora'
            end
            Kora.bridge.removeKeys = function() return true end
            Kora.bridge.hasKeys = function() return true end
        ]]
    end
end
_G.Kora = {
    bridge = {},
    compat = {},
    logging = {
        error = function(event)
            events[#events + 1] = event
        end,
    },
}

assert(loadfile(root .. 'modules/bridge/bridge_init.lua'))()
assert(loadfile(root .. 'modules/bridge/server.lua'))()

local function test(name, callback)
    local ok, err = pcall(callback)
    if not ok then error(('bridge smoke test failed: %s: %s'):format(name, tostring(err)), 0) end
    print(('PASS bridge: %s'):format(name))
end

test('rejects incomplete adapters', function()
    local ok = pcall(Kora.bridge.register, 'vehiclekeys', 'incomplete', { giveKeys = function() end })
    assert(not ok, 'registration must reject a missing contract method')
end)

test('auto prefers a started Kora provider and loads only that module', function()
    Kora.bridge.register('vehiclekeys', 'zz_vehiclekeys', {
        giveKeys = function() return 'third-party' end,
        removeKeys = function() return true end,
        hasKeys = function() return true end,
    })
    assert(Kora.bridge.getProvider('vehiclekeys') == 'kora_vehiclekeys')
    assert(Kora.bridge.giveKeys(1, 'ABC123') == 'kora')
    assert(#loadedPaths == 1)
    assert(loadedPaths[1] == 'modules/bridge/modules/vehiclekeys/kora_vehiclekeys/server.lua')
end)

test('forced provider selects only the configured adapter', function()
    config.bridge.vehiclekeys = 'zz_vehiclekeys'
    assert(Kora.bridge.getProvider('vehiclekeys') == 'zz_vehiclekeys')
    assert(Kora.bridge.giveKeys(1, 'ABC123') == 'third-party')
    assert(#loadedPaths == 1, 'forced registered provider must not load other module files')
end)

test('missing provider returns a safe fallback and logs', function()
    config.bridge.vehiclekeys = 'not_installed'
    assert(Kora.bridge.getProvider('vehiclekeys') == nil)
    assert(Kora.bridge.giveKeys(1, 'ABC123') == false)
    assert(events[#events] == 'bridge.provider_unavailable')
end)

test('provider exceptions are contained and logged', function()
    config.bridge.vehiclekeys = 'kora_vehiclekeys'
    _G.shouldThrow = true
    assert(Kora.bridge.giveKeys(1, 'ABC123') == false)
    assert(events[#events] == 'bridge.provider_call_failed')
    _G.shouldThrow = false
end)

test('resource stop and start invalidate provider resolution', function()
    config.bridge.vehiclekeys = 'auto'
    assert(Kora.bridge.getProvider('vehiclekeys') == 'kora_vehiclekeys')
    states.kora_vehiclekeys = 'stopped'
    handlers.onResourceStop('kora_vehiclekeys')
    assert(Kora.bridge.getProvider('vehiclekeys') == 'zz_vehiclekeys')
    states.kora_vehiclekeys = 'started'
    handlers.onResourceStart('kora_vehiclekeys')
    assert(Kora.bridge.getProvider('vehiclekeys') == 'kora_vehiclekeys')
end)
