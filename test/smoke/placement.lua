local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")
local net = mocks.install()

local currentResource = "qblib_test"
_G.GetCurrentResourceName = function() return currentResource end

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/util/shared.lua")
dofile(repoRoot .. "modules/loops/shared.lua")

local PED_MODEL = joaat("a_m_y_beach_01")
local VEHICLE_MODEL = joaat("blista")
local OBJECT_MODEL = joaat("prop_bin_08")
local INVALID_MODEL = joaat("definitely_invalid")
local STUCK_MODEL = joaat("never_loads")
local modelKinds = {
    [PED_MODEL] = "ped",
    [VEHICLE_MODEL] = "vehicle",
    [OBJECT_MODEL] = "object",
    [STUCK_MODEL] = "object",
}

_G.IsModelValid = function(hash) return hash ~= INVALID_MODEL end
_G.IsModelAPed = function(hash) return modelKinds[hash] == "ped" end
_G.IsModelAVehicle = function(hash) return modelKinds[hash] == "vehicle" end
_G.HasModelLoaded = function(hash) return hash ~= STUCK_MODEL end
_G.RequestModel = function() end
_G.SetModelAsNoLongerNeeded = function() end

local entities = {}
local nextEntity = 100
local lastEntity = nil
local createdKinds = {}

local function spawn(kind, model, x, y, z, heading)
    nextEntity = nextEntity + 1
    lastEntity = nextEntity
    createdKinds[#createdKinds + 1] = kind
    entities[nextEntity] = {
        model = model,
        coords = { x = x, y = y, z = z },
        rotation = { x = 0.0, y = 0.0, z = heading or 0.0 },
        heading = (heading or 0.0) % 360.0,
    }
    return nextEntity
end

_G.CreatePed = function(_, model, x, y, z, heading) return spawn("ped", model, x, y, z, heading) end
_G.CreateVehicle = function(model, x, y, z, heading) return spawn("vehicle", model, x, y, z, heading) end
_G.CreateObjectNoOffset = function(model, x, y, z) return spawn("object", model, x, y, z, 0.0) end
_G.DoesEntityExist = function(entity) return entities[entity] ~= nil or entity == 1 end
_G.DeleteEntity = function(entity) entities[entity] = nil end
_G.SetEntityHeading = function(entity, heading)
    entities[entity].heading = heading % 360.0
    entities[entity].rotation.z = ((heading + 180.0) % 360.0) - 180.0
end
_G.GetEntityHeading = function(entity) return entities[entity].heading end
_G.GetEntityCoords = function(entity)
    local coords = entities[entity].coords
    return { x = coords.x, y = coords.y, z = coords.z }
end
_G.GetEntityRotation = function(entity)
    local rotation = entities[entity].rotation
    return { x = rotation.x, y = rotation.y, z = rotation.z }
end
_G.SetEntityCoordsNoOffset = function(entity, x, y, z)
    entities[entity].coords = { x = x, y = y, z = z }
end
_G.SetEntityRotation = function(entity, pitch, roll, yaw)
    entities[entity].rotation = { x = pitch, y = roll, z = yaw }
    entities[entity].heading = yaw % 360.0
end
_G.SetEntityCollision = function(entity, enabled)
    entities[entity].collision = enabled
end
_G.SetEntityAlpha = function(entity, alpha)
    entities[entity].alpha = alpha
end
_G.SetBlockingOfNonTemporaryEvents = function(entity, enabled)
    entities[entity].blocked = enabled
end
_G.SetEntityInvincible = function(entity, enabled)
    entities[entity].invincible = enabled
end
_G.NetworkHasControlOfEntity = function() return true end
_G.NetworkRequestControlOfEntity = function() end
_G.SetEntityAsMissionEntity = function() end

local frozen = {}
_G.PlayerPedId = function() return 1 end
_G.FreezeEntityPosition = function(entity, enabled) frozen[entity] = enabled end

local rayHit = true
local rayCoords = { x = 10.0, y = 20.0, z = 30.0 }
local gameplayCamRotation = { x = 0.0, y = 0.0, z = 0.0 }
_G.GetGameplayCamCoord = function() return { x = 0.0, y = 0.0, z = 10.0 } end
_G.GetGameplayCamRot = function()
    return { x = gameplayCamRotation.x, y = gameplayCamRotation.y, z = gameplayCamRotation.z }
end
_G.StartShapeTestRay = function() return 1 end
_G.GetShapeTestResult = function()
    return 2, rayHit and 1 or 0, rayCoords, { x = 0.0, y = 0.0, z = 1.0 }, 0
end

local cameras = {}
local nextCamera = 500
local destroyedCameras = {}
_G.CreateCamWithParams = function(_, x, y, z, pitch, roll, yaw)
    nextCamera = nextCamera + 1
    cameras[nextCamera] = {
        coords = { x = x, y = y, z = z },
        rotation = { x = pitch, y = roll, z = yaw },
    }
    return nextCamera
end
_G.DoesCamExist = function(cam) return cameras[cam] ~= nil end
_G.SetCamActive = function() end
_G.RenderScriptCams = function() end
_G.DestroyCam = function(cam)
    destroyedCameras[cam] = true
    cameras[cam] = nil
end
_G.GetGameplayCamFov = function() return 50.0 end
_G.SetCamCoord = function(cam, x, y, z) cameras[cam].coords = { x = x, y = y, z = z } end
_G.SetCamRot = function(cam, pitch, roll, yaw) cameras[cam].rotation = { x = pitch, y = roll, z = yaw } end
_G.GetCamCoord = function(cam) return cameras[cam].coords end
_G.GetCamRot = function(cam) return cameras[cam].rotation end

local disabledControls = {}
_G.DisableControlAction = function(group, control)
    disabledControls[("%d:%d"):format(group, control)] = true
end
_G.PlayerId = function() return 1 end
_G.DisablePlayerFiring = function() end
_G.GetDisabledControlNormal = function() return 0.0 end
_G.GetFrameTime = function() return 0.1 end
local shiftDown = false
_G.IsRawKeyDown = function() return shiftDown end
_G.IsControlPressed = function() return false end
_G.IsDisabledControlPressed = function() return false end

_G.RequestScaleformMovie = function() return 1 end
_G.HasScaleformMovieLoaded = function() return true end
_G.SetScaleformMovieAsNoLongerNeeded = function() end
_G.BeginScaleformMovieMethod = function() end
_G.EndScaleformMovieMethod = function() end
_G.ScaleformMovieMethodAddParamInt = function() end
_G.BeginTextCommandScaleformString = function() end
_G.AddTextComponentSubstringPlayerName = function() end
_G.EndTextCommandScaleformString = function() end
_G.DrawScaleformMovieFullscreen = function() end
_G.GetControlInstructionalButton = function() return 't_mock' end

local radarCalls = {}
local radarHidden = false
_G.IsRadarHidden = function() return radarHidden end
_G.DisplayRadar = function(visible)
    radarCalls[#radarCalls + 1] = visible
    radarHidden = not visible
end

dofile(repoRoot .. "modules/stream/client.lua")
dofile(repoRoot .. "local/resources/client.lua")
dofile(repoRoot .. "modules/controls/client.lua")
dofile(repoRoot .. "modules/keybind/client.lua")
dofile(repoRoot .. "modules/freecam/client.lua")
dofile(repoRoot .. "modules/instructional/client.lua")
dofile(repoRoot .. "modules/entities/client.lua")
dofile(repoRoot .. "modules/raycast/client.lua")

local nuiMessages = {}
local nuiRequests = {}
local nextNuiResponse = nil
QB.nui = {
    send = function(action, data) nuiMessages[#nuiMessages + 1] = { action = action, data = data } end,
    request = function(action, data)
        nuiRequests[#nuiRequests + 1] = { action = action, data = data }
        local p = promise.new()
        if nextNuiResponse ~= nil then p:resolve(nextNuiResponse) end
        return p
    end,
    withFocus = function(_, _, fn) return fn() end,
}

local notifications = {}
QB.notify = {
    send = function(payload) notifications[#notifications + 1] = payload end,
}

local zoneCreatorActive = false
QB.zones = {
    isCreatorActive = function() return zoneCreatorActive end,
}

dofile(repoRoot .. "modules/placement/client.lua")

local function press(name)
    local handler = net.commands["+qblib_placement_" .. name]
    harness.assertTrue(type(handler) == "function", "missing placement keybind: " .. name)
    handler()
end

local function release(name)
    local handler = net.commands["-qblib_placement_" .. name]
    if handler then handler() end
end

local function tap(name)
    press(name)
    release(name)
end

local function finishCameraTransition()
    net.step()
end

local function cancelPlacement()
    tap("cancel")
    finishCameraTransition()
end

local function assertNear(actual, expected, message)
    if math.abs(actual - expected) > 0.000001 then
        error(("%s (expected %.6f, got %.6f)"):format(message, expected, actual), 2)
    end
end

harness.test("generateSnippet returns a four-decimal Lua table with named Euler axes", function()
    local snippet = QB.placement.generateSnippet({
        model = "prop_o'hare",
        coords = { x = 1.23456, y = -2.0, z = 3.5 },
        heading = 270,
        rotation = { pitch = 1.25, roll = -2.5, yaw = -90 },
    })

    harness.assertTrue(snippet:find("model = 'prop_o\\'hare'", 1, true) ~= nil, "model names should be Lua-escaped")
    harness.assertTrue(snippet:find("vector3(1.2346, -2.0000, 3.5000)", 1, true) ~= nil, "coords should use four decimals")
    harness.assertTrue(snippet:find("heading = 270.0000", 1, true) ~= nil, "heading should be included")
    harness.assertTrue(snippet:find("pitch = 1.2500", 1, true) ~= nil, "pitch should be named")
    harness.assertTrue(snippet:find("roll = -2.5000", 1, true) ~= nil, "roll should be named")
    harness.assertTrue(snippet:find("yaw = -90.0000", 1, true) ~= nil, "yaw should be named")
end)

harness.test("generateSnippet rejects non-finite transform values", function()
    local valid = {
        model = OBJECT_MODEL,
        coords = { x = 1, y = 2, z = 3 },
        heading = 90,
        rotation = { pitch = 0, roll = 0, yaw = 0 },
    }
    valid.coords.x = math.huge
    harness.assertThrows(function() QB.placement.generateSnippet(valid) end,
        "infinite coordinates must not produce a snippet")

    valid.coords.x = 1
    valid.rotation.yaw = 0 / 0
    harness.assertThrows(function() QB.placement.generateSnippet(valid) end,
        "NaN rotations must not produce a snippet")
end)

harness.test("start rejects invalid models before spawning or taking controls", function()
    local before = #createdKinds
    local p = QB.placement.start(INVALID_MODEL)
    harness.assertEqual(p.state, "rejected", "invalid models should reject immediately")
    harness.assertEqual(#createdKinds, before, "invalid models must not spawn a preview")
    harness.assertFalse(QB.placement.isActive(), "a rejected start must not leak active state")
end)

harness.test("start rejects non-finite model hashes before spawning or taking controls", function()
    local before = #createdKinds
    local p = QB.placement.start(math.huge)
    harness.assertEqual(p.state, "rejected", "non-finite hashes should reject immediately")
    harness.assertEqual(#createdKinds, before, "non-finite hashes must not spawn a preview")
    harness.assertFalse(QB.placement.isActive(), "a rejected hash must not leak active state")
end)

harness.test("start rejects when placement is disabled", function()
    Config.placement.enabled = false
    local p = QB.placement.start(OBJECT_MODEL)
    Config.placement.enabled = true

    harness.assertEqual(p.state, "rejected", "disabled placement should reject immediately")
    harness.assertFalse(QB.placement.isActive(), "a disabled start must not leak active state")
end)

harness.test("start rejects when the initial camera raycast misses", function()
    rayHit = false
    local p = QB.placement.start(OBJECT_MODEL)
    rayHit = true

    harness.assertEqual(p.state, "rejected", "a surface hit is required")
    harness.assertFalse(QB.placement.isActive(), "a missed raycast must clean up immediately")
end)

harness.test("start propagates a model streaming timeout", function()
    local p = QB.placement.start(STUCK_MODEL)
    harness.assertEqual(p.state, "rejected", "unloadable models should reject")
    harness.assertFalse(QB.placement.isActive(), "a streaming timeout must not leak active state")
end)

harness.test("ped, vehicle, and object previews use the existing auto-detected entity creation", function()
    local cases = {
        { PED_MODEL, "ped" },
        { VEHICLE_MODEL, "vehicle" },
        { OBJECT_MODEL, "object" },
    }

    for _, case in ipairs(cases) do
        local p = QB.placement.start(case[1])
        harness.assertEqual(p.state, "pending", "placement should remain pending while editing")
        harness.assertEqual(createdKinds[#createdKinds], case[2], "entity type should be auto-detected")
        harness.assertEqual(entities[lastEntity].collision, false, "preview collision should be disabled")
        harness.assertEqual(entities[lastEntity].alpha, Config.placement.previewAlpha, "preview should be translucent")
        harness.assertEqual(entities[lastEntity].invincible, true, "preview should use the static preset")
        harness.assertTrue(QB.placement.isActive(), "placement should report active")
        cancelPlacement()
        harness.assertEqual(p.state, "resolved", "cancel should settle the placement")
        harness.assertEqual(p.value, nil, "cancel should resolve nil")
    end
end)

harness.test("a second placement and the zone creator are mutually exclusive", function()
    local first = QB.placement.start(OBJECT_MODEL)
    local second = QB.placement.start(OBJECT_MODEL)
    harness.assertEqual(second.state, "rejected", "a second placement should reject")
    cancelPlacement()
    harness.assertEqual(first.state, "resolved", "the first placement should still cancel normally")

    zoneCreatorActive = true
    local blocked = QB.placement.start(OBJECT_MODEL)
    zoneCreatorActive = false
    harness.assertEqual(blocked.state, "rejected", "placement must reject while the zone creator is active")
end)

harness.test("arrow and Page keys move relative to camera yaw with frame-time scaling", function()
    gameplayCamRotation.z = 0.0
    local p = QB.placement.start(OBJECT_MODEL)
    local entity = lastEntity

    press("forward")
    net.step()
    release("forward")
    assertNear(entities[entity].coords.y, rayCoords.y + 0.1, "Up should move forward along camera yaw")

    press("right")
    net.step()
    release("right")
    assertNear(entities[entity].coords.x, rayCoords.x + 0.1, "Right should move camera-relative right")

    press("up")
    net.step()
    release("up")
    assertNear(entities[entity].coords.z, rayCoords.z + 0.1, "Page Up should move world Z")

    shiftDown = true
    press("forward")
    net.step()
    release("forward")
    shiftDown = false
    assertNear(entities[entity].coords.y, rayCoords.y + 0.35, "Shift should multiply movement by 2.5")

    cancelPlacement()
    harness.assertEqual(p.state, "resolved", "movement test placement should cancel")
end)

harness.test("Tab cycles yaw, pitch, and roll while brackets rotate the active axis", function()
    gameplayCamRotation.z = 0.0
    local p = QB.placement.start(OBJECT_MODEL)
    local entity = lastEntity

    press("rotateRight")
    net.step()
    release("rotateRight")
    assertNear(entities[entity].rotation.z, 4.5, "] should increase yaw first")

    tap("cycle")
    press("rotateRight")
    net.step()
    release("rotateRight")
    assertNear(entities[entity].rotation.x, 4.5, "Tab should select pitch second")

    tap("cycle")
    press("rotateLeft")
    net.step()
    release("rotateLeft")
    assertNear(entities[entity].rotation.y, -4.5, "Tab should select roll third and [ should decrease it")

    cancelPlacement()
    harness.assertEqual(p.state, "resolved", "rotation test placement should cancel")
end)

harness.test("Keep Editing leaves the preview and promise pending", function()
    local p = QB.placement.start(OBJECT_MODEL)
    local entity = lastEntity
    nextNuiResponse = { confirmed = false }
    tap("confirm")
    nextNuiResponse = nil

    harness.assertEqual(p.state, "pending", "Keep Editing must not settle placement")
    harness.assertTrue(entities[entity] ~= nil, "Keep Editing must preserve the preview")
    cancelPlacement()
end)

harness.test("placement hides the radar once for its lifetime", function()
    radarCalls = {}
    radarHidden = false

    local p = QB.placement.start(OBJECT_MODEL)
    net.step()
    net.step()

    local hides = 0
    for _, visible in ipairs(radarCalls) do
        if not visible then hides = hides + 1 end
    end
    harness.assertEqual(hides, 1, "placement should not reapply the persistent radar state every frame")

    cancelPlacement()
    harness.assertEqual(p.state, "resolved", "radar test placement should cancel")
end)

harness.test("confirmation returns full transform data and deletes the preview", function()
    gameplayCamRotation.z = -90.0
    local p = QB.placement.start("prop_bin_08")
    local entity = lastEntity
    nextNuiResponse = { confirmed = true }
    tap("confirm")
    nextNuiResponse = nil

    harness.assertEqual(p.state, "resolved", "confirmation should resolve the placement")
    harness.assertEqual(p.value.model, "prop_bin_08", "result should retain the original model")
    harness.assertEqual(p.value.heading, 270.0, "heading should be read independently and normalized by the native")
    harness.assertEqual(p.value.rotation.yaw, -90.0, "Euler yaw should retain its signed value")
    harness.assertEqual(entities[entity], nil, "confirmed previews must be deleted")
    harness.assertEqual(nuiRequests[#nuiRequests].action, "placement:confirm", "confirmation should use the placement dialog")
    harness.assertTrue(nuiRequests[#nuiRequests].data.snippet:find("heading = 270.0000", 1, true) ~= nil,
        "the popup should receive copyable full transform data")

    finishCameraTransition()
    harness.assertFalse(QB.placement.isActive(), "placement should be inactive after camera teardown")
    harness.assertEqual(frozen[1], false, "the player should be unfrozen after camera teardown")
    harness.assertTrue(radarCalls[#radarCalls] == true, "the radar should be restored")
end)

harness.test("placement preserves a radar that was already hidden", function()
    radarHidden = true
    radarCalls = {}

    local p = QB.placement.start(OBJECT_MODEL)
    cancelPlacement()

    harness.assertEqual(p.state, "resolved", "cancel should still settle placement")
    harness.assertFalse(radarCalls[#radarCalls], "placement must not force an originally hidden radar on")
    radarHidden = false
end)

harness.test("an unexpectedly deleted preview rejects and cleans up", function()
    local p = QB.placement.start(OBJECT_MODEL)
    entities[lastEntity] = nil
    net.step()

    harness.assertEqual(p.state, "rejected", "a vanished preview should reject the session")
    finishCameraTransition()
    harness.assertFalse(QB.placement.isActive(), "crash cleanup should release placement state")
end)

harness.test("stopping the owning resource cancels and deletes its preview", function()
    currentResource = "placement_consumer"
    local p = QB.placement.start(OBJECT_MODEL)
    local entity = lastEntity
    currentResource = "qblib_test"

    net.fire("onClientResourceStop", "placement_consumer")
    harness.assertEqual(p.state, "resolved", "owner stop should cancel rather than strand the promise")
    harness.assertEqual(entities[entity], nil, "owner stop should delete the preview")
    local sentClose = false
    for _, message in ipairs(nuiMessages) do
        if message.action == "placement:closeConfirm" then sentClose = true end
    end
    harness.assertTrue(sentClose, "owner stop should close any focus-owning placement summary")
    finishCameraTransition()
end)

harness.test("qblib stop performs immediate camera, entity, HUD, radar, and freeze cleanup", function()
    local p = QB.placement.start(OBJECT_MODEL)
    local entity = lastEntity
    local activeCamera
    for cam in pairs(cameras) do activeCamera = cam end

    net.fire("onClientResourceStop", "qblib_test")

    harness.assertEqual(p.state, "rejected", "qblib stop should reject the interrupted session")
    harness.assertEqual(entities[entity], nil, "qblib stop should delete the preview immediately")
    harness.assertTrue(destroyedCameras[activeCamera] == true, "qblib stop should destroy the camera immediately")
    harness.assertEqual(frozen[1], false, "qblib stop should unfreeze the player")
    local clearedHud = false
    local closedConfirm = false
    for _, message in ipairs(nuiMessages) do
        if message.action == "placement:hud" and message.data == nil then clearedHud = true end
        if message.action == "placement:closeConfirm" then closedConfirm = true end
    end
    harness.assertTrue(clearedHud, "qblib stop should clear the HUD")
    harness.assertTrue(closedConfirm, "qblib stop should close the placement summary")
    harness.assertTrue(radarCalls[#radarCalls] == true, "qblib stop should restore the radar")
end)

harness.report("placement")
