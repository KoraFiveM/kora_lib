local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/logging/shared.lua")
dofile(repoRoot .. "modules/util/shared.lua")

local currentPed = 100
_G.PlayerId = function() return 5 end
_G.GetPlayerServerId = function() return 42 end
_G.PlayerPedId = function() return currentPed end
_G.IsPedInAnyVehicle = function() return false end
_G.GetVehiclePedIsIn = function() return 0 end
_G.GetVehicleMaxNumberOfPassengers = function() return 0 end
_G.GetPedInVehicleSeat = function() return 0 end
_G.GetSelectedPedWeapon = function() return 0 end
_G.GetEntityHealth = function() return 200 end
_G.GetPedArmour = function() return 0 end
_G.GetPlayerStamina = function() return 100 end
_G.GetEntityCoords = function() return { x = 0, y = 0, z = 0 } end

dofile(repoRoot .. "local/resources/client.lua")
dofile(repoRoot .. "modules/cache/client.lua")

local screenEffectCalls, ragdollCalls, multiplierCalls, restoreStaminaCalls, randomCalls = {}, {}, {}, {}, {}
local forcedRandom = nil

local originalRandom = math.random
math.random = function(a, b)
    if a and b then
        table.insert(randomCalls, { a, b })
        if forcedRandom then return forcedRandom end
    end
    return originalRandom(a, b)
end

_G.StartScreenEffect = function(name) table.insert(screenEffectCalls, name) end
_G.StopScreenEffect = function() end
_G.IsPedRunning = function() return true end
_G.SetPedToRagdoll = function(ped) table.insert(ragdollCalls, { ped = ped }) end
_G.RestorePlayerStamina = function(playerId) table.insert(restoreStaminaCalls, playerId) end
_G.SetRunSprintMultiplierForPlayer = function(playerId, multiplier)
    table.insert(multiplierCalls, { playerId = playerId, multiplier = multiplier })
end
_G.SetFlash = function() end
_G.ShakeGameplayCam = function() end
_G.DoScreenFadeOut = function() end
_G.DoScreenFadeIn = function() end
_G.IsScreenFadedOut = function() return true end
_G.SetEntityCoords = function() end

dofile(repoRoot .. "modules/visuals/client.lua")

local function runToCompletion(steps)
    for _ = 1, (steps or 60) do
        net.step()
    end
end

local function resetRecorders()
    screenEffectCalls, ragdollCalls, multiplierCalls, restoreStaminaCalls, randomCalls = {}, {}, {}, {}, {}
    forcedRandom = nil
end

