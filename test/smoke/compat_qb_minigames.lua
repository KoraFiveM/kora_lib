local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/minigames/shared.lua")

-- compat/client/qb-minigames.lua only ever calls Kora.minigames.play -- mocked
-- directly here (same "resolve synchronously" trick test/smoke/minigames.lua
-- and compat_qb_menu.lua both use) rather than loading the real
-- server-authoritative implementation, since this file is exercising the
-- TRANSLATION layer (opts mapping, return-shape reshaping), not the puzzle
-- logic itself -- that's covered by test/smoke/minigames.lua.
local lastCall = nil
local nextResult = nil

Kora.minigames.play = function(gameType, opts)
    lastCall = { gameType = gameType, opts = opts }
    local p = promise.new()
    p:resolve(nextResult)
    return p
end

dofile(repoRoot .. "compat/shared.lua")
dofile(repoRoot .. "compat/client/qb-minigames.lua")

-- Mirrors what a real cross-resource exports['qb-minigames']:Fn() call does
-- under the hood: fire the __cfx_export_ event with a setCB stub and capture
-- what gets passed to it. Same helper compat_qb_menu.lua uses.
local function getExport(providedResource, exportName)
    local handlers = net.eventHandlers[("__cfx_export_%s_%s"):format(providedResource, exportName)]
    harness.assertTrue(handlers ~= nil and handlers[1] ~= nil, exportName .. " should be registered")

    local captured
    handlers[1](function(fn) captured = fn end)
    return captured
end

local Hacking = getExport("qb-minigames", "Hacking")
local KeyMinigame = getExport("qb-minigames", "KeyMinigame")
local Lockpick = getExport("qb-minigames", "Lockpick")
local StartPinpad = getExport("qb-minigames", "StartPinpad")
local Quiz = getExport("qb-minigames", "Quiz")
local Skillbar = getExport("qb-minigames", "Skillbar")
local WordGuess = getExport("qb-minigames", "WordGuess")
local WordScramble = getExport("qb-minigames", "WordScramble")

harness.test("Hacking maps onto play('hacking', ...) and returns a plain boolean", function()
    nextResult = { success = true, attempts = 1 }
    local ok = Hacking(5, 30)

    harness.assertEqual(lastCall.gameType, "hacking", "should call the hacking type")
    harness.assertEqual(lastCall.opts.solutionsize, 5, "solutionsize should pass through")
    harness.assertEqual(lastCall.opts.timeout, 30, "timeout should pass through")
    harness.assertTrue(ok, "should return the plain success boolean, matching upstream's Hacking")
end)

harness.test("KeyMinigame maps onto play('keys', ...) and returns { quit, faults }", function()
    nextResult = { success = true, attempts = 1, faults = 2 }
    local result = KeyMinigame(10)

    harness.assertEqual(lastCall.gameType, "keys", "should call the keys type")
    harness.assertEqual(lastCall.opts.amount, 10, "amount should pass through")
    harness.assertFalse(result.quit, "should not report quit when the round wasn't cancelled")
    harness.assertEqual(result.faults, 2, "faults should pass through from the play() result")
end)

harness.test("KeyMinigame reports quit = true when the round was cancelled", function()
    nextResult = { success = false, cancelled = true, attempts = 0 }
    local result = KeyMinigame(10)

    harness.assertTrue(result.quit, "a cancelled round should report quit = true")
    harness.assertEqual(result.faults, 0, "faults should default to 0 when absent")
end)

harness.test("Lockpick maps pins onto pinCount (documented divergence) and returns a plain boolean", function()
    nextResult = { success = true, attempts = 1 }
    local ok = Lockpick(5)

    harness.assertEqual(lastCall.gameType, "lockpick", "should call the lockpick type")
    harness.assertEqual(lastCall.opts.pinCount, 5, "pins should map onto pinCount")
    harness.assertTrue(ok, "should return the plain success boolean")
end)

