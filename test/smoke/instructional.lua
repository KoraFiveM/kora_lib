local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir, repoRoot = scriptDir .. '../', scriptDir .. '../../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
local mocks = require('mocks')
local net = mocks.install()

local methods, strings, released = {}, {}, false
function _G.RequestScaleformMovie() return 1 end
function _G.HasScaleformMovieLoaded() return true end
function _G.SetScaleformMovieAsNoLongerNeeded() released = true end
function _G.BeginScaleformMovieMethod(_, method) methods[#methods + 1] = method end
function _G.EndScaleformMovieMethod() end
function _G.ScaleformMovieMethodAddParamInt() end
function _G.BeginTextCommandScaleformString() end
function _G.AddTextComponentSubstringPlayerName(value) strings[#strings + 1] = value end
function _G.EndTextCommandScaleformString() end
function _G.DrawScaleformMovieFullscreen() end
function _G.GetControlInstructionalButton(_, control) return 't_' .. tostring(control) end

dofile(repoRoot .. 'build/initiate.lua')
dofile(repoRoot .. 'compat/shared.lua')
dofile(repoRoot .. 'local/resources/client.lua')
dofile(repoRoot .. 'modules/instructional/client.lua')

harness.test('instructional buttons draw and replace their labels', function()
    local display = QB.instructional.show({ { control = 32, label = 'Movement: Camera' } })
    harness.assertTrue(display.isVisible())
    harness.assertEqual(methods[#methods], 'DRAW_INSTRUCTIONAL_BUTTONS')
    display.setButtons({ { command = 'freecam_grid', label = 'Movement: Grid' } })
    net.step()
    harness.assertEqual(strings[#strings], 'Movement: Grid')
    harness.assertTrue(display.hide())
    net.step()
    harness.assertTrue(released)
end)

harness.test('instructional displays validate and clean up with their owner', function()
    harness.assertThrows(function() QB.instructional.show({ { label = 'Bad' } }) end)
    local display = QB.instructional.show({ { control = 32, label = 'Move' } })
    net.fire('onClientResourceStop', 'qblib_test')
    harness.assertFalse(display.isVisible())
end)

harness.report('instructional')
