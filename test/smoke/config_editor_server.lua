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
local registeredCommand
local stoppedResource
local startedResource

_G.IsPlayerAceAllowed = function(_, object) return allowed and object == 'kora_lib.config.edit' end
_G.GetCurrentResourceName = function() return 'kora_lib' end
_G.GetResourceState = function(resource) return resource == 'kora_admin' and 'stopped' or 'started' end
_G.StopResource = function(resource) stoppedResource = resource; return true end
_G.StartResource = function(resource) startedResource = resource; return true end
Kora = {
    callback = { register = function(name, handler) callbacks[name] = handler end },
    commands = { add = function(name, _, _, _, handler, options)
        registeredCommand = { name = name, handler = handler, options = options }
    end },
    config = {
        catalog = function() return { { resource = 'sample', schema = { kind = 'object',
            fieldKeys = { enabled = 'enabled', secret = 'secret', tokens = 'tokens' }, fields = {
            enabled = { kind = 'boolean', path = { 'enabled' } }, secret = { sensitive = true },
            tokens = { kind = 'list', item = { sensitive = true } },
        } } } } end,
        read = function() return { resource = 'sample', schema = { kind = 'object',
            fieldKeys = { enabled = 'enabled', secret = 'secret', tokens = 'tokens', position = 'position' }, fields = {
            enabled = { kind = 'boolean', path = { 'enabled' } }, secret = { sensitive = true },
            tokens = { kind = 'list', sensitive = true, item = { sensitive = true } },
            position = { kind = 'vector3', path = { 'position' } },
        } }, configured = { enabled = true, secret = 'hidden', tokens = { 'hidden' },
            position = { __koraLibConfigType = 'vector3', x = 1, y = 2, z = 3 } },
            values = { enabled = false, secret = 'hidden', tokens = { 'hidden' },
                position = { __koraLibConfigType = 'vector3', x = 4, y = 5, z = 6 } } } end,
        commit = function() commits = commits + 1; return { ok = true } end,
        reset = function() return { ok = true } end,
    },
}

dofile(repoRoot .. 'modules/config/editor_server.lua')

H.test('every editor callback requires the exact configuration ACE', function()
    local value, err = callbacks['kora_lib:configCatalog'](12)
    H.assertEqual(value, nil)
    H.assertEqual(err, 'permission denied')
    allowed = true
    value = callbacks['kora_lib:configCatalog'](12)
    H.assertEqual(value[1].schema.fields.secret, nil)
    H.assertEqual(value[1].schema.fields.tokens, nil)
    H.assertEqual(value[1].schema.fieldKeys.secret, nil)
    H.assertEqual(value[1].schema.fieldKeys.tokens, nil)
    H.assertEqual(value[1].schema.fieldKeys.enabled, 'enabled')
    H.assertFalse(value[1].loaded)
    H.assertEqual(value[1].configured, nil)

    value = callbacks['kora_lib:configRead'](12, 'sample')
    H.assertEqual(value.configured.secret, nil)
    H.assertEqual(value.schema.fields.tokens, nil)
    H.assertEqual(value.schema.fieldKeys.secret, nil)
    H.assertEqual(value.configured.position.__koraLibConfigType, nil)
    H.assertEqual(value.configured.position.z, 3)
    H.assertTrue(value.loaded)
end)

H.test('an unavailable owner returns a normal editor error', function()
    local commit = Kora.config.commit
    Kora.config.commit = function() error('resource stopped', 0) end
    local value, err = callbacks['kora_lib:configCommit'](12,
        { resource = 'sample', path = { 'enabled' }, value = false, revision = 1 })
    H.assertEqual(value, nil)
    H.assertEqual(err, 'configuration is unavailable')
    Kora.config.commit = commit
end)

