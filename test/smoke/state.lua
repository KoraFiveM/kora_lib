local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
local mocks = require('mocks')
local net = mocks.install()

local nextCookie = 0
local nativeHandlers, removed = {}, {}
_G.AddStateBagChangeHandler = function(keyFilter, bagFilter, handler)
    nextCookie = nextCookie + 1
    nativeHandlers[nextCookie] = { keyFilter = keyFilter, bagFilter = bagFilter, handler = handler }
    return nextCookie
end
_G.RemoveStateBagChangeHandler = function(cookie)
    removed[cookie] = true
    nativeHandlers[cookie] = nil
end
_G.GetEntityFromStateBagName = function(bagName)
    if bagName == 'entity:42' then return 420 end
    if bagName == 'entity:error' then error('resolver failed') end
    return 0
end

local invokingResource
_G.GetInvokingResource = function() return invokingResource end

dofile(repoRoot .. 'build/initiate.lua')
dofile(repoRoot .. 'local/resources/client.lua')
dofile(repoRoot .. 'local/resources/server.lua')

dofile(repoRoot .. 'modules/state/client.lua')
local clientOnChange, clientOffChange = QB.state.onChange, QB.state.offChange

harness.test('client subscriptions preserve filters and normalize the callback context', function()
    local change
    invokingResource = 'client_owner'
    local id = clientOnChange('locked', 'entity:42', function(context) change = context end)
    invokingResource = nil

    harness.assertEqual(nativeHandlers[id].keyFilter, 'locked')
    harness.assertEqual(nativeHandlers[id].bagFilter, 'entity:42')
    nativeHandlers[id].handler('entity:42', 'locked', true, 9, true)
    harness.assertEqual(change.entity, 420)
    harness.assertEqual(change.bagName, 'entity:42')
    harness.assertEqual(change.key, 'locked')
    harness.assertEqual(change.value, true)
    harness.assertEqual(change.reserved, 9)
    harness.assertEqual(change.replicated, true)
end)

harness.test('wildcards, resolver failure, handler errors, and explicit removal are safe', function()
    local id = clientOnChange(nil, nil, function() error('boom') end)
    harness.assertEqual(nativeHandlers[id].keyFilter, nil)
    harness.assertEqual(nativeHandlers[id].bagFilter, nil)
    harness.assertTrue(pcall(nativeHandlers[id].handler, 'entity:error', 'x', 1, 0, false))
    harness.assertTrue(clientOffChange(id))
    harness.assertTrue(removed[id])
    harness.assertFalse(clientOffChange(id))
end)

harness.test('client resource stop removes only that owners listeners', function()
    invokingResource = 'stop_client'
    local stopped = clientOnChange(nil, nil, function() end)
    invokingResource = 'stay_client'
    local stayed = clientOnChange(nil, nil, function() end)
    invokingResource = nil
    net.fire('onClientResourceStop', 'stop_client')
    harness.assertTrue(removed[stopped])
    harness.assertTrue(nativeHandlers[stayed] ~= nil)
end)

dofile(repoRoot .. 'modules/state/server.lua')
local serverOnChange, serverOffChange = QB.state.onChange, QB.state.offChange

harness.test('server subscriptions expose the same context and explicit teardown', function()
    local entity
    local id = serverOnChange('ready', nil, function(context) entity = context.entity end)
    nativeHandlers[id].handler('entity:42', 'ready', 'yes', 0, false)
    harness.assertEqual(entity, 420)
    harness.assertTrue(serverOffChange(id))
    harness.assertTrue(removed[id])
end)

harness.test('server resource stop removes its native handlers', function()
    invokingResource = 'stop_server'
    local id = serverOnChange(nil, nil, function() end)
    invokingResource = nil
    net.fire('onResourceStop', 'stop_server')
    harness.assertTrue(removed[id])
end)

harness.report('state')
