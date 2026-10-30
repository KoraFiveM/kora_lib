local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir, repoRoot = scriptDir .. '../', scriptDir .. '../../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
local mocks = require('mocks')
local net = mocks.install()

local drawThread
local createThread = CreateThread
function _G.CreateThread(callback)
    createThread(function()
        drawThread = coroutine.running()
        callback()
    end)
end

local methods, strings, slots, draws, released = {}, {}, {}, 0, false
function _G.RequestScaleformMovie() return 1 end
function _G.HasScaleformMovieLoaded() return true end
function _G.SetScaleformMovieAsNoLongerNeeded() released = true end
function _G.BeginScaleformMovieMethod(_, method) methods[#methods + 1] = method end
function _G.EndScaleformMovieMethod() end
function _G.ScaleformMovieMethodAddParamInt(value) slots[#slots + 1] = value end
function _G.BeginTextCommandScaleformString() end
function _G.AddTextComponentSubstringPlayerName(value) strings[#strings + 1] = value end
function _G.EndTextCommandScaleformString() end
function _G.DrawScaleformMovieFullscreen() draws = draws + 1 end
function _G.GetControlInstructionalButton(_, control) return 't_' .. tostring(control) end

dofile(repoRoot .. 'build/initiate.lua')
dofile(repoRoot .. 'compat/shared.lua')
dofile(repoRoot .. 'local/resources/client.lua')
dofile(arg[1] or repoRoot .. 'modules/instructional/client.lua')

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
    net.fire('onClientResourceStop', 'kora_lib_test')
    harness.assertFalse(display.isVisible())
end)

harness.test('draw work follows active displays while gaps and replacements keep their order', function()
    net.step()
    local removed
    for _ = 1, 1000 do
        removed = QB.instructional.show({ { control = 1, label = 'Temporary' } })
        harness.assertTrue(removed.hide())
    end
    harness.assertFalse(removed.isVisible())
    harness.assertFalse(removed.hide())
    harness.assertFalse(removed.setButtons({ { control = 1, label = 'Cannot revive' } }))

    local invoking = GetInvokingResource
    GetInvokingResource = function() return 'first_owner' end
    local first = QB.instructional.show({ { control = 1, label = 'First' } })
    local middle = QB.instructional.show({ { control = 2, label = 'Middle' } })
    local third = QB.instructional.show({ { control = 3, label = 'Third' } })
    GetInvokingResource = function() return 'other_owner' end
    local last = QB.instructional.show({ { control = 4, label = 'Last' } })
    GetInvokingResource = invoking
    harness.assertTrue(middle.hide())
    harness.assertTrue(first.setButtons({ { control = 5, label = 'First replacement' }, { control = 6, label = 'First extra' } }))
    strings, slots = {}, {}
    local drawCount, instructions = draws, 0
    debug.sethook(drawThread, function() instructions = instructions + 100 end, '', 100)
    local ok, err = pcall(net.step)
    debug.sethook(drawThread)
    harness.assertTrue(ok, tostring(err))
    print(('instructional active-frame Lua instructions (100-instruction samples): %d'):format(instructions))
    harness.assertEqual(draws, drawCount + 1, 'active displays still render every frame')
    harness.assertEqual(#strings, 8)
    harness.assertEqual(strings[2], 'First replacement')
    harness.assertEqual(strings[4], 'First extra')
    harness.assertEqual(strings[6], 'Third')
    harness.assertEqual(strings[8], 'Last')
    for index = 1, 4 do harness.assertEqual(slots[index], index - 1) end
    harness.assertTrue(first.isVisible())
    harness.assertTrue(third.isVisible())
    harness.assertTrue(last.isVisible())
    harness.assertFalse(middle.isVisible())

    strings, slots, released = {}, {}, false
    net.fire('onClientResourceStop', 'first_owner')
    harness.assertFalse(first.isVisible())
    harness.assertFalse(third.isVisible())
    harness.assertTrue(last.isVisible())
    net.step()
    harness.assertEqual(#strings, 2)
    harness.assertEqual(strings[2], 'Last')
    harness.assertEqual(slots[1], 0)
    harness.assertFalse(released)
    harness.assertTrue(last.hide())
    net.step()
    harness.assertTrue(released, 'the movie is released when the last display is removed')
    harness.assertTrue(instructions < 2000, 'one frame must not scan a thousand removed handles')
end)

harness.report('instructional')