H.test('reads sanitize secrets and commits only valid requests', function()
    local entry = callbacks['kora_lib:configRead'](12, 'sample')
    H.assertEqual(entry.configured.secret, nil)
    H.assertEqual(entry.configured.tokens, nil)
    local value, err = callbacks['kora_lib:configCommit'](12, { resource = 'sample', path = {}, revision = 1 })
    H.assertEqual(value, nil)
    H.assertEqual(err, 'invalid configuration request')
    for _, revision in ipairs({ 0, -1, 1.5, 0 / 0, math.huge, -math.huge }) do
        value, err = callbacks['kora_lib:configCommit'](12,
            { resource = 'sample', path = { 'enabled' }, value = false, revision = revision })
        H.assertEqual(value, nil)
        H.assertEqual(err, 'invalid configuration request')
    end
    callbacks['kora_lib:configCommit'](12, { resource = 'sample', path = { 'enabled' }, value = false, revision = 1 })
    H.assertEqual(commits, 1)
end)

H.test('reads preserve authored numeric object keys', function()
    Kora.config.read = function()
        return {
            resource = 'sample',
            schema = { kind = 'object', fields = {
                restricted = { kind = 'object', fieldKeys = { ['2'] = 2 }, fields = {
                    ['2'] = { kind = 'boolean' },
                } },
            } },
            configured = { restricted = { [2] = true } }, values = { restricted = { [2] = false } },
        }
    end

    local entry = callbacks['kora_lib:configRead'](12, 'sample')
    H.assertTrue(entry.configured.restricted[2])
    H.assertFalse(entry.values.restricted[2])
    H.assertEqual(entry.schema.fields.restricted.fieldKeys['2'], 2)
end)

H.test('reads retain added inferred-list rows using the first authored item schema', function()
    Kora.config.read = function()
        return {
            resource = 'sample',
            schema = { kind = 'object', fields = {
                locations = { kind = 'list', items = { { kind = 'string' } } },
            } },
            configured = { locations = { 'airport', 'city' } },
            values = { locations = { 'airport', 'city' } },
        }
    end

    local entry = callbacks['kora_lib:configRead'](12, 'sample')
    H.assertEqual(entry.configured.locations[2], 'city')
    H.assertEqual(entry.values.locations[2], 'city')
end)

H.test('an authorised owner can restart a registered resource but not kora_lib', function()
    local result = callbacks['kora_lib:configRestart'](12, 'sample')
    H.assertTrue(result.ok)
    H.assertEqual(stoppedResource, 'sample')
    H.assertEqual(startedResource, 'sample')

    Kora.config.catalog = function() return { { resource = 'kora_lib', schema = {} } } end
    result = callbacks['kora_lib:configRestart'](12, 'kora_lib')
    H.assertFalse(result.ok)
end)

H.test('the command uses the same exact ACE check', function()
    allowed = false
    H.assertEqual(registeredCommand.name, 'config')
    H.assertFalse(registeredCommand.options.checkPermission(12, 'kora_lib.config.edit'))
    allowed = true
    H.assertTrue(registeredCommand.options.checkPermission(12, 'kora_lib.config.edit'))
    registeredCommand.handler(12, { 'sample' })
    local event = mocks.lastEntry(net.triggeredClientEvents, 'kora_lib:client:configOpened')
    H.assertEqual(event[1], 'sample')
end)

H.test('Discord-only qbadmin access is authoritative while compatible mode retains ACE access', function()
    _G.GetResourceState = function() return 'started' end
    _G.exports = { kora_admin = { canEditConfig = function() return false end } }
    allowed = true
    local value, err = callbacks['kora_lib:configCatalog'](12)
    H.assertEqual(value, nil)
    H.assertEqual(err, 'permission denied')

    exports.kora_admin.canEditConfig = function() return true end
    allowed = false
    H.assertTrue(callbacks['kora_lib:configCatalog'](12) ~= nil)

    exports.kora_admin.canEditConfig = function() return nil end
    allowed = true
    H.assertTrue(callbacks['kora_lib:configCatalog'](12) ~= nil)

    exports.kora_admin.canEditConfig = function() error('permission bridge unavailable') end
    H.assertEqual(callbacks['kora_lib:configCatalog'](12), nil)

    exports.kora_admin.canEditConfig = function() error('No such export canEditConfig in resource qbadmin') end
    H.assertTrue(callbacks['kora_lib:configCatalog'](12) ~= nil)
end)

H.report('config_editor_server')
