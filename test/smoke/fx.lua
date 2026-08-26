local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/loops/shared.lua")

local DICT = "test_ptfx"
local STUCK_DICT = "test_stuck_ptfx" -- never reports as loaded

local loadedDicts = {}
local usedAssetNextCall = nil
local startCalls = {}
local stopCalls = {}
local screenStarts = {}
local screenStops = {}
local nextParticleId = 0

function _G.RequestNamedPtfxAsset(dict) loadedDicts[dict] = (dict ~= STUCK_DICT) end
function _G.HasNamedPtfxAssetLoaded(dict) return loadedDicts[dict] == true end
function _G.RemoveNamedPtfxAsset(dict) loadedDicts[dict] = nil end
function _G.UseParticleFxAssetNextCall(dict) usedAssetNextCall = dict end
function _G.GetEntityBoneIndexByName(entity, bone) return bone == "missing_bone" and -1 or 3 end

function _G.StartParticleFxLoopedOnEntity(name, entity)
    nextParticleId = nextParticleId + 1
    startCalls[#startCalls + 1] = { kind = "loopedOnEntity", name = name, entity = entity }
    return nextParticleId
end

function _G.StartParticleFxLoopedOnEntityBone(name, entity, ox, oy, oz, rx, ry, rz, boneIndex)
    nextParticleId = nextParticleId + 1
    startCalls[#startCalls + 1] = { kind = "loopedOnEntityBone", name = name, entity = entity, boneIndex = boneIndex }
    return nextParticleId
end

function _G.StartParticleFxLoopedAtCoord(name, x, y, z)
    nextParticleId = nextParticleId + 1
    startCalls[#startCalls + 1] = { kind = "loopedAtCoord", name = name, x = x, y = y, z = z }
    return nextParticleId
end

function _G.StartParticleFxNonLoopedOnEntity(name, entity)
    startCalls[#startCalls + 1] = { kind = "nonLoopedOnEntity", name = name, entity = entity }
end

function _G.StartParticleFxNonLoopedAtCoord(name, x, y, z)
    startCalls[#startCalls + 1] = { kind = "nonLoopedAtCoord", name = name, x = x, y = y, z = z }
end

function _G.StopParticleFxLooped(particleId)
    stopCalls[#stopCalls + 1] = particleId
end

function _G.StartScreenEffect(name, duration, looped)
    screenStarts[#screenStarts + 1] = { name = name, duration = duration, looped = looped }
end

function _G.StopScreenEffect(name)
    screenStops[#screenStops + 1] = name
end

dofile(repoRoot .. "modules/stream/client.lua")
dofile(repoRoot .. "local/resources/client.lua")
dofile(repoRoot .. "modules/fx/client.lua")

harness.test("playPtfx at coords fires a non-looped start by default", function()
    local handle = QB.fx.playPtfx({ dict = DICT, name = "fx_a", coords = { x = 1, y = 2, z = 3 } })
    harness.assertTrue(handle ~= false, "expected a handle back")
    harness.assertFalse(handle.looped, "should default to non-looped")
    harness.assertEqual(startCalls[#startCalls].kind, "nonLoopedAtCoord", "should call the non-looped at-coord native")
    harness.assertEqual(usedAssetNextCall, DICT, "should flag the dict via UseParticleFxAssetNextCall before starting")
end)

harness.test("playPtfx on an entity, looped, with a bone attaches via the bone-index native", function()
    local handle = QB.fx.playPtfx({ dict = DICT, name = "fx_b", entity = 1, bone = "spine", looped = true })
    harness.assertTrue(handle.looped, "should report looped")
    harness.assertTrue(handle.particleId ~= nil, "a looped effect should carry a particle id")
    harness.assertEqual(startCalls[#startCalls].kind, "loopedOnEntityBone", "should use the bone-index looped native")
    harness.assertEqual(startCalls[#startCalls].boneIndex, 3, "should resolve the bone name to its index")
end)

harness.test("playPtfx on an entity, looped, with no bone uses the plain entity native", function()
    QB.fx.playPtfx({ dict = DICT, name = "fx_c", entity = 1, looped = true })
    harness.assertEqual(startCalls[#startCalls].kind, "loopedOnEntity", "should use the plain on-entity looped native")
end)

harness.test("stop ends a looped effect", function()
    local handle = QB.fx.playPtfx({ dict = DICT, name = "fx_d", entity = 1, looped = true })
    local stopped = QB.fx.stop(handle)
    harness.assertTrue(stopped, "stop should report true for an active looped handle")
    harness.assertEqual(stopCalls[#stopCalls], handle.particleId, "should call StopParticleFxLooped with the right id")
end)

harness.test("stop is a no-op for a non-looped handle", function()
    local handle = QB.fx.playPtfx({ dict = DICT, name = "fx_e", coords = { x = 0, y = 0, z = 0 } })
    harness.assertFalse(QB.fx.stop(handle), "stopping a non-looped handle should report false")
end)

harness.test("playPtfx propagates a streaming failure for a dict that never loads", function()
    local handle, err = QB.fx.playPtfx({ dict = STUCK_DICT, name = "fx_f", coords = { x = 0, y = 0, z = 0 } })
    harness.assertFalse(handle, "playPtfx should fail when the dict never streams in")
    harness.assertTrue(err ~= nil, "a streaming failure should come with an error message")
end)

harness.test("looped effects are auto-stopped when their owning resource stops", function()
    _G.GetInvokingResource = function() return "some_other_resource" end
    local handle = QB.fx.playPtfx({ dict = DICT, name = "fx_g", entity = 1, looped = true })
    _G.GetInvokingResource = function() return nil end

    net.fire("onClientResourceStop", "some_other_resource")

    -- No direct "is stopped" query for a particle handle; assert via the stop call log instead.
    local found = false
    for _, id in ipairs(stopCalls) do if id == handle.particleId then found = true end end
    harness.assertTrue(found, "the looped effect should have been stopped when its resource stopped")
end)

harness.test("screenEffect starts and stops a named effect", function()
    local handle = QB.fx.screenEffect("TestEffect", 500, true)
    harness.assertEqual(screenStarts[#screenStarts].name, "TestEffect", "should start the named effect")
    harness.assertEqual(screenStarts[#screenStarts].duration, 500, "should pass through duration")
    harness.assertEqual(screenStarts[#screenStarts].looped, true, "should pass through looped")

    local stopped = QB.fx.stopScreenEffect(handle)
    harness.assertTrue(stopped, "stopScreenEffect should report true")
    harness.assertEqual(screenStops[#screenStops], "TestEffect", "should stop the same named effect")
end)

harness.report("fx")
