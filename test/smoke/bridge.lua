local scriptDir = debug.getinfo(1, 'S').source:match('^@(.*/)') or 'test/smoke/'
local root = scriptDir .. '../../'

if _VERSION == 'Lua 5.1' then
    _G.load = function(source, name, _, environment)
        local chunk, err = loadstring(source, name)
        if chunk and environment then setfenv(chunk, environment) end
        return chunk, err
    end
end

local config = { bridge = { vehiclekeys = 'auto' } }
local states = { kora_vehiclekeys = 'started' }
local handlers = {}
local loadedPaths = {}

_G.Config = config
_G.IsDuplicityVersion = function() return true end
_G.GetResourceState = function(resource) return states[resource] or 'missing' end
_G.AddEventHandler = function(name, callback) handlers[name] = callback end
_G.LoadResourceFile = function(resource, path)
    assert(resource == 'kora_lib')
    if path == 'modules/bridge/modules/vehiclekeys/kora_vehiclekeys/server.lua' then
        loadedPaths[#loadedPaths + 1] = path
        return [[
            Kora.bridge.giveKeys = function(src, plate) return src, plate, 'kora' end
            Kora.bridge.removeKeys = function() return true end
            Kora.bridge.hasKeys = function() return true end
        ]]
    end
end
_G.Kora = { bridge = {}, logging = { error = function() end } }

assert(loadfile(root .. 'modules/bridge/bridge_init.lua'))()

local function test(name, callback)
    local ok, err = pcall(callback)
    if not ok then error(('bridge smoke test failed: %s: %s'):format(name, tostring(err)), 0) end
    print(('PASS bridge: %s'):format(name))
end

test('loads configured provider functions directly onto Kora.bridge', function()
    local src, plate, provider = Kora.bridge.giveKeys(12, 'ABC123')
    assert(src == 12 and plate == 'ABC123' and provider == 'kora')
    assert(Kora.bridge.getProvider('vehiclekeys') == 'kora_vehiclekeys')
    assert(#loadedPaths == 1)
end)

test('removes provider functions when the provider stops', function()
    states.kora_vehiclekeys = 'stopped'
    handlers.onResourceStop('kora_vehiclekeys')
    assert(Kora.bridge.getProvider('vehiclekeys') == nil)
    assert(Kora.bridge.giveKeys == nil)
end)

test('loads provider functions again when the provider starts', function()
    states.kora_vehiclekeys = 'started'
    handlers.onResourceStart('kora_vehiclekeys')
    assert(Kora.bridge.getProvider('vehiclekeys') == 'kora_vehiclekeys')
    assert(Kora.bridge.giveKeys(7, 'XYZ789') == 7)
    assert(#loadedPaths == 2)
end)

test('does not load a forced provider that is not in the catalog', function()
    config.bridge.vehiclekeys = 'unknown'
    handlers.onResourceStop('kora_vehiclekeys')
    assert(Kora.bridge.getProvider('vehiclekeys') == nil)
    assert(Kora.bridge.giveKeys == nil)
    assert(#loadedPaths == 2)
end)
