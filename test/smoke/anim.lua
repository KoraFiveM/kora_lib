local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/util/shared.lua")
dofile(repoRoot .. "modules/loops/shared.lua")

local ANIM_DICT = "test@anim"
local STUCK_DICT = "test@stuck"

local loadedDicts = {}
local playCalls = {}
local stopCalls = {}
local existingEntities = { [1] = true, [2] = true }
local existingProps = {}
local propAttach = {}
local scenarios = {}
local clearedTasks = {}
local nextProp = 100

function _G.DoesAnimDictExist() return true end
function _G.RequestAnimDict(dict) loadedDicts[dict] = (dict ~= STUCK_DICT) end
function _G.HasAnimDictLoaded(dict) return loadedDicts[dict] == true end
function _G.RemoveAnimDict(dict) loadedDicts[dict] = nil end

function _G.TaskPlayAnim(entity, dict, clip, blendIn, blendOut, duration, flag)
    playCalls[entity] = { dict = dict, clip = clip, blendIn = blendIn, blendOut = blendOut, duration = duration, flag = flag }
    stopCalls[entity] = nil
end

function _G.StopAnimTask(entity, dict, clip, blendOut)
    stopCalls[entity] = { dict = dict, clip = clip, blendOut = blendOut }
end

function _G.IsEntityPlayingAnim(entity, dict, clip)
    local call = playCalls[entity]
    return (call and call.dict == dict and call.clip == clip and stopCalls[entity] == nil) and true or false
end

function _G.DoesEntityExist(e) return existingEntities[e] == true or existingProps[e] == true end

function _G.IsModelValid() return true end
function _G.HasModelLoaded() return true end
function _G.RequestModel() end
function _G.SetModelAsNoLongerNeeded() end
function _G.GetEntityBoneIndexByName(entity, bone)
    if bone == "missing_bone" or bone == "PH_R_Hand" then return -1 end
    return 5
end
function _G.GetPedBoneIndex(entity, boneId) return boneId == 28422 and 77 or boneId == 999 and -1 or 9 end

function _G.CreateObjectNoOffset()
    nextProp = nextProp + 1
    existingProps[nextProp] = true
    return nextProp
end

function _G.IsEntityAPed(entity) return entity == 1 end
function _G.AttachEntityToEntity(prop, entity, boneIndex, ...)
    propAttach[prop] = { entity = entity, boneIndex = boneIndex, args = table.pack(...) }
end

function _G.DetachEntity(prop) propAttach[prop] = nil end
function _G.DeleteEntity(e) existingProps[e] = nil end
function _G.TaskStartScenarioInPlace(entity, scenario) scenarios[entity] = scenario end
function _G.ClearPedTasks(entity) clearedTasks[entity] = 'normal' end
function _G.ClearPedTasksImmediately(entity) clearedTasks[entity] = 'immediate' end

dofile(repoRoot .. "modules/stream/client.lua")
dofile(repoRoot .. "local/resources/client.lua")
dofile(repoRoot .. "modules/anim/client.lua")

harness.test("play starts an anim and tracks it as playing", function()
    local handle = Kora.anim.play(1, ANIM_DICT, "clip_a")
    harness.assertTrue(handle ~= false, "expected a handle back")
    harness.assertEqual(playCalls[1].dict, ANIM_DICT, "should call TaskPlayAnim with the given dict")
    harness.assertEqual(playCalls[1].clip, "clip_a", "should call TaskPlayAnim with the given clip")
    harness.assertTrue(Kora.anim.isPlaying(1), "isPlaying should report true right after play")
end)

harness.test("play applies option defaults", function()
    Kora.anim.play(1, ANIM_DICT, "clip_a")
    harness.assertEqual(playCalls[1].blendIn, 8.0, "default blendInSpeed")
    harness.assertEqual(playCalls[1].blendOut, 8.0, "default blendOutSpeed")
    harness.assertEqual(playCalls[1].duration, -1, "default duration")
    harness.assertEqual(playCalls[1].flag, 1, "default flag")
end)

harness.test("play rejects non-finite animation durations before starting", function()
    local previous = playCalls[1]
    harness.assertThrows(function()
        Kora.anim.play(1, ANIM_DICT, "clip_a", { duration = math.huge })
    end, "an infinite duration should be rejected")
    harness.assertThrows(function()
        Kora.anim.play(1, ANIM_DICT, "clip_a", { duration = 1.5 })
    end, "a fractional duration should be rejected")
    harness.assertThrows(function()
        Kora.anim.play(1, ANIM_DICT, "clip_a", { duration = -2 })
    end, "only -1 may use the native indefinite-duration sentinel")
    harness.assertThrows(function()
        Kora.anim.play(1, ANIM_DICT, "clip_a", { onFinish = true })
    end, "an invalid finish callback should fail before scheduling a cleanup thread")
    harness.assertThrows(function()
        Kora.anim.play(1, ANIM_DICT, "clip_a", { flag = false })
    end, "a false animation flag must not default")
    harness.assertThrows(function()
        Kora.anim.play(1, ANIM_DICT, "clip_a", { blendInSpeed = math.huge })
    end, "non-finite blend speeds must fail before streaming")
    harness.assertThrows(function()
        Kora.anim.play(1, ANIM_DICT, "clip_a", { lockX = 'yes' })
    end, "axis locks must be booleans")
    harness.assertThrows(function()
        Kora.anim.play(1, ANIM_DICT, "clip_a", true)
    end, "options must be a table")
    harness.assertEqual(playCalls[1], previous, "invalid durations must not start an animation")
end)