harness.test("crack's final ragdoll uses the ped current when it fires, not the one from when the effect started", function()
    resetRecorders()
    forcedRandom = 999999

    currentPed = 100
    Kora.visuals.crack(2000)
    net.step()
    currentPed = 777
    runToCompletion()

    harness.assertTrue(#ragdollCalls > 0, "crack's unconditional final ragdoll should have fired")
    harness.assertEqual(ragdollCalls[#ragdollCalls].ped, 777,
        "the final ragdoll should use the ped current when it fires, not the one cached at thread start")
end)

harness.test("ecstacy's ragdoll uses the ped current when it fires", function()
    resetRecorders()
    forcedRandom = 999999

    currentPed = 100
    Kora.visuals.ecstacy(2000)
    net.step()
    currentPed = 888
    runToCompletion()

    harness.assertTrue(#ragdollCalls > 0, "ecstacy's ragdoll should have fired")
    harness.assertEqual(ragdollCalls[#ragdollCalls].ped, 888,
        "ecstacy's ragdoll should use the ped current when it fires, not the one cached at thread start")
end)

harness.test("a shorter effect finishing after a longer effect started does not reset the sprint multiplier out from under it", function()
    resetRecorders()
    forcedRandom = 999999
    currentPed = 100

    Kora.visuals.crack(2000)
    for _ = 1, 3 do net.step() end
    Kora.visuals.meth(2000)
    runToCompletion()

    local resetCount = 0
    for _, call in ipairs(multiplierCalls) do
        if call.multiplier == 1.0 then resetCount = resetCount + 1 end
    end

    harness.assertEqual(resetCount, 1,
        "crack's premature reset-to-1.0 must be a no-op once meth has claimed the slot -- only meth's own teardown should reset it")
    harness.assertEqual(multiplierCalls[#multiplierCalls].multiplier, 1.0,
        "the surviving reset-to-1.0 should be the last multiplier call (meth's own teardown)")
end)

harness.test("a solo effect with nothing else running still resets its own multiplier", function()
    resetRecorders()
    forcedRandom = 999999
    currentPed = 100

    Kora.visuals.meth(2000)
    runToCompletion()

    harness.assertEqual(multiplierCalls[#multiplierCalls].multiplier, 1.0,
        "a solo effect must still reset the multiplier normally when nothing has superseded it")
end)

harness.test("a newer short effect restores the older effect still running underneath", function()
    resetRecorders()
    forcedRandom = 999999
    currentPed = 100

    Kora.visuals.coke(2000)
    net.step()
    net.step()
    Kora.visuals.meth(2000)
    runToCompletion(80)

    local sawMeth, restoredCoke = false, false
    for _, call in ipairs(multiplierCalls) do
        if call.multiplier == 1.49 then
            sawMeth = true
        elseif sawMeth and call.multiplier == 1.1 then
            restoredCoke = true
        end
    end

    harness.assertTrue(restoredCoke,
        "when the newer meth boost ends first it should restore the older coke boost, not reset to 1.0")
    harness.assertEqual(multiplierCalls[#multiplierCalls].multiplier, 1.0,
        "the final remaining effect should still restore the native default")
end)

harness.test("meth applies its tuned multiplier and tick count, and never ragdolls", function()
    resetRecorders()
    forcedRandom = 1
    currentPed = 100

    Kora.visuals.meth(2000)
    runToCompletion()

    harness.assertEqual(multiplierCalls[1].multiplier, 1.49, "meth's sprint multiplier should be 1.49")
    harness.assertEqual(#restoreStaminaCalls, 8, "meth should run exactly 8 stamina ticks")
    harness.assertEqual(#ragdollCalls, 0, "meth has no ragdoll behaviour at all, even with every roll forced to succeed")
    harness.assertTrue(screenEffectCalls[1] == "DrugsTrevorClownsFightIn", "meth should play its own screen effect prefix")
end)

harness.test("crack applies its tuned multiplier and tick count, and does ragdoll", function()
    resetRecorders()
    forcedRandom = 1
    currentPed = 100

    Kora.visuals.crack(2000)
    runToCompletion()

    harness.assertEqual(multiplierCalls[1].multiplier, 1.3, "crack's sprint multiplier should be 1.3")
    harness.assertEqual(#restoreStaminaCalls, 8, "crack should run exactly 8 stamina ticks")
    harness.assertTrue(#ragdollCalls > 0, "crack should ragdoll (per-tick and/or final) when every roll succeeds")
    harness.assertTrue(screenEffectCalls[1] == "DrugsMichaelAliensFightIn", "crack should play its own screen effect prefix")
end)

harness.test("coke applies its tuned multiplier and distinct 20-tick count", function()
    resetRecorders()
    forcedRandom = 1
    currentPed = 100

    Kora.visuals.coke(2000)
    runToCompletion(120)

    harness.assertEqual(multiplierCalls[1].multiplier, 1.1, "coke's sprint multiplier should be 1.1")
    harness.assertEqual(#restoreStaminaCalls, 20, "coke should run 20 stamina ticks, distinct from crack's 8")
end)

harness.test("coke rolls its replay chance out of 300, not 100", function()
    resetRecorders()

    Kora.visuals.coke(2000)
    runToCompletion(120)

    local sawTriHundred = false
    for _, call in ipairs(randomCalls) do
        if call[1] == 1 and call[2] == 300 then sawTriHundred = true end
    end
    harness.assertTrue(sawTriHundred, "coke's replay roll should be against {1, 300}")
end)

harness.test("crack/meth never roll a replay chance out of 300", function()
    resetRecorders()

    Kora.visuals.crack(2000)
    Kora.visuals.meth(2000)
    runToCompletion()

    for _, call in ipairs(randomCalls) do
        harness.assertFalse(call[1] == 1 and call[2] == 300,
            "coke's out-of-300 replay scale must not leak into crack/meth via the shared helper")
    end
end)

harness.test("fade moves the ped via SetEntityCoords between fade-out and fade-in", function()
    local movedTo = nil
    local original = _G.SetEntityCoords
    _G.SetEntityCoords = function(_, x, y, z) movedTo = { x = x, y = y, z = z } end

    Kora.visuals.fade({ x = 10, y = 20, z = 30 }, 100)

    harness.assertEqual(movedTo.x, 10, "fade should move the ped to the given coords")
    _G.SetEntityCoords = original
end)

harness.test("fade executes a masked cross-resource callable", function()
    local called = false
    local masked = setmetatable({}, {
        __call = function() called = true end,
    })

    Kora.visuals.fade(100, masked)

    harness.assertTrue(called, "a callable table from the exports boundary should run while faded out")
end)

harness.test("visual effect durations reject unsafe numeric values before scheduling work", function()
    harness.assertThrows(function() Kora.visuals.trevor(math.huge) end,
        "an infinite effect duration should be rejected")
    harness.assertThrows(function() Kora.visuals.ecstacy(0 / 0) end,
        "a NaN effect duration should be rejected")
    harness.assertThrows(function() Kora.visuals.fade(-1) end,
        "a negative fade duration should be rejected")
end)

harness.test("fade restores the screen before re-raising a callback error", function()
    local fadeIns = 0
    local original = _G.DoScreenFadeIn
    _G.DoScreenFadeIn = function() fadeIns = fadeIns + 1 end

    local ok, err = pcall(function()
        Kora.visuals.fade(100, function() error("expected fade callback failure") end)
    end)

    _G.DoScreenFadeIn = original

    harness.assertFalse(ok, "the callback error should still reach the caller")
    harness.assertTrue(tostring(err):find("expected fade callback failure", 1, true) ~= nil,
        "fade should preserve the original callback error")
    harness.assertEqual(fadeIns, 1, "fade-in must run even when the callback fails")
end)

harness.test("fade continues after a bounded wait when the native never reports completion", function()
    local original = _G.IsScreenFadedOut
    _G.IsScreenFadedOut = function() return false end

    local ran = false
    Kora.visuals.fade(0, function() ran = true end)

    _G.IsScreenFadedOut = original
    harness.assertTrue(ran, "a stalled fade native must not strand the caller forever")
end)

harness.test("trevor/alien each play their own screen effect prefix", function()
    resetRecorders()
    Kora.visuals.trevor(1000)
    runToCompletion(10)
    harness.assertEqual(screenEffectCalls[1], "DrugsTrevorClownsFightIn", "trevor should play the Trevor prefix")

    resetRecorders()
    Kora.visuals.alien(1000)
    runToCompletion(10)
    harness.assertEqual(screenEffectCalls[1], "DrugsMichaelAliensFightIn", "alien should play the Aliens prefix")
end)

harness.test("ecstacy calls SetFlash on start and eventually ragdolls", function()
    resetRecorders()
    forcedRandom = 999999
    currentPed = 100

    local flashCalls = 0
    local original = _G.SetFlash
    _G.SetFlash = function() flashCalls = flashCalls + 1 end

    Kora.visuals.ecstacy(2000)

    harness.assertTrue(flashCalls > 0, "ecstacy should call SetFlash on start")

    runToCompletion()
    harness.assertTrue(#ragdollCalls > 0, "ecstacy should ragdoll once its loop ends")

    _G.SetFlash = original
end)

harness.report("visuals")
