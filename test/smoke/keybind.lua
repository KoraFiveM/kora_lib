local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
local mocks = require('mocks')
local net = mocks.install()

local mappings = {}
_G.RegisterKeyMapping = function(name, description, mapper, key)
    mappings[#mappings + 1] = { name = name, description = description, mapper = mapper, key = key }
end
_G.GetControlInstructionalButton = function() return 't_K' end

local invokingResource
_G.GetInvokingResource = function() return invokingResource end
local pauseMenuActive = false
_G.IsPauseMenuActive = function() return pauseMenuActive end

dofile(repoRoot .. 'build/initiate.lua')
dofile(repoRoot .. 'local/resources/client.lua')
dofile(repoRoot .. 'modules/keybind/client.lua')

harness.test('client startup requests the current server-command mappings', function()
    local sync = mocks.lastEntry(net.triggeredServerEvents, 'qblib:commands:keybind:sync')
    harness.assertTrue(sync ~= nil, 'the client should request command keybind synchronization')
end)

harness.test('options API registers a protected press handler and mapper', function()
    local calls = 0
    invokingResource = 'qbchat'
    local handle = QB.keybind.add({
        name = 'qbchat_open',
        description = 'Open chat',
        defaultKey = 'T',
        defaultMapper = 'keyboard',
        onPressed = function(bind)
            calls = calls + 1
            harness.assertEqual(bind.name, 'qbchat_open')
        end,
    })
    invokingResource = nil

    net.commands['+qbchat_open']()
    net.commands['-qbchat_open']()
    harness.assertEqual(calls, 1)
    harness.assertEqual(handle.resource, 'qbchat')
    harness.assertEqual(mappings[#mappings].key, 'T')
    harness.assertEqual(mappings[#mappings].mapper, 'keyboard')
end)

harness.test('add registers primary and secondary press/release mappings', function()
    local phases = {}
    local mappingCount = #mappings
    invokingResource = 'chat_a'
    local handle = QB.keybind.add({
        name = 'chat_open',
        description = 'Open chat',
        defaultKey = 'T',
        secondaryKey = 'F2',
        onPressed = function(bind) phases[#phases + 1] = { phase = 'press', bind = bind } end,
        onReleased = function(bind) phases[#phases + 1] = { phase = 'release', bind = bind } end,
    })
    invokingResource = nil

    harness.assertEqual(#mappings, mappingCount + 2, 'primary and secondary mappings should be registered')
    harness.assertEqual(mappings[mappingCount + 1].name, '+chat_open')
    harness.assertEqual(mappings[mappingCount + 1].mapper, 'keyboard')
    harness.assertEqual(mappings[mappingCount + 2].name, '~!+chat_open')

    net.commands['+chat_open']()
    harness.assertTrue(handle.isPressed(), 'press should set the live state')
    net.commands['+chat_open']()
    harness.assertEqual(#phases, 1, 'a repeated +command while held should not duplicate the press edge')
    net.commands['-chat_open']()
    harness.assertFalse(handle.isPressed(), 'release should clear the live state')
    harness.assertEqual(phases[1].bind, handle)
    harness.assertEqual(phases[2].phase, 'release')
end)

harness.test('disabled state suppresses callbacks and disabling while held clears state', function()
    local presses, releases = 0, 0
    invokingResource = 'disabled_owner'
    local handle = QB.keybind.add({
        name = 'disabled_action', description = 'Disabled action', defaultKey = 'D',
        onPressed = function() presses = presses + 1 end,
        onReleased = function() releases = releases + 1 end,
    })
    invokingResource = nil

    net.commands['+disabled_action']()
    harness.assertTrue(handle.isPressed())
    harness.assertTrue(handle.disable(true))
    harness.assertTrue(handle.isDisabled())
    harness.assertFalse(handle.isPressed())
    net.commands['-disabled_action']()
    net.commands['+disabled_action']()
    harness.assertEqual(presses, 1, 'disabled presses should be ignored')
    harness.assertEqual(releases, 0, 'disabling while held should not synthesize a release callback')

    handle.disable(false)
    net.commands['+disabled_action']()
    net.commands['-disabled_action']()
    harness.assertEqual(presses, 2)
    harness.assertEqual(releases, 1)
end)

harness.test('pause menu suppresses new keybind presses', function()
    local presses = 0
    local handle = QB.keybind.add({
        name = 'pause_safe_action', description = 'Pause safe', defaultKey = 'P',
        onPressed = function() presses = presses + 1 end,
    })

    pauseMenuActive = true
    net.commands['+pause_safe_action']()
    pauseMenuActive = false

    harness.assertEqual(presses, 0, 'a gameplay keybind should not fire through the pause menu')
    harness.assertFalse(handle.isPressed(), 'a suppressed pause-menu press must not leave held state behind')
end)

harness.test('getCurrentBinding returns FiveM current primary display token', function()
    local handle = QB.keybind.add({
        name = 'current_binding', description = 'Current', defaultKey = 'K', onPressed = function() end,
    })
    harness.assertEqual(handle.getCurrentBinding(), 'K')
end)

harness.test('replacement reuses native wrappers and stale handles cannot remove it', function()
    local firstCalls, secondCalls = 0, 0
    invokingResource = 'first_owner'
    local first = QB.keybind.add({
        name = 'replace_me', description = 'Replace', defaultKey = 'R',
        onPressed = function() firstCalls = firstCalls + 1 end,
    })
    invokingResource = 'second_owner'
    local second = QB.keybind.add({
        name = 'replace_me', description = 'Replace', defaultKey = 'R',
        onPressed = function() secondCalls = secondCalls + 1 end,
    })
    invokingResource = nil

    harness.assertFalse(first.remove(), 'a stale handle must not remove the replacement')
    net.commands['+replace_me']()
    harness.assertEqual(firstCalls, 0)
    harness.assertEqual(secondCalls, 1)
    harness.assertTrue(second.remove())
    net.commands['-replace_me']()
    net.commands['+replace_me']()
    harness.assertEqual(secondCalls, 1, 'the persistent wrapper should be inert after removal')
end)

harness.test('a resource cannot remove another resource\'s keybind by name', function()
    invokingResource = 'keybind_owner'
    QB.keybind.add({ name = 'owned_action', description = 'Owned', defaultKey = 'O', onPressed = function() end })

    invokingResource = 'other_resource'
    harness.assertFalse(QB.keybind.remove('owned_action'), 'a foreign resource must not remove the binding')

    invokingResource = 'keybind_owner'
    harness.assertTrue(QB.keybind.remove('owned_action'), 'the owner should remove its binding')
    invokingResource = nil
end)

harness.test('resource stop disposes only bindings still owned by that resource', function()
    invokingResource = 'stopping_resource'
    QB.keybind.add({ name = 'stopping_action', description = 'Stop', defaultKey = 'S', onPressed = function() error('inert') end })
    invokingResource = 'surviving_resource'
    QB.keybind.add({ name = 'surviving_action', description = 'Stay', defaultKey = 'A', onPressed = function() end })
    invokingResource = nil

    net.fire('onClientResourceStop', 'stopping_resource')
    net.commands['+stopping_action']()

    local names = {}
    for _, entry in ipairs(QB.keybind.list()) do names[entry.name] = true end
    harness.assertFalse(names.stopping_action)
    harness.assertTrue(names.surviving_action)
end)

harness.test('an owner restart reactivates the stable wrapper without duplicate registration', function()
    local firstCalls, restartedCalls = 0, 0
    local beforeMappings = #mappings
    invokingResource = 'restarting_resource'
    QB.keybind.add({
        name = 'restart_action', description = 'Restart action', defaultKey = 'F6',
        onPressed = function() firstCalls = firstCalls + 1 end,
    })
    invokingResource = nil

    net.fire('onClientResourceStop', 'restarting_resource')
    net.commands['+restart_action']()
    harness.assertEqual(firstCalls, 0, 'the stale wrapper must be inert while its owner is stopped')

    invokingResource = 'restarting_resource'
    QB.keybind.add({
        name = 'restart_action', description = 'Restart action', defaultKey = 'F6',
        onPressed = function() restartedCalls = restartedCalls + 1 end,
    })
    invokingResource = nil
    net.commands['+restart_action']()
    net.commands['-restart_action']()

    harness.assertEqual(restartedCalls, 1)
    harness.assertEqual(#mappings, beforeMappings + 1, 'restart must reuse the existing native mapping')
end)

harness.test('callback errors are contained', function()
    QB.keybind.add({ name = 'broken_action', description = 'Broken', defaultKey = 'B', onPressed = function() error('boom') end })
    harness.assertTrue(pcall(net.commands['+broken_action']))
end)

harness.test('server command mappings use the same registry and transport', function()
    TriggerClientEvent('qblib:commands:keybind:add', 1, 'admin', {
        description = 'Open admin', defaultKey = 'F7', resource = 'qbadmin',
    })
    net.commands['+qblib_command:admin']()
    local execute = mocks.lastEntry(net.triggeredServerEvents, 'qblib:commands:keybind:execute')
    harness.assertEqual(execute[1], 'admin')

    net.commands['-qblib_command:admin']()
    TriggerClientEvent('qblib:commands:keybind:remove', 1, 'admin')
    net.commands['+qblib_command:admin']()
    harness.assertEqual(mocks.lastEntry(net.triggeredServerEvents, 'qblib:commands:keybind:execute'), execute,
        'removed command mappings should become inert')
end)

harness.test('malformed options are rejected', function()
    harness.assertFalse(pcall(QB.keybind.add, { name = 'bad name', description = 'Bad', onPressed = function() end }))
    harness.assertFalse(pcall(QB.keybind.add, { name = 'bad', description = 'Bad' }))
    harness.assertFalse(pcall(QB.keybind.add, 'not an options table'))
    harness.assertFalse(pcall(QB.keybind.add, { name = 'bad_handler', description = 'Bad', onPressed = 'not callable' }))
end)

harness.report('keybind')
