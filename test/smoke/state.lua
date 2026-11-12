local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
local mocks = require('mocks')
local net = mocks.install()

_G.GlobalState = {}
dofile(repoRoot .. 'build/initiate.lua')
dofile(repoRoot .. 'modules/state/shared.lua')
dofile(repoRoot .. 'modules/util/shared.lua')

harness.test('awaitGlobal returns false as a resolved value and times out safely', function()
    GlobalState.ready = false
    harness.assertEqual(Kora.state.awaitGlobal('ready', 10), false)
    local value, reason = Kora.state.awaitGlobal('missing', 10, 5)
    harness.assertEqual(value, nil)
    harness.assertEqual(reason, 'timeout')
end)

harness.test('awaitGlobal rejects non-finite limits before waiting', function()
    harness.assertThrows(function()
        Kora.state.awaitGlobal('missing', math.huge)
    end, 'an infinite timeout must not create an unbounded wait')
    harness.assertThrows(function()
        Kora.state.awaitGlobal('missing', 10, math.huge)
    end, 'an infinite poll interval must not schedule an invalid wait')
    harness.assertThrows(function()
        Kora.state.awaitGlobal('missing', false)
    end, 'an explicit false timeout must not default')
    harness.assertThrows(function()
        Kora.state.awaitGlobal('missing', 10, false)
    end, 'an explicit false poll interval must not default')
end)

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
    if bagName == 'player:7' then return 999 end
    return 0
end

local invokingResource
_G.GetInvokingResource = function() return invokingResource end

dofile(repoRoot .. 'local/resources/client.lua')
dofile(repoRoot .. 'local/resources/server.lua')

dofile(repoRoot .. 'modules/state/client.lua')
local clientOnChange, clientOffChange = Kora.state.onChange, Kora.state.offChange

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

harness.test('removed client listeners ignore callbacks that were already queued', function()
    local calls = 0
    local id = clientOnChange(nil, nil, function() calls = calls + 1 end)
    local queuedCallback = nativeHandlers[id].handler
    clientOffChange(id)
    queuedCallback('global', 'x', 1, 0, true)
    harness.assertEqual(calls, 0)
end)

harness.test('listener removal requires a positive finite integer ID', function()
    for _, id in ipairs({ 0, -1, 1.5, math.huge, '1' }) do
        harness.assertThrows(function() clientOffChange(id) end,
            'client listener removal must reject malformed IDs')
    end
end)

harness.test('player and global bags expose entity zero without native resolution', function()
    local seen = {}
    local id = clientOnChange(nil, nil, function(context) seen[#seen + 1] = context.entity end)
    nativeHandlers[id].handler('player:7', 'x', 1, 0, true)
    nativeHandlers[id].handler('global', 'x', 2, 0, true)
    harness.assertEqual(seen[1], 0, 'player bags should not masquerade as entities')
    harness.assertEqual(seen[2], 0, 'global bags should expose entity zero')
    clientOffChange(id)
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

harness.test('foreign resources cannot remove client state listeners', function()
    invokingResource = 'client_listener_owner'
    local id = clientOnChange(nil, nil, function() end)

    invokingResource = 'other_resource'
    harness.assertFalse(clientOffChange(id), 'a foreign resource must not remove the listener')
    harness.assertTrue(nativeHandlers[id] ~= nil, 'the listener must remain active after refusal')

    invokingResource = 'client_listener_owner'
    harness.assertTrue(clientOffChange(id), 'the owner should remove its listener')
    invokingResource = nil
end)

dofile(repoRoot .. 'modules/state/server.lua')
local serverOnChange, serverOffChange = Kora.state.onChange, Kora.state.offChange

harness.test('server subscriptions expose the same context and explicit teardown', function()
    local entity
    local id = serverOnChange('ready', nil, function(context) entity = context.entity end)
    nativeHandlers[id].handler('entity:42', 'ready', 'yes', 0, false)
    harness.assertEqual(entity, 420)
    harness.assertTrue(serverOffChange(id))
    harness.assertTrue(removed[id])
    harness.assertThrows(function() serverOffChange(math.huge) end,
        'server listener removal must reject non-finite IDs')
end)

harness.test('removed server listeners ignore callbacks that were already queued', function()
    local calls = 0
    local id = serverOnChange(nil, nil, function() calls = calls + 1 end)
    local queuedCallback = nativeHandlers[id].handler
    serverOffChange(id)
    queuedCallback('global', 'x', 1, 0, true)
    harness.assertEqual(calls, 0)
end)

harness.test('server resource stop removes its native handlers', function()
    invokingResource = 'stop_server'
    local id = serverOnChange(nil, nil, function() end)
    invokingResource = nil
    net.fire('onResourceStop', 'stop_server')
    harness.assertTrue(removed[id])
end)

harness.test('foreign resources cannot remove server state listeners', function()
    invokingResource = 'server_listener_owner'
    local id = serverOnChange(nil, nil, function() end)

    invokingResource = 'other_resource'
    harness.assertFalse(serverOffChange(id), 'a foreign resource must not remove the listener')
    harness.assertTrue(nativeHandlers[id] ~= nil, 'the listener must remain active after refusal')

    invokingResource = 'server_listener_owner'
    harness.assertTrue(serverOffChange(id), 'the owner should remove its listener')
    invokingResource = nil
end)

harness.report('state')
