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

local openedResource
local sampleRequestId
local config = makeConfig({
    config_open = function(_, resource)
        openedResource = resource
        return true
    end,
})
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
    H.assertEqual(serverEvents[#serverEvents].name, 'kora_lib:server:configRequested')
    H.assertEqual(serverEvents[#serverEvents].values[1], 'sample')
    sampleRequestId = serverEvents[#serverEvents].values[2]
    H.assertEqual(sampleRequestId, 1)
end)

H.test('client snapshots apply shared and client-only fields only', function()
    netEvents['kora_lib:client:configSnapshot']('sample', { shared = 15, clientOnly = 'red' }, 2, sampleRequestId)
    H.assertEqual(values.shared, 15)
    H.assertEqual(values.clientOnly, 'red')
    H.assertEqual(values.serverOnly, true)
    H.assertEqual(observed[1], 15)
    H.assertEqual(observed[2], 10)
end)

H.test('live client updates apply a new revision', function()
    netEvents['kora_lib:client:configUpdated']('sample', { 'shared' }, 20, 3)
    H.assertEqual(values.shared, 20)
    H.assertEqual(observed[1], 20)
    H.assertEqual(observed[2], 15)
end)

H.test('a delayed snapshot cannot overwrite a newer live update', function()
    netEvents['kora_lib:client:configSnapshot']('sample', { shared = 15 }, 2, sampleRequestId)
    H.assertEqual(values.shared, 20)
end)

H.test('consumer-local QB.config forwards editor opens to kora_lib', function()
    H.assertTrue(config.open('sample'))
    H.assertEqual(openedResource, 'sample')
end)

H.test('snapshots clear optional scalar and object defaults and notify bindings', function()
    local config = makeConfig({})
    local values = config.define({
        note = config.optional('enabled', config.string('example'), { live = true }),
        details = config.optional({ label = 'default' }, config.object({ label = '' }), { live = true }),
    })
    local changes = 0
    config.onChange('note', function(value, previous)
        H.assertEqual(value, nil)
        H.assertEqual(previous, 'enabled')
        changes = changes + 1
    end)
    local bound = 'not updated'
    config.bind('remote', 'note', function(value) bound = value end)
    local remoteRequestId = serverEvents[#serverEvents].values[2]
    netEvents['kora_lib:client:configSnapshot']('remote', { note = 'enabled' }, 1, remoteRequestId)
    H.assertEqual(bound, 'enabled')
    local cleared = { __koraLibConfigType = 'nil' }
    local localRequestId = serverEvents[#serverEvents - 1].values[2]
    netEvents['kora_lib:client:configSnapshot']('sample', { note = cleared, details = cleared }, 2, localRequestId)
    netEvents['kora_lib:client:configUpdated']('remote', { 'note' }, cleared, 2)
    H.assertEqual(values.note, nil)
    H.assertEqual(values.details, nil)
    H.assertEqual(changes, 1)
    H.assertEqual(bound, nil, 'remote bindings must receive the cleared value')
end)

H.test('client bridge exports refuse commits and resets without persistence natives', function()
    local bridges = {}
    _G.exports = function(name, handler) bridges[name] = handler end
    _G.GetInvokingResource = function() return 'sample' end
    _G.SaveResourceFile = nil
    local consumer = makeConfig({})
    local settings = consumer.define({ enabled = consumer.boolean(true, { live = true }) })
    local snapshot = bridges.kora_lib_configRead()
    local request = { path = { 'enabled' }, value = false, revision = snapshot.revision }
    H.assertEqual(bridges.kora_lib_configCommit(request).ok, false)
    H.assertEqual(bridges.kora_lib_configReset(request).ok, false)
    H.assertEqual(settings.enabled, true)
    H.assertEqual(bridges.kora_lib_configRead().revision, snapshot.revision)
end)

for name, value in pairs(previousGlobals) do _G[name] = value end

H.report('config_client')
