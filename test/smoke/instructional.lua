local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir, repoRoot = scriptDir .. '../', scriptDir .. '../../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
local mocks = require('mocks')
local net = mocks.install()

local sent = {}
-- Mirror production tokens: mouse is b_100, Esc/Shift/Ctrl/Alt are b_199 /
-- b_1000 / b_1013 / b_1015, and everything else is the bare t_<id> form.
function _G.GetControlInstructionalButton(_, control)
    if control == 99 then return 'b_100' end
    if control == 200 then return 'b_199' end
    if control == 21 then return 'b_1000' end
    if control == 36 then return 'b_1013' end
    if control == 19 then return 'b_1015' end
    return 't_' .. tostring(control)
end

dofile(repoRoot .. 'build/initiate.lua')
dofile(repoRoot .. 'modules/logging/shared.lua')
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
    harness.assertEqual(#last()[1].keys, 0, 'an unnamed control shows no key, never its number')
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
    harness.assertEqual(#last()[1].keys, 1, 'unnamed control 38 contributes no key')
    harness.assertEqual(last()[1].keys[1], 'LMB')
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

harness.test('unnamed controls use keyFallback text, and named glyphs win over it', function()
    local display = Kora.instructional.show({
        { control = 200, label = 'Close inventory', keyFallback = 'Esc' },
        { control = 99, label = 'Use', keyFallback = 'Enter' },
        { control = 21, label = 'Quick transfer', keyFallback = 'Shift' },
        { control = 36, label = 'Move half', keyFallback = 'Ctrl' },
        { control = 19, label = 'Move one', keyFallback = 'Alt' },
    })
    harness.assertEqual(last()[1].keys[1], 'Esc', 'Esc b_199 maps to a name, not 199')
    harness.assertEqual(last()[2].keys[1], 'LMB', 'a named glyph ignores keyFallback')
    harness.assertEqual(last()[3].keys[1], 'Shift', 'Shift b_1000 maps to a name, not 1000')
    harness.assertEqual(last()[4].keys[1], 'Ctrl', 'Ctrl b_1013 maps to a name, not 1013')
    harness.assertEqual(last()[5].keys[1], 'Alt', 'Alt b_1015 maps to a name, not 1015')
    harness.assertThrows(function() Kora.instructional.show({ { control = 1, label = 'x', keyFallback = '' } }) end)
    display.hide()
end)

harness.test('unknown b_ codes prefer keyFallback and never show the raw id', function()
    local previous = GetControlInstructionalButton
    GetControlInstructionalButton = function() return 'b_9999' end
    local display = Kora.instructional.show({
        { control = 1, label = 'Custom', keyFallback = 'F13' },
    })
    harness.assertEqual(last()[1].keys[1], 'F13')
    display.hide()
    display = Kora.instructional.show({ { control = 1, label = 'No fallback' } })
    harness.assertEqual(#last()[1].keys, 0, 'unknown b_ without keyFallback shows no key')
    display.hide()
    GetControlInstructionalButton = previous
end)

harness.test('grouped buttons collapse into one row', function()
    local display = Kora.instructional.show({
        { control = 32, label = 'Move forward', group = 'Move' },
        { control = 33, label = 'Move backward', group = 'Move' },
        { control = 177, label = 'Cancel' },
    })
    harness.assertEqual(#last(), 2)
    harness.assertEqual(last()[1].label, 'Move')
    harness.assertEqual(#last()[1].keys, 0, 'unnamed controls 32 and 33 add no keys to the merged row')
    harness.assertThrows(function() Kora.instructional.show({ { control = 1, label = 'x', group = '' } }) end)
    display.hide()
end)

harness.report('instructional')
