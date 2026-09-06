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
local notices = {}
QB.permissions = {
    hasPermission = function(src, permission, prefix)
        harness.assertEqual(src, mocks.SOURCE)
        harness.assertEqual(permission, Config.editor.permission)
        harness.assertEqual(prefix, Config.editor.permissionPrefix)
        return granted
    end,
}
QB.notify = {
    send = function(src, payload) notices[#notices + 1] = { src = src, payload = payload } end,
}

dofile(repoRoot .. 'modules/editor/server.lua')

harness.test('editor commands deny players without the configured permission', function()
    granted = false
    net.commands[Config.editor.zoneCommand](mocks.SOURCE, { 'box' })
    harness.assertEqual(#notices, 1, 'a denied command should explain the failure')
    harness.assertTrue(mocks.lastEntry(net.triggeredClientEvents, 'qblib:editor:startZoneCreator') == nil,
        'a denied command must not start an editor')
end)

harness.test('zone command validates the shape before starting the client editor', function()
    granted = true
    net.commands[Config.editor.zoneCommand](mocks.SOURCE, { 'invalid' })
    harness.assertEqual(#notices, 2, 'an invalid shape should show command usage')

    net.commands[Config.editor.zoneCommand](mocks.SOURCE, { 'POLY' })
    local entry = mocks.lastEntry(net.triggeredClientEvents, 'qblib:editor:startZoneCreator')
    harness.assertEqual(entry.target, mocks.SOURCE)
    harness.assertEqual(entry[1], 'poly')
end)

harness.test('placement command accepts bounded model names only', function()
    granted = true
    net.commands[Config.editor.placementCommand](mocks.SOURCE, { '../bad-model' })
    harness.assertEqual(#notices, 3, 'an unsafe model argument should show command usage')

    net.commands[Config.editor.placementCommand](mocks.SOURCE, { 'prop_bin_08' })
    local entry = mocks.lastEntry(net.triggeredClientEvents, 'qblib:editor:startPlacement')
    harness.assertEqual(entry.target, mocks.SOURCE)
    harness.assertEqual(entry[1], 'prop_bin_08')
end)

harness.report('editor')
