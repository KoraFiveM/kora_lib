-- QB.config's consumer bridge is deliberately plain-Lua testable: config
-- ownership and persistence happen in the consuming VM, rather than through a
-- qblib export with hidden cross-resource filesystem access.

local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path
local H = require('harness')
local makeConfig = dofile(repoRoot .. 'modules/config/consumer.lua')

local files = {}
local registered = {}
local clientUpdates = {}
local savedResources = {}
local previousGlobals = {
    GetCurrentResourceName = GetCurrentResourceName,
    IsDuplicityVersion = IsDuplicityVersion,
    LoadResourceFile = LoadResourceFile,
    SaveResourceFile = SaveResourceFile,
    GetInvokingResource = GetInvokingResource,
    TriggerClientEvent = TriggerClientEvent,
    exports = exports,
}

_G.GetCurrentResourceName = function() return 'sample' end
_G.IsDuplicityVersion = function() return true end
_G.LoadResourceFile = function(_, path) return files[path] end
_G.SaveResourceFile = function(resource, path, contents)
    savedResources[#savedResources + 1] = resource
    files[path] = contents
    return true
end
_G.GetInvokingResource = function() return 'qblib' end
_G.TriggerClientEvent = function(name, target, ...)
    clientUpdates[#clientUpdates + 1] = { name = name, target = target, values = { ... } }
end
_G.exports = setmetatable({}, {
    __call = function(_, name, fn) registered[name] = fn end,
})

local registrations = {}
local library = {
    config_register = function(_, definition)
        registrations[#registrations + 1] = definition
        return true
    end,
}

H.test('defines typed settings and writes only an override file', function()
    files['config.lua'] = 'this source is never changed'
    savedResources = {}
    local config = makeConfig(library)
    local values = config.define({
        shared = config.number(10, { min = 1, max = 20, live = true }),
        clientOnly = config.string('blue', { scope = 'client' }),
        serverOnly = config.boolean(true, { scope = 'server' }),
    })
    local observed
    config.onChange('shared', function(value, previous)
        observed = { value, previous }
    end)

    local result = registered.qblib_configCommit({ path = { 'shared' }, value = 15, revision = 1 })
    H.assertTrue(result.ok, result.error)
    H.assertEqual(values.shared, 15)
    H.assertEqual(observed[1], 15)
    H.assertEqual(observed[2], 10)
    H.assertEqual(files['config.lua'], 'this source is never changed')
    H.assertTrue(type(files['config.local.lua']) == 'string')
    H.assertTrue(files['config.local.lua']:find('%["shared"%] = 15', 1) ~= nil)
    H.assertEqual(registrations[#registrations].client.serverOnly, nil)
    H.assertEqual(savedResources[#savedResources], 'sample')
end)

H.test('restart-required changes are saved but do not alter running values', function()
    files = {}
    registered = {}
    registrations = {}
    local config = makeConfig(library)
    local values = config.define({ restart = config.string('old') })
    local result = registered.qblib_configCommit({ path = { 'restart' }, value = 'new', revision = 1 })
    H.assertTrue(result.ok, result.error)
    H.assertEqual(values.restart, 'old')
    H.assertEqual(result.configured.restart, 'new')
    H.assertTrue(result.restartRequired)
    local reset = registered.qblib_configReset({ path = { 'restart' }, revision = result.revision })
    H.assertTrue(reset.ok, reset.error)
    H.assertTrue(files['config.local.lua']:find('restart', 1, true) == nil)
end)

H.test('server-only roots register an empty client snapshot', function()
    files = {}
    registered = {}
    registrations = {}
    local config = makeConfig(library)
    config.define({ webhook = config.string('https://example.invalid') }, { scope = 'server' })
    H.assertEqual(next(registrations[#registrations].client), nil)
end)

H.test('client-only live settings update clients without running server handlers', function()
    files = {}
    registered = {}
    registrations = {}
    clientUpdates = {}
    local config = makeConfig(library)
    local values = config.define({ visual = config.number(1, { scope = 'client', live = true }) })
    config.onChange('visual', function() error('client-only handler ran on the server') end)
    local result = registered.qblib_configCommit({ path = { 'visual' }, value = 2, revision = 1 })
    H.assertTrue(result.ok, result.error)
    H.assertEqual(values.visual, 2)
    H.assertEqual(clientUpdates[#clientUpdates].name, 'qblib:client:configUpdated')
end)

H.test('uses the previous override when the current override is invalid', function()
    files = {
        ['config.local.lua'] = 'return { enabled = ',
        ['config.local.lua.bak'] = 'return { enabled = false }',
    }
    registered = {}
    local config = makeConfig(library)
    local values = config.define({ enabled = config.boolean(true) })
    H.assertFalse(values.enabled)
end)

H.test('adoption preserves executable and runtime-only legacy fields outside the catalog', function()
    files = {}
    registered = {}
    registrations = {}
    local callback = function() return true end
    local legacy = { enabled = true, callback = callback, registry = {} }
    local config = makeConfig(library)
    config.adopt(legacy)
    H.assertEqual(legacy.callback, callback)
    H.assertTrue(type(legacy.registry) == 'table')
    H.assertEqual(registrations[#registrations].schema.fields.callback, nil)
    H.assertEqual(registrations[#registrations].schema.fields.registry, nil)
end)

H.test('nullable descriptors retain a nil authored default', function()
    files = {}
    registered = {}
    local config = makeConfig(library)
    local values = config.define({ message = config.optional(nil, config.string('example')) })
    H.assertEqual(values.message, nil)
    local result = registered.qblib_configCommit({ path = { 'message' }, value = 'hello', revision = 1 })
    H.assertTrue(result.ok, result.error)
end)

H.test('typed lists, maps, colours, and vectors validate and serialize', function()
    files = {}
    registered = {}
    local config = makeConfig(library)
    config.define({
        tags = config.list({ 'starter' }, config.string('', { minLength = 1 })),
        flags = config.map({ primary = true }, config.boolean(false)),
        colour = config.color('#95FF00'),
        location = config.vector3({ x = 1, y = 2, z = 3 }),
    })
    local list = registered.qblib_configCommit({ path = { 'tags' }, value = { 'one', 'two' }, revision = 1 })
    H.assertTrue(list.ok, list.error)
    local map = registered.qblib_configCommit({ path = { 'flags' }, value = { primary = false, secondary = true }, revision = 2 })
    H.assertTrue(map.ok, map.error)
    local vector = registered.qblib_configCommit({ path = { 'location' }, value = { x = 4, y = 5, z = 6 }, revision = 3 })
    H.assertTrue(vector.ok, vector.error)
    local invalid = registered.qblib_configCommit({ path = { 'colour' }, value = 'green', revision = 4 })
    H.assertFalse(invalid.ok)
    H.assertTrue(files['config.local.lua']:find('%["secondary"%] = true', 1) ~= nil)
end)

H.test('a refused live handler rolls back the saved value and revision', function()
    files = {}
    registered = {}
    local config = makeConfig(library)
    config.define({ enabled = config.boolean(true, { live = true }) })
    config.onChange('enabled', function() return false end)
    local result = registered.qblib_configCommit({ path = { 'enabled' }, value = false, revision = 1 })
    H.assertFalse(result.ok)
    H.assertEqual(result.revision, 1)
    H.assertTrue(files['config.local.lua']:find('enabled', 1, true) == nil,
        files['config.local.lua'])
    H.assertEqual(files['config.local.lua.bak'], '')
end)

H.test('invalid values and stale edits are refused without persistence', function()
    files = {}
    registered = {}
    local config = makeConfig(library)
    config.define({ amount = config.integer(2, { min = 1, max = 3 }) })
    local invalid = registered.qblib_configCommit({ path = { 'amount' }, value = 4, revision = 1 })
    H.assertFalse(invalid.ok)
    H.assertEqual(files['config.local.lua'], nil)
    local stale = registered.qblib_configCommit({ path = { 'amount' }, value = 2, revision = 9 })
    H.assertFalse(stale.ok)
end)

H.test('invalid authored defaults and incoherent field constraints fail at startup', function()
    files = {}
    registered = {}
    local config = makeConfig(library)
    H.assertThrows(function()
        config.define({ amount = config.integer(1.5) })
    end, 'an integer descriptor must not accept a fractional authored default')

    config = makeConfig(library)
    H.assertThrows(function()
        config.define({ amount = config.number(2, { min = 3, max = 1 }) })
    end, 'a field minimum must not exceed its maximum')
end)

H.test('unknown nested paths return a normal validation error', function()
    files = {}
    registered = {}
    local config = makeConfig(library)
    config.define({ nested = { enabled = true } })

    local ok, result = pcall(registered.qblib_configCommit,
        { path = { 'missing', 'enabled' }, value = false, revision = 1 })
    H.assertTrue(ok, 'an unknown nested path must not crash the configuration bridge')
    H.assertFalse(result.ok)
    H.assertEqual(result.error, 'Unknown configuration option.')
end)

H.test('numeric-looking map keys remain strings when edited', function()
    files = {}
    registered = {}
    local config = makeConfig(library)
    config.define({ flags = config.map({ ['1'] = true }, config.boolean(false)) })

    local result = registered.qblib_configCommit({ path = { 'flags', '1' }, value = false, revision = 1 })
    H.assertTrue(result.ok, result.error)
    H.assertFalse(result.configured.flags['1'])
    H.assertEqual(result.configured.flags[1], nil)
end)

for name, value in pairs(previousGlobals) do _G[name] = value end

H.report('config')
