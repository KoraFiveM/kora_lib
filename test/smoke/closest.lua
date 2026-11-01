local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/util/shared.lua")

-- Kora.closest is a thin wrapper over Kora.world.getClosestEntity -- stubbed out
-- here so these tests cover the wrapper's own argument-mapping and
-- ped-to-player-id logic, not Kora.world's entity-scanning (already covered by
-- test/smoke/world.lua).
local lastWorldCall
local worldReturn

local function stubWorld(entityType, coords, options)
    lastWorldCall = { entityType = entityType, coords = coords, options = options }
    return table.unpack(worldReturn or {})
end

Kora.world = { getClosestEntity = stubWorld }

local function reset()
    lastWorldCall = nil
    worldReturn = nil
end

_G.PlayerPedId = function() return 100 end

local activePlayers = { 0, 1 }
local playerPeds = { [0] = 100, [1] = 200 }
_G.GetActivePlayers = function() return activePlayers end
_G.GetPlayerPed = function(playerId) return playerPeds[playerId] end

Kora.cache = { get = function(key) return key == 'coords' and { x = 1, y = 2, z = 3 } or nil end }

dofile(repoRoot .. "modules/closest/client.lua")

harness.test("player resolves coords from Kora.cache and maps the returned ped back to a player id", function()
    reset()
    worldReturn = { 200, { x = 5, y = 5, z = 5 }, 12.5 }
    local result = Kora.closest.player(nil, 20.0)

    harness.assertEqual(lastWorldCall.entityType, "player", "should query the 'player' entity type")
    harness.assertEqual(lastWorldCall.coords.x, 1, "coords should default to Kora.cache.get('coords')")
    harness.assertEqual(lastWorldCall.options.radius, 20.0, "the given distance should become the search radius")
    harness.assertTrue(lastWorldCall.options.excludeEntities == nil,
        "Kora.world excludes the local ped by default without an extra exclusion table")
    harness.assertEqual(result.id, 1, "the returned ped should be mapped back to its player id")
    harness.assertEqual(result.distance, 12.5, "distance should pass through from Kora.world")
end)

harness.test("player defaults radius to 15.0 when distance is omitted", function()
    reset()
    worldReturn = { false }
    Kora.closest.player({ x = 0, y = 0, z = 0 })
    harness.assertEqual(lastWorldCall.options.radius, 15.0, "default radius should be 15.0")
end)

harness.test('closest helpers reject explicit invalid distances', function()
    harness.assertThrows(function()
        Kora.closest.vehicle({ x = 0, y = 0, z = 0 }, false)
    end)
    harness.assertThrows(function()
        Kora.closest.object({ x = 0, y = 0, z = 0 }, math.huge)
    end)
end)

harness.test('closest helpers reject invalid explicit coordinates before querying the world', function()
    reset()
    harness.assertThrows(function()
        Kora.closest.vehicle(false)
    end)
    harness.assertEqual(lastWorldCall, nil, 'invalid coordinates must not start a world query')
end)

harness.test("player returns {id=nil, distance=nil} when nothing is found", function()
    reset()
    worldReturn = { false }
    local result = Kora.closest.player({ x = 0, y = 0, z = 0 }, 10.0)
    harness.assertEqual(result.id, nil, "id should be nil when nothing matched")
    harness.assertEqual(result.distance, nil, "distance should be nil when nothing matched")
end)

harness.test("player discards a ped that no longer maps to an active player", function()
    reset()
    worldReturn = { 999, { x = 5, y = 5, z = 5 }, 12.5 }
    local result = Kora.closest.player({ x = 0, y = 0, z = 0 })
    harness.assertEqual(result.id, nil, "an unmapped ped is not a player result")
    harness.assertEqual(result.distance, nil, "an unmapped ped must not retain a stale distance")
end)

harness.test("vehicle/object query Kora.world by entity type without excluding any entity", function()
    reset()
    worldReturn = { 55, { x = 1, y = 1, z = 1 }, 3.2 }
    local vehicle = Kora.closest.vehicle({ x = 0, y = 0, z = 0 }, 25.0)
    harness.assertEqual(lastWorldCall.entityType, "vehicle", "vehicle should query the 'vehicle' entity type")
    harness.assertEqual(vehicle.id, 55, "vehicle id should pass through directly, unlike player")
    harness.assertEqual(vehicle.distance, 3.2, "distance should pass through")
    harness.assertTrue(lastWorldCall.options.excludeEntities == nil, "vehicle queries should not exclude any entity")

    reset()
    worldReturn = { 77, { x = 1, y = 1, z = 1 }, 5.0 }
    Kora.closest.object({ x = 0, y = 0, z = 0 }, 25.0)
    harness.assertEqual(lastWorldCall.entityType, "object", "object should query the 'object' entity type")
    harness.assertTrue(lastWorldCall.options.excludeEntities == nil, "object queries should not exclude any entity")
end)

