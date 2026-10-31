local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir, repoRoot = scriptDir .. '../', scriptDir .. '../../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
local mocks = require('mocks')
local net = mocks.install()

local input, frozen, rendered = {}, false, false
function _G.GetGameplayCamCoord() return { x = 0, y = 0, z = 0 } end
function _G.GetGameplayCamRot() return { x = 0, y = 0, z = 0 } end
function _G.GetGameplayCamFov() return 60.0 end
function _G.PlayerPedId() return 1 end
function _G.CreateCamWithParams() return 1 end
function _G.DoesCamExist() return true end
function _G.DestroyCam() end
function _G.SetCamActive() end
function _G.SetCamCoord() end
function _G.SetCamRot() end
function _G.RenderScriptCams(value) rendered = value end
function _G.FreezeEntityPosition(_, value) frozen = value end
function _G.GetDisabledControlNormal(_, control) return input[control] or 0.0 end
function _G.IsControlPressed() return false end
function _G.GetFrameTime() return 0.1 end
function _G.IsDisabledControlPressed(_, control) return input[control] == true end
function _G.DisableControlAction() end

dofile(repoRoot .. 'config.lua')
dofile(repoRoot .. 'build/initiate.lua')
dofile(repoRoot .. 'compat/shared.lua')
dofile(repoRoot .. 'modules/util/shared.lua')
dofile(repoRoot .. 'local/resources/client.lua')
dofile(repoRoot .. 'modules/controls/client.lua')
dofile(arg[1] or repoRoot .. 'modules/freecam/client.lua')

harness.test('freecam moves, rejects boundary steps, changes mode/focus, and restores state', function()
    input[31] = -1.0
    local cam = assert(Kora.freecam.start({ maxDistance = 1.0 }))
    harness.assertTrue(frozen)
    harness.assertTrue(rendered)
    harness.assertTrue(math.abs(cam.getCoords().y - 0.6) < 0.0001)
    net.step()
    harness.assertTrue(math.abs(cam.getCoords().y - 0.6) < 0.0001, 'a step outside maxDistance must be rejected')
    harness.assertEqual(cam.getCamera(), 1)
    harness.assertTrue(cam.setMovementMode('grid'))
    harness.assertEqual(cam.getMovementMode(), 'grid')
    harness.assertTrue(cam.setFocus({ x = 1, y = 1, z = 0 }))
    harness.assertTrue(cam.stop())
    harness.assertFalse(Kora.freecam.isActive())
    harness.assertFalse(frozen)
    input[31] = nil
end)

harness.test('freecam validates zones and cleans up when its owner stops', function()
    harness.assertThrows(function() Kora.freecam.start({ zone = {} }) end)
    local cam = assert(Kora.freecam.start({ zone = { contains = function() return true end } }))
    harness.assertFalse(Kora.freecam.start())
    net.fire('onClientResourceStop', 'kora_lib_test')
    harness.assertFalse(cam.isActive())
    harness.assertFalse(frozen)
end)

harness.test('focus can be cleared and reacquired without changing handle contracts', function()
    input[1], input[2] = 0.5, 0.2
    local cam = assert(Kora.freecam.start({
        focusCoords = { x = 0, y = 1, z = 0 }, lookSensitivity = 10,
    }))
    harness.assertEqual(cam.getRotation().yaw, 0)
    harness.assertEqual(cam.getRotation().pitch, 0)

    local focus = { x = 1, y = 0, z = 0 }
    harness.assertTrue(cam.setFocus(focus))
    focus.x, focus.y = 0, 1
    harness.assertThrows(function() cam.setFocus(false) end)
    harness.assertThrows(function() cam.setFocus({ x = 0, y = 1 }) end)
    harness.assertThrows(function() cam.setFocus({ x = 0 / 0, y = 1, z = 0 }) end)
    net.step()
    harness.assertEqual(cam.getRotation().yaw, 270, 'focus coordinates must remain a validated copy')
    harness.assertEqual(cam.getRotation().pitch, 0)

    local cleared = table.pack(cam.setFocus(nil))
    harness.assertEqual(cleared.n, 1)
    harness.assertEqual(cleared[1], true)
    harness.assertTrue(cam.setFocus(nil), 'clearing an already-unfocused active handle remains valid')
    net.step()
    harness.assertEqual(cam.getRotation().yaw, 265, 'clearing focus restores mouse-look calculation')
    harness.assertEqual(cam.getRotation().pitch, -2)

    harness.assertTrue(cam.setFocus({ x = 0, y = 1, z = 0 }))
    net.step()
    harness.assertEqual(cam.getRotation().yaw, 0, 'focus can be acquired again')
    harness.assertEqual(cam.getRotation().pitch, 0)
    harness.assertTrue(cam.stop())
    harness.assertEqual(cam.setFocus(nil), false)
    harness.assertEqual(cam.setFocus(false), false, 'inactive handles return before argument validation')
    input[1], input[2] = nil, nil
end)

harness.report('freecam')
