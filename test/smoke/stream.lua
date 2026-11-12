local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

mocks.install()

dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/loops/shared.lua")
dofile(repoRoot .. "modules/util/shared.lua")

local loadedModels = {}
local neverLoads = { [9999] = true }
local removedModels = {}

local invalidModelHash = joaat("totally-invalid")
function _G.IsModelValid(model) return model ~= invalidModelHash end
function _G.HasModelLoaded(model) return loadedModels[model] == true end
function _G.RequestModel(model) loadedModels[model] = not neverLoads[model] end
function _G.SetModelAsNoLongerNeeded(model) removedModels[model] = true end

local animDicts = { ["move_m@generic"] = true }
function _G.DoesAnimDictExist(dict) return animDicts[dict] == true end
function _G.RequestAnimDict() end
function _G.HasAnimDictLoaded() return true end
function _G.RemoveAnimDict() end

function _G.RequestNamedPtfxAsset() end
function _G.HasNamedPtfxAssetLoaded() return true end
function _G.RemoveNamedPtfxAsset() end

local removedAnimSets = {}
function _G.RequestAnimSet() end
function _G.HasAnimSetLoaded() return false end
function _G.RemoveAnimSet(animSet) removedAnimSets[animSet] = true end

function _G.RequestClipSet() end
function _G.HasClipSetLoaded() return true end
function _G.RemoveClipSet() end

function _G.RequestIpl() end
function _G.IsIplActive() return true end
function _G.RemoveIpl() end

function _G.RequestScaleformMovie() return 1 end
function _G.HasScaleformMovieLoaded() return true end
function _G.SetScaleformMovieAsNoLongerNeeded() end

function _G.IsWeaponValid() return true end
function _G.RequestWeaponAsset() end
function _G.HasWeaponAssetLoaded() return true end
function _G.RemoveWeaponAsset() end

local audioBankRequests = 0
local releasedAudioBanks = {}
function _G.RequestScriptAudioBank(bank)
    audioBankRequests = audioBankRequests + 1
    return bank ~= "never_loads"
end
function _G.ReleaseNamedScriptAudioBank(bank) releasedAudioBanks[bank] = true end

local requestedCollisionAt = nil
function _G.RequestCollisionAtCoord(x, y, z) requestedCollisionAt = { x = x, y = y, z = z } end
function _G.HasCollisionLoadedAroundEntity() return requestedCollisionAt ~= nil end
function _G.PlayerPedId() return 1 end

dofile(repoRoot .. "modules/stream/client.lua")

harness.test("loadModel converts a string model to a numeric hash", function()
    local hash = Kora.stream.loadModel("prop_test")
    harness.assertTrue(type(hash) == "number", "string models should resolve via joaat")
end)

harness.test("loadModel requests, waits, runs the callback, then releases the model", function()
    local seen
    local model = joaat("prop_test_2")
    local result = Kora.stream.loadModel(model, function(m) seen = m end)

    harness.assertEqual(result, model, "loadModel should return the model on success")
    harness.assertEqual(seen, model, "the callback should receive the loaded model")
    harness.assertTrue(removedModels[model], "the model should be released after the callback runs")
end)

harness.test("loadModel rejects a model IsModelValid refuses", function()
    harness.assertThrows(function()
        Kora.stream.loadModel("totally-invalid")
    end, "an invalid model should raise instead of silently failing")
end)

harness.test("streaming loaders reject malformed callbacks, options, and native inputs", function()
    harness.assertThrows(function() Kora.stream.loadModel(false) end)
    harness.assertThrows(function() Kora.stream.loadModel("prop_test", false) end)
    harness.assertThrows(function() Kora.stream.loadModel("prop_test", nil, false) end)
    harness.assertThrows(function() Kora.stream.loadAnimSet("move", nil, false) end)
    harness.assertThrows(function() Kora.stream.loadClipSet("move", nil, false) end)
    harness.assertThrows(function() Kora.stream.loadIpl("move", nil, false) end)
    harness.assertThrows(function() Kora.stream.loadScaleformMovie("move", nil, false) end)
    harness.assertThrows(function() Kora.stream.loadTextureDict("commonmenu", nil, "yes") end)
    harness.assertThrows(function() Kora.stream.loadWeaponAsset(false) end)
    harness.assertThrows(function() Kora.stream.loadWeaponAsset("weapon_pistol", nil, false) end)
    harness.assertThrows(function() Kora.stream.loadCollision({ x = 1, y = 2, z = 3 }, false) end)
    harness.assertThrows(function() Kora.stream.loadCollision({ x = 1, y = 2, z = 3 }, nil, false) end)
end)

harness.test("loadAnimSet supports caller cancellation while waiting", function()
    local polls = 0
    local result, err = Kora.stream.loadAnimSet("move", nil, {
        shouldContinue = function()
            polls = polls + 1
            return polls < 2
        end,
    })

    harness.assertFalse(result)
    harness.assertEqual(err, "cancelled")
    harness.assertTrue(removedAnimSets.move)
end)

