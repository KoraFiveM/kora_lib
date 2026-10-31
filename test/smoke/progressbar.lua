local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local mockHandle = mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/util/shared.lua")
dofile(repoRoot .. "modules/loops/shared.lua")
dofile(repoRoot .. "local/resources/client.lua")

-- progressbar talks to the NUI through Kora.nui.send only (see AGENTS.md "UI
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
local ragdoll = false
local cuffed = false
local falling = false
local swimming = false
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
local playedEmotes = {}
local cancelledEmotes = {}

_G.exports = {
    kora_emotemenu = {
        playEmote = function(_, emote) playedEmotes[#playedEmotes + 1] = emote end,
        cancelEmote = function(_, forced) cancelledEmotes[#cancelledEmotes + 1] = forced end,
    },
}

function _G.PlayerPedId() return 1 end
function _G.PlayerId() return 7 end
function _G.DisablePlayerFiring(_, _) firingCalls = firingCalls + 1 end
function _G.IsEntityDead(_)
    if deadError then error("simulated death-check failure") end
    return dead
end
function _G.IsPedRagdoll(_) return ragdoll end
function _G.IsPedCuffed(_) return cuffed end
function _G.IsPedFalling(_) return falling end
function _G.IsPedSwimming(_) return swimming end
function _G.IsPedInAnyVehicle(_, _) return inVehicle end
function _G.IsControlJustPressed(_, control) return pressedControls[control] == true end
function _G.DisableControlAction(_, control, _) disabledControls[control] = true end
function _G.FreezeEntityPosition(entity, frozen) freezeCalls[#freezeCalls + 1] = { entity = entity, frozen = frozen } end
function _G.HasAnimDictLoaded(dict) return animDictsLoaded[dict] == true end
function _G.DoesAnimDictExist(dict) return invalidAnimDicts[dict] ~= true end
function _G.RequestAnimDict(dict) requestedAnimDicts[dict] = true end
function _G.RemoveAnimDict(dict) removedAnimDicts[dict] = true end
function _G.TaskPlayAnim(_, dict, clip, blendIn, blendOut, duration, flag, playbackRate, lockX, lockY, lockZ)
    table.insert(playedAnims, { dict = dict, clip = clip, blendIn = blendIn, blendOut = blendOut,
        duration = duration, flag = flag, playbackRate = playbackRate, lockX = lockX, lockY = lockY, lockZ = lockZ })
end
function _G.StopAnimTask(_, dict, clip, blendOut)
    stoppedAnims[#stoppedAnims + 1] = { dict = dict, clip = clip, blendOut = blendOut }
end
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
_G.CreateObject = _G.CreateObjectNoOffset
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
    ragdoll = false
    cuffed = false
    falling = false
    swimming = false
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
    playedEmotes = {}
    cancelledEmotes = {}
end

harness.test("start rejects a missing label", function()
    reset()
    harness.assertThrows(function()
        Kora.progressbar.start({ duration = 1000 })
    end, "a payload with no label should be rejected")
end)

harness.test("start rejects a non-positive duration", function()
    reset()
    harness.assertThrows(function()
        Kora.progressbar.start({ label = "hi", duration = 0 })
    end, "a zero duration should be rejected")
end)

harness.test("start rejects a duration over Config.progressbar.maxDuration", function()
    reset()
    harness.assertThrows(function()
        Kora.progressbar.start({ label = "hi", duration = Config.progressbar.maxDuration + 1 })
    end, "a duration over the configured max should be rejected")
end)

harness.test("start can opt out of the duration cap for compatibility providers", function()
    reset()
    local duration = Config.progressbar.maxDuration + 1

    local completed = Kora.progressbar.start({
        label = "long compatibility action",
        duration = duration,
        maxDuration = false,
    })

    harness.assertTrue(completed, "the compatibility override should allow a duration above kora_lib's default cap")
end)

harness.test("start rejects non-finite duration values before creating a session", function()
    reset()
    harness.assertThrows(function()
        Kora.progressbar.start({ label = "invalid", duration = math.huge, maxDuration = false })
    end, "an uncapped infinite duration should be rejected")
    harness.assertThrows(function()
        Kora.progressbar.start({ label = "invalid", duration = 100, maxDuration = math.huge })
    end, "an infinite duration cap should be rejected")
end)

harness.test("start rejects non-finite animation and prop transform values", function()
    reset()
    harness.assertThrows(function()
        Kora.progressbar.start({ label = "invalid", duration = 100, anim = {
            dict = "anim@test", clip = "loop", playbackRate = math.huge,
        } })
    end)
    harness.assertThrows(function()
        Kora.progressbar.start({ label = "invalid", duration = 100, props = {
            { model = "valid", offset = { x = 0 / 0, y = 0, z = 0 } },
        } })
    end)
end)

harness.test("start rejects a malformed anim table", function()
    reset()
    harness.assertThrows(function()
        Kora.progressbar.start({ label = "hi", duration = 1000, anim = { dict = "missing_clip" } })
    end, "an anim with no clip should be rejected")
end)

harness.test("start validates prop descriptors and the configured maximum", function()
    reset()
    harness.assertThrows(function()
        Kora.progressbar.start({ label = "hi", duration = 1000, props = { { model = "valid", offset = { x = 0 } } } })
    end, "a malformed prop offset should be rejected")

    local props = {}
    for index = 1, Config.progressbar.maxProps + 1 do props[index] = { model = "valid" } end
    harness.assertThrows(function()
        Kora.progressbar.start({ label = "hi", duration = 1000, props = props })
    end, "too many props should be rejected before the bar starts")
end)

harness.test("start runs to completion and reports it", function()
    reset()
    local completed = Kora.progressbar.start({ label = "Working...", duration = 500 })

    harness.assertTrue(completed, "an uninterrupted bar should complete")
    harness.assertFalse(Kora.progressbar.isActive(), "the bar should no longer be active once start returns")

    harness.assertEqual(#nuiMessages, 1, "only the start message should have been sent (no cancel)")
    harness.assertEqual(nuiMessages[1].action, "progressStart", "the NUI should receive a progressStart action")
    harness.assertEqual(nuiMessages[1].data.label, "Working...", "the NUI payload should carry the label through")
    harness.assertEqual(nuiMessages[1].data.duration, 500, "the NUI payload should carry the duration through")
end)

harness.test("dying cancels the bar immediately", function()
    reset()
    dead = true
    local completed = Kora.progressbar.start({ label = "Working...", duration = 5000 })

    harness.assertFalse(completed, "a dead ped should never complete a bar")
    harness.assertEqual(nuiMessages[2].action, "progressCancel", "a cancelled bar should hide the NUI bar early")
end)

harness.test("ox interruption flags allow or reject ped states", function()
    reset()
    dead, ragdoll, cuffed, falling, swimming = true, true, true, true, true
    local completed = Kora.progressbar.start({
        label = "Working...", duration = 100,
        useWhileDead = true, allowRagdoll = true, allowCuffed = true,
        allowFalling = true, allowSwimming = true,
    })
    harness.assertTrue(completed, "explicit allow flags should permit every matching ped state")

    reset()
    ragdoll = true
    harness.assertFalse(Kora.progressbar.start({ label = "Working...", duration = 100 }),
        "ragdoll should interrupt by default")
end)

harness.test("canCancel lets X abort the bar", function()
    reset()
    pressedControls[73] = true
    local completed = Kora.progressbar.start({ label = "Working...", duration = 5000, canCancel = true })

    harness.assertFalse(completed, "pressing X should cancel the bar")
end)

harness.test("canCancel lets Escape abort the bar", function()
    reset()
    pressedControls[322] = true
    local completed = Kora.progressbar.start({ label = "Working...", duration = 5000, canCancel = true })

    harness.assertFalse(completed, "pressing Escape should cancel the bar")
end)

harness.test("cancel controls are ignored unless canCancel is set", function()
    reset()
    pressedControls[322] = true
    local completed = Kora.progressbar.start({ label = "Working...", duration = 500, canCancel = false })

    harness.assertTrue(completed, "cancel controls should be inert without canCancel = true")
end)

harness.test("cancel controls can be delegated to a compatibility command", function()
    reset()
    pressedControls[73] = true
    pressedControls[322] = true

    local completed = Kora.progressbar.start({
        label = "Command-owned cancellation",
        duration = 100,
        canCancel = true,
        cancelControls = false,
    })

    harness.assertTrue(completed, "kora_lib should not poll its native cancel keys when a compatibility command owns them")
end)

harness.test("disable.combat and disable.car disable the expected controls", function()
    reset()
    inVehicle = true
    Kora.progressbar.start({ label = "Working...", duration = 500, disable = { combat = true, car = true } })

    harness.assertTrue(disabledControls[24] == true, "attack should be disabled")
    harness.assertTrue(disabledControls[71] == true, "vehicle accelerate should be disabled while in a vehicle")
    harness.assertTrue(firingCalls > 0, "combat suppression should also disable player firing")
end)

harness.test("disable.sprint and disable.mouse use the expected control leases", function()
    reset()
    Kora.progressbar.start({ label = "Working...", duration = 100, disable = { sprint = true, mouse = true } })
    harness.assertTrue(disabledControls[21], "sprint should be disabled")
    harness.assertTrue(disabledControls[1] and disabledControls[2] and disabledControls[106], "look controls should be disabled")
end)

harness.test("disable.car is a no-op while not in a vehicle", function()
    reset()
    inVehicle = false
    Kora.progressbar.start({ label = "Working...", duration = 500, disable = { car = true } })

    harness.assertTrue(disabledControls[71] == nil, "vehicle controls should not be touched while on foot")
end)

harness.test("disable.car follows entering and leaving a vehicle", function()
    reset()
    local result
    CreateThread(function()
        result = Kora.progressbar.start({ label = "Working...", duration = 5000, disable = { car = true } })
    end)

    harness.assertTrue(disabledControls[71] == nil, "vehicle controls should start untouched on foot")

    inVehicle = true
    mockHandle.step()
    harness.assertTrue(disabledControls[71] == true, "entering a vehicle should acquire the driving controls")

    inVehicle = false
    disabledControls = {}
    mockHandle.step()
    harness.assertTrue(disabledControls[71] == nil, "leaving the vehicle should release the driving controls")

    Kora.progressbar.cancel()
    mockHandle.step()
    harness.assertEqual(result, false, "the test bar should settle after cancellation")
end)

harness.test("an anim is played for the duration and cleaned up afterward", function()
    reset()
    animDictsLoaded["anim@test"] = true
    local completed = Kora.progressbar.start({
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

harness.test("animation timing and lock flags are forwarded", function()
    reset()
    animDictsLoaded["anim@test"] = true
    Kora.progressbar.start({
        label = "Working...", duration = 100,
        anim = { dict = "anim@test", clip = "loop", duration = 250, playbackRate = 0.75,
            lockX = true, lockY = false, lockZ = true, stopBlendOut = 1.0 },
    })
    local played = playedAnims[1]
    harness.assertEqual(played.duration, 250, "animation duration should be forwarded")
    harness.assertEqual(played.playbackRate, 0.75, "animation playbackRate should be forwarded")
    harness.assertTrue(played.lockX and not played.lockY and played.lockZ, "animation lock axes should be forwarded")
    harness.assertEqual(stoppedAnims[1].blendOut, 1.0, "the compatibility cleanup blend-out should be independent of playback blendOut")
end)

harness.test("a bar still completes if its anim dict never loads", function()
    reset()
    -- animDictsLoaded left empty: HasAnimDictLoaded stays false the whole poll.
    local completed = Kora.progressbar.start({
        label = "Working...",
        duration = 500,
        anim = { dict = "anim@missing", clip = "loop" },
    })

    harness.assertTrue(completed, "a missing anim dict should degrade, not abort, the bar")
    harness.assertEqual(#playedAnims, 0, "TaskPlayAnim should never have been called")
    harness.assertTrue(requestedAnimDicts["anim@missing"] == true, "the dict should still have been requested")
end)

harness.test("strict animation loading raises for compatibility providers", function()
    reset()

    harness.assertThrows(function()
        Kora.progressbar.start({
            label = "Strict animation",
            duration = 1000,
            anim = { dict = "anim@missing", clip = "idle" },
            strictAnim = true,
        })
    end, "strict animation loading should preserve ox_lib's error contract")
    harness.assertFalse(Kora.progressbar.isActive(), "strict animation failure must still clean up the active session")
end)

harness.test("an invalid anim dict degrades without making a streaming request", function()
    reset()
    invalidAnimDicts["anim@invalid"] = true

    local completed = Kora.progressbar.start({
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
    local completed = Kora.progressbar.start({
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
    local completed = Kora.progressbar.start({
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
    harness.assertFalse(createdObjects[1].mission, "progress props should use kora_lib lifecycle ownership")
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

harness.test("legacy prop and proptwo attach with coords and clean up", function()
    reset()
    local completed = Kora.progressbar.start({
        label = "Working...",
        duration = 100,
        prop = { model = "prop_one", coords = { x = 1.0, y = 2.0, z = 3.0 }, bone = 57005,
            rotation = { x = 4.0, y = 5.0, z = 6.0 } },
        proptwo = { model = "prop_two", coords = { x = 7.0, y = 8.0, z = 9.0 }, bone = 60309,
            rotation = { x = 10.0, y = 11.0, z = 12.0 } },
    })

    harness.assertTrue(completed, "legacy props should not change successful completion")
    harness.assertEqual(#createdObjects, 2, "both legacy props should be created")
    harness.assertEqual(pedBoneCalls[1], 57005, "the first supplied bone should be used")
    harness.assertEqual(pedBoneCalls[2], 60309, "the second supplied bone should be used")
    harness.assertEqual(attachCalls[1][4], 1.0, "coords should become the attachment offset")
    harness.assertEqual(attachCalls[2][4], 7.0, "proptwo coords should become the attachment offset")
    harness.assertEqual(#deletedEntities, 2, "both legacy props should be deleted")
end)

harness.test("emotes are cleaned up and animation takes priority", function()
    reset()
    harness.assertTrue(Kora.progressbar.start({ label = "Reading", duration = 100, emote = "clipboard" }))
    harness.assertEqual(playedEmotes[1], "clipboard", "an emote-only bar should play its emote")
    harness.assertTrue(cancelledEmotes[1], "the active emote should be cancelled at completion")

    reset()
    pressedControls[73] = true
    harness.assertFalse(Kora.progressbar.start({ label = "Reading", duration = 5000, canCancel = true, emote = "clipboard" }),
        "X should use the normal cancellation path")
    harness.assertEqual(playedEmotes[1], "clipboard", "a cancellable emote-only bar should play its emote")
    harness.assertTrue(cancelledEmotes[1], "cancellation should stop the active emote")

    reset()
    animDictsLoaded["anim@test"] = true
    harness.assertTrue(Kora.progressbar.start({
        label = "Working", duration = 100, emote = "clipboard",
        anim = { dict = "anim@test", clip = "loop" },
    }), "an animation-backed bar should complete")
    harness.assertEqual(#playedEmotes, 0, "an animation should suppress the emote")
    harness.assertEqual(#stoppedAnims, 1, "cancellation should stop the animation")
end)

harness.test("a prop creation failure is cosmetic and cleans up earlier props", function()
    reset()
    failCreateAt[2] = true
    local completed = Kora.progressbar.start({
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
        Kora.progressbar.start({
            label = "Working...",
            duration = 500,
            disable = { move = true, combat = true },
            anim = { dict = "anim@test", clip = "loop" },
            props = { { model = "prop_one" } },
        })
    end, "the simulated native error should escape after cleanup")

    harness.assertFalse(Kora.progressbar.isActive(), "the busy flag should always clear")
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
        result = Kora.progressbar.start({
            label = "Working...",
            duration = 5000,
            disable = { move = true, combat = true },
            props = { { model = "prop_one" } },
        })
    end)
    _G.GetInvokingResource = function() return nil end

    harness.assertTrue(Kora.progressbar.isActive(), "the bar should be running before its owner stops")
    mockHandle.fire("onClientResourceStop", "progress_consumer")
    harness.assertFalse(Kora.progressbar.isActive(), "resource cleanup should clear the active bar immediately")
    harness.assertEqual(#deletedEntities, 1, "resource cleanup should delete the prop")
    harness.assertEqual(freezeCalls[#freezeCalls].frozen, false, "resource cleanup should unfreeze the ped")

    mockHandle.step()
    harness.assertEqual(result, false, "the interrupted start call should settle as cancelled")
end)

harness.test("start refuses to run a second bar while one is active, then recovers", function()
    reset()

    local firstResult
    CreateThread(function()
        firstResult = Kora.progressbar.start({ label = "First", duration = 5000 })
    end)

    harness.assertTrue(Kora.progressbar.isActive(), "the first bar should be active after CreateThread's first resume")

    local completed, err = Kora.progressbar.start({ label = "Second", duration = 500 })
    harness.assertFalse(completed, "a second bar should be refused while the first is active")
    harness.assertTrue(err ~= nil, "the refusal should include a reason")

    local cancelled = Kora.progressbar.cancel()
    harness.assertTrue(cancelled, "cancel() should report that a bar was actually running")

    mockHandle.step()

    harness.assertEqual(firstResult, false, "the first bar should resolve as cancelled once resumed")
    harness.assertFalse(Kora.progressbar.isActive(), "the module should be free for a new bar once the first one ends")

    local recovered = Kora.progressbar.start({ label = "Third", duration = 500 })
    harness.assertTrue(recovered, "a fresh bar should be able to run once the previous one finished")
end)

harness.test("only the initiating resource can cancel an active bar", function()
    reset()

    local result
    CreateThread(function()
        result = Kora.progressbar.start({ label = "Owned", duration = 5000 }, "progress_owner")
    end)

    harness.assertFalse(Kora.progressbar.cancel("other_resource"),
        "another resource must not be able to cancel the active bar")
    harness.assertTrue(Kora.progressbar.cancel("progress_owner"),
        "the initiating resource should be able to cancel its bar")
    mockHandle.step()
    harness.assertFalse(result, "the owner's cancellation should settle the bar as incomplete")
end)

local legacyExports = {}
Kora.compat.provideExport = function(identity, name, callback)
    harness.assertEqual(identity, 'progressbar')
    legacyExports[name] = callback
end
LocalPlayer = { state = { inv_busy = false } }
function LocalPlayer.state:set(key, value) self[key] = value end
dofile(repoRoot .. 'compat/client/progressbar.lua')

harness.test('legacy progress exports preserve callbacks, busy rejection and sequential bars', function()
    reset()
    local started, ticks, finished, rejected = 0, 0, {}, false
    legacyExports.ProgressWithStartAndTick({ label = 'First', duration = 5000,
        controlDisables = { disableMovement = true, disableCombat = true } },
        function() started = started + 1 end, function() ticks = ticks + 1 end,
        function(cancelled)
            finished[#finished + 1] = cancelled
            legacyExports.Progress({ label = 'Second', duration = 5000 }, function(value) finished[#finished + 1] = value end)
        end)
    harness.assertTrue(legacyExports.isDoingSomething())
    harness.assertTrue(LocalPlayer.state.inv_busy)
    harness.assertEqual(started, 1)
    legacyExports.Progress({ label = 'Rejected', duration = 10 }, function() rejected = true end)
    harness.assertFalse(rejected)
    mockHandle.fire('progressbar:client:ToggleBusyness', false)
    mockHandle.step()
    harness.assertEqual(finished[1], false)
    harness.assertTrue(legacyExports.isDoingSomething(), 'a finish callback can start the next bar')
    mockHandle.fire('progressbar:client:cancel')
    mockHandle.step()
    harness.assertEqual(finished[2], true)
    harness.assertFalse(legacyExports.isDoingSomething())
    harness.assertFalse(LocalPlayer.state.inv_busy)
    harness.assertTrue(ticks > 0)
end)

harness.test('legacy events preserve dead guard, custom props and scenario, mouse and busy toggle', function()
    reset()
    dead = true
    local called = false
    legacyExports.Progress({ label = 'Dead', duration = 50 }, function() called = true end)
    harness.assertFalse(called)
    harness.assertFalse(legacyExports.isDoingSomething())
    dead = false
    mockHandle.fire('progressbar:client:ToggleBusyness', true)
    harness.assertTrue(legacyExports.isDoingSomething())
    mockHandle.fire('progressbar:client:ToggleBusyness', false)
    mockHandle.fire('progressbar:client:ProgressWithStartEvent', { label = 'Scenario', duration = 5000,
        animation = { task = 'WORLD_HUMAN_HAMMERING' },
        controlDisables = { disableMouse = true }, prop = { model = 'prop_one' }, propTwo = { model = 'prop_two' } },
        function() called = true end, function() end)
    harness.assertTrue(called)
    harness.assertEqual(#createdObjects, 2)
    harness.assertEqual(scenarioCalls[#scenarioCalls].name, 'WORLD_HUMAN_HAMMERING')
    harness.assertTrue(createdObjects[1].networked)
    harness.assertTrue(attachCalls[1][10], 'legacy props preserve the upstream attachment flag')
    harness.assertEqual(#networkCalls, 6, 'both legacy props configure network visibility and ownership')
    mockHandle.fire('progressbar:client:cancel')
    mockHandle.step()
    harness.assertFalse(legacyExports.isDoingSomething())
    harness.assertEqual(#deletedEntities, 2, 'cancel deletes both owned networked props')
end)

harness.test('legacy owner shutdown restores inventory state and suppresses stale callbacks', function()
    reset()
    LocalPlayer.state.inv_busy = true
    _G.GetInvokingResource = function() return 'legacy_owner' end
    local called = false
    legacyExports.ProgressWithTickEvent({ label = 'Owned', duration = 5000 }, function() end, function() called = true end)
    _G.GetInvokingResource = function() return nil end
    mockHandle.fire('onClientResourceStop', 'legacy_owner')
    mockHandle.step()
    harness.assertFalse(called)
    harness.assertFalse(legacyExports.isDoingSomething())
    harness.assertTrue(LocalPlayer.state.inv_busy)
    LocalPlayer.state.inv_busy = false
end)

harness.test('core forwarding preserves the original resource owner', function()
    reset()
    local finished = false
    _G.GetInvokingResource = function() return 'kora_core' end
    legacyExports.Progress({ label = 'Core forwarded', duration = 5000, prop = { model = 'prop_one' } }, function() finished = true end, 'original_job')
    _G.GetInvokingResource = function() return nil end
    mockHandle.fire('onClientResourceStop', 'original_job')
    mockHandle.step()
    harness.assertFalse(legacyExports.isDoingSomething())
    harness.assertFalse(finished)
    harness.assertEqual(#deletedEntities, 1, 'owner stop deletes its networked prop')
end)

harness.test('ordinary callers cannot spoof a progress owner', function()
    reset()
    _G.GetInvokingResource = function() return 'real_consumer' end
    legacyExports.Progress({ label = 'Owned', duration = 5000 }, nil, 'spoofed_owner')
    _G.GetInvokingResource = function() return nil end
    mockHandle.fire('onClientResourceStop', 'spoofed_owner')
    harness.assertTrue(legacyExports.isDoingSomething())
    mockHandle.fire('onClientResourceStop', 'real_consumer')
    mockHandle.step()
    harness.assertFalse(legacyExports.isDoingSomething())
end)

harness.test('a queued legacy bar cannot start after its owner stops', function()
    reset()
    local createThread, invoking = CreateThread, GetInvokingResource
    local queued, callbacks = {}, 0
    _G.CreateThread = function(callback) queued[#queued + 1] = callback end
    _G.GetInvokingResource = function() return 'queued_owner' end
    legacyExports.Progress({ label = 'Queued', duration = 5000,
        controlDisables = { disableMovement = true, disableCombat = true },
        prop = { model = 'prop_one' } }, function() callbacks = callbacks + 1 end)
    _G.CreateThread, _G.GetInvokingResource = createThread, invoking
    harness.assertTrue(LocalPlayer.state.inv_busy)
    mockHandle.fire('onClientResourceStop', 'queued_owner')
    harness.assertFalse(LocalPlayer.state.inv_busy)
    harness.assertFalse(legacyExports.isDoingSomething())
    for _, callback in ipairs(queued) do createThread(callback) end
    mockHandle.step()
    harness.assertFalse(Kora.progressbar.isActive(), 'a stopped owner cannot acquire a new native bar')
    harness.assertFalse(legacyExports.isDoingSomething())
    harness.assertFalse(LocalPlayer.state.inv_busy)
    harness.assertEqual(#createdObjects, 0, 'a stopped owner cannot spawn props')
    harness.assertEqual(callbacks, 0, 'a stopped owner cannot receive stale callbacks')
    harness.assertTrue(next(disabledControls) == nil, 'no orphaned control lease is acquired')
end)

harness.test('cancelling a queued legacy bar settles without starting it', function()
    reset()
    local createThread = CreateThread
    local queued, finishes, cancelled = {}, 0, nil
    _G.CreateThread = function(callback) queued[#queued + 1] = callback end
    legacyExports.Progress({ label = 'Queued cancellation', duration = 5000,
        controlDisables = { disableMovement = true, disableCombat = true },
        prop = { model = 'prop_one' } }, function(value)
            finishes, cancelled = finishes + 1, value
        end)
    _G.CreateThread = createThread
    mockHandle.fire('progressbar:client:cancel')
    for _, callback in ipairs(queued) do createThread(callback) end
    mockHandle.step()
    harness.assertEqual(finishes, 1)
    harness.assertTrue(cancelled)
    harness.assertFalse(Kora.progressbar.isActive())
    harness.assertFalse(legacyExports.isDoingSomething())
    harness.assertFalse(LocalPlayer.state.inv_busy)
    harness.assertEqual(#createdObjects, 0)
    harness.assertTrue(next(disabledControls) == nil, 'cancelled queued actions never acquire controls')
end)

harness.report("progressbar")
