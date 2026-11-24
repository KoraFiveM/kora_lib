local scriptDir = debug.getinfo(1, 'S').source:match('^@(.*/)') or 'test/smoke/'
local root = scriptDir .. '../../'

if not table.pack then
    function table.pack(...) return { n = select('#', ...), ... } end
end
if not table.unpack then table.unpack = unpack end

local config = { bridge = { vehiclekeys = 'auto' } }
local states = { kora_vehiclekeys = 'started', zz_vehiclekeys = 'started' }
local handlers = {}
local events = {}

_G.Config = config
_G.IsDuplicityVersion = function() return true end
_G.GetResourceState = function(resource) return states[resource] or 'missing' end
_G.AddEventHandler = function(name, callback) handlers[name] = callback end
_G.Kora = {
    bridge = {},
    compat = {},
    logging = {
        error = function(event)
            events[#events + 1] = event
        end,
    },
}

assert(loadfile(root .. 'modules/bridge/shared.lua'))()
assert(loadfile(root .. 'modules/bridge/server.lua'))()

local function keysAdapter(value)
    return {
        giveKeys = function() return value end,
        removeKeys = function() return value end,
        hasKeys = function() return value end,
    }
end

local function test(name, callback)
    local ok, err = pcall(callback)
    if not ok then error(('bridge smoke test failed: %s: %s'):format(name, tostring(err)), 0) end
    print(('PASS bridge: %s'):format(name))
end

test('rejects incomplete adapters', function()
    local ok = pcall(Kora.bridge.register, 'vehiclekeys', 'incomplete', { giveKeys = function() end })
    assert(not ok, 'registration must reject a missing contract method')
end)

test('auto prefers a started Kora provider', function()
    Kora.bridge.register('vehiclekeys', 'zz_vehiclekeys', keysAdapter('third-party'))
    Kora.bridge.register('vehiclekeys', 'kora_vehiclekeys', keysAdapter('kora'))
    assert(Kora.bridge.getProvider('vehiclekeys') == 'kora_vehiclekeys')
    assert(Kora.bridge.giveKeys(1, 'ABC123') == 'kora')
end)

test('forced provider selects only the configured adapter', function()
    config.bridge.vehiclekeys = 'zz_vehiclekeys'
    assert(Kora.bridge.getProvider('vehiclekeys') == 'zz_vehiclekeys')
    assert(Kora.bridge.giveKeys(1, 'ABC123') == 'third-party')
end)

test('missing provider returns a safe fallback and logs', function()
    config.bridge.vehiclekeys = 'not_installed'
    assert(Kora.bridge.getProvider('vehiclekeys') == nil)
    assert(Kora.bridge.giveKeys(1, 'ABC123') == false)
    assert(events[#events] == 'bridge.provider_unavailable')
end)

test('provider exceptions are contained and logged', function()
    config.bridge.vehiclekeys = 'kora_vehiclekeys'
    states.throwing = 'started'
    Kora.bridge.register('vehiclekeys', 'throwing', {
        giveKeys = function() error('provider detail must not escape') end,
        removeKeys = function() end,
        hasKeys = function() end,
    })
    config.bridge.vehiclekeys = 'throwing'
    assert(Kora.bridge.giveKeys(1, 'ABC123') == false)
    assert(events[#events] == 'bridge.provider_call_failed')
end)

test('resource stop and start invalidate provider resolution', function()
    config.bridge.vehiclekeys = 'kora_vehiclekeys'
    assert(Kora.bridge.getProvider('vehiclekeys') == 'kora_vehiclekeys')
    states.kora_vehiclekeys = 'stopped'
    handlers.onResourceStop('kora_vehiclekeys')
    assert(Kora.bridge.getProvider('vehiclekeys') == nil)
    states.kora_vehiclekeys = 'started'
    handlers.onResourceStart('kora_vehiclekeys')
    assert(Kora.bridge.getProvider('vehiclekeys') == 'kora_vehiclekeys')
end)