harness.test("ped queries rely on Kora.world's default local-ped exclusion", function()
    reset()
    worldReturn = { 66, { x = 1, y = 1, z = 1 }, 4.1 }
    Kora.closest.ped({ x = 0, y = 0, z = 0 }, 25.0)
    harness.assertEqual(lastWorldCall.entityType, "ped", "ped should query the 'ped' entity type")
    harness.assertTrue(lastWorldCall.options.excludeEntities == nil,
        "a redundant exclusion table should not be allocated")
end)

-- client.lua and server.lua both define Kora.closest.player/vehicle/ped/object; dofile-ing
-- server.lua overwrites the client versions, safe since all client tests already ran.
Kora.world.getClosestEntity = stubWorld

local serverPlayers = { "10", "11" }
local serverPlayerPeds = { [10] = 300, [11] = 400, ["10"] = 300, ["11"] = 400 }
_G.GetPlayers = function() return serverPlayers end
_G.GetPlayerPed = function(src) return serverPlayerPeds[src] end
_G.GetEntityCoords = function() return { x = 9, y = 9, z = 9 } end

dofile(repoRoot .. "modules/closest/server.lua")

harness.test('[server] closest helpers reject explicit invalid distances', function()
    harness.assertThrows(function()
        Kora.closest.vehicle(10, { x = 0, y = 0, z = 0 }, false)
    end)
end)

harness.test('[server] closest helpers reject invalid sources and coordinates before querying the world', function()
    reset()
    harness.assertThrows(function()
        Kora.closest.vehicle('10', { x = 0, y = 0, z = 0 })
    end)
    harness.assertEqual(lastWorldCall, nil, 'invalid sources must not start a world query')
    harness.assertThrows(function()
        Kora.closest.vehicle(10, false)
    end)
    harness.assertEqual(lastWorldCall, nil, 'invalid coordinates must not start a world query')
end)

harness.test("[server] player resolves coords from the source's ped when omitted, excludes the source's own ped, and maps the returned ped to a player id", function()
    reset()
    worldReturn = { 400, { x = 2, y = 2, z = 2 }, 8.0 }
    local result = Kora.closest.player(10, nil, 30.0)

    harness.assertEqual(lastWorldCall.entityType, "player", "should query the 'player' entity type")
    harness.assertEqual(lastWorldCall.coords.x, 9, "coords should default to the source player's ped coords")
    harness.assertEqual(lastWorldCall.options.excludeEntities[1], 300, "the source's own ped should be excluded")
    harness.assertEqual(result.id, 11, "the returned ped should be mapped back to a numeric player id")
end)

harness.test("[server] vehicle/object query Kora.world without excluding any entity", function()
    reset()
    worldReturn = { 88, { x = 1, y = 1, z = 1 }, 6.0 }
    local vehicle = Kora.closest.vehicle(10, { x = 0, y = 0, z = 0 }, 25.0)
    harness.assertEqual(lastWorldCall.entityType, "vehicle", "vehicle should query the 'vehicle' entity type")
    harness.assertEqual(vehicle.id, 88, "vehicle id should pass through directly")
    harness.assertTrue(lastWorldCall.options.excludeEntities == nil, "vehicle queries should not exclude any entity")
end)

harness.test("[server] player discards a ped that no longer maps to a player", function()
    reset()
    worldReturn = { 999, { x = 2, y = 2, z = 2 }, 8.0 }
    local result = Kora.closest.player(10, { x = 0, y = 0, z = 0 })
    harness.assertEqual(result.id, nil, "an unmapped ped is not a player result")
    harness.assertEqual(result.distance, nil, "an unmapped ped must not retain a stale distance")
end)

harness.test("[server] ped queries exclude the source's own ped, same as player", function()
    reset()
    worldReturn = { 99, { x = 1, y = 1, z = 1 }, 7.0 }
    Kora.closest.ped(10, { x = 0, y = 0, z = 0 }, 25.0)
    harness.assertEqual(lastWorldCall.options.excludeEntities[1], 300, "ped queries should exclude the caller's own ped")
end)

harness.report("closest")