harness.test("streaming loaders reject empty asset names before native requests", function()
    harness.assertThrows(function() Kora.stream.loadModel("") end)
    harness.assertThrows(function() Kora.stream.loadPtfx("") end)
    harness.assertThrows(function() Kora.stream.loadAnimDict("") end)
    harness.assertThrows(function() Kora.stream.loadAnimSet("") end)
    harness.assertThrows(function() Kora.stream.loadClipSet("") end)
    harness.assertThrows(function() Kora.stream.loadIpl("") end)
    harness.assertThrows(function() Kora.stream.loadScaleformMovie("") end)
    harness.assertThrows(function() Kora.stream.loadTextureDict("") end)
    harness.assertThrows(function() Kora.stream.loadAudioBank("") end)
    harness.assertThrows(function() Kora.stream.loadWeaponAsset("") end)
end)

harness.test("loadModel gives up and still cleans up when a model never streams in", function()
    local model, err = Kora.stream.loadModel(9999)
    harness.assertFalse(model, "should report failure for a model that never loads")
    harness.assertTrue(err ~= nil, "the failure should come with a reason")
    harness.assertTrue(removedModels[9999], "the stuck request should still be released")
end)

harness.test("loadModel supports caller cancellation while waiting", function()
    local polls = 0
    local model, err = Kora.stream.loadModel(9999, nil, {
        timeout = 5000,
        shouldContinue = function()
            polls = polls + 1
            return polls < 2
        end,
    })
    harness.assertFalse(model)
    harness.assertEqual(err, "cancelled")
    harness.assertTrue(removedModels[9999])
end)

harness.test("loadModel re-raises a callback error after cleaning up", function()
    local model = joaat("prop_test_3")
    harness.assertThrows(function()
        Kora.stream.loadModel(model, function() error("callback exploded") end)
    end, "a callback error should propagate to the caller")
    harness.assertTrue(removedModels[model], "cleanup should still happen even when the callback errors")
end)

harness.test("loadAnimDict validates the dict exists before requesting it", function()
    harness.assertThrows(function()
        Kora.stream.loadAnimDict("does-not-exist")
    end, "an unknown anim dict should raise")
end)

harness.test("loadAnimDict loads a known dict and runs its callback", function()
    local ran = false
    local result = Kora.stream.loadAnimDict("move_m@generic", function() ran = true end)
    harness.assertEqual(result, "move_m@generic", "should return the dict name")
    harness.assertTrue(ran, "the callback should run once the dict is loaded")
end)

harness.test("loadPtfx loads and runs its callback", function()
    local ran = false
    Kora.stream.loadPtfx("core", function() ran = true end)
    harness.assertTrue(ran, "the ptfx callback should run once the asset is loaded")
end)

harness.test("loadWeaponAsset converts a string weapon name and runs its callback", function()
    local seen
    Kora.stream.loadWeaponAsset("weapon_pistol", function(hash) seen = hash end)
    harness.assertTrue(type(seen) == "number", "the weapon name should resolve to a numeric hash")
end)

harness.test("loadAudioBank loads, runs its callback, then releases the bank", function()
    audioBankRequests = 0
    local ran = false

    local result = Kora.stream.loadAudioBank("DLC_TEST_SOUNDSET", function() ran = true end)

    harness.assertEqual(result, "DLC_TEST_SOUNDSET", "should return the bank name")
    harness.assertTrue(ran, "the callback should run once the bank is loaded")
    harness.assertTrue(audioBankRequests > 0, "RequestScriptAudioBank doubles as the poll predicate, so it must be called")
    harness.assertTrue(releasedAudioBanks["DLC_TEST_SOUNDSET"], "the bank should be released right after the callback")
end)

harness.test("loadAudioBank gives up on a bank that never reports ready", function()
    local result, err = Kora.stream.loadAudioBank("never_loads")
    harness.assertFalse(result, "a bank that never loads should report failure")
    harness.assertTrue(err ~= nil, "a failed load should come with an error message")
end)

harness.test("loadAudioBank rejects a non-string bank", function()
    harness.assertThrows(function() Kora.stream.loadAudioBank(123) end, "a numeric audio bank should raise")
end)

harness.test("loadCollision requests at the given coords and runs its callback", function()
    requestedCollisionAt = nil
    local ran = false

    local ok = Kora.stream.loadCollision({ x = 10, y = 20, z = 30 }, function() ran = true end)

    harness.assertTrue(ok, "collision should report success once loaded")
    harness.assertTrue(ran, "the callback should run once collision is ready")
    harness.assertEqual(requestedCollisionAt.x, 10, "the request should use the given coords")
    harness.assertEqual(requestedCollisionAt.z, 30, "the request should use the given coords")
end)

harness.test("loadCollision rejects malformed coords", function()
    harness.assertThrows(function() Kora.stream.loadCollision({ x = 1, y = 2 }) end, "coords missing z should raise")
    harness.assertThrows(function() Kora.stream.loadCollision({ x = math.huge, y = 2, z = 3 }) end,
        "non-finite collision coordinates should raise")
end)

harness.report("stream")
