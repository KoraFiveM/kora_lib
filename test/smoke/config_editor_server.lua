local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local H = require('harness')
local mocks = require('mocks')
local net = mocks.install()
local callbacks = {}
local allowed = false
local commits = 0

_G.IsPlayerAceAllowed = function(_, object) return allowed and object == 'qblib.config.edit' end
QB = {
    callback = { register = function(name, handler) callbacks[name] = handler end },
    config = {
        catalog = function() return { { resource = 'sample', schema = { kind = 'object', fields = {
            enabled = { kind = 'boolean', path = { 'enabled' } }, secret = { sensitive = true },
            tokens = { kind = 'list', item = { sensitive = true } },
        } } } } end,
        read = function() return { resource = 'sample', schema = { kind = 'object', fields = {
            enabled = { kind = 'boolean', path = { 'enabled' } }, secret = { sensitive = true },
            tokens = { kind = 'list', item = { sensitive = true } },
        } }, configured = { enabled = true, secret = 'hidden', tokens = { 'hidden' } }, values = { enabled = false, secret = 'hidden', tokens = { 'hidden' } } } end,
        commit = function() commits = commits + 1; return { ok = true } end,
        reset = function() return { ok = true } end,
    },
}

dofile(repoRoot .. 'modules/config/editor_server.lua')

H.test('every editor callback requires the exact configuration ACE', function()
    local value, err = callbacks['qblib:configCatalog'](12)
    H.assertEqual(value, nil)
    H.assertEqual(err, 'permission denied')
    allowed = true
    value = callbacks['qblib:configCatalog'](12)
    H.assertEqual(value[1].schema.fields.secret, nil)
end)

H.test('reads sanitize secrets and commits only valid requests', function()
    local entry = callbacks['qblib:configRead'](12, 'sample')
    H.assertEqual(entry.configured.secret, nil)
    H.assertEqual(entry.configured.tokens[1], nil)
    local value, err = callbacks['qblib:configCommit'](12, { resource = 'sample', path = {}, revision = 1 })
    H.assertEqual(value, nil)
    H.assertEqual(err, 'invalid configuration request')
    callbacks['qblib:configCommit'](12, { resource = 'sample', path = { 'enabled' }, value = false, revision = 1 })
    H.assertEqual(commits, 1)
end)

H.test('the command uses the same exact ACE check', function()
    allowed = false
    net.commands.config(12, {})
    H.assertEqual(#net.triggeredClientEvents, 0)
    allowed = true
    net.commands.config(12, { 'sample' })
    local event = mocks.lastEntry(net.triggeredClientEvents, 'qblib:client:configOpened')
    H.assertEqual(event[1], 'sample')
end)

H.report('config_editor_server')
