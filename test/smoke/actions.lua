local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
require('mocks').install()

dofile(repoRoot .. 'build/initiate.lua')

local progressPayload
QB.progressbar = {
    start = function(payload)
        progressPayload = payload
        return true
    end,
}

dofile(repoRoot .. 'modules/actions/client.lua')

harness.test('actions run begin, progress, then complete with an opaque token', function()
    local completed
    local started = QB.actions.run({
        label = 'Test action',
        duration = 2000,
        disable = { move = true },
        begin = function(value) return 'token:' .. value end,
        complete = function(result, value) completed = { result = result, value = value } end,
    }, 'station')

    harness.assertTrue(started, 'the action should start')
    harness.assertEqual(progressPayload.label, 'Test action', 'progress should receive the action label')
    harness.assertEqual(completed.result.token, 'token:station', 'completion should receive the begin token')
    harness.assertTrue(completed.result.completed, 'completion should receive progress success')
    harness.assertEqual(completed.value, 'station', 'arguments should be forwarded')
    harness.assertFalse(QB.actions.isActive(), 'the action lock should clear after completion')
end)

harness.test('actions do not run progress or complete when begin declines', function()
    progressPayload = nil
    local completeCalled = false
    local started, reason = QB.actions.run({
        label = 'Denied action',
        begin = function() return nil, 'too far away' end,
        complete = function() completeCalled = true end,
    })
    harness.assertFalse(started, 'a declined begin should not start')
    harness.assertEqual(reason, 'too far away', 'the rejection reason should pass through')
    harness.assertTrue(progressPayload == nil, 'no progress should start after rejection')
    harness.assertFalse(completeCalled, 'complete should not run after rejection')
end)

harness.report('actions')
