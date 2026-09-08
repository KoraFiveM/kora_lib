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

local minigameAuthorization
QB.minigames = {
    play = function(_, _, authorization)
        minigameAuthorization = authorization
        local p = promise.new()
        p:resolve({ success = true, proof = 'proof:value' })
        return p
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

harness.test('actions preserve trailing nil arguments for begin and complete', function()
    local beginCount, completeCount
    local started = QB.actions.run({
        label = 'Nil-safe action',
        begin = function(...)
            beginCount = select('#', ...)
            return 'token:nil-safe'
        end,
        complete = function(_, ...)
            completeCount = select('#', ...)
        end,
    }, 'station', nil)

    harness.assertTrue(started, 'the action should start')
    harness.assertEqual(beginCount, 2, 'begin should receive the trailing nil')
    harness.assertEqual(completeCount, 2, 'complete should receive the trailing nil')
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

harness.test('actions forward begin proof authorization into the minigame', function()
    minigameAuthorization = nil
    local completed
    local started = QB.actions.run({
        label = 'Authorized action',
        minigame = 'mash',
        begin = function() return 'action:token', nil, 'authorization:value' end,
        complete = function(result) completed = result end,
    })

    harness.assertTrue(started, 'the action should start')
    harness.assertEqual(minigameAuthorization, 'authorization:value',
        'the begin authorization should be passed as play third argument')
    harness.assertEqual(completed.proof, 'proof:value', 'the authorized proof should reach complete')
    harness.assertEqual(completed.authorization, 'authorization:value',
        'complete should receive the authorization needed to consume the proof')
end)

harness.test('cross-resource actions accept an already-settled minigame result', function()
    local originalInvokingResource = GetInvokingResource
    _G.GetInvokingResource = function() return 'consumer_resource' end
    QB.minigames.play = function()
        return { success = true, proof = 'proof:cross-resource' }
    end

    local completed
    local ok, started = pcall(QB.actions.run, {
        label = 'Cross-resource action',
        minigame = 'mash',
        begin = function() return 'action:cross-resource', nil, 'authorization:cross-resource' end,
        complete = function(result) completed = result end,
    })
    _G.GetInvokingResource = originalInvokingResource

    harness.assertTrue(ok, 'a plain export result must not be passed to Citizen.Await')
    harness.assertTrue(started, 'the cross-resource action should start')
    harness.assertEqual(completed.proof, 'proof:cross-resource', 'the settled proof should reach complete')
end)

harness.test('actions abort an issued server token when the UX throws', function()
    local original = QB.progressbar.start
    QB.progressbar.start = function() error('progress exploded') end
    local completionCalls, abort
    completionCalls = 0

    local ok, err = pcall(QB.actions.run, {
        label = 'Exploding action',
        begin = function() return 'action:abort' end,
        complete = function(result)
            completionCalls = completionCalls + 1
            abort = result
        end,
    })
    QB.progressbar.start = original

    harness.assertFalse(ok, 'the original UX error should still be raised')
    harness.assertTrue(tostring(err):find('progress exploded', 1, true) ~= nil,
        'the original error should be preserved')
    harness.assertEqual(completionCalls, 1, 'the issued token should be completed exactly once')
    harness.assertFalse(abort.completed, 'the cleanup completion must be an abort')
    harness.assertEqual(abort.token, 'action:abort', 'the abort must carry the issued token')
    harness.assertFalse(QB.actions.isActive(), 'the local action lock should still clear')
end)

harness.test('actions report a cancelled progress bar as incomplete', function()
    local original = QB.progressbar.start
    QB.progressbar.start = function() return false end
    local completion
    local started = QB.actions.run({
        label = 'Cancelled action',
        begin = function() return 'action:cancelled' end,
        complete = function(result) completion = result end,
    })
    QB.progressbar.start = original

    harness.assertTrue(started, 'the server-authorized action did start')
    harness.assertFalse(completion.completed, 'a cancelled progress bar must not become success')
end)

harness.test('actions report a failed minigame as incomplete', function()
    local original = QB.minigames.play
    QB.minigames.play = function() return { success = false } end
    local completion
    local started = QB.actions.run({
        label = 'Failed minigame action',
        minigame = 'mash',
        begin = function() return 'action:failed-game' end,
        complete = function(result) completion = result end,
    })
    QB.minigames.play = original

    harness.assertTrue(started, 'the server-authorized minigame action did start')
    harness.assertFalse(completion.completed, 'a failed minigame must not become success')
end)

harness.test('a throwing completion callback is never invoked twice', function()
    local calls = 0
    local ok, err = pcall(QB.actions.run, {
        label = 'Throwing completion',
        begin = function() return 'action:complete-error' end,
        complete = function()
            calls = calls + 1
            error('completion exploded')
        end,
    })

    harness.assertFalse(ok, 'the completion error should reach the caller')
    harness.assertTrue(tostring(err):find('completion exploded', 1, true) ~= nil)
    harness.assertEqual(calls, 1, 'completion must be attempted exactly once')
    harness.assertFalse(QB.actions.isActive(), 'the action lock should clear after completion failure')
end)

harness.report('actions')
