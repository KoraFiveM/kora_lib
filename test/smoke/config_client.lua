local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local H = require('harness')
local makeConfig = dofile(repoRoot .. 'modules/config/consumer.lua')

local netEvents, serverEvents = {}, {}
local previousGlobals = {
    AddEventHandler = AddEventHandler,
    GetCurrentResourceName = GetCurrentResourceName,
    IsDuplicityVersion = IsDuplicityVersion,
    RegisterNetEvent = RegisterNetEvent,
    TriggerServerEvent = TriggerServerEvent,
    exports = exports,
}

_G.GetCurrentResourceName = function() return 'sample' end
_G.IsDuplicityVersion = function() return false end
_G.RegisterNetEvent = function(name, handler)
    if handler then netEvents[name] = handler end
end
_G.AddEventHandler = function() end
_G.TriggerServerEvent = function(name, ...)
    serverEvents[#serverEvents + 1] = { name = name, values = { ... } }
end
_G.exports = nil

local config = makeConfig({})
local values = config.define({
    shared = config.number(10, { live = true }),
    clientOnly = config.string('blue', { scope = 'client', live = true }),
    serverOnly = config.boolean(true, { scope = 'server' }),
})
local observed
config.onChange('shared', function(value, previous)
    observed = { value, previous }
end)

H.test('client consumers request their resource snapshot', function()
    H.assertEqual(serverEvents[#serverEvents].name, 'qblib:server:configRequested')
    H.assertEqual(serverEvents[#serverEvents].values[1], 'sample')
end)

H.test('client snapshots apply shared and client-only fields only', function()
    netEvents['qblib:client:configSnapshot']('sample', { shared = 15, clientOnly = 'red' }, 2)
    H.assertEqual(values.shared, 15)
    H.assertEqual(values.clientOnly, 'red')
    H.assertEqual(values.serverOnly, true)
    H.assertEqual(observed[1], 15)
    H.assertEqual(observed[2], 10)
end)

H.test('live client updates apply a new revision', function()
    netEvents['qblib:client:configUpdated']('sample', { 'shared' }, 20, 3)
    H.assertEqual(values.shared, 20)
    H.assertEqual(observed[1], 20)
    H.assertEqual(observed[2], 15)
end)

for name, value in pairs(previousGlobals) do _G[name] = value end

H.report('config_client')