harness.test("StartPinpad maps onto play('pinpad', ...) and returns { quit, correct }", function()
    nextResult = { success = true, attempts = 1 }
    local result = StartPinpad(1234)

    harness.assertEqual(lastCall.gameType, "pinpad", "should call the pinpad type")
    harness.assertEqual(lastCall.opts.numbers, 1234, "numbers should pass through")
    harness.assertFalse(result.quit, "should not report quit")
    harness.assertTrue(result.correct, "correct should mirror the play() success result")
end)

harness.test("Quiz maps questions/correctRequired/timer straight through", function()
    nextResult = { success = false, attempts = 1 }
    local questions = { { question = "2+2?", answer = "4", options = { "3", "4" } } }
    local ok = Quiz(questions, 1, 15)

    harness.assertEqual(lastCall.gameType, "quiz", "should call the quiz type")
    harness.assertEqual(lastCall.opts.questions, questions, "questions should pass through unchanged")
    harness.assertEqual(lastCall.opts.correctRequired, 1, "correctRequired should pass through")
    harness.assertEqual(lastCall.opts.timer, 15, "timer should pass through")
    harness.assertFalse(ok, "should return the plain success boolean")
end)

harness.test("Skillbar maps difficulty onto a zoneSize (documented divergence) and drops validKeys", function()
    nextResult = { success = true, attempts = 1 }
    local ok = Skillbar("hard", "wasdfgh")

    harness.assertEqual(lastCall.gameType, "skillbar", "should call the skillbar type")
    harness.assertTrue(lastCall.opts.zoneSize < 0.14, "hard should map onto a smaller zoneSize than the default")
    harness.assertTrue(ok, "should return the plain success boolean")
end)

harness.test("Skillbar defaults to the easy zoneSize for an unrecognized/absent difficulty", function()
    nextResult = { success = true, attempts = 1 }
    Skillbar()

    harness.assertEqual(lastCall.opts.zoneSize, 0.20, "an absent difficulty should default to the easy zoneSize")
end)

harness.test("WordGuess maps word/hint/guesses straight through", function()
    nextResult = { success = true, attempts = 1 }
    local ok = WordGuess("fivem", "the game modification", 5)

    harness.assertEqual(lastCall.gameType, "wordguess", "should call the wordguess type")
    harness.assertEqual(lastCall.opts.word, "fivem", "word should pass through")
    harness.assertEqual(lastCall.opts.hint, "the game modification", "hint should pass through")
    harness.assertEqual(lastCall.opts.guesses, 5, "guesses should pass through")
    harness.assertTrue(ok, "should return the plain success boolean")
end)

harness.test("WordScramble maps word/hint/timer straight through", function()
    nextResult = { success = true, attempts = 1 }
    local ok = WordScramble("fivem", "the game modification", 30)

    harness.assertEqual(lastCall.gameType, "wordscramble", "should call the wordscramble type")
    harness.assertEqual(lastCall.opts.word, "fivem", "word should pass through")
    harness.assertEqual(lastCall.opts.timer, 30, "timer should pass through")
    harness.assertTrue(ok, "should return the plain success boolean")
end)

harness.test("a Kora.minigames.play rejection is treated as a losing round, not a crash", function()
    Kora.minigames.play = function() error("A minigame is already in progress.") end
    local ok = Hacking(5, 30)
    harness.assertFalse(ok, "a rejected play() call should surface as success = false, not error the caller")
end)

-- Kora.minigames.play already waits when reached through a compatibility export.
-- A second Citizen.Await on its plain result would yield nil under CfxLua.
harness.test("the export path consumes Kora.minigames.play's plain result directly", function()
    _G.GetInvokingResource = function() return "consumer-resource" end
    Kora.minigames.play = function()
        return { success = true, attempts = 1 }
    end

    harness.assertTrue(Hacking(5, 30), "the success result should survive the export path")
    _G.GetInvokingResource = function() return nil end
end)

harness.report("compat_qb_minigames")
