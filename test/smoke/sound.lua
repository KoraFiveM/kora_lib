local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

-- QB.timers is a shared module that resolves its ownership registry by realm;
-- QB.sound uses it for the auto-release timer, so both realms have to agree.
function _G.IsDuplicityVersion() return false end

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")

-- --- audio natives, mocked --------------------------------------------------
local nextSoundId = 0
local freeIds = true
local played = {}
local stopped = {}
local released = {}
local releasedBanks = {}
local forcedSoundId

function _G.GetSoundId()
    if not freeIds then return -1 end
    if forcedSoundId then return forcedSoundId end
    nextSoundId = nextSoundId + 1
    return nextSoundId
end

function _G.StopSound(id) stopped[#stopped + 1] = id end
function _G.ReleaseSoundId(id) released[#released + 1] = id end
function _G.ReleaseNamedScriptAudioBank(bank) releasedBanks[#releasedBanks + 1] = bank end

function _G.PlaySoundFrontend(id, name, set, network)
    played[#played + 1] = { kind = "frontend", id = id, name = name, set = set, network = network }
end

function _G.PlaySoundFromCoord(id, name, x, y, z, set, network, range)
    played[#played + 1] = { kind = "coords", id = id, name = name, set = set, network = network,
                            x = x, y = y, z = z, range = range }
end

function _G.PlaySoundFromEntity(id, name, entity, set, network)
    played[#played + 1] = { kind = "entity", id = id, name = name, set = set, network = network, entity = entity }
end

function _G.DoesEntityExist(entity) return entity == 55 end

dofile(repoRoot .. "local/resources/client.lua")
dofile(repoRoot .. "modules/timers/shared.lua")

-- QB.stream.loadAudioBank is the only cross-module call QB.sound makes. Stubbed
-- rather than loading modules/stream/client.lua, which drags in a much larger
-- native surface for one boolean.
local requestedBanks = {}
local bankLoads = true
QB.stream.loadAudioBank = function(bank)
    requestedBanks[#requestedBanks + 1] = bank
    return bankLoads
end

dofile(repoRoot .. "modules/sound/client.lua")

local function lastPlayed() return played[#played] end

local function contains(list, value)
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end

harness.test("playFrontend allocates a real sound id and fires the native", function()
    local id = QB.sound.playFrontend("Lose_1st", "GTAO_FM_Events_Soundset")

    harness.assertTrue(type(id) == "number" and id > 0, "should return an allocated sound id")
    harness.assertEqual(lastPlayed().kind, "frontend", "should use the frontend native")
    harness.assertEqual(lastPlayed().id, id, "the native must receive the allocated id, not -1")
    harness.assertEqual(lastPlayed().name, "Lose_1st", "sound name should be forwarded")
    harness.assertEqual(lastPlayed().set, "GTAO_FM_Events_Soundset", "sound set should be forwarded")
    harness.assertEqual(lastPlayed().network, false, "network should default to false")
    harness.assertTrue(QB.sound.isLive(id), "the id should be held until stopped or released")

    QB.sound.stop(id)
end)

harness.test("playFromCoords forwards position and the configured default range", function()
    local id = QB.sound.playFromCoords({ x = 1, y = 2, z = 3 }, "Beep_Red", "DLC_HEIST_HACKING_SNAKE_SOUNDS")

    harness.assertEqual(lastPlayed().kind, "coords", "should use the positional native")
    harness.assertEqual(lastPlayed().x, 1.0, "x should be forwarded")
    harness.assertEqual(lastPlayed().y, 2.0, "y should be forwarded")
    harness.assertEqual(lastPlayed().z, 3.0, "z should be forwarded")
    harness.assertEqual(lastPlayed().range, math.floor(Config.sound.defaultRange), "range should fall back to config")

    QB.sound.stop(id)
end)

harness.test("playFromEntity refuses an entity that does not exist", function()
    local id = QB.sound.playFromEntity(55, "Beep_Red", "SET")
    harness.assertEqual(lastPlayed().entity, 55, "a live entity should be accepted")
    QB.sound.stop(id)

    harness.assertThrows(function() QB.sound.playFromEntity(999, "Beep_Red", "SET") end,
        "a missing entity should be refused")
end)

harness.test("stop releases the id and refuses a second stop", function()
    local id = QB.sound.playFrontend("Lose_1st", "SET")

    harness.assertTrue(QB.sound.stop(id), "the first stop should succeed")
    harness.assertTrue(contains(stopped, id), "StopSound must be called")
    harness.assertTrue(contains(released, id), "ReleaseSoundId must be called")
    harness.assertFalse(QB.sound.isLive(id), "the id should no longer be held")

    local ok, err = QB.sound.stop(id)
    harness.assertFalse(ok, "stopping twice should fail the second time")
    harness.assertEqual(err, "Sound id is not tracked by QB.sound.", "should explain the refusal")
end)

harness.test("stop refuses an id this module never allocated", function()
    local ok, err = QB.sound.stop(987654)
    harness.assertFalse(ok, "an untracked id must be refused, not stopped")
    harness.assertEqual(err, "Sound id is not tracked by QB.sound.", "should explain the refusal")
end)

harness.test("the id is auto-released once its release timer fires", function()
    local id = QB.sound.playFrontend("Lose_1st", "SET")
    harness.assertTrue(QB.sound.isLive(id), "sanity: live immediately after play")

    -- The auto-release is a QB.timers.setTimeout, so it is parked in a Wait()
    -- until the mock steps its coroutine.
    net.step()

    harness.assertFalse(QB.sound.isLive(id), "the id must be released without an explicit stop")
    harness.assertTrue(contains(released, id), "ReleaseSoundId must be called by the auto-release")
end)

harness.test("releaseAfter = 0 opts out of the auto-release", function()
    local id = QB.sound.playFrontend("Lose_1st", "SET", { releaseAfter = 0 })

    net.step()

    harness.assertTrue(QB.sound.isLive(id), "an opted-out sound must stay held for the caller to stop")
    QB.sound.stop(id)
end)

harness.test("options.bank is requested before the sound plays", function()
    local before = #played
    local id = QB.sound.playFrontend("Lose_1st", "SET", { bank = "DLC_MPHEIST/HEIST_FLEECA_BANK" })

    harness.assertEqual(requestedBanks[#requestedBanks], "DLC_MPHEIST/HEIST_FLEECA_BANK", "the bank should be requested")
    harness.assertEqual(#played, before + 1, "the sound should still play once the bank loads")
    QB.sound.stop(id)
end)

harness.test("shared audio banks are loaded once and released after the final sound", function()
    local bank = "DLC_SHARED_BANK"
    local loadCount = #requestedBanks
    local first = QB.sound.playFrontend("First", "SET", { bank = bank, releaseAfter = 0 })
    local second = QB.sound.playFrontend("Second", "SET", { bank = bank, releaseAfter = 0 })
    harness.assertEqual(#requestedBanks, loadCount + 1, "a retained bank should not be requested twice")

    QB.sound.stop(first)
    harness.assertFalse(contains(releasedBanks, bank), "the bank must remain while another sound uses it")
    QB.sound.stop(second)
    harness.assertTrue(contains(releasedBanks, bank), "the final sound should release its audio bank")
end)

harness.test("an old auto-release timer cannot stop a reused sound id", function()
    forcedSoundId = 777
    local old = QB.sound.playFrontend("Old", "SET")
    QB.sound.stop(old)
    local replacement = QB.sound.playFrontend("Replacement", "SET", { releaseAfter = 0 })

    net.step()
    harness.assertTrue(QB.sound.isLive(replacement), "the stale timer must not stop a newer claim with the same numeric id")
    QB.sound.stop(replacement)
    forcedSoundId = nil
end)

harness.test("a bank that fails to load aborts the play without allocating an id", function()
    bankLoads = false
    local before = #played

    local id, err = QB.sound.playFrontend("Lose_1st", "SET", { bank = "NOPE" })

    harness.assertFalse(id, "a failed bank load must not return a sound id")
    harness.assertTrue(err ~= nil and err:find("NOPE", 1, true) ~= nil, "the error should name the bank")
    harness.assertEqual(#played, before, "nothing should have been played")

    bankLoads = true
end)

harness.test("exhausting the sound id pool is reported, not silently played", function()
    freeIds = false
    local before = #played

    local id, err = QB.sound.playFrontend("Lose_1st", "SET")

    harness.assertFalse(id, "GetSoundId returning -1 must surface as a failure")
    harness.assertEqual(err, "No free sound id available.", "should explain why")
    harness.assertEqual(#played, before, "nothing should have been played")

    freeIds = true
end)

harness.test("sounds are stopped and released when their owning resource stops", function()
    _G.GetInvokingResource = function() return "some_other_resource" end
    local id = QB.sound.playFrontend("Lose_1st", "SET", { releaseAfter = 0 })
    _G.GetInvokingResource = function() return nil end

    harness.assertTrue(QB.sound.isLive(id), "sanity: live before the resource stops")

    net.fire("onClientResourceStop", "some_other_resource")

    harness.assertTrue(contains(stopped, id), "the sweep must stop the sound before releasing it")
    harness.assertTrue(contains(released, id), "the sweep must release the id")
    harness.assertFalse(QB.sound.isLive(id), "the sweep must clear the public live state")
end)

harness.test("an empty name or set is refused", function()
    harness.assertThrows(function() QB.sound.playFrontend("", "SET") end, "an empty name should be refused")
    harness.assertThrows(function() QB.sound.playFrontend("Lose_1st", "") end, "an empty set should be refused")
end)

harness.report("sound")
