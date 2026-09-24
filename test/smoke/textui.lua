local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
local mocks = require('mocks')
local network = mocks.install()

dofile(repoRoot .. 'config.lua')
dofile(repoRoot .. 'build/initiate.lua')
dofile(repoRoot .. 'local/resources/client.lua')

local messages = {}
QB.nui.send = function(action, data)
    messages[#messages + 1] = { action = action, data = data }
end

local owner = 'alpha'
_G.GetInvokingResource = function() return owner end
dofile(repoRoot .. 'modules/textui/client.lua')

harness.test('show renders the newest handle and exposes visibility state', function()
    messages = {}
    local first = QB.textui.show('First', { key = 'E', position = 'left-center' })
    local second = QB.textui.show('Second', { icon = 'Car' })

    harness.assertTrue(QB.textui.isOpen(), 'stack should report open')
    harness.assertTrue(QB.textui.isOpen(first), 'first handle should remain live')
    harness.assertFalse(QB.textui.isVisible(first), 'older handle should be hidden')
    harness.assertTrue(QB.textui.isVisible(second), 'newest handle should be visible')
    harness.assertEqual(messages[#messages].data.text, 'Second', 'newest prompt should be sent to NUI')
    QB.textui.hide(second)
    QB.textui.hide(first)
end)

harness.test('presentation options are validated and forwarded to NUI', function()
    messages = {}
    local style = { backgroundColor = '#111111' }
    local id = QB.textui.show('**Markdown**', {
        icon = 'Bell',
        iconColor = '#22c55e',
        iconAnimation = 'pulse',
        alignIcon = 'top',
        style = style,
    })

    local payload = messages[#messages].data
    harness.assertEqual(payload.iconColor, '#22c55e', 'icon colour should be forwarded')
    harness.assertEqual(payload.iconAnimation, 'pulse', 'icon animation should be forwarded')
    harness.assertEqual(payload.alignIcon, 'top', 'icon alignment should be forwarded')
    harness.assertEqual(payload.style, style, 'surface style should be forwarded')
    QB.textui.hide(id)

    local css = 'background-color: #111; color: white'
    id = QB.textui.show('String style', { style = css })
    harness.assertEqual(messages[#messages].data.style, css, 'CSS declaration strings should be forwarded unchanged')
    QB.textui.hide(id)
end)

harness.test('updating a hidden handle does not replace the visible entry', function()
    messages = {}
    local lower = QB.textui.show('Lower')
    local upper = QB.textui.show('Upper')
    local before = #messages

    harness.assertTrue(QB.textui.update(lower, 'Updated lower', { position = 'top-center' }),
        'live hidden handle should update')
    harness.assertEqual(#messages, before, 'hidden update should not send a visual change')
    harness.assertTrue(QB.textui.isVisible(upper), 'upper entry should stay visible')
    QB.textui.hide(upper)
    QB.textui.hide(lower)
end)

harness.test('hiding the newest entry restores the previous one', function()
    messages = {}
    local lower = QB.textui.show('Restore me')
    local upper = QB.textui.show('Temporary')

    harness.assertTrue(QB.textui.hide(upper), 'upper handle should be removed')
    harness.assertTrue(QB.textui.isVisible(lower), 'lower handle should become visible')
    harness.assertEqual(messages[#messages].data.text, 'Restore me', 'restored entry should be sent to NUI')
    QB.textui.hide(lower)
end)

harness.test('removing the final entry sends the hide payload', function()
    messages = {}
    local id = QB.textui.show('Only')
    harness.assertTrue(QB.textui.hide(id), 'live entry should be removed')
    harness.assertFalse(messages[#messages].data, 'empty stack should send false')
    harness.assertFalse(QB.textui.isOpen(id), 'removed handle should no longer be open')
    harness.assertFalse(QB.textui.hide(id), 'repeat removal should be a no-op')
end)

harness.test('resource stop removes only owned entries and restores the next owner', function()
    messages = {}
    owner = 'alpha'
    local alpha = QB.textui.show('Alpha')
    owner = 'beta'
    local beta = QB.textui.show('Beta')

    network.fire('onClientResourceStop', 'beta')
    harness.assertFalse(QB.textui.isOpen(beta), 'stopped owner handle should be removed')
    harness.assertTrue(QB.textui.isVisible(alpha), 'previous owner should be restored')
    harness.assertEqual(messages[#messages].data.text, 'Alpha', 'restored owner should render')
    owner = 'alpha'
    QB.textui.hide(alpha)
end)

harness.test('foreign resources cannot update or hide an owned prompt', function()
    owner = 'alpha'
    local id = QB.textui.show('Alpha only')
    owner = 'beta'
    harness.assertFalse(QB.textui.update(id, 'Hijacked'), 'another resource must not update this prompt')
    harness.assertFalse(QB.textui.hide(id), 'another resource must not hide this prompt')
    harness.assertTrue(QB.textui.isOpen(id), 'the original prompt should remain live')
    owner = 'alpha'
    harness.assertTrue(QB.textui.hide(id), 'the owner should still be able to hide its prompt')
end)

harness.test('invalid text and positions are rejected', function()
    harness.assertThrows(function() QB.textui.show('') end, 'empty text should fail')
    harness.assertThrows(function() QB.textui.show('Nope', { position = 'middle' }) end,
        'unsupported position should fail')
    harness.assertThrows(function() QB.textui.show('Nope', { position = false }) end,
        'false position should not silently default')
    harness.assertThrows(function() QB.textui.show('Nope', { iconAnimation = 'flash' }) end,
        'unsupported icon animation should fail')
    harness.assertThrows(function() QB.textui.show('Nope', { alignIcon = 'bottom' }) end,
        'unsupported icon alignment should fail')
end)

harness.report('textui')
