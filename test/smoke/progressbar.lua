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
dofile(repoRoot .. "local/resources/client.lua")

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
local invalidAnimDicts = {}
local playedAnims = {}
local stoppedAnims = {}
local removedAnimDicts = {}
local requestedAnimDicts = {}
local firingCalls = 0
local freezeCalls = {}
local scenarioCalls = {}
local clearTaskCalls = 0
local modelLoads = {}
local releasedModels = {}
local invalidModels = {}
local missingModels = {}
local createdObjects = {}
local entityExists = {}
local nextEntity = 100
local failCreateAt = {}
local networkCalls = {}
local attachCalls = {}
local deletedEntities = {}
local detachedEntities = {}
local namedBoneCalls = {}
local pedBoneCalls = {}
local deadError = false

function _G.PlayerPedId() return 1 end
function _G.PlayerId() return 7 end
function _G.DisablePlayerFiring(_, _) firingCalls = firingCalls + 1 end
function _G.IsEntityDead(_)
    if deadError then error("simulated death-check failure") end
    return dead
end
function _G.IsPedInAnyVehicle(_, _) return inVehicle end
function _G.IsControlJustPressed(_, control) return pressedControls[control] == true end
function _G.DisableControlAction(_, control, _) disabledControls[control] = true end
function _G.FreezeEntityPosition(entity, frozen) freezeCalls[#freezeCalls + 1] = { entity = entity, frozen = frozen } end
function _G.HasAnimDictLoaded(dict) return animDictsLoaded[dict] == true end
function _G.DoesAnimDictExist(dict) return invalidAnimDicts[dict] ~= true end
function _G.RequestAnimDict(dict) requestedAnimDicts[dict] = true end
function _G.RemoveAnimDict(dict) removedAnimDicts[dict] = true end
function _G.TaskPlayAnim(_, dict, clip, ...) table.insert(playedAnims, { dict = dict, clip = clip }) end
function _G.StopAnimTask(_, dict, clip, _) table.insert(stoppedAnims, { dict = dict, clip = clip }) end
function _G.TaskStartScenarioInPlace(_, name, _, playEnter)
    scenarioCalls[#scenarioCalls + 1] = { name = name, playEnter = playEnter }
end
function _G.ClearPedTasks(_) clearTaskCalls = clearTaskCalls + 1 end

function _G.IsModelValid(hash) return invalidModels[hash] ~= true end
function _G.HasModelLoaded(hash) return missingModels[hash] ~= true end
function _G.RequestModel(hash) modelLoads[hash] = true end
function _G.SetModelAsNoLongerNeeded(hash) releasedModels[hash] = true end
function _G.GetEntityCoords(_) return { x = 10.0, y = 20.0, z = 30.0 } end
function _G.CreateObjectNoOffset(hash, x, y, z, networked, mission, door)
    local index = #createdObjects + 1
    createdObjects[index] = {
        hash = hash, x = x, y = y, z = z,
        networked = networked, mission = mission, door = door,
    }
    if failCreateAt[index] then return 0 end
    nextEntity = nextEntity + 1
    entityExists[nextEntity] = true
    createdObjects[index].entity = nextEntity
    return nextEntity
end
function _G.DoesEntityExist(entity) return entityExists[entity] == true end
function _G.SetEntityAsMissionEntity(entity, scriptHost, grab)
    networkCalls[#networkCalls + 1] = { native = "mission", entity = entity, scriptHost = scriptHost, grab = grab }
end
function _G.NetworkGetNetworkIdFromEntity(entity) return entity + 1000 end
function _G.SetNetworkIdExistsOnAllMachines(netId, value)
    networkCalls[#networkCalls + 1] = { native = "exists", netId = netId, value = value }
end
function _G.NetworkUseHighPrecisionBlending(netId, value)
    networkCalls[#networkCalls + 1] = { native = "precision", netId = netId, value = value }
end
function _G.SetNetworkIdCanMigrate(netId, value)
    networkCalls[#networkCalls + 1] = { native = "migrate", netId = netId, value = value }
end
function _G.GetPedBoneIndex(_, bone)
    pedBoneCalls[#pedBoneCalls + 1] = bone
    return bone + 1
end
function _G.GetEntityBoneIndexByName(_, bone)
    namedBoneCalls[#namedBoneCalls + 1] = bone
    return bone == "PH_R_Hand" and 88 or -1
end
function _G.AttachEntityToEntity(...) attachCalls[#attachCalls + 1] = { ... } end
function _G.DetachEntity(entity, _, _) detachedEntities[#detachedEntities + 1] = entity end
function _G.DeleteEntity(entity)
    deletedEntities[#deletedEntities + 1] = entity
    entityExists[entity] = false
end

dofile(repoRoot .. "modules/stream/client.lua")
dofile(repoRoot .. "modules/controls/client.lua")
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
    invalidAnimDicts = {}
    firingCalls = 0
    freezeCalls = {}
    scenarioCalls = {}
    clearTaskCalls = 0
    modelLoads = {}
    releasedModels = {}
    invalidModels = {}
    missingModels = {}
    createdObjects = {}
    entityExists = {}
    nextEntity = 100
    failCreateAt = {}
    networkCalls = {}
    attachCalls = {}
    deletedEntities = {}
    detachedEntities = {}
    namedBoneCalls = {}
    pedBoneCalls = {}
    deadError = false
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

harness.test("start validates prop descriptors and the configured maximum", function()
    reset()
    harness.assertThrows(function()
        QB.progressbar.start({ label = "hi", duration = 1000, props = { { model = "valid", offset = { x = 0 } } } })
    end, "a malformed prop offset should be rejected")

    local props = {}
    for index = 1, Config.progressbar.maxProps + 1 do props[index] = { model = "valid" } end
    harness.assertThrows(function()
        QB.progressbar.start({ label = "hi", duration = 1000, props = props })
    end, "too many props should be rejected before the bar starts")
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
    harness.assertTrue(firingCalls > 0, "combat suppression should also disable player firing")
end)

harness.test("disable.car is a no-op while not in a vehicle", function()
    reset()
    inVehicle = false
    QB.progressbar.start({ label = "Working...", duration = 500, disable = { car = true } })

    harness.assertTrue(disabledControls[71] == nil, "vehicle controls should not be touched while on foot")
end)

harness.test("disable.car follows entering and leaving a vehicle", function()
    reset()
    local result
    CreateThread(function()
        result = QB.progressbar.start({ label = "Working...", duration = 5000, disable = { car = true } })
    end)

    harness.assertTrue(disabledControls[71] == nil, "vehicle controls should start untouched on foot")

    inVehicle = true
    mockHandle.step()
    harness.assertTrue(disabledControls[71] == true, "entering a vehicle should acquire the driving controls")

    inVehicle = false
    disabledControls = {}
    mockHandle.step()
    harness.assertTrue(disabledControls[71] == nil, "leaving the vehicle should release the driving controls")

    QB.progressbar.cancel()
    mockHandle.step()
    harness.assertEqual(result, false, "the test bar should settle after cancellation")
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

harness.test("an invalid anim dict degrades without making a streaming request", function()
    reset()
    invalidAnimDicts["anim@invalid"] = true

    local completed = QB.progressbar.start({
        label = "Invalid animation",
        duration = 100,
        anim = { dict = "anim@invalid", clip = "loop" },
    })

    harness.assertTrue(completed, "an invalid animation should not abort the gameplay action")
    harness.assertTrue(requestedAnimDicts["anim@invalid"] == nil,
        "the shared stream validator should reject the invalid dictionary before requesting it")
end)

harness.test("a scenario is started and cleared when the bar ends", function()
    reset()
    local completed = QB.progressbar.start({
        label = "Working...",
        duration = 500,
        scenario = { name = "WORLD_HUMAN_HAMMERING", playEnter = false },
    })

    harness.assertTrue(completed, "a scenario-backed bar should complete")
    harness.assertEqual(scenarioCalls[1].name, "WORLD_HUMAN_HAMMERING", "the scenario name should be forwarded")
    harness.assertFalse(scenarioCalls[1].playEnter, "playEnter should be forwarded")
    harness.assertEqual(clearTaskCalls, 1, "the scenario should be cleared afterward")
end)

harness.test("local props use defaults, custom attachment fields, and clean up", function()
    reset()
    local completed = QB.progressbar.start({
        label = "Working...",
        duration = 500,
        props = {
            { model = "prop_one" },
            {
                model = "prop_two",
                bone = "PH_R_Hand",
                offset = { x = 1.0, y = 2.0, z = 3.0 },
                rotation = { x = 4.0, y = 5.0, z = 6.0 },
                softPinning = false,
                collision = true,
                rotationOrder = 2,
                syncRotation = false,
            },
        },
    })

    harness.assertTrue(completed, "props should not change successful completion")
    harness.assertEqual(#createdObjects, 2, "both props should be created")
    harness.assertFalse(createdObjects[1].networked, "progress props must remain local under strict entity lockdown")
    harness.assertFalse(createdObjects[1].mission, "progress props should use qblib lifecycle ownership")
    harness.assertFalse(createdObjects[1].door, "the object door flag should remain false")
    harness.assertEqual(pedBoneCalls[1], 60309, "the default numeric bone should be 60309")
    harness.assertEqual(namedBoneCalls[1], "PH_R_Hand", "named bones should resolve by name")
    harness.assertEqual(attachCalls[1][4], 0.0, "default offset X should be zero")
    harness.assertEqual(attachCalls[1][11], true, "soft pinning should default on")
    harness.assertEqual(attachCalls[1][12], false, "collision should default off")
    harness.assertEqual(attachCalls[2][4], 1.0, "custom offset X should be forwarded")
    harness.assertEqual(attachCalls[2][10], false, "the undocumented p9 attachment argument should be false")
    harness.assertEqual(attachCalls[2][11], false, "custom soft pinning should be forwarded")
    harness.assertEqual(attachCalls[2][12], true, "custom collision should be forwarded")
    harness.assertEqual(attachCalls[2][14], 2, "rotation order should be forwarded")
    harness.assertEqual(attachCalls[2][15], false, "syncRotation should be forwarded")
    harness.assertEqual(#deletedEntities, 2, "both props should be deleted after completion")
    harness.assertEqual(#detachedEntities, 2, "both props should be detached before deletion")
    harness.assertEqual(#networkCalls, 0, "local progress props must not call network configuration natives")
end)

harness.test("a prop creation failure is cosmetic and cleans up earlier props", function()
    reset()
    failCreateAt[2] = true
    local completed = QB.progressbar.start({
        label = "Working...",
        duration = 500,
        props = { { model = "prop_one" }, { model = "prop_two" } },
    })

    harness.assertTrue(completed, "a failed cosmetic prop should not cancel the action")
    harness.assertEqual(#createdObjects, 2, "creation should be attempted for both props")
    harness.assertEqual(#deletedEntities, 1, "the successfully created prop should still be cleaned up")
end)

harness.test("an internal error still tears down props, controls, animation, and freezing", function()
    reset()
    animDictsLoaded["anim@test"] = true
    deadError = true

    harness.assertThrows(function()
        QB.progressbar.start({
            label = "Working...",
            duration = 500,
            disable = { move = true, combat = true },
            anim = { dict = "anim@test", clip = "loop" },
            props = { { model = "prop_one" } },
        })
    end, "the simulated native error should escape after cleanup")

    harness.assertFalse(QB.progressbar.isActive(), "the busy flag should always clear")
    harness.assertEqual(freezeCalls[#freezeCalls].frozen, false, "the ped should be unfrozen")
    harness.assertEqual(#stoppedAnims, 1, "the animation should be stopped")
    harness.assertEqual(#deletedEntities, 1, "the attached prop should be deleted")
    harness.assertEqual(nuiMessages[#nuiMessages].action, "progressCancel", "the NUI should be cancelled")

    disabledControls = {}
    mockHandle.step()
    harness.assertTrue(next(disabledControls) == nil, "the combat control lease should be released")
end)

harness.test("the owning resource stopping cancels and tears down an active bar", function()
    reset()
    _G.GetInvokingResource = function() return "progress_consumer" end
    local result
    CreateThread(function()
        result = QB.progressbar.start({
            label = "Working...",
            duration = 5000,
            disable = { move = true, combat = true },
            props = { { model = "prop_one" } },
        })
    end)
    _G.GetInvokingResource = function() return nil end

    harness.assertTrue(QB.progressbar.isActive(), "the bar should be running before its owner stops")
    mockHandle.fire("onClientResourceStop", "progress_consumer")
    harness.assertFalse(QB.progressbar.isActive(), "resource cleanup should clear the active bar immediately")
    harness.assertEqual(#deletedEntities, 1, "resource cleanup should delete the prop")
    harness.assertEqual(freezeCalls[#freezeCalls].frozen, false, "resource cleanup should unfreeze the ped")

    mockHandle.step()
    harness.assertEqual(result, false, "the interrupted start call should settle as cancelled")
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
