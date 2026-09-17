local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local H = require('harness')
local definition, openArgs, committed = nil, nil, nil
local restarted
local events = {}
local entry = {
    resource = 'sample', revision = 2, loaded = true,
    schema = { kind = 'object', fields = { enabled = { kind = 'boolean', path = { 'enabled' }, label = 'Enabled',
        description = 'Controls whether the sample is enabled.', scope = 'shared', live = true } } },
    configured = { enabled = true }, values = { enabled = false },
}
local otherEntry = {
    resource = 'other', revision = 1, loaded = true,
    schema = { kind = 'object', fields = {
        mode = { kind = 'enum', path = { 'mode' }, label = 'Mode',
            description = 'Select the operating mode.', scope = 'shared', live = false,
            options = { { value = 1, label = 'One' }, { value = 2, label = 'Two' } } },
        nickname = { kind = 'string', path = { 'nickname' }, label = 'Nickname',
            description = 'Optional display name.', scope = 'shared', live = false },
    } },
    configured = { mode = 1, nickname = '' }, values = { mode = 1, nickname = '' },
}

local function navigation(id)
    for _, item in ipairs(definition.navigation or {}) do
        if item.id == id then return item end
    end
end

QB = {
    callback = { trigger = function(name, request)
        if name == 'qblib:configCatalog' then return {
            { resource = entry.resource, revision = entry.revision, schema = entry.schema, loaded = false },
            { resource = otherEntry.resource, revision = otherEntry.revision, schema = otherEntry.schema, loaded = false },
        } end
        if name == 'qblib:configRead' then
            if request == 'sample' then return entry end
            if request == 'other' then return otherEntry end
            return nil, 'configuration is unavailable'
        end
        if name == 'qblib:configCommit' then
            committed = request
            local target = request.resource == 'sample' and entry or otherEntry
            target.configured[request.path[1]] = request.value
            target.values[request.path[1]] = request.value
            target.revision = target.revision + 1
            return { ok = true, applied = request.resource == 'sample' }
        end
        if name == 'qblib:configReset' then return { ok = true, applied = true } end
        if name == 'qblib:configRestart' then restarted = request; return { ok = true } end
    end },
    config = {}, notify = { send = function() end },
    nui = { registerApp = function(value) definition = value end, openApp = function(_, opts) openArgs = opts end },
}
json = {
    encode = function(value)
        if type(value) == 'string' then return ('%q'):format(value) end
        if type(value) == 'number' or type(value) == 'boolean' then return tostring(value) end
        return '{}'
    end,
    decode = function(value)
        if value == '42' then return 42 end
        if value == 'true' then return true end
        if value == 'false' then return false end
        local quoted = value:match('^"(.*)"$')
        if quoted then return quoted end
        return {}
    end,
}
function RegisterNetEvent(name, handler) events[name] = handler end

dofile(repoRoot .. 'modules/config/editor_client.lua')

H.test('every registered resource remains available in the sidebar', function()
    QB.config.open('sample')
    H.assertEqual(definition.id, 'qblib:config')
    H.assertEqual(openArgs.viewId, 'resource:sample')
    H.assertEqual(definition.navigation[1].id, 'resources')
    H.assertEqual(definition.navigation[2].label, 'other')
    H.assertEqual(definition.navigation[3].label, 'sample')
    H.assertEqual(definition.navigation[2].group, 'Resources')
    H.assertEqual(definition.navigation[3].onOpen, 'config:resource')
    H.assertEqual(definition.navigation[3].badge, 1)

    local tableBlock = navigation('resource:sample').content.blocks[1]
    H.assertEqual(tableBlock.columns[1].key, 'label')
    H.assertEqual(tableBlock.columns[2].key, 'description')
    H.assertEqual(tableBlock.columns[2].width, '34%')
    H.assertEqual(tableBlock.rows[1].label.label, 'Enabled')
    H.assertEqual(tableBlock.rows[1].label.description, 'Key: enabled')
    H.assertEqual(tableBlock.rows[1].key, 'enabled')
    H.assertEqual(tableBlock.rows[1].description, 'Controls whether the sample is enabled.')
end)

