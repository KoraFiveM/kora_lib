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
_G.GetCamCoord = function(cam) return { x = 0, y = 0, z = 0 } end
_G.GetCamRot = function(cam, order) return { x = 0, y = 0, z = 0 } end

-- Configurable per-test: what the next StartShapeTestRay/GetShapeTestResult
-- pair reports, and the raw args StartShapeTestRay was called with (so a
-- test can assert on the flags/ignoreEntity actually passed through).
local nextResult = { hit = 0 }
local pendingReads = 0
local lastRayArgs
local startedRays, resultReads = 0, 0

_G.StartShapeTestRay = function(...)
    lastRayArgs = { ... }
    startedRays = startedRays + 1
    return startedRays
end

_G.GetShapeTestResult = function()
    resultReads = resultReads + 1
    if pendingReads > 0 then
        pendingReads = pendingReads - 1
        return 1, 1, { x = 999, y = 999, z = 999 }, { x = 9, y = 9, z = 9 }, 999999
    end
    if nextResult.hit == 0 then
        return 2, 0, nil, nil, nil
    end
    return 2, 1, nextResult.coords, nextResult.surfaceNormal, nextResult.entityHit
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

harness.test("fromCoords waits for a pending shape test before reading its entity handle", function()
    pendingReads = 2
    nextResult = {
        hit = 1,
        coords = { x = 5, y = 6, z = 7 },
        surfaceNormal = { x = 0, y = 0, z = 1 },
        entityHit = 42,
    }

    local hit, coords, entity = QB.raycast.fromCoords({ x = 0, y = 0, z = 0 }, { x = 10, y = 0, z = 0 })

    harness.assertTrue(hit, "the completed shape test should be returned")
    harness.assertEqual(coords.x, 5, "pending output coordinates must be ignored")
    harness.assertEqual(entity, 42, "pending output entity handles must be ignored")
end)

harness.test("fromCoords treats a shape test that never settles as a miss", function()
    pendingReads = math.huge

    local hit, coords, entity, normal = QB.raycast.fromCoords(
        { x = 0, y = 0, z = 0 },
        { x = 10, y = 0, z = 0 }
    )

    pendingReads = 0
    harness.assertFalse(hit, "a timed-out shape test must not expose pending output")
    harness.assertTrue(coords == nil and entity == nil and normal == nil,
        "a timed-out shape test must return no stale result fields")
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

harness.test("fromCam delegates to fromCoords using the given camera handle", function()
    nextResult = {
        hit = 1,
        coords = { x = 4, y = 5, z = 6 },
        surfaceNormal = { x = 1, y = 0, z = 0 },
        entityHit = 7,
    }
    local hit, coords, entity = QB.raycast.fromCam(999, 50.0)

    harness.assertTrue(hit, "fromCam should report the same hit as the underlying ray")
    harness.assertEqual(coords.x, 4, "fromCam should surface the hit coords")
    harness.assertEqual(entity, 7, "the struck entity handle should be returned")
end)

harness.test("start fires the shape test without reading a result", function()
    nextResult = { hit = 0 }
    resultReads = 0

    local handle = QB.raycast.start({ x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 }, 26, 5)

    harness.assertTrue(type(handle) == "number", "start should hand back the raw ray handle")
    harness.assertEqual(resultReads, 0, "start must not consume the result -- that is await/poll's job")
    harness.assertEqual(lastRayArgs[7], 26, "start should pass flags through like fromCoords")
    harness.assertEqual(lastRayArgs[8], 5, "start should pass ignoreEntity through like fromCoords")
end)

harness.test("two rays started together settle in one wait instead of two", function()
    nextResult = {
        hit = 1,
        coords = { x = 2, y = 0, z = 0 },
        surfaceNormal = { x = 0, y = 0, z = 1 },
        entityHit = 11,
    }

    -- Both rays are in flight before either is awaited, which is the whole
    -- point of the split API: the engine settles shape tests once per frame,
    -- so the second await finds its result already there.
    local first = QB.raycast.startFromCamera(10.0, 511)
    local second = QB.raycast.startFromCamera(10.0, 26)
    harness.assertTrue(first ~= second, "each started ray should get its own handle")

    pendingReads = 1
    local hit, coords, entity = QB.raycast.await(first)
    harness.assertTrue(hit, "the first await should settle its ray")
    harness.assertEqual(entity, 11, "and report its entity")

    resultReads = 0
    local secondHit, secondCoords = QB.raycast.await(second)
    harness.assertTrue(secondHit, "the second ray should settle too")
    harness.assertEqual(secondCoords.x, 2, "and report its coords")
    harness.assertEqual(resultReads, 1, "an already-settled ray must not yield another frame")
end)

harness.test("poll reports an unsettled ray without yielding, and never leaks pending output", function()
    nextResult = {
        hit = 1,
        coords = { x = 3, y = 0, z = 0 },
        surfaceNormal = { x = 0, y = 0, z = 1 },
        entityHit = 12,
    }
    local handle = QB.raycast.start({ x = 0, y = 0, z = 0 }, { x = 5, y = 0, z = 0 })

    pendingReads = 1
    local settled, hit, coords, entity = QB.raycast.poll(handle)
    harness.assertFalse(settled, "a pending shape test must report settled = false")
    harness.assertFalse(hit, "and must not claim a hit")
    harness.assertTrue(coords == nil and entity == nil, "pending output slots must never reach the caller")

    settled, hit, coords, entity = QB.raycast.poll(handle)
    harness.assertTrue(settled, "the completed shape test should report settled = true")
    harness.assertTrue(hit, "and its hit")
    harness.assertEqual(coords.x, 3, "and its coords")
    harness.assertEqual(entity, 12, "and its entity handle")
end)

harness.test("poll reports a settled miss as settled, not pending", function()
    nextResult = { hit = 0 }
    local handle = QB.raycast.start({ x = 0, y = 0, z = 0 }, { x = 5, y = 0, z = 0 })

    local settled, hit = QB.raycast.poll(handle)
    harness.assertTrue(settled, "a completed miss is settled -- a caller must not poll it forever")
    harness.assertFalse(hit, "a miss reports hit = false")
end)

harness.report("raycast")
