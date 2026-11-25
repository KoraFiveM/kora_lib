local scriptDir = debug.getinfo(1, 'S').source:match('^@(.*/)') or 'test/smoke/'
local root = scriptDir .. '../../'

if _VERSION == 'Lua 5.1' then
    _G.load = function(source, name, _, environment)
        local chunk, err = loadstring(source, name)
        if chunk and environment then setfenv(chunk, environment) end
        return chunk, err
    end
end

local config = {
    Bridge = {
        vehiclekeys = 'kora_vehiclekeys',
    },
}
local paths = {}
local registeredExports = {}

_G.Config = config
_G.IsDuplicityVersion = function() return true end
_G.exports = function(name, callback) registeredExports[name] = callback end
_G.LoadResourceFile = function(resource, path)
    assert(resource == 'kora_lib')
    paths[#paths + 1] = path
    if path == 'modules/bridge/modules/vehiclekeys/kora_vehiclekeys/server.lua' then
        return [[
            function Kora.bridge.giveKeys(src, plate) return src, plate, 'kora' end
            exports('bridge_giveKeys', Kora.bridge.giveKeys)

            function Kora.bridge.removeKeys() return true end
            exports('bridge_removeKeys', Kora.bridge.removeKeys)

            function Kora.bridge.hasKeys() return true end
            exports('bridge_hasKeys', Kora.bridge.hasKeys)
        ]]
    end
end
_G.Kora = { bridge = {} }

assert(loadfile(root .. 'modules/bridge/bridge_init.lua'))()

assert(paths[1] == 'modules/bridge/modules/vehiclekeys/kora_vehiclekeys/shared.lua')
assert(paths[2] == 'modules/bridge/modules/vehiclekeys/kora_vehiclekeys/server.lua')
assert(#paths == 2)

local src, plate, provider = Kora.bridge.giveKeys(12, 'ABC123')
assert(src == 12 and plate == 'ABC123' and provider == 'kora')
assert(registeredExports.bridge_giveKeys == Kora.bridge.giveKeys)
assert(registeredExports.bridge_removeKeys == Kora.bridge.removeKeys)
assert(registeredExports.bridge_hasKeys == Kora.bridge.hasKeys)
print('PASS bridge: Config.Bridge loads the selected provider folder and its realm functions')
