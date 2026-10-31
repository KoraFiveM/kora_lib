local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
local mocks = require('mocks')
local net = mocks.install()

dofile(repoRoot .. 'config.lua')
dofile(repoRoot .. 'build/initiate.lua')

local granted = false
local legacyGranted = false
local notices = {}
Kora.permissions = {
    hasPermission = function(src, permission, prefix)
        harness.assertEqual(src, mocks.SOURCE)
        harness.assertEqual(permission, Config.editor.permission)
        -- The deprecated qblib.editor ACE is consulted after the kora_lib one.
        if prefix == 'qblib' then return legacyGranted end
        harness.assertEqual(prefix, Config.editor.permissionPrefix)
        return granted
    end,
}
Kora.notify = {
    send = function(src, payload) notices[#notices + 1] = { src = src, payload = payload } end,
}

dofile(repoRoot .. 'modules/editor/server.lua')

harness.test('editor commands deny players without the configured permission', function()
    granted = false
    net.commands[Config.editor.zoneCommand](mocks.SOURCE, { 'box' })
    harness.assertEqual(#notices, 1, 'a denied command should explain the failure')
    harness.assertTrue(mocks.lastEntry(net.triggeredClientEvents, 'kora_lib:editor:startZoneCreator') == nil,
        'a denied command must not start an editor')
end)

harness.test('the deprecated qblib.editor ACE still grants access', function()
    granted = false
    legacyGranted = true
    local before = #notices
    net.commands[Config.editor.zoneCommand](mocks.SOURCE, { 'box' })
    harness.assertEqual(#notices, before, 'a legacy grant should not be denied')
    harness.assertTrue(mocks.lastEntry(net.triggeredClientEvents, 'kora_lib:editor:startZoneCreator') ~= nil)
    legacyGranted = false
end)

harness.test('zone command validates the shape before starting the client editor', function()
    granted = true
    net.commands[Config.editor.zoneCommand](mocks.SOURCE, { 'invalid' })
    harness.assertEqual(#notices, 2, 'an invalid shape should show command usage')

    net.commands[Config.editor.zoneCommand](mocks.SOURCE, { 'POLY' })
    local entry = mocks.lastEntry(net.triggeredClientEvents, 'kora_lib:editor:startZoneCreator')
    harness.assertEqual(entry.target, mocks.SOURCE)
    harness.assertEqual(entry[1], 'poly')
end)

harness.test('placement command accepts bounded model names only', function()
    granted = true
    net.commands[Config.editor.placementCommand](mocks.SOURCE, { '../bad-model' })
    harness.assertEqual(#notices, 3, 'an unsafe model argument should show command usage')

    net.commands[Config.editor.placementCommand](mocks.SOURCE, { 'prop_bin_08' })
    local entry = mocks.lastEntry(net.triggeredClientEvents, 'kora_lib:editor:startPlacement')
    harness.assertEqual(entry.target, mocks.SOURCE)
    harness.assertEqual(entry[1], 'prop_bin_08')
end)

harness.report('editor')
