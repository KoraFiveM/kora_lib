-- QB.config's consumer bridge is deliberately plain-Lua testable: config
-- ownership and persistence happen in the consuming VM, rather than through a
-- kora_lib export with hidden cross-resource filesystem access.

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
_G.GetInvokingResource = function() return 'kora_lib' end
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

    local result = registered.kora_lib_configCommit({ path = { 'shared' }, value = 15, revision = 1 })
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

H.test('generates readable labels and descriptions when a field does not provide them', function()
    files = {}
    registered = {}
    registrations = {}
    local config = makeConfig(library)
    config.define({
        speedUnit = config.enum('kmh', { options = { 'kmh', 'mph' } }),
        allowCustomisation = true,
        spawnPoints = { 'airport' },
    })

    local fields = registrations[#registrations].schema.fields
    H.assertEqual(fields.speedUnit.label, 'Speed Unit')
    H.assertEqual(fields.speedUnit.description,
        'Selects Speed Unit for sample. Only the authored choices are accepted for speedUnit, preventing an unsupported mode from being saved.')
    H.assertEqual(fields.allowCustomisation.label, 'Allow Customisation')
    H.assertEqual(fields.allowCustomisation.description,
        'Enables or disables Allow Customisation for sample. This true/false value is read from allowCustomisation.')
    H.assertEqual(fields.spawnPoints.description,
        'Defines the ordered entries used by sample for Spawn Points. Add, remove, or edit numbered rows; every row is checked against the resource schema before spawnPoints is saved.')
end)

H.test('uses authored description overrides and preserves common acronyms in labels', function()
    files = {}
    registered = {}
    registrations = {}
    local config = makeConfig(library)
    config.define({ analysisTTL = 300000 }, {
        descriptions = { analysisTTL = 'Maximum time allowed for the complete analysis workflow.' },
    })

    local field = registrations[#registrations].schema.fields.analysisTTL
    H.assertEqual(field.label, 'Analysis TTL')
    H.assertEqual(field.description, 'Maximum time allowed for the complete analysis workflow.')
end)

H.test('inferred lists accept new rows using the authored first row as their schema', function()
    files = {}
    registered = {}
    registrations = {}
    local config = makeConfig(library)
    config.define({ locations = { 'airport' } })

    local result = registered.kora_lib_configCommit({
        path = { 'locations' }, value = { 'airport', 'city' }, revision = 1,
    })
    H.assertTrue(result.ok, result.error)
    H.assertEqual(result.configured.locations[2], 'city')

    registered = {}
    registrations = {}
    config = makeConfig(library)
    local restarted = config.define({ locations = { 'airport' } })
    H.assertEqual(restarted.locations[2], 'city')
    H.assertEqual(registrations[#registrations].client.locations[2], 'city')
end)

H.test('explicit maps accept newly added string keys', function()
    files = {}
    registered = {}
    registrations = {}
    local config = makeConfig(library)
    config.define({ roles = config.map({ police = true }, config.boolean(false)) })

    local result = registered.kora_lib_configCommit({
        path = { 'roles' }, value = { police = true, ambulance = true }, revision = 1,
    })
    H.assertTrue(result.ok, result.error)
    H.assertTrue(result.configured.roles.ambulance)

    registered = {}
    registrations = {}
    config = makeConfig(library)
    local restarted = config.define({ roles = config.map({ police = true }, config.boolean(false)) })
    H.assertTrue(restarted.roles.ambulance)
    H.assertTrue(registrations[#registrations].client.roles.ambulance)
end)

H.test('explicit mixed-key maps preserve integer and text keys', function()
    files = {}
    registered = {}
    registrations = {}
    local config = makeConfig(library)
    config.define({ rates = config.map({ default = 0.5, [0] = 0.1 }, config.number(0, { min = 0 }), {
        keyType = 'mixed',
    }) })

    local result = registered.kora_lib_configCommit({
        path = { 'rates' }, value = { default = 0.75, [0] = 0.2, [7] = 1.0 }, revision = 1,
    })
    H.assertTrue(result.ok, result.error)
    H.assertEqual(result.configured.rates.default, 0.75)
    H.assertEqual(result.configured.rates[0], 0.2)
    H.assertEqual(result.configured.rates[7], 1.0)
    H.assertEqual(result.configured.rates['7'], nil)
    H.assertEqual(registrations[#registrations].schema.fields.rates.keyType, 'mixed')
    H.assertTrue(files['config.local.lua']:find('%[0%] = 0.2') ~= nil, files['config.local.lua'])
end)

H.test('maps can protect required fallback keys', function()
    files = {}
    registered = {}
    registrations = {}
    local config = makeConfig(library)
    config.define({ rates = config.map({ default = 0.5, [0] = 0.1 }, config.number(0), {
        keyType = 'mixed', requiredKeys = { 'default' },
    }) })

    local result = registered.kora_lib_configCommit({
        path = { 'rates' }, value = { [0] = 0.2 }, revision = 1,
    })
    H.assertFalse(result.ok)
    H.assertTrue(result.error:find('default', 1, true) ~= nil, result.error)
end)

H.test('inferred labels include their configuration context', function()
    files = {}
    registered = {}
    registrations = {}
    local config = makeConfig(library)
    config.define({ serviceRateLimit = { max = 5, window = 10000 } })

    local schema = registrations[#registrations].schema.fields.serviceRateLimit.fields
    H.assertEqual(schema.max.label, 'Service Rate Limit Max')
    H.assertEqual(schema.window.label, 'Service Rate Limit Window')
end)

H.test('restart-required changes are saved but do not alter running values', function()
    files = {}
    registered = {}
    registrations = {}
    local config = makeConfig(library)
    local values = config.define({ restart = config.string('old') })
    local result = registered.kora_lib_configCommit({ path = { 'restart' }, value = 'new', revision = 1 })
    H.assertTrue(result.ok, result.error)
    H.assertEqual(values.restart, 'old')
    H.assertEqual(result.configured.restart, 'new')
    H.assertTrue(result.restartRequired)
    H.assertEqual(registrations[#registrations].client.restart, 'old')
    H.assertEqual(registered.kora_lib_configRead().client.restart, 'old')
    local reset = registered.kora_lib_configReset({ path = { 'restart' }, revision = result.revision })
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

H.test('nested server-only collection values are excluded from client snapshots', function()
    files = {}
    registered = {}
    registrations = {}
    local config = makeConfig(library)
    config.define({
        groups = config.map({ internal = 'secret' }, config.string('', { scope = 'server' })),
        visible = config.list({ 'public' }, config.string('')),
    })

    local client = registrations[#registrations].client
    H.assertEqual(next(client.groups), nil)
    H.assertEqual(client.visible[1], 'public')
end)

H.test('client-only live settings update clients without running server handlers', function()
    files = {}
    registered = {}
    registrations = {}
    clientUpdates = {}
    local config = makeConfig(library)
    local values = config.define({ visual = config.number(1, { scope = 'client', live = true }) })
    config.onChange('visual', function() error('client-only handler ran on the server') end)
    local result = registered.kora_lib_configCommit({ path = { 'visual' }, value = 2, revision = 1 })
    H.assertTrue(result.ok, result.error)
    H.assertEqual(values.visual, 2)
    H.assertEqual(clientUpdates[#clientUpdates - 1].name, 'kora_lib:client:configUpdated')
    H.assertEqual(clientUpdates[#clientUpdates].name, 'qblib:client:configUpdated', 'deprecated alias for older consumers')
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
    local read = registered.kora_lib_configRead()
    H.assertEqual(read.values.callback, nil)
    H.assertEqual(read.values.registry, nil)
end)

H.test('adoption validates sparse numeric object keys against their authored values', function()
    files = {}
    registered = {}
    registrations = {}
    local legacy = {
        restricted = {
            [2] = { enabled = true },
            [10] = { enabled = false },
        },
    }
    local config = makeConfig(library)

    config.adopt(legacy)

    H.assertTrue(legacy.restricted[2].enabled)
    H.assertFalse(legacy.restricted[10].enabled)
    H.assertTrue(registrations[#registrations].client.restricted[2].enabled)
    H.assertFalse(registrations[#registrations].client.restricted[10].enabled)
    H.assertEqual(registrations[#registrations].schema.fieldKeys.restricted, 'restricted')
    H.assertEqual(registrations[#registrations].schema.fields.restricted.fieldKeys['2'], 2)
end)

H.test('sparse numeric object keys persist and reload without becoming strings', function()
    files = {}
    registered = {}
    registrations = {}
    local config = makeConfig(library)
    local values = { classes = { [8] = true, [13] = true } }
    config.adopt(values)

    local result = registered.kora_lib_configCommit({ path = { 'classes', '13' }, value = false, revision = 1 })

    H.assertTrue(result.ok, result.error)
    H.assertTrue(result.restartRequired)
    H.assertTrue(result.configured.classes[8])
    H.assertFalse(result.configured.classes[13])
    H.assertEqual(result.configured.classes['13'], nil)
    H.assertTrue(files['config.local.lua']:find('%[13%] = false') ~= nil, files['config.local.lua'])
    H.assertTrue(values.classes[13])

    registered = {}
    registrations = {}
    config = makeConfig(library)
    values = { classes = { [8] = true, [13] = true } }
    config.adopt(values)
    H.assertFalse(values.classes[13])
    H.assertEqual(values.classes['13'], nil)
end)

H.test('adopted runtime callbacks do not break commit or reset responses', function()
    files, registered, registrations = {}, {}, {}
    local config = makeConfig(library)
    local callback = function() end
    local values = { amount = config.number(10, { live = true }), callback = callback, runtime = {} }
    config.adopt(values)
    values.runtime.callback = callback
    local result = registered.kora_lib_configCommit({ path = { 'amount' }, value = 15, revision = 1 })
    H.assertTrue(result.ok, result.error)
    H.assertEqual(values.amount, 15)
    H.assertEqual(result.values.amount, 15)
    H.assertEqual(result.values.callback, nil)
    H.assertEqual(result.values.runtime, nil)
    H.assertEqual(values.callback, callback)
    result = registered.kora_lib_configReset({ path = { 'amount' }, revision = 2 })
    H.assertTrue(result.ok, result.error)
    H.assertEqual(result.values.amount, 10)
end)

H.test('cleared optional defaults survive reload and can be reset', function()
    files, registered, registrations = {}, {}, {}
    local config = makeConfig(library)
    local values = config.define({ note = config.optional('enabled', config.string('example'), { live = true }) })
    local result = registered.kora_lib_configCommit({ path = { 'note' }, revision = 1 })
    H.assertTrue(result.ok, result.error)
    H.assertEqual(values.note, nil)
    H.assertEqual(registrations[#registrations].client.note.__koraLibConfigType, 'nil')

    config = makeConfig(library)
    values = config.define({ note = config.optional('enabled', config.string('example'), { live = true }) })
    H.assertEqual(values.note, nil, 'reload must preserve the explicit clear')
    result = registered.kora_lib_configReset({ path = { 'note' }, revision = 1 })
    H.assertTrue(result.ok, result.error)
    H.assertEqual(values.note, 'enabled')
    H.assertEqual(next(assert(load(files['config.local.lua']))()), nil, 'reset must remove the override')
end)

H.test('nullable descriptors retain a nil authored default', function()
    files = {}
    registered = {}
    local config = makeConfig(library)
    local values = config.define({ message = config.optional(nil, config.string('example')) })
    H.assertEqual(values.message, nil)
    H.assertEqual(registrations[#registrations].schema.fields.message.innerDefault, 'example')
    local result = registered.kora_lib_configCommit({ path = { 'message' }, value = 'hello', revision = 1 })
    H.assertTrue(result.ok, result.error)
end)

H.test('optional fields do not publish sensitive inner defaults or accept redundant nesting', function()
    files = {}
    registered = {}
    registrations = {}
    local config = makeConfig(library)
    config.define({ secret = config.optional(nil, config.string('do-not-publish', { sensitive = true })) })
    local secret = registrations[#registrations].schema.fields.secret
    H.assertTrue(secret.sensitive)
    H.assertEqual(secret.innerDefault, nil)

    H.assertThrows(function()
        config.define({ nested = config.optional(nil, config.optional(nil, config.string('value'))) })
    end, 'nested optional fields should fail at definition time')
end)

H.test('editable collections become sensitive when any nested value is sensitive', function()
    files = {}
    registered = {}
    registrations = {}
    local config = makeConfig(library)
    config.define({
        secrets = config.list({}, config.object({
            name = config.string('service'),
            token = config.string('do-not-publish', { sensitive = true }),
        })),
        credentials = config.map({}, config.string('do-not-publish', { sensitive = true })),
    })

    local fields = registrations[#registrations].schema.fields
    H.assertTrue(fields.secrets.sensitive,
        'a list edited as one value must hide nested sensitive object fields')
    H.assertTrue(fields.credentials.sensitive,
        'a map edited as one value must hide sensitive entries')
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
    local list = registered.kora_lib_configCommit({ path = { 'tags' }, value = { 'one', 'two' }, revision = 1 })
    H.assertTrue(list.ok, list.error)
    local map = registered.kora_lib_configCommit({ path = { 'flags' }, value = { primary = false, secondary = true }, revision = 2 })
    H.assertTrue(map.ok, map.error)
    local vector = registered.kora_lib_configCommit({ path = { 'location' }, value = { x = 4, y = 5, z = 6 }, revision = 3 })
    H.assertTrue(vector.ok, vector.error)
    local invalid = registered.kora_lib_configCommit({ path = { 'colour' }, value = 'green', revision = 4 })
    H.assertFalse(invalid.ok)
    H.assertTrue(files['config.local.lua']:find('%["secondary"%] = true', 1) ~= nil)
end)

H.test('every editable value kind can update the active snapshot live', function()
    files = {}
    registered = {}
    registrations = {}
    local config = makeConfig(library)
    local values = config.define({
        enabled = config.boolean(true, { live = true }),
        title = config.string('old', { live = true }),
        count = config.integer(1, { live = true }),
        ratio = config.number(1.5, { live = true }),
        mode = config.enum('one', { options = { 'one', 'two' }, live = true }),
        colour = config.color('#000000', { live = true }),
        point2 = config.vector2({ x = 1, y = 2 }, { live = true }),
        point3 = config.vector3({ x = 1, y = 2, z = 3 }, { live = true }),
        point4 = config.vector4({ x = 1, y = 2, z = 3, w = 4 }, { live = true }),
        tags = config.list({ 'old' }, config.string(''), { live = true }),
        flags = config.map({ old = true }, config.boolean(false), { live = true }),
        note = config.optional(nil, config.string('example'), { live = true }),
    })
    local edits = {
        { 'enabled', false },
        { 'title', 'new' },
        { 'count', 2 },
        { 'ratio', 2.5 },
        { 'mode', 'two' },
        { 'colour', '#95FF00' },
        { 'point2', { x = 2, y = 3 } },
        { 'point3', { x = 2, y = 3, z = 4 } },
        { 'point4', { x = 2, y = 3, z = 4, w = 5 } },
        { 'tags', { 'new', 'second' } },
        { 'flags', { new = false } },
        { 'note', 'set' },
        { 'note', nil },
    }
    for index, edit in ipairs(edits) do
        local result = registered.kora_lib_configCommit({ path = { edit[1] }, value = edit[2], revision = index })
        H.assertTrue(result.ok, result.error)
        H.assertTrue(result.applied, edit[1] .. ' should apply live')
    end
    H.assertFalse(values.enabled)
    H.assertEqual(values.title, 'new')
    H.assertEqual(values.count, 2)
    H.assertEqual(values.ratio, 2.5)
    H.assertEqual(values.mode, 'two')
    H.assertEqual(values.colour, '#95FF00')
    H.assertEqual(values.point2.x, 2)
    H.assertEqual(values.point3.z, 4)
    H.assertEqual(values.point4.w, 5)
    H.assertEqual(values.tags[2], 'second')
    H.assertFalse(values.flags.new)
    H.assertEqual(values.note, nil)
end)

H.test('a refused live handler rolls back the saved value and revision', function()
    files = {}
    registered = {}
    local config = makeConfig(library)
    config.define({ enabled = config.boolean(true, { live = true }) })
    config.onChange('enabled', function() return false end)
    local result = registered.kora_lib_configCommit({ path = { 'enabled' }, value = false, revision = 1 })
    H.assertFalse(result.ok)
    H.assertEqual(result.revision, 1)
    H.assertTrue(files['config.local.lua']:find('enabled', 1, true) == nil,
        files['config.local.lua'])
    H.assertEqual(files['config.local.lua.bak'], '')
end)

H.test('a refused apply hook restores the prior backup', function()
    files = { ['config.local.lua.bak'] = 'return { preserved = true }' }
    registered = {}
    local config = makeConfig(library)
    config.define({ enabled = config.boolean(true, { live = true }) })
    config.onApply(function() return false end)

    local result = registered.kora_lib_configCommit({ path = { 'enabled' }, value = false, revision = 1 })
    H.assertFalse(result.ok)
    H.assertEqual(result.revision, 1)
    H.assertTrue(files['config.local.lua']:find('enabled', 1, true) == nil, files['config.local.lua'])
    H.assertEqual(files['config.local.lua.bak'], 'return { preserved = true }')
end)

H.test('invalid values and stale edits are refused without persistence', function()
    files = {}
    registered = {}
    local config = makeConfig(library)
    config.define({ amount = config.integer(2, { min = 1, max = 3 }) })
    local invalid = registered.kora_lib_configCommit({ path = { 'amount' }, value = 4, revision = 1 })
    H.assertFalse(invalid.ok)
    H.assertEqual(files['config.local.lua'], nil)
    local stale = registered.kora_lib_configCommit({ path = { 'amount' }, value = 2, revision = 9 })
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

    config = makeConfig(library)
    H.assertThrows(function()
        config.define({ mode = config.enum(true, { options = { true, false } }) })
    end, 'enum options must use browser-safe string or number values')
end)

H.test('unknown nested paths return a normal validation error', function()
    files = {}
    registered = {}
    local config = makeConfig(library)
    config.define({ nested = { enabled = true } })

    local ok, result = pcall(registered.kora_lib_configCommit,
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

    local result = registered.kora_lib_configCommit({ path = { 'flags', '1' }, value = false, revision = 1 })
    H.assertTrue(result.ok, result.error)
    H.assertFalse(result.configured.flags['1'])
    H.assertEqual(result.configured.flags[1], nil)
end)

H.test('a numeric server flag preserves validation, live hooks, and commit authorization', function()
    files = {}
    registered = {}
    local previousIsDuplicityVersion = _G.IsDuplicityVersion
    _G.IsDuplicityVersion = function() return 1 end
    local config = makeConfig(library)
    _G.IsDuplicityVersion = previousIsDuplicityVersion
    local values = config.define({ count = config.integer(1, { live = true, scope = 'server' }) })
    config.onValidate(function(proposed) return proposed.count > 0, 'count must be positive' end)
    local applied
    config.onApply(function(proposed) applied = proposed.count end)

    local refused = registered.kora_lib_configCommit({ path = { 'count' }, value = 0, revision = 1 })
    H.assertFalse(refused.ok)
    H.assertEqual(values.count, 1)
    H.assertEqual(applied, nil)
    local accepted = registered.kora_lib_configCommit({ path = { 'count' }, value = 2, revision = 1 })
    H.assertTrue(accepted.ok, accepted.error)
    H.assertEqual(values.count, 2)
    H.assertEqual(applied, 2)

    local previousGetInvokingResource = _G.GetInvokingResource
    _G.GetInvokingResource = function() return 'other' end
    local unauthorized = registered.kora_lib_configCommit({ path = { 'count' }, value = 3, revision = 2 })
    _G.GetInvokingResource = previousGetInvokingResource
    H.assertFalse(unauthorized.ok)
    H.assertEqual(values.count, 2)
end)

H.test('client flags cannot register server validation or application hooks', function()
    local previousIsDuplicityVersion = _G.IsDuplicityVersion
    for _, flag in ipairs({ false, 0 }) do
        _G.IsDuplicityVersion = function() return flag end
        local config = makeConfig(library)
        H.assertThrows(function() config.onValidate(function() return true end) end)
        H.assertThrows(function() config.onApply(function() end) end)
    end
    _G.IsDuplicityVersion = previousIsDuplicityVersion
end)

H.test('owner validation, application, and bindings use the active snapshot', function()
    files = {}
    registered = {}
    local config = makeConfig(library)
    local values = config.register({ enabled = config.boolean(true, { live = true }) })
    config.onValidate(function(proposed)
        return proposed.enabled ~= false, 'enabled cannot be disabled'
    end)
    local refused = registered.kora_lib_configCommit({ path = { 'enabled' }, value = false, revision = 1 })
    H.assertFalse(refused.ok)
    H.assertTrue(values.enabled)

    config = makeConfig(library)
    values = config.register({ enabled = config.boolean(true, { live = true }) })
    local applied, observed
    config.onApply(function(proposed, active) applied = { proposed.enabled, active.enabled } end)
    config.bind('sample', { 'enabled' }, function(value, previous, change) observed = { value, previous, change } end)
    local result = registered.kora_lib_configCommit({ path = { 'enabled' }, value = false, revision = 1 })
    H.assertTrue(result.ok, result.error)
    H.assertFalse(applied[1])
    H.assertTrue(applied[2])
    H.assertEqual(observed[1], false)
    H.assertTrue(observed[2])
    H.assertFalse(config.get('sample', { 'enabled' }))
end)

H.test('clients re-request their active snapshot when kora_lib restarts', function()
    local previousIsDuplicityVersion = _G.IsDuplicityVersion
    local previousAddEventHandler = _G.AddEventHandler
    local previousRegisterNetEvent = _G.RegisterNetEvent
    local previousTriggerServerEvent = _G.TriggerServerEvent
    local handlers, requests = {}, {}

    _G.IsDuplicityVersion = function() return false end
    _G.AddEventHandler = function(name, handler) handlers[name] = handler end
    _G.RegisterNetEvent = function() end
    _G.TriggerServerEvent = function(name, resource)
        requests[#requests + 1] = { name = name, resource = resource }
    end

    local worked, failure = pcall(function()
        local clientConfig = makeConfig({})
        clientConfig.define({ speedUnit = clientConfig.enum('kmh', {
            options = { 'kmh', 'mph' }, live = true,
        }) })
        handlers.onClientResourceStart('unrelated')
        handlers.onClientResourceStart('kora_lib')
        handlers.onClientResourceStart('sample')
    end)

    _G.IsDuplicityVersion = previousIsDuplicityVersion
    _G.AddEventHandler = previousAddEventHandler
    _G.RegisterNetEvent = previousRegisterNetEvent
    _G.TriggerServerEvent = previousTriggerServerEvent

    H.assertTrue(worked, failure)
    H.assertEqual(#requests, 3, 'define, kora_lib restart, and owner restart should each request a snapshot')
    for index = 1, #requests do
        H.assertEqual(requests[index].name, 'kora_lib:server:configRequested')
        H.assertEqual(requests[index].resource, 'sample')
    end
end)

H.test('advanced metadata inherits and permits explicit everyday overrides', function()
    files = {}
    local config = makeConfig(library)
    config.define({
        enabled = true,
        entries = config.list({}, config.string('')),
        tuning = config.object({
            timeout = 1000,
            visible = config.boolean(true, { advanced = false }),
        }, { advanced = true }),
        everydayList = config.list({}, config.string(''), { advanced = false }),
    })
    local fields = registrations[#registrations].schema.fields
    H.assertFalse(fields.enabled.advanced)
    H.assertTrue(fields.entries.advanced)
    H.assertTrue(fields.tuning.fields.timeout.advanced)
    H.assertFalse(fields.tuning.fields.visible.advanced)
    H.assertFalse(fields.everydayList.advanced)
    local valid = pcall(function()
        makeConfig(library).define({ value = config.number(1, { advanced = 'yes' }) })
    end)
    H.assertFalse(valid)
end)

H.test('snapshots preserve false values in every container and numeric map keys', function()
    files, registered, registrations = {}, {}, {}
    local config = makeConfig(library)
    config.define({
        enabled = false,
        nested = { enabled = false },
        flags = config.list({ false, true }, config.boolean(false)),
        inferred = config.map({ default = false }, nil),
        classes = config.map({ [0] = false, [7] = true }, nil, { keyType = 'integer' }),
        optional = config.optional(false, config.boolean(true)),
        private = config.boolean(false, { scope = 'server' }),
    })
    local snapshot = registered.kora_lib_configRead()
    H.assertEqual(config.get('sample', { 'classes', '0' }), false)
    for _, values in ipairs({ snapshot.values, snapshot.configured, snapshot.client }) do
        H.assertEqual(values.enabled, false)
        H.assertEqual(values.nested.enabled, false)
        H.assertEqual(values.flags[1], false)
        H.assertEqual(values.inferred.default, false)
        H.assertEqual(values.classes[0], false)
        H.assertEqual(values.classes[7], true)
        H.assertEqual(values.optional, false)
    end
    H.assertEqual(snapshot.client.private, nil)
end)

for name, value in pairs(previousGlobals) do _G[name] = value end

H.test('the deprecated qblib_config* bridge exports stay registered', function()
    registered = {}
    local config = makeConfig(library)
    config.define({ visual = config.number(1, { scope = 'client', live = true }) })
    for _, method in ipairs({ 'Read', 'Commit', 'Reset' }) do
        H.assertTrue(registered['qblib_config' .. method] ~= nil, 'missing deprecated export ' .. method)
        H.assertEqual(registered['qblib_config' .. method], registered['kora_lib_config' .. method])
    end
end)

H.report('config')