H.test('editing stays inside the resource view and saves via qblib callbacks', function()
    events['qblib:client:configOpened']()
    definition.onAction('config:resource', { viewId = 'resources', itemId = 'resource:sample' })
    local result = definition.onAction('config:setting', { viewId = 'resource:sample', itemId = 'enabled' })
    local sampleView
    for _, item in ipairs(result.update.navigation) do
        if item.id == 'resource:sample' then sampleView = item break end
    end
    H.assertTrue(sampleView ~= nil)
    H.assertEqual(sampleView.content.blocks[2].type, 'form')
    H.assertEqual(sampleView.content.blocks[2].fields[1].id, 'value')
    H.assertEqual(result.navigate.viewId, 'resource:sample')
    H.assertEqual(#result.update.navigation, 3)

    result = definition.onAction('config:save', { viewId = 'resource:sample', value = { value = false } })
    H.assertEqual(committed.resource, 'sample')
    H.assertEqual(committed.path[1], 'enabled')
    H.assertFalse(committed.value)
    H.assertEqual(result.notice.tone, 'success')
    for _, item in ipairs(result.update.navigation) do
        if item.id == 'resource:sample' then
            H.assertEqual(item.content.blocks[2].id, 'config-edit-form-3')
            break
        end
    end
end)

H.test('vectors and optional values use typed controls instead of raw JSON', function()
    entry.schema = { kind = 'object', fields = {
        location = { kind = 'vector3', path = { 'location' }, label = 'Location',
            description = 'World location.', scope = 'shared', live = true },
        note = { kind = 'optional', path = { 'note' }, label = 'Note', description = 'Optional note.',
            scope = 'shared', live = true, innerDefault = 'example',
            inner = { kind = 'string', path = { 'note' }, label = 'Note', scope = 'shared' } },
    } }
    entry.configured = { location = { x = 1, y = 2, z = 3 } }
    entry.values = { location = { x = 1, y = 2, z = 3 } }

    QB.config.open('sample')
    local result = definition.onAction('config:setting', {
        viewId = 'resource:sample', itemId = 'location',
    })
    local sampleView
    for _, item in ipairs(result.update.navigation) do
        if item.id == 'resource:sample' then sampleView = item break end
    end
    local vector = sampleView.content.blocks[2].fields[1]
    H.assertEqual(vector.type, 'vector')
    H.assertEqual(vector.dimensions, 3)
    H.assertEqual(vector.default.z, 3)
    definition.onAction('config:save', {
        viewId = 'resource:sample', value = { value = { x = 4, y = 5, z = 6 } },
    })
    H.assertEqual(committed.value.y, 5)

    result = definition.onAction('config:setting', { viewId = 'resource:sample', itemId = 'note' })
    for _, item in ipairs(result.update.navigation) do
        if item.id == 'resource:sample' then sampleView = item break end
    end
    local fields = sampleView.content.blocks[2].fields
    H.assertEqual(fields[1].id, 'valueEnabled')
    H.assertFalse(fields[1].default)
    H.assertEqual(fields[2].default, 'example')
    H.assertEqual(fields[2].visibleWhen.fieldId, 'valueEnabled')

    definition.onAction('config:save', {
        viewId = 'resource:sample', value = { valueEnabled = true, value = 'hello' },
    })
    H.assertEqual(committed.value, 'hello')
    definition.onAction('config:save', {
        viewId = 'resource:sample', value = { valueEnabled = false, value = 'ignored' },
    })
    H.assertEqual(committed.value, nil)
end)

H.test('restart-required resources expose and run an explicit apply action', function()
    QB.config.open('other')
    local view = navigation('resource:other')
    H.assertEqual(view.content.actions[1].id, 'config:restart')
    local result = definition.onAction('config:restart', { viewId = 'resource:other' })
    H.assertEqual(restarted, 'other')
    H.assertEqual(result.notice.tone, 'success')
end)

H.test('enum values retain their authored type and strings may be empty', function()
    QB.config.open('other')
    local result = definition.onAction('config:setting', { viewId = 'resource:other', itemId = 'mode' })
    local otherView
    for _, item in ipairs(result.update.navigation) do
        if item.id == 'resource:other' then otherView = item break end
    end
    local enumField = otherView.content.blocks[2].fields[1]
    H.assertEqual(enumField.default, 'config-option:1')
    H.assertEqual(enumField.options[2].value, 'config-option:2')

    definition.onAction('config:save', {
        viewId = 'resource:other', value = { value = 'config-option:2' },
    })
    H.assertEqual(committed.value, 2)

    result = definition.onAction('config:setting', { viewId = 'resource:other', itemId = 'nickname' })
    for _, item in ipairs(result.update.navigation) do
        if item.id == 'resource:other' then otherView = item break end
    end
    H.assertFalse(otherView.content.blocks[2].fields[1].required)
    definition.onAction('config:save', { viewId = 'resource:other', value = { value = '' } })
    H.assertEqual(committed.value, '')
end)

H.test('numeric config keys keep their authored values in the editor', function()
    entry.schema = { kind = 'object', fields = {
        restricted = { kind = 'object', path = { 'restricted' }, fieldKeys = { ['2'] = 2 }, fields = {
            ['2'] = { kind = 'boolean', path = { 'restricted', '2' }, label = 'Restricted 2',
                description = 'Controls restriction two.', scope = 'shared' },
        } },
    } }
    entry.configured = { restricted = { [2] = true } }
    entry.values = { restricted = { [2] = false } }

    QB.config.open('sample')
    local result = definition.onAction('config:setting', {
        viewId = 'resource:sample', itemId = 'restricted\31' .. '2',
    })
    local details
    for _, item in ipairs(result.update.navigation) do
        if item.id == 'resource:sample' then details = item.content.blocks[1].items break end
    end
    H.assertEqual(details[2].value, 'true')
    H.assertEqual(details[3].value, 'false')
end)

H.test('list settings use editable key and value rows and preserve value types', function()
    entry.schema = { kind = 'object', fields = {
        locations = { kind = 'list', path = { 'locations' }, label = 'Locations',
            description = 'Ordered locations.', scope = 'shared', items = {
                { kind = 'string', path = { 'locations', '1' }, label = 'Location' },
            } },
    } }
    entry.configured = { locations = { 'airport' } }
    entry.values = { locations = { 'airport' } }

    QB.config.open('sample')
    local result = definition.onAction('config:setting', {
        viewId = 'resource:sample', itemId = 'locations',
    })
    local field
    for _, item in ipairs(result.update.navigation) do
        if item.id == 'resource:sample' then field = item.content.blocks[2].fields[1] break end
    end
    H.assertEqual(field.type, 'key-value')
    H.assertEqual(field.keyMode, 'integer')
    H.assertEqual(field.default[1].key, '1')
    H.assertEqual(field.default[1].value, '"airport"')

    definition.onAction('config:save', { viewId = 'resource:sample', value = { value = {
        { key = '1', value = '"city"' },
        { key = '2', value = '42' },
    } } })
    H.assertEqual(committed.value[1], 'city')
    H.assertEqual(committed.value[2], 42)
end)

H.test('map settings accept new text keys and boolean values', function()
    entry.schema = { kind = 'object', fields = {
        roles = { kind = 'map', path = { 'roles' }, label = 'Roles',
            description = 'Authorised roles.', scope = 'shared',
            item = { kind = 'boolean', path = { 'roles', '*' }, label = 'Role' },
            values = { police = { kind = 'boolean', path = { 'roles', 'police' }, label = 'Police' } } },
    } }
    entry.configured = { roles = { police = true } }
    entry.values = { roles = { police = true } }

    QB.config.open('sample')
    local result = definition.onAction('config:setting', {
        viewId = 'resource:sample', itemId = 'roles',
    })
    local field
    for _, item in ipairs(result.update.navigation) do
        if item.id == 'resource:sample' then field = item.content.blocks[2].fields[1] break end
    end
    H.assertEqual(field.type, 'key-value')
    H.assertEqual(field.keyMode, 'string')

    definition.onAction('config:save', { viewId = 'resource:sample', value = { value = {
        { key = 'police', value = 'true' },
        { key = 'ambulance', value = 'false' },
    } } })
    H.assertTrue(committed.value.police)
    H.assertFalse(committed.value.ambulance)
end)

H.test('unavailable resource actions return a visible workflow error', function()
    local result = definition.onAction('config:resource', { viewId = 'resources', itemId = 'missing' })
    H.assertEqual(result.notice.tone, 'destructive')
    H.assertEqual(result.notice.message, 'configuration is unavailable')
end)

H.report('config_editor_client')
