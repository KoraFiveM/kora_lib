local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

mocks.install()

local function vector3(x, y, z)
    return { x = x, y = y, z = z }
end

local cameraHandles = 0
local rendered
local restoredView

function _G.vector3(x, y, z) return vector3(x, y, z) end
function _G.CreateCamWithParams() cameraHandles = cameraHandles + 1 return cameraHandles end
function _G.DoesCamExist(handle) return handle > 0 end
function _G.DestroyCam() end
function _G.PointCamAtCoord() end
function _G.SetCamActive() end
function _G.RenderScriptCams(active) rendered = active end
function _G.GetFollowPedCamViewMode() return 1 end
function _G.SetFollowPedCamViewMode(viewMode) restoredView = viewMode end
function _G.IsControlJustPressed() return false end

dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/util/shared.lua")
local messages = {}
local instructionButtons
local instructionsHidden = false
Kora.nui = { send = function(action, data) messages[#messages + 1] = { action = action, data = data } end }
Kora.instructional = {
    show = function(buttons)
        instructionButtons = buttons
        return { hide = function() instructionsHidden = true end }
    end,
}
dofile(repoRoot .. "modules/camera/client.lua")

local cameras = {
    { label = "CAM 01", coords = vector3(10, 20, 30), target = vector3(10, 20, 28) },
    { label = "CAM 02", coords = vector3(40, 50, 60), target = vector3(40, 50, 58) },
}

harness.test("camera opens a fixed network and switches cameras", function()
    Kora.camera.open({ mode = "cctv", cameras = cameras, viewMode = 4 })
    harness.assertTrue(Kora.camera.isOpen(), "camera should be open")
    harness.assertEqual(rendered, true, "fixed cameras should render through script cams")
    harness.assertEqual(cameraHandles, 1, "the first camera should be created")
    harness.assertEqual(#instructionButtons, 3, "a camera network should show switch and exit instructions")
    Kora.camera.next()
    harness.assertEqual(cameraHandles, 2, "next should create the second camera")
    harness.assertEqual(messages[#messages].data.cameraLabel, "CAM 02", "next should update the HUD label")
end)

harness.test("camera close restores the player's view and rejects malformed cameras", function()
    Kora.camera.close("test")
    harness.assertFalse(Kora.camera.isOpen(), "camera should be closed")
    harness.assertEqual(rendered, false, "script cameras should be disabled")
    harness.assertEqual(restoredView, 1, "the previous follow-camera mode should be restored")
    harness.assertTrue(instructionsHidden, "closing should hide camera instructions")
    harness.assertThrows(function()
        Kora.camera.open({ mode = "cctv", cameras = { { coords = { x = 1, y = 2 } } } })
    end, "malformed camera coordinates should fail early")
end)

harness.test("operator mode keeps the native view and still shows the HUD", function()
    rendered = nil
    Kora.camera.open({ mode = "helicam", recording = true })
    harness.assertTrue(Kora.camera.isOpen(), "operator mode should open without fixed cameras")
    harness.assertEqual(rendered, nil, "operator mode should not replace the native camera")
    Kora.camera.close()
end)

harness.report("camera")
