local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")

_G.PlayerPedId = function() return 1 end

local entityData = {}
local pools = { CPed = {}, CVehicle = {}, CObject = {} }
local activePlayers = {}
local playerPeds = {}

_G.GetGamePool = function(poolType) return pools[poolType] or {} end
_G.GetActivePlayers = function() return activePlayers end
_G.GetPlayerPed = function(playerId) return playerPeds[playerId] end
_G.DoesEntityExist = function(entity) return entityData[entity] ~= nil end
_G.GetEntityCoords = function(entity) return entityData[entity].coords end
_G.GetEntityModel = function(entity) return entityData[entity].model end
_G.IsEntityVisible = function(entity)
    local visible = entityData[entity].visible
    if visible == nil then return true end
    return visible
end

dofile(repoRoot .. "modules/world/client.lua")

-- Clears every mock entity/pool between tests so one test's fixtures can't
-- leak into the next.
local function reset()
    entityData = {}
    pools = { CPed = {}, CVehicle = {}, CObject = {} }
    activePlayers = {}
    playerPeds = {}
end

local function addToPool(poolType, entity, x, y, z, model, visible)
    entityData[entity] = { coords = { x = x, y = y, z = z }, model = model or 1, visible = visible }
    table.insert(pools[poolType], entity)
end

local ORIGIN = { x = 0, y = 0, z = 0 }

