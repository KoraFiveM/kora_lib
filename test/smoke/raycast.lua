local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/util/shared.lua")

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
    local hit, coords, entity, normal = Kora.raycast.fromCoords({ x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 })

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
    local hit, coords, entity, normal = Kora.raycast.fromCoords({ x = 0, y = 0, z = 0 }, { x = 10, y = 0, z = 0 })

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

    local hit, coords, entity = Kora.raycast.fromCoords({ x = 0, y = 0, z = 0 }, { x = 10, y = 0, z = 0 })

    harness.assertTrue(hit, "the completed shape test should be returned")
    harness.assertEqual(coords.x, 5, "pending output coordinates must be ignored")
    harness.assertEqual(entity, 42, "pending output entity handles must be ignored")
end)

harness.test("fromCoords treats a shape test that never settles as a miss", function()
    pendingReads = math.huge

    local hit, coords, entity, normal = Kora.raycast.fromCoords(
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
    Kora.raycast.fromCoords({ x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 })

    harness.assertEqual(lastRayArgs[7], -1, "flags should default to -1 (everything)")
    harness.assertEqual(lastRayArgs[8], 1, "ignoreEntity should default to PlayerPedId()")
end)

harness.test("raycast rejects non-finite coordinates and camera distances before native calls", function()
    local started = startedRays
    harness.assertThrows(function()
        Kora.raycast.start({ x = 0, y = math.huge, z = 0 }, { x = 1, y = 0, z = 0 })
    end)
    harness.assertThrows(function() Kora.raycast.startFromCamera(math.huge) end)
    harness.assertThrows(function()
        Kora.raycast.start({ x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 }, false)
    end)
    harness.assertThrows(function()
        Kora.raycast.start({ x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 }, 1, 2.5)
    end)
    harness.assertThrows(function() Kora.raycast.await(false) end)
    harness.assertThrows(function() Kora.raycast.poll(1.5) end)
    harness.assertEqual(startedRays, started, "invalid inputs must not start a shape test")
end)

harness.test("fromCoords passes explicit flags and ignoreEntity through", function()
    nextResult = { hit = 0 }
    Kora.raycast.fromCoords({ x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 }, 16, 99)

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
    local hit, coords, entity = Kora.raycast.fromCamera(50.0)

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
    local hit, coords, entity = Kora.raycast.fromCam(999, 50.0)

    harness.assertTrue(hit, "fromCam should report the same hit as the underlying ray")
    harness.assertEqual(coords.x, 4, "fromCam should surface the hit coords")
    harness.assertEqual(entity, 7, "the struck entity handle should be returned")
end)

harness.test("start fires the shape test without reading a result", function()
    nextResult = { hit = 0 }
    resultReads = 0

    local handle = Kora.raycast.start({ x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 }, 26, 5)

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
    local first = Kora.raycast.startFromCamera(10.0, 511)
    local second = Kora.raycast.startFromCamera(10.0, 26)
    harness.assertTrue(first ~= second, "each started ray should get its own handle")

    pendingReads = 1
    local hit, coords, entity = Kora.raycast.await(first)
    harness.assertTrue(hit, "the first await should settle its ray")
    harness.assertEqual(entity, 11, "and report its entity")

    resultReads = 0
    local secondHit, secondCoords = Kora.raycast.await(second)
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
    local handle = Kora.raycast.start({ x = 0, y = 0, z = 0 }, { x = 5, y = 0, z = 0 })

    pendingReads = 1
    local settled, hit, coords, entity = Kora.raycast.poll(handle)
    harness.assertFalse(settled, "a pending shape test must report settled = false")
    harness.assertFalse(hit, "and must not claim a hit")
    harness.assertTrue(coords == nil and entity == nil, "pending output slots must never reach the caller")

    settled, hit, coords, entity = Kora.raycast.poll(handle)
    harness.assertTrue(settled, "the completed shape test should report settled = true")
    harness.assertTrue(hit, "and its hit")
    harness.assertEqual(coords.x, 3, "and its coords")
    harness.assertEqual(entity, 12, "and its entity handle")
end)

harness.test("poll reports a settled miss as settled, not pending", function()
    nextResult = { hit = 0 }
    local handle = Kora.raycast.start({ x = 0, y = 0, z = 0 }, { x = 5, y = 0, z = 0 })

    local settled, hit = Kora.raycast.poll(handle)
    harness.assertTrue(settled, "a completed miss is settled -- a caller must not poll it forever")
    harness.assertFalse(hit, "a miss reports hit = false")
end)

local acquiredLeases = 0
local releasedLeases = 0
local shownPrompts = 0
local hiddenPrompts = 0
local markerCalls = 0
local createdPreview
local removedPreview
local previewExists = false
local nativeRemovedPreview
local confirmAfterPolls = 1
local confirmPolls = 0
local cancelPressed = false
local rotateLeft = false

Kora.controls.acquire = function()
    acquiredLeases = acquiredLeases + 1
    return acquiredLeases
end
Kora.controls.release = function()
    releasedLeases = releasedLeases + 1
    return true
end
Kora.compat.acquireControls = function()
    acquiredLeases = acquiredLeases + 1
    return acquiredLeases
end
Kora.compat.releaseControlLease = function()
    releasedLeases = releasedLeases + 1
    return true
end
Kora.textui.show = function()
    shownPrompts = shownPrompts + 1
    return shownPrompts
end
Kora.textui.hide = function()
    hiddenPrompts = hiddenPrompts + 1
    return true
end
Kora.entities.create = function(model, coords, options)
    createdPreview = {
        entity = 99,
        model = model,
        coords = coords,
        heading = options.heading,
    }
    previewExists = true
    return 99
end
Kora.entities.remove = function(entity)
    removedPreview = entity
    previewExists = false
    return true
end

_G.DoesEntityExist = function(entity) return entity == 99 and previewExists end
_G.SetEntityAsMissionEntity = function() end
_G.DeleteEntity = function(entity)
    nativeRemovedPreview = entity
    previewExists = false
end
_G.DrawMarker = function() markerCalls = markerCalls + 1 end
_G.SetEntityCollision = function() end
_G.SetEntityAlpha = function() end
_G.SetEntityCoordsNoOffset = function() end
_G.SetEntityHeading = function() end
_G.GetFrameTime = function() return 0.1 end
_G.IsDisabledControlPressed = function(_, control)
    return rotateLeft and control == 174
end
_G.IsDisabledControlJustReleased = function(_, control)
    if control == 38 then
        confirmPolls = confirmPolls + 1
        return confirmPolls >= confirmAfterPolls
    end
    return control == 177 and cancelPressed
end

local function resetGrabberMocks()
    markerCalls = 0
    createdPreview = nil
    removedPreview = nil
    previewExists = false
    nativeRemovedPreview = nil
    confirmAfterPolls = 1
    confirmPolls = 0
    cancelPressed = false
    rotateLeft = false
end

harness.test("getCoords defaults to an orb and returns rounded coordinates", function()
    resetGrabberMocks()
    nextResult = {
        hit = 1,
        coords = { x = 1.234, y = -5.678, z = 9.876 },
        surfaceNormal = { x = 0, y = 0, z = 1 },
        entityHit = 0,
    }

    local result = Kora.raycast.getCoords()

    harness.assertEqual(result.coords.x, 1.23, "x should be rounded to two decimal places")
    harness.assertEqual(result.coords.y, -5.68, "negative values should be rounded to two decimal places")
    harness.assertEqual(result.coords.z, 9.88, "z should be rounded to two decimal places")
    harness.assertFalse(result.object, "orb mode should not report an object")
    harness.assertEqual(markerCalls, 1, "orb mode should draw its marker at the hit")
    harness.assertEqual(releasedLeases, acquiredLeases, "confirm should release its controls")
    harness.assertEqual(hiddenPrompts, shownPrompts, "confirm should hide its prompt")
end)

harness.test("getCoords rejects an explicit non-table options value before starting", function()
    resetGrabberMocks()
    local leases = acquiredLeases

    harness.assertThrows(function()
        Kora.raycast.getCoords(false)
    end)
    harness.assertEqual(acquiredLeases, leases, "invalid options must not acquire controls or start the grabber")
end)

harness.test("getCoords rejects non-finite preview model hashes before starting", function()
    resetGrabberMocks()
    local leases = acquiredLeases

    harness.assertThrows(function()
        Kora.raycast.getCoords({ type = "object", object = math.huge })
    end)
    harness.assertEqual(acquiredLeases, leases, "invalid model hashes must not acquire controls or create a preview")
end)

harness.test("getCoords uses a heading-only object preview and ignores it on later rays", function()
    resetGrabberMocks()
    confirmAfterPolls = 2
    rotateLeft = true
    nextResult = {
        hit = 1,
        coords = { x = 10, y = 20, z = 30 },
        surfaceNormal = { x = 0, y = 0, z = 1 },
        entityHit = 0,
    }

    local result = Kora.raycast.getCoords({ type = "object", object = "prop_bin_08" })

    harness.assertEqual(createdPreview.model, "prop_bin_08", "the requested preview model should be created")
    harness.assertEqual(lastRayArgs[8], 99, "later rays should ignore the preview instead of hitting it")
    harness.assertEqual(result.coords.w, 168, "only heading should change while rotate-left is held")
    harness.assertEqual(result.object, "prop_bin_08", "the result should identify the preview model")
    harness.assertEqual(removedPreview, 99, "confirm should remove the temporary preview")
    harness.assertFalse(previewExists, "confirm must not leave a preview entity alive")
    harness.assertEqual(nativeRemovedPreview, nil, "an already-removed preview must not be deleted again")
end)

harness.test("getCoords deletes its preview if the entity helper fails or leaves it alive", function()
    local remove = Kora.entities.remove
    for _, outcome in ipairs({ "false", "error", "still-alive" }) do
        resetGrabberMocks()
        nextResult = { hit = 1, coords = { x = 10, y = 20, z = 30 }, surfaceNormal = { x = 0, y = 0, z = 1 }, entityHit = 0 }
        Kora.entities.remove = function()
            if outcome == "error" then error("simulated removal failure") end
            return outcome == "still-alive"
        end
        local ok, result = pcall(Kora.raycast.getCoords, { type = "object", object = "prop_bin_08" })
        Kora.entities.remove = remove

        harness.assertTrue(ok, "preview fallback cleanup should preserve the coordinate result")
        harness.assertEqual(result.object, "prop_bin_08", "cleanup should preserve the selected model")
        harness.assertEqual(nativeRemovedPreview, 99, "the fallback must delete the resource-owned preview")
        harness.assertFalse(previewExists, "the preview must not survive fallback cleanup")
        harness.assertEqual(releasedLeases, acquiredLeases, "fallback cleanup must release controls")
        harness.assertEqual(hiddenPrompts, shownPrompts, "fallback cleanup must hide the prompt")
    end
end)

harness.test("getCoords cancels without coordinates when Backspace is released", function()
    resetGrabberMocks()
    confirmAfterPolls = math.huge
    cancelPressed = true
    nextResult = { hit = 0 }

    local result = Kora.raycast.getCoords()

    harness.assertTrue(result == nil, "cancel should return nil")
    harness.assertEqual(releasedLeases, acquiredLeases, "cancel should release its controls")
    harness.assertEqual(hiddenPrompts, shownPrompts, "cancel should hide its prompt")
end)

harness.test("getCoords cleans up and reports preview creation failures", function()
    resetGrabberMocks()
    nextResult = {
        hit = 1,
        coords = { x = 1, y = 2, z = 3 },
        surfaceNormal = { x = 0, y = 0, z = 1 },
        entityHit = 0,
    }
    local create = Kora.entities.create
    Kora.entities.create = function() return false, "model did not load" end

    local ok, err = pcall(Kora.raycast.getCoords, { type = "object", object = "missing_prop" })
    Kora.entities.create = create

    harness.assertFalse(ok, "a failed preview should reject the grabber")
    harness.assertTrue(tostring(err):find("model did not load", 1, true) ~= nil,
        "the entity creation error should reach the caller")
    harness.assertEqual(releasedLeases, acquiredLeases, "errors should release controls")
    harness.assertEqual(hiddenPrompts, shownPrompts, "errors should hide the prompt")
end)

harness.test("getCoords exits cleanly when its owning resource stops", function()
    resetGrabberMocks()
    confirmAfterPolls = math.huge
    nextResult = { hit = 0 }
    local wait = Wait
    _G.Wait = function()
        net.fire("onClientResourceStop", "kora_lib_test")
    end

    local result = Kora.raycast.getCoords()
    _G.Wait = wait

    harness.assertTrue(result == nil, "resource shutdown should cancel the grabber")
    harness.assertEqual(releasedLeases, acquiredLeases, "resource shutdown should release controls")
    harness.assertEqual(hiddenPrompts, shownPrompts, "resource shutdown should hide the prompt")
end)

harness.report("raycast")
