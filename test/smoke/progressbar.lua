local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local mockHandle = mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/loops/shared.lua")

-- progressbar talks to the NUI through QB.nui.send only (see AGENTS.md "UI
-- conventions"), so modules/nui/client.lua needs to be loaded too.
-- RegisterNUICallback/SetNuiFocus are unused by anything exercised here.
local nuiMessages = {}
function _G.SendNUIMessage(msg) table.insert(nuiMessages, msg) end
_G.RegisterNUICallback = function() end
_G.SetNuiFocus = function() end
dofile(repoRoot .. "modules/nui/client.lua")

-- Ped/control natives are specific to this module, so they're mocked here
-- rather than in the shared test/mocks.lua, per the root AGENTS.md testing
-- convention.
local dead = false
local inVehicle = false
local pressedControls = {}
local disabledControls = {}
local animDictsLoaded = {}
local playedAnims = {}
local stoppedAnims = {}
local removedAnimDicts = {}
local requestedAnimDicts = {}

function _G.PlayerPedId() return 1 end
function _G.IsEntityDead(_) return dead end
function _G.IsPedInAnyVehicle(_, _) return inVehicle end
function _G.IsControlJustPressed(_, control) return pressedControls[control] == true end
function _G.DisableControlAction(_, control, _) disabledControls[control] = true end
function _G.FreezeEntityPosition(_, _) end
function _G.HasAnimDictLoaded(dict) return animDictsLoaded[dict] == true end
function _G.RequestAnimDict(dict) requestedAnimDicts[dict] = true end
function _G.RemoveAnimDict(dict) removedAnimDicts[dict] = true end
function _G.TaskPlayAnim(_, dict, clip, ...) table.insert(playedAnims, { dict = dict, clip = clip }) end
function _G.StopAnimTask(_, dict, clip, _) table.insert(stoppedAnims, { dict = dict, clip = clip }) end

dofile(repoRoot .. "modules/progressbar/client.lua")

local function reset()
    dead = false
    inVehicle = false
    pressedControls = {}
    disabledControls = {}
    nuiMessages = {}
    playedAnims = {}
    stoppedAnims = {}
    removedAnimDicts = {}
    requestedAnimDicts = {}
end

harness.test("start rejects a missing label", function()
    reset()
    harness.assertThrows(function()
        QB.progressbar.start({ duration = 1000 })
    end, "a payload with no label should be rejected")
end)

harness.test("start rejects a non-positive duration", function()
    reset()
    harness.assertThrows(function()
        QB.progressbar.start({ label = "hi", duration = 0 })
    end, "a zero duration should be rejected")
end)

harness.test("start rejects a duration over Config.progressbar.maxDuration", function()
    reset()
    harness.assertThrows(function()
        QB.progressbar.start({ label = "hi", duration = Config.progressbar.maxDuration + 1 })
    end, "a duration over the configured max should be rejected")
end)

harness.test("start rejects a malformed anim table", function()
    reset()
    harness.assertThrows(function()
        QB.progressbar.start({ label = "hi", duration = 1000, anim = { dict = "missing_clip" } })
    end, "an anim with no clip should be rejected")
end)

harness.test("start runs to completion and reports it", function()
    reset()
    local completed = QB.progressbar.start({ label = "Working...", duration = 500 })

    harness.assertTrue(completed, "an uninterrupted bar should complete")
    harness.assertFalse(QB.progressbar.isActive(), "the bar should no longer be active once start returns")

    harness.assertEqual(#nuiMessages, 1, "only the start message should have been sent (no cancel)")
    harness.assertEqual(nuiMessages[1].action, "progressStart", "the NUI should receive a progressStart action")
    harness.assertEqual(nuiMessages[1].data.label, "Working...", "the NUI payload should carry the label through")
    harness.assertEqual(nuiMessages[1].data.duration, 500, "the NUI payload should carry the duration through")
end)

harness.test("dying cancels the bar immediately", function()
    reset()
    dead = true
    local completed = QB.progressbar.start({ label = "Working...", duration = 5000 })

    harness.assertFalse(completed, "a dead ped should never complete a bar")
    harness.assertEqual(nuiMessages[2].action, "progressCancel", "a cancelled bar should hide the NUI bar early")
end)

harness.test("canCancel lets the configured control abort the bar", function()
    reset()
    pressedControls[Config.progressbar.cancelControl] = true
    local completed = QB.progressbar.start({ label = "Working...", duration = 5000, canCancel = true })

    harness.assertFalse(completed, "pressing the cancel control should cancel the bar")
end)

harness.test("the cancel control is ignored unless canCancel is set", function()
    reset()
    pressedControls[Config.progressbar.cancelControl] = true
    local completed = QB.progressbar.start({ label = "Working...", duration = 500, canCancel = false })

    harness.assertTrue(completed, "the cancel control should be inert without canCancel = true")
end)

harness.test("disable.combat and disable.car disable the expected controls", function()
    reset()
    inVehicle = true
    QB.progressbar.start({ label = "Working...", duration = 500, disable = { combat = true, car = true } })

    harness.assertTrue(disabledControls[24] == true, "attack should be disabled")
    harness.assertTrue(disabledControls[71] == true, "vehicle accelerate should be disabled while in a vehicle")
end)

harness.test("disable.car is a no-op while not in a vehicle", function()
    reset()
    inVehicle = false
    QB.progressbar.start({ label = "Working...", duration = 500, disable = { car = true } })

    harness.assertTrue(disabledControls[71] == nil, "vehicle controls should not be touched while on foot")
end)

harness.test("an anim is played for the duration and cleaned up afterward", function()
    reset()
    animDictsLoaded["anim@test"] = true
    local completed = QB.progressbar.start({
        label = "Working...",
        duration = 500,
        anim = { dict = "anim@test", clip = "loop" },
    })

    harness.assertTrue(completed, "the bar should still complete normally")
    harness.assertEqual(#playedAnims, 1, "TaskPlayAnim should have been called once")
    harness.assertEqual(playedAnims[1].dict, "anim@test", "the anim dict should be forwarded")
    harness.assertEqual(#stoppedAnims, 1, "StopAnimTask should have been called once the bar ended")
    harness.assertTrue(removedAnimDicts["anim@test"] == true, "the anim dict should be released afterward")
end)

harness.test("a bar still completes if its anim dict never loads", function()
    reset()
    -- animDictsLoaded left empty: HasAnimDictLoaded stays false the whole poll.
    local completed = QB.progressbar.start({
        label = "Working...",
        duration = 500,
        anim = { dict = "anim@missing", clip = "loop" },
    })

    harness.assertTrue(completed, "a missing anim dict should degrade, not abort, the bar")
    harness.assertEqual(#playedAnims, 0, "TaskPlayAnim should never have been called")
    harness.assertTrue(requestedAnimDicts["anim@missing"] == true, "the dict should still have been requested")
end)

harness.test("start refuses to run a second bar while one is active, then recovers", function()
    reset()

    local firstResult
    CreateThread(function()
        firstResult = QB.progressbar.start({ label = "First", duration = 5000 })
    end)

    harness.assertTrue(QB.progressbar.isActive(), "the first bar should be active after CreateThread's first resume")

    local completed, err = QB.progressbar.start({ label = "Second", duration = 500 })
    harness.assertFalse(completed, "a second bar should be refused while the first is active")
    harness.assertTrue(err ~= nil, "the refusal should include a reason")

    local cancelled = QB.progressbar.cancel()
    harness.assertTrue(cancelled, "cancel() should report that a bar was actually running")

    mockHandle.step()

    harness.assertEqual(firstResult, false, "the first bar should resolve as cancelled once resumed")
    harness.assertFalse(QB.progressbar.isActive(), "the module should be free for a new bar once the first one ends")

    local recovered = QB.progressbar.start({ label = "Third", duration = 500 })
    harness.assertTrue(recovered, "a fresh bar should be able to run once the previous one finished")
end)

harness.report("progressbar")
