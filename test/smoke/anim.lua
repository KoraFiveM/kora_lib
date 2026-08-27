local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/loops/shared.lua")

local ANIM_DICT = "test@anim"
local STUCK_DICT = "test@stuck" -- never reports as loaded, to exercise the failure path

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
    stopCalls[entity] = nil -- starting a new anim un-stops the entity, same as the real native
end

function _G.StopAnimTask(entity, dict, clip, blendOut)
    stopCalls[entity] = { dict = dict, clip = clip, blendOut = blendOut }
end

function _G.IsEntityPlayingAnim(entity, dict, clip)
    local call = playCalls[entity]
    return (call and call.dict == dict and call.clip == clip and stopCalls[entity] == nil) and 1 or 0
end

function _G.DoesEntityExist(e) return existingEntities[e] == true or existingProps[e] == true end

-- Prop/streaming natives, for attachProp.
function _G.IsModelValid() return true end
function _G.HasModelLoaded() return true end
function _G.RequestModel() end
function _G.SetModelAsNoLongerNeeded() end
function _G.GetEntityBoneIndexByName(entity, bone) return bone == "missing_bone" and -1 or 5 end

function _G.CreateObjectNoOffset()
    nextProp = nextProp + 1
    existingProps[nextProp] = true
    return nextProp
end

function _G.AttachEntityToEntity(prop, entity, boneIndex)
    propAttach[prop] = { entity = entity, boneIndex = boneIndex }
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
    local handle = QB.anim.play(1, ANIM_DICT, "clip_a")
    harness.assertTrue(handle ~= false, "expected a handle back")
    harness.assertEqual(playCalls[1].dict, ANIM_DICT, "should call TaskPlayAnim with the given dict")
    harness.assertEqual(playCalls[1].clip, "clip_a", "should call TaskPlayAnim with the given clip")
    harness.assertTrue(QB.anim.isPlaying(1), "isPlaying should report true right after play")
end)

harness.test("play applies option defaults", function()
    QB.anim.play(1, ANIM_DICT, "clip_a")
    harness.assertEqual(playCalls[1].blendIn, 8.0, "default blendInSpeed")
    harness.assertEqual(playCalls[1].blendOut, 8.0, "default blendOutSpeed")
    harness.assertEqual(playCalls[1].duration, -1, "default duration")
    harness.assertEqual(playCalls[1].flag, 1, "default flag")
end)

harness.test("stop ends the anim and releases the dict", function()
    QB.anim.play(1, ANIM_DICT, "clip_a")
    local stopped = QB.anim.stop(1)
    harness.assertTrue(stopped, "stop should report true when something was active")
    harness.assertFalse(QB.anim.isPlaying(1), "isPlaying should be false after stop")
    harness.assertFalse(loadedDicts[ANIM_DICT] == true, "the dict should be released on stop")
end)

harness.test("stop on an entity with nothing active reports false", function()
    harness.assertFalse(QB.anim.stop(2), "stopping an entity that never played anything should report false")
end)

harness.test("play propagates a streaming failure for a dict that never loads", function()
    local handle, err = QB.anim.play(1, STUCK_DICT, "clip_a")
    harness.assertFalse(handle, "play should fail when the dict never streams in")
    harness.assertTrue(err ~= nil, "a streaming failure should come with an error message")
end)

harness.test("anims are auto-stopped when their owning resource stops", function()
    _G.GetInvokingResource = function() return "some_other_resource" end
    QB.anim.play(1, ANIM_DICT, "clip_a")
    _G.GetInvokingResource = function() return nil end

    harness.assertTrue(QB.anim.isPlaying(1), "the anim should be playing before its resource stops")

    net.fire("onClientResourceStop", "some_other_resource")

    harness.assertFalse(QB.anim.isPlaying(1), "the anim should be stopped once its owning resource stops")
end)

harness.test("attachProp creates and attaches a prop at the resolved bone", function()
    local prop, err = QB.anim.attachProp(1, "test_prop", "test_bone", { x = 0.1, y = 0, z = 0 }, { x = 0, y = 0, z = 90 })
    harness.assertTrue(prop ~= false, "expected a real prop handle, got error: " .. tostring(err))
    harness.assertTrue(_G.DoesEntityExist(prop), "the prop should exist")
    harness.assertEqual(propAttach[prop].entity, 1, "the prop should be attached to the given entity")
    harness.assertEqual(propAttach[prop].boneIndex, 5, "the prop should be attached at the resolved bone index")
end)

harness.test("attachProp refuses an unknown bone", function()
    local prop, err = QB.anim.attachProp(1, "test_prop", "missing_bone")
    harness.assertFalse(prop, "attachProp should fail for a bone that doesn't resolve")
    harness.assertTrue(err ~= nil, "should explain the failure")
end)

harness.test("detachProp removes a tracked prop", function()
    local prop = QB.anim.attachProp(1, "test_prop", "test_bone")
    local ok = QB.anim.detachProp(prop)
    harness.assertTrue(ok, "detachProp should report success")
    harness.assertFalse(_G.DoesEntityExist(prop), "the prop should no longer exist")
end)

harness.test("detachProp refuses a prop this module never created", function()
    local foreignProp = 424242
    existingProps[foreignProp] = true

    local ok, err = QB.anim.detachProp(foreignProp)

    harness.assertFalse(ok, "an untracked prop must be refused")
    harness.assertTrue(_G.DoesEntityExist(foreignProp), "the foreign prop must still exist")

    existingProps[foreignProp] = nil
end)

harness.test('playScenario and clear use the task helpers', function()
    QB.anim.playScenario(1, 'WORLD_HUMAN_STAND_IMPATIENT')
    harness.assertEqual(scenarios[1], 'WORLD_HUMAN_STAND_IMPATIENT', 'scenario should start on the entity')
    QB.anim.clear(1, true)
    harness.assertEqual(clearedTasks[1], 'immediate', 'immediate clear should use ClearPedTasksImmediately')
end)

harness.report("anim")
