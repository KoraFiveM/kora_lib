local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

mocks.install()

dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/loops/shared.lua")

harness.test("returns immediately when the predicate is already true", function()
    local result = QB.loops.controlled(function() return true end)
    harness.assertEqual(result, true, "an immediately-true predicate should return true")
end)

harness.test("returns the predicate's truthy value, not just `true`", function()
    local result = QB.loops.controlled(function() return "done" end)
    harness.assertEqual(result, "done", "the loop should pass through whatever truthy value the predicate returns")
end)

harness.test("gives up after exhausting its try count", function()
    local attempts = 0
    local result, err = QB.loops.controlled(function()
        attempts = attempts + 1
        return false
    end, 3, false)

    harness.assertEqual(result, false, "should report failure once tries are exhausted")
    harness.assertEqual(attempts, 3, "should stop polling exactly at the try count")
    harness.assertEqual(err, "Loop failed due to exceeding try count.", "should explain why it gave up")
end)

harness.test("gives up after its timeout elapses", function()
    local result, err = QB.loops.controlled(function() return false end, false, 100)
    harness.assertEqual(result, false, "should report failure once the timeout elapses")
    harness.assertEqual(err, "Loop timed out.", "should explain why it gave up")
end)

harness.test("a zero timeout makes one failed attempt without waiting a frame", function()
    local attempts = 0
    local result, err = QB.loops.controlled(function()
        attempts = attempts + 1
        return false
    end, false, 0)

    harness.assertEqual(result, false, "a zero timeout should fail")
    harness.assertEqual(err, "Loop timed out.", "a zero timeout should report a timeout")
    harness.assertEqual(attempts, 1, "a zero timeout should not poll after its deadline")
end)

harness.test("succeeds partway through an exponential backoff", function()
    local attempts = 0
    local result = QB.loops.controlled(function()
        attempts = attempts + 1
        return attempts >= 3
    end, false, 10000, true)

    harness.assertEqual(result, true, "should succeed once the predicate turns true")
    harness.assertEqual(attempts, 3, "should have polled exactly until success")
end)

harness.test("exponential backoff also times out when nothing ever succeeds", function()
    local result, err = QB.loops.controlled(function() return false end, false, 200, true)
    harness.assertEqual(result, false, "should report failure once the timeout elapses")
    harness.assertEqual(err, "Loop timed out.", "should explain why it gave up")
end)

harness.test("a numeric backoff polls on a fixed interval until it succeeds", function()
    local attempts = 0
    local result = QB.loops.controlled(function()
        attempts = attempts + 1
        return attempts >= 3
    end, false, 10000, 100)

    harness.assertEqual(result, true, "should succeed once the predicate turns true")
    harness.assertEqual(attempts, 3, "should have polled exactly until success")
end)

harness.test("a fixed interval still honours the timeout", function()
    local result, err = QB.loops.controlled(function() return false end, false, 250, 100)
    harness.assertEqual(result, false, "should report failure once the timeout elapses")
    harness.assertEqual(err, "Loop timed out.", "should explain why it gave up")
end)

harness.test("a negative fixed interval is rejected", function()
    harness.assertThrows(function()
        QB.loops.controlled(function() return true end, false, false, -50)
    end, "a negative backoff interval should raise")
end)

harness.test('rejects malformed polling options before starting', function()
    harness.assertThrows(function() QB.loops.controlled(false) end)
    harness.assertThrows(function() QB.loops.controlled(function() end, 1.5) end)
    local called = false
    harness.assertThrows(function()
        QB.loops.controlled(function()
            called = true
        end, false, math.huge)
    end)
    harness.assertFalse(called)
    harness.assertThrows(function() QB.loops.controlled(function() end, false, false, 0 / 0) end)
end)

harness.report("loops")
