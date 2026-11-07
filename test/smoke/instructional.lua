local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir, repoRoot = scriptDir .. '../', scriptDir .. '../../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
local mocks = require('mocks')
local net = mocks.install()

local sent = {}
function _G.GetControlInstructionalButton(_, control) return control == 99 and 'b_1004' or 't_' .. tostring(control) end

dofile(repoRoot .. 'build/initiate.lua')
dofile(repoRoot .. 'compat/shared.lua')
dofile(repoRoot .. 'local/resources/client.lua')
Kora.nui = { send = function(action, data) sent[#sent + 1] = { action = action, data = data } end }
dofile(arg[1] or repoRoot .. 'modules/instructional/client.lua')

local function last() return sent[#sent].data.buttons end

harness.test('instructional buttons publish to the NUI and replace their labels', function()
    local display = Kora.instructional.show({ { control = 32, label = 'Movement: Camera' } })
    harness.assertTrue(display.isVisible())
    harness.assertEqual(sent[#sent].action, 'instructional:set')
    harness.assertEqual(last()[1].label, 'Movement: Camera')
    harness.assertEqual(last()[1].keys[1], '32')
    display.setButtons({ { command = 'freecam_grid', label = 'Movement: Grid' } })
    harness.assertEqual(last()[1].label, 'Movement: Grid')
    harness.assertTrue(display.hide())
    harness.assertEqual(#last(), 0)
end)

harness.test('buttons sharing a label merge into one row and icon codes get names', function()
    local display = Kora.instructional.show({
        { control = 38, label = 'Place point' },
        { control = 99, label = 'Place point' },
        { control = 38, label = 'Place point' },
        { control = 177, label = 'Cancel' },
    })
    harness.assertEqual(#last(), 2)
    harness.assertEqual(#last()[1].keys, 2)
    harness.assertEqual(last()[1].keys[2], 'LMB')
    local count = #sent
    display.setButtons({
        { control = 38, label = 'Place point' }, { control = 99, label = 'Place point' }, { control = 177, label = 'Cancel' },
    })
    harness.assertEqual(#sent, count, 'identical payloads are not re-sent')
    display.hide()
end)

harness.test('instructional displays validate and clean up with their owner', function()
    harness.assertThrows(function() Kora.instructional.show({ { label = 'Bad' } }) end)
    local display = Kora.instructional.show({ { control = 32, label = 'Move' } })
    net.fire('onClientResourceStop', 'kora_lib_test')
    harness.assertFalse(display.isVisible())
    harness.assertEqual(#last(), 0)
end)

harness.test('multiple displays keep their order across removals and owners', function()
    local invoking = GetInvokingResource
    GetInvokingResource = function() return 'first_owner' end
    local first = Kora.instructional.show({ { control = 1, label = 'First' } })
    local middle = Kora.instructional.show({ { control = 2, label = 'Middle' } })
    GetInvokingResource = function() return 'other_owner' end
    local lastDisplay = Kora.instructional.show({ { control = 4, label = 'Last' } })
    GetInvokingResource = invoking
    harness.assertTrue(middle.hide())
    harness.assertFalse(middle.hide())
    harness.assertFalse(middle.setButtons({ { control = 1, label = 'Cannot revive' } }))
    harness.assertEqual(last()[1].label, 'First')
    harness.assertEqual(last()[2].label, 'Last')
    net.fire('onClientResourceStop', 'first_owner')
    harness.assertFalse(first.isVisible())
    harness.assertEqual(#last(), 1)
    harness.assertTrue(lastDisplay.hide())
    harness.assertEqual(#last(), 0)
end)

harness.report('instructional')