harness.test("stop ends the anim and releases the dict", function()
    Kora.anim.play(1, ANIM_DICT, "clip_a")
    local stopped = Kora.anim.stop(1)
    harness.assertTrue(stopped, "stop should report true when something was active")
    harness.assertFalse(Kora.anim.isPlaying(1), "isPlaying should be false after stop")
    harness.assertFalse(loadedDicts[ANIM_DICT] == true, "the dict should be released on stop")
end)

harness.test('stop rejects an invalid blend-out speed without releasing the animation', function()
    Kora.anim.play(1, ANIM_DICT, 'clip_a')

    harness.assertThrows(function() Kora.anim.stop(1, math.huge) end)
    harness.assertTrue(Kora.anim.isPlaying(1), 'invalid native input must not clear tracked animation state')

    Kora.anim.stop(1)
end)

harness.test("stop on an entity with nothing active reports false", function()
    harness.assertFalse(Kora.anim.stop(2), "stopping an entity that never played anything should report false")
end)

harness.test("play propagates a streaming failure for a dict that never loads", function()
    local handle, err = Kora.anim.play(1, STUCK_DICT, "clip_a")
    harness.assertFalse(handle, "play should fail when the dict never streams in")
    harness.assertTrue(err ~= nil, "a streaming failure should come with an error message")
end)

harness.test("anims are auto-stopped when their owning resource stops", function()
    _G.GetInvokingResource = function() return "some_other_resource" end
    Kora.anim.play(1, ANIM_DICT, "clip_a")
    _G.GetInvokingResource = function() return nil end

    harness.assertTrue(Kora.anim.isPlaying(1), "the anim should be playing before its resource stops")

    net.fire("onClientResourceStop", "some_other_resource")

    harness.assertFalse(Kora.anim.isPlaying(1), "the anim should be stopped once its owning resource stops")
end)

harness.test('an onFinish error does not prevent delayed animation cleanup', function()
    local handle = Kora.anim.play(1, ANIM_DICT, 'clip_a', {
        duration = 100,
        onFinish = function() error('onFinish failed') end,
    })

    harness.assertTrue(handle ~= false)
    net.step()
    harness.assertFalse(Kora.anim.isPlaying(1), 'the animation must stop before an onFinish callback runs')
end)

harness.test("attachProp creates and attaches a prop at the resolved bone", function()
    local prop, err = Kora.anim.attachProp(1, "test_prop", "test_bone", { x = 0.1, y = 0, z = 0 }, { x = 0, y = 0, z = 90 })
    harness.assertTrue(prop ~= false, "expected a real prop handle, got error: " .. tostring(err))
    harness.assertTrue(_G.DoesEntityExist(prop), "the prop should exist")
    harness.assertEqual(propAttach[prop].entity, 1, "the prop should be attached to the given entity")
    harness.assertEqual(propAttach[prop].boneIndex, 5, "the prop should be attached at the resolved bone index")
end)

harness.test("attachProp forwards the complete native signature for ped and object targets", function()
    for _, entity in ipairs({ 1, 2 }) do
        local prop = Kora.anim.attachProp(entity, "test_prop", "test_bone",
            { x = 1, y = 2, z = 3 }, { x = 4, y = 5, z = 6 },
            { softPin = true, collision = true, vertexIndex = 2, fixedRot = false })
        local args = propAttach[prop].args
        harness.assertEqual(args.n, 12, "native needs twelve arguments after the bone index")
        for index = 1, 6 do harness.assertEqual(args[index], index) end
        harness.assertEqual(args[7], false, "p9")
        harness.assertEqual(args[8], true, "soft pinning")
        harness.assertEqual(args[9], true, "collision")
        harness.assertEqual(args[10], entity == 1, "ped flag")
        harness.assertEqual(args[11], 2, "rotation order")
        harness.assertEqual(args[12], false, "rotation synchronization")
        Kora.anim.detachProp(prop)
    end
end)

