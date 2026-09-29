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
dofile(repoRoot .. 'modules/freecam/client.lua')

harness.test('freecam moves, rejects boundary steps, changes mode/focus, and restores state', function()
    input[31] = -1.0
    local cam = assert(QB.freecam.start({ maxDistance = 1.0 }))
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
    harness.assertFalse(QB.freecam.isActive())
    harness.assertFalse(frozen)
    input[31] = nil
end)

harness.test('freecam validates zones and cleans up when its owner stops', function()
    harness.assertThrows(function() QB.freecam.start({ zone = {} }) end)
    local cam = assert(QB.freecam.start({ zone = { contains = function() return true end } }))
    harness.assertFalse(QB.freecam.start())
    net.fire('onClientResourceStop', 'qblib_test')
    harness.assertFalse(cam.isActive())
    harness.assertFalse(frozen)
end)

harness.report('freecam')
