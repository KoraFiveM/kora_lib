local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local H = require('harness')
local definition, openArgs, committed = nil, nil, nil
local events = {}
local entry = {
    resource = 'sample', revision = 2,
    schema = { kind = 'object', fields = { enabled = { kind = 'boolean', path = { 'enabled' }, label = 'Enabled', scope = 'shared', live = true } } },
    configured = { enabled = true }, values = { enabled = false },
}

QB = {
    callback = { trigger = function(name, request)
        if name == 'qblib:configCatalog' then return { { resource = 'sample' } } end
        if name == 'qblib:configRead' then return entry end
        if name == 'qblib:configCommit' then committed = request; return { ok = true, applied = true } end
    end },
    config = {}, notify = { send = function() end },
    nui = { registerApp = function(value) definition = value end, openApp = function(_, opts) openArgs = opts end },
}
json = { encode = function() return '{}' end, decode = function() return {} end }
function RegisterNetEvent(name, handler) events[name] = handler end

dofile(repoRoot .. 'modules/config/editor_client.lua')

H.test('QB.config.open owns the AppShell application', function()
    QB.config.open('sample')
    H.assertEqual(definition.id, 'qblib:config')
    H.assertEqual(openArgs.viewId, 'settings')
    H.assertEqual(definition.navigation[2].label, 'sample')
end)

H.test('the qblib event opens the same workspace and saves via qblib callbacks', function()
    events['qblib:client:configOpened']()
    definition.onAction('config:resource', { itemId = 'sample' })
    definition.onAction('config:setting', { itemId = 'enabled' })
    definition.onAction('config:save', { value = { value = false } })
    H.assertEqual(committed.resource, 'sample')
    H.assertEqual(committed.path[1], 'enabled')
    H.assertFalse(committed.value)
end)

H.report('config_editor_client')