harness.test("attachProp takes a ped bone id, and falls back to it for a known ped bone name", function()
    local prop, err = Kora.anim.attachProp(1, "test_prop", 57005)
    harness.assertTrue(prop ~= false, "a numeric ped bone id should attach: " .. tostring(err))
    harness.assertEqual(propAttach[prop].boneIndex, 9, "numeric ids resolve through GetPedBoneIndex")
    Kora.anim.detachProp(prop)

    prop, err = Kora.anim.attachProp(1, "test_prop", "PH_R_Hand")
    harness.assertTrue(prop ~= false, "PH_R_Hand should fall back to its ped bone id: " .. tostring(err))
    harness.assertEqual(propAttach[prop].boneIndex, 77, "the fallback uses GetPedBoneIndex(ped, 28422)")
    Kora.anim.detachProp(prop)

    prop, err = Kora.anim.attachProp(2, "test_prop", 57005)
    harness.assertFalse(prop, "a ped bone id on a non-ped entity must fail")
    harness.assertTrue(err ~= nil, "should explain the failure")

    prop = Kora.anim.attachProp(1, "test_prop", 999)
    harness.assertFalse(prop, "an unknown ped bone id must fail")
    harness.assertThrows(function() Kora.anim.attachProp(1, "test_prop", 1.5) end)
    harness.assertThrows(function() Kora.anim.attachProp(1, "test_prop", -1) end)
end)

harness.test("attachProp refuses an unknown bone", function()
    local prop, err = Kora.anim.attachProp(1, "test_prop", "missing_bone")
    harness.assertFalse(prop, "attachProp should fail for a bone that doesn't resolve")
    harness.assertTrue(err ~= nil, "should explain the failure")
end)

harness.test('attachProp rejects malformed transforms and options before streaming', function()
    harness.assertThrows(function()
        Kora.anim.attachProp(1, 'test_prop', 'test_bone', false)
    end)
    harness.assertThrows(function()
        Kora.anim.attachProp(1, 'test_prop', 'test_bone', nil, { x = 0, y = math.huge, z = 0 })
    end)
    harness.assertThrows(function()
        Kora.anim.attachProp(1, 'test_prop', 'test_bone', nil, nil, { collision = 'yes' })
    end)
    harness.assertThrows(function()
        Kora.anim.attachProp(1, 'test_prop', 'test_bone', nil, nil, { vertexIndex = 6 })
    end)
end)

harness.test("detachProp removes a tracked prop", function()
    local prop = Kora.anim.attachProp(1, "test_prop", "test_bone")
    local ok = Kora.anim.detachProp(prop)
    harness.assertTrue(ok, "detachProp should report success")
    harness.assertFalse(_G.DoesEntityExist(prop), "the prop should no longer exist")
end)

harness.test("detachProp refuses a prop this module never created", function()
    local foreignProp = 424242
    existingProps[foreignProp] = true

    local ok, err = Kora.anim.detachProp(foreignProp)

    harness.assertFalse(ok, "an untracked prop must be refused")
    harness.assertTrue(_G.DoesEntityExist(foreignProp), "the foreign prop must still exist")

    existingProps[foreignProp] = nil
end)

harness.test("foreign resources cannot stop or detach tracked animation state", function()
    _G.GetInvokingResource = function() return "anim_owner" end
    Kora.anim.play(1, ANIM_DICT, "clip_a")
    local prop = Kora.anim.attachProp(1, "test_prop", "test_bone")

    _G.GetInvokingResource = function() return "other_resource" end
    local replacement, replacementReason = Kora.anim.play(1, ANIM_DICT, "clip_b")
    harness.assertFalse(replacement, "another resource must not replace a tracked animation")
    harness.assertTrue(replacementReason ~= nil, "foreign replacement should explain why it was refused")
    harness.assertFalse(Kora.anim.stop(1), "another resource must not stop a tracked animation")
    local detached, reason = Kora.anim.detachProp(prop)
    harness.assertFalse(detached, "another resource must not detach a tracked prop")
    harness.assertTrue(reason ~= nil, "foreign prop removal should explain why it was refused")
    harness.assertTrue(Kora.anim.isPlaying(1), "the foreign stop must leave the animation active")
    harness.assertTrue(_G.DoesEntityExist(prop), "the foreign detach must leave the prop intact")

    _G.GetInvokingResource = function() return "anim_owner" end
    harness.assertTrue(Kora.anim.stop(1), "the owner should still stop its animation")
    harness.assertTrue(Kora.anim.detachProp(prop), "the owner should still detach its prop")
    _G.GetInvokingResource = function() return nil end
end)

harness.test('playScenario and clear use the task helpers', function()
    Kora.anim.playScenario(1, 'WORLD_HUMAN_STAND_IMPATIENT')
    harness.assertEqual(scenarios[1], 'WORLD_HUMAN_STAND_IMPATIENT', 'scenario should start on the entity')
    Kora.anim.clear(1, true)
    harness.assertEqual(clearedTasks[1], 'immediate', 'immediate clear should use ClearPedTasksImmediately')
end)

harness.report("anim")
