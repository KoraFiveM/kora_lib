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
_G.GetGameplayCamCoord = function() return { x = 0, y = 0, z = 0 } end
_G.GetGameplayCamRot = function() return { x = 0, y = 0, z = 0 } end

-- Configurable per-test: what the next StartShapeTestRay/GetShapeTestResult
-- pair reports, and the raw args StartShapeTestRay was called with (so a
-- test can assert on the flags/ignoreEntity actually passed through).
local nextResult = { hit = 0 }
local lastRayArgs

_G.StartShapeTestRay = function(...)
    lastRayArgs = { ... }
    return 1
end

_G.GetShapeTestResult = function()
    if nextResult.hit == 0 then
        return 0, 0, nil, nil, nil
    end
    return 0, 1, nextResult.coords, nextResult.surfaceNormal, nextResult.entityHit
end

dofile(repoRoot .. "modules/raycast/client.lua")

harness.test("fromCoords reports a miss as false with no other values", function()
    nextResult = { hit = 0 }
    local hit, coords, entity, normal = QB.raycast.fromCoords({ x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 })

    harness.assertFalse(hit, "a miss should report hit = false")
    harness.assertTrue(coords == nil, "coords should be nil on a miss")
    harness.assertTrue(entity == nil, "entity should be nil on a miss")
    harness.assertTrue(normal == nil, "normal should be nil on a miss")
end)

harness.test("fromCoords reports coords, entity, and normal on a hit", function()
    nextResult = {
        hit = 1,
        coords = { x = 5, y = 6, z = 7 },
        surfaceNormal = { x = 0, y = 0, z = 1 },
        entityHit = 42,
    }
    local hit, coords, entity, normal = QB.raycast.fromCoords({ x = 0, y = 0, z = 0 }, { x = 10, y = 0, z = 0 })

    harness.assertTrue(hit, "a hit should report hit = true")
    harness.assertEqual(coords.x, 5, "hit coords should come from GetShapeTestResult")
    harness.assertEqual(entity, 42, "the struck entity handle should be returned")
    harness.assertEqual(normal.z, 1, "the surface normal should be returned")
end)

harness.test("fromCoords defaults flags to -1 and ignoreEntity to PlayerPedId()", function()
    nextResult = { hit = 0 }
    QB.raycast.fromCoords({ x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 })

    harness.assertEqual(lastRayArgs[7], -1, "flags should default to -1 (everything)")
    harness.assertEqual(lastRayArgs[8], 1, "ignoreEntity should default to PlayerPedId()")
end)

harness.test("fromCoords passes explicit flags and ignoreEntity through", function()
    nextResult = { hit = 0 }
    QB.raycast.fromCoords({ x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 }, 16, 99)

    harness.assertEqual(lastRayArgs[7], 16, "an explicit flags value should be used as-is")
    harness.assertEqual(lastRayArgs[8], 99, "an explicit ignoreEntity value should be used as-is")
end)

harness.test("fromCamera delegates to fromCoords using the gameplay camera", function()
    nextResult = {
        hit = 1,
        coords = { x = 1, y = 2, z = 3 },
        surfaceNormal = { x = 0, y = 1, z = 0 },
        entityHit = 0,
    }
    local hit, coords, entity = QB.raycast.fromCamera(50.0)

    harness.assertTrue(hit, "fromCamera should report the same hit as the underlying ray")
    harness.assertEqual(coords.x, 1, "fromCamera should surface the hit coords")
    harness.assertEqual(entity, 0, "entity 0 (bare world geometry) should still be returned, not nil")
end)

harness.report("raycast")