harness.test("getNearbyEntities sorts matches ascending by distance", function()
    reset()
    addToPool("CPed", 10, 5, 0, 0)
    addToPool("CPed", 11, 1, 0, 0)
    addToPool("CPed", 12, 3, 0, 0)

    local matches = QB.world.getNearbyEntities("ped", ORIGIN, 50.0)

    harness.assertEqual(#matches, 3, "all three peds should be within radius")
    harness.assertEqual(matches[1].entity, 11, "closest ped should be first")
    harness.assertEqual(matches[2].entity, 12, "second closest should be second")
    harness.assertEqual(matches[3].entity, 10, "farthest should be last")
end)

harness.test("getNearbyEntities excludes matches beyond radius", function()
    reset()
    addToPool("CPed", 10, 5, 0, 0)
    addToPool("CPed", 11, 100, 0, 0)

    local matches = QB.world.getNearbyEntities("ped", ORIGIN, 10.0)

    harness.assertEqual(#matches, 1, "only the in-range ped should match")
    harness.assertEqual(matches[1].entity, 10, "the in-range ped should be entity 10")
end)

harness.test("getNearbyEntities on an empty pool returns an empty list, not nil", function()
    reset()
    local matches = QB.world.getNearbyEntities("vehicle", ORIGIN, 50.0)

    harness.assertTrue(matches ~= nil, "result should never be nil")
    harness.assertEqual(#matches, 0, "an empty pool should produce zero matches")
end)

harness.test("models filter accepts numeric hashes", function()
    reset()
    addToPool("CObject", 20, 5, 0, 0, 111)
    addToPool("CObject", 21, 6, 0, 0, 222)

    local matches = QB.world.getNearbyEntities("object", ORIGIN, 50.0, { models = { 111 } })

    harness.assertEqual(#matches, 1, "only the matching model should be returned")
    harness.assertEqual(matches[1].entity, 20, "entity 20 has the requested model")
end)

harness.test("models filter accepts strings hashed with joaat", function()
    reset()
    addToPool("CObject", 20, 5, 0, 0, joaat("prop_bin_08"))
    addToPool("CObject", 21, 6, 0, 0, joaat("prop_bin_09"))

    local matches = QB.world.getNearbyEntities("object", ORIGIN, 50.0, { models = { "prop_bin_08" } })

    harness.assertEqual(#matches, 1, "string models should be joaat-hashed before comparing")
    harness.assertEqual(matches[1].entity, 20, "entity 20 has the requested model")
end)

harness.test("the local player's own ped is excluded from ped queries by default", function()
    reset()
    addToPool("CPed", 1, 0, 0, 0) -- PlayerPedId() == 1
    addToPool("CPed", 10, 5, 0, 0)

    local matches = QB.world.getNearbyEntities("ped", ORIGIN, 50.0)

    harness.assertEqual(#matches, 1, "the own ped should be excluded")
    harness.assertEqual(matches[1].entity, 10, "only the other ped should remain")
end)

harness.test("includeOwnPed includes the local player's own ped", function()
    reset()
    addToPool("CPed", 1, 0, 0, 0)
    addToPool("CPed", 10, 5, 0, 0)

    local matches = QB.world.getNearbyEntities("ped", ORIGIN, 50.0, { includeOwnPed = true })

    harness.assertEqual(#matches, 2, "the own ped should now be included")
end)

harness.test("excludeEntities filters explicit handles", function()
    reset()
    addToPool("CVehicle", 30, 5, 0, 0)
    addToPool("CVehicle", 31, 6, 0, 0)

    local matches = QB.world.getNearbyEntities("vehicle", ORIGIN, 50.0, { excludeEntities = { 30 } })

    harness.assertEqual(#matches, 1, "the excluded entity should be dropped")
    harness.assertEqual(matches[1].entity, 31, "only the non-excluded vehicle should remain")
end)

harness.test("invisible entities are excluded by default, included with includeInvisible", function()
    reset()
    addToPool("CObject", 40, 5, 0, 0, 1, false)
    addToPool("CObject", 41, 6, 0, 0, 1, true)

    local defaultMatches = QB.world.getNearbyEntities("object", ORIGIN, 50.0)
    harness.assertEqual(#defaultMatches, 1, "the invisible object should be excluded by default")
    harness.assertEqual(defaultMatches[1].entity, 41, "only the visible object should remain")

    local allMatches = QB.world.getNearbyEntities("object", ORIGIN, 50.0, { includeInvisible = true })
    harness.assertEqual(#allMatches, 2, "includeInvisible should include both objects")
end)

harness.test("predicate runs last and can reject a candidate that passed every other filter", function()
    reset()
    addToPool("CPed", 10, 5, 0, 0)
    addToPool("CPed", 11, 6, 0, 0)

    local seen = {}
    local matches = QB.world.getNearbyEntities("ped", ORIGIN, 50.0, {
        predicate = function(entity, coords, distance)
            table.insert(seen, entity)
            return entity == 10
        end,
    })

    harness.assertEqual(#matches, 1, "only the predicate-accepted entity should be returned")
    harness.assertEqual(matches[1].entity, 10, "entity 10 should be the surviving match")
    harness.assertEqual(#seen, 2, "the predicate should have run against every candidate that reached it")
end)

harness.test("getClosestEntity returns false when nothing is within range", function()
    reset()
    addToPool("CPed", 10, 100, 0, 0)

    local entity = QB.world.getClosestEntity("ped", ORIGIN, { radius = 10.0 })

    harness.assertFalse(entity, "no ped is within the given radius")
end)

harness.test("getClosestEntity returns the nearest entity, its coords, and its distance", function()
    reset()
    addToPool("CPed", 10, 5, 0, 0)
    addToPool("CPed", 11, 1, 0, 0)

    local entity, coords, distance = QB.world.getClosestEntity("ped", ORIGIN, { radius = 50.0 })

    harness.assertEqual(entity, 11, "the nearest ped should be returned")
    harness.assertEqual(coords.x, 1, "the returned coords should belong to the nearest ped")
    harness.assertEqual(distance, 1, "the returned distance should match the nearest ped")
end)

harness.test("getClosestEntity falls back to Config.world.defaultRadius when radius is omitted", function()
    reset()
    addToPool("CPed", 10, Config.world.defaultRadius + 10, 0, 0)
    addToPool("CPed", 11, Config.world.defaultRadius - 1, 0, 0)

    local entity = QB.world.getClosestEntity("ped", ORIGIN)

    harness.assertEqual(entity, 11, "only the ped within the default radius should match")
end)

harness.test("player type enumerates via GetActivePlayers/GetPlayerPed, not GetGamePool", function()
    reset()
    activePlayers = { 0, 1 }
    playerPeds = { [0] = 50, [1] = 51 }
    entityData[50] = { coords = { x = 5, y = 0, z = 0 }, model = 1 }
    entityData[51] = { coords = { x = 1, y = 0, z = 0 }, model = 1 }

    local matches = QB.world.getNearbyEntities("player", ORIGIN, 50.0)

    harness.assertEqual(#matches, 2, "both player peds should be returned")
    harness.assertEqual(matches[1].entity, 51, "the closer player ped should be first")
end)

harness.report("world")
