-- kora_lib bootstraps its own configuration bridge directly rather than through
-- @kora_lib/init.lua, which is the consumer-facing export proxy. Keep that
-- bootstrap path covered so kora_lib remains the platform's first consumer.

local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local H = require('harness')
local sourceFile = assert(io.open(repoRoot .. 'modules/config/consumer.lua', 'r'))
local consumerSource = sourceFile:read('*a')
sourceFile:close()

local files, bridge, netEvents, clientEvents = {}, {}, {}, {}
local previousGlobals = {
    AddEventHandler = AddEventHandler,
    Config = Config,
    exports = exports,
    GetCurrentResourceName = GetCurrentResourceName,
    GetGameTimer = GetGameTimer,
    GetInvokingResource = GetInvokingResource,
    IsDuplicityVersion = IsDuplicityVersion,
    LoadResourceFile = LoadResourceFile,
    RegisterNetEvent = RegisterNetEvent,
    SaveResourceFile = SaveResourceFile,
    source = source,
    TriggerClientEvent = TriggerClientEvent,
}

_G.GetCurrentResourceName = function() return 'kora_lib' end
_G.GetGameTimer = function() return 1000 end
_G.GetInvokingResource = function() return nil end
_G.IsDuplicityVersion = function() return true end
_G.LoadResourceFile = function(_, path)
    if path == 'modules/config/consumer.lua' then return consumerSource end
    return files[path]
end
_G.SaveResourceFile = function(_, path, contents)
    files[path] = contents
    return true
end
_G.RegisterNetEvent = function(name, handler)
    if handler then netEvents[name] = handler end
end
_G.AddEventHandler = function() end
_G.TriggerClientEvent = function(name, target, ...)
    clientEvents[#clientEvents + 1] = { name = name, target = target, values = { ... } }
end
_G.exports = setmetatable({ kora_lib = bridge }, {
    __call = function(_, name, handler) bridge[name] = handler end,
})

dofile(repoRoot .. 'build/initiate.lua')
Config = {
    ui = { interact = true },
    discord = { roleSyncInterval = 300000 },
}
dofile(repoRoot .. 'modules/config/server.lua')

H.test('kora_lib registers its own shared and server-only configuration', function()
    local entry = QB.config.read('kora_lib')
    H.assertEqual(entry.schema.fields.ui.scope, 'shared')
    H.assertEqual(entry.schema.fields.discord.scope, 'server')
    H.assertEqual(entry.values.discord.roleSyncInterval, 300000)
end)

H.test('kora_lib self registration withholds its server-only configuration from clients', function()
    _G.source = 42
    netEvents['kora_lib:server:configRequested']('kora_lib', 1)
    local snapshot = clientEvents[#clientEvents - 1]
    H.assertEqual(snapshot.name, 'kora_lib:client:configSnapshot')
    H.assertEqual(clientEvents[#clientEvents].name, 'qblib:client:configSnapshot', 'deprecated alias for older consumers')
    H.assertEqual(snapshot.target, 42)
    H.assertEqual(snapshot.values[2].discord, nil)
    H.assertEqual(snapshot.values[4], 1)
end)

H.test('configuration snapshot requests are rate limited per player', function()
    _G.source = 43
    local before = #clientEvents
    for requestId = 1, 40 do netEvents['kora_lib:server:configRequested']('kora_lib', requestId) end
    -- Each accepted request answers on the kora_lib: name and its deprecated alias.
    H.assertEqual(#clientEvents - before, 60)
end)

for name, value in pairs(previousGlobals) do _G[name] = value end

H.report('config_self')
