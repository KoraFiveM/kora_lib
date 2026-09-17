-- AppShell presentation for qblib's configuration service. The server owns
-- authorization; this client file never treats a locally opened app as access.

local catalog = {}
local entriesByResource = {}
local resourcesByView = {}
local activeEdit
local ENUM_OPTION_PREFIX = 'config-option:'

local function pathId(path) return table.concat(path, '\31') end
local function displayPath(path) return table.concat(path, '.') end
local function resourceViewId(resource) return 'resource:' .. resource end

local function objectTableKey(schema, key)
    return schema.fieldKeys and schema.fieldKeys[key] or key
end

-- Calls made from qblib itself receive the raw callback promise. Consumer
-- resources get the auto-awaited export result, so normalize both paths here.
local function triggerCallback(name, ...)
    local direct = table.pack(QB.callback.trigger(name, ...))
    local response = direct[1]
    if type(response) ~= 'table' or response.state == nil then
        return table.unpack(direct, 1, direct.n)
    end

    local result = Citizen.Await(response)
    local packed = response.qblibCallbackResults
    if packed then return table.unpack(packed, 1, packed.n) end
    return result
end

local function displayValue(value)
    if type(value) == 'table' then
        local ok, encoded = pcall(json.encode, value)
        return ok and encoded or '[complex value]'
    end
    return value == nil and 'nil' or tostring(value)
end

local function schemaLeaves(schema, configured, running, out)
    if type(schema) ~= 'table' or schema.sensitive then return end
    if schema.kind == 'object' then
        for key, child in pairs(schema.fields or {}) do
            local tableKey = objectTableKey(schema, key)
            local configuredValue
            local runningValue
            if type(configured) == 'table' then configuredValue = configured[tableKey] end
            if type(running) == 'table' then runningValue = running[tableKey] end
            schemaLeaves(child, configuredValue, runningValue, out)
        end
        return
    end
    out[#out + 1] = { schema = schema, configured = configured, running = running }
end

local function settingsFor(entry)
    if entry._settings and entry._settingsSchema == entry.schema
        and entry._settingsConfigured == entry.configured and entry._settingsValues == entry.values then
        return entry._settings
    end
    local leaves = {}
    if not entry.unavailable then schemaLeaves(entry.schema, entry.configured, entry.values, leaves) end
    table.sort(leaves, function(a, b) return displayPath(a.schema.path) < displayPath(b.schema.path) end)
    entry._settings = leaves
    entry._settingsSchema = entry.schema
    entry._settingsConfigured = entry.configured
    entry._settingsValues = entry.values
    return leaves
end

local function findSetting(entry, id)
    for _, setting in ipairs(settingsFor(entry)) do
        if pathId(setting.schema.path) == id then return setting end
    end
end

local function encodeFieldValue(value)
    if value == nil then return '' end
    local ok, encoded = pcall(json.encode, value)
    return ok and encoded or ''
end

local function tableRows(value, kind)
    local rows = {}
    if type(value) ~= 'table' then return rows end

    if kind == 'list' then
        for index = 1, #value do
            rows[#rows + 1] = { key = tostring(index), value = encodeFieldValue(value[index]) }
        end
        return rows
    end

    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys)
    for index = 1, #keys do
        local key = keys[index]
        rows[#rows + 1] = { key = key, value = encodeFieldValue(value[key]) }
    end
    return rows
end

local fieldForSchema

fieldForSchema = function(schema, value, id, label, description)
    local common = { id = id, label = label or schema.label, description = description or schema.description }

    if schema.kind == 'optional' then
        local enabledId = id .. 'Enabled'
        local fields = { {
            id = enabledId,
            label = 'Set a value',
            description = ('When disabled, %s uses no override value.'):format(label or schema.label),
            type = 'checkbox',
            default = value ~= nil,
        } }
        local innerValue = value ~= nil and value or schema.innerDefault
        local innerFields = fieldForSchema(schema.inner, innerValue, id, label or schema.label,
            description or schema.description)
        for _, field in ipairs(innerFields) do
            field.visibleWhen = { fieldId = enabledId, equals = true }
            fields[#fields + 1] = field
        end
        return fields
    end

    if schema.kind == 'boolean' then
        common.type = 'checkbox'
        common.default = value == true
        return { common }
    end
    if schema.kind == 'number' or schema.kind == 'integer' then
        common.type = 'number'
        common.default = value
        common.min = schema.min
        common.max = schema.max
        common.step = schema.step or (schema.kind == 'integer' and 1 or 0.1)
        common.wholeNumber = schema.kind == 'integer'
        common.required = true
        return { common }
    end
    if schema.kind == 'enum' then
        local options = {}
        local selected
        for index, option in ipairs(schema.options or {}) do
            local candidate = type(option) == 'table' and option.value or option
            local token = ENUM_OPTION_PREFIX .. index
            options[#options + 1] = {
                value = token,
                label = type(option) == 'table' and (option.label or tostring(candidate)) or tostring(candidate),
            }
            if candidate == value then selected = token end
        end
        common.type = 'select'
        common.default = selected
        common.options = options
        common.required = true
        return { common }
    end
    if schema.kind == 'string' then
        common.type = 'text'
        common.default = type(value) == 'string' and value or ''
        common.required = schema.minLength ~= nil and schema.minLength > 0
        common.minLength = schema.minLength
        common.maxLength = schema.maxLength
        -- Config patterns are Lua patterns, not JavaScript regular
        -- expressions. The owner validates them on save; passing one to the
        -- browser would incorrectly reject valid Lua-pattern input.
        return { common }
    end
    if schema.kind == 'color' then
        common.type = 'color'
        common.colorFormat = 'hex'
        common.default = type(value) == 'string' and value or '#000000'
        common.required = true
        return { common }
    end
    if schema.kind == 'list' or schema.kind == 'map' then
        common.type = 'key-value'
        common.default = tableRows(value, schema.kind)
        common.keyMode = schema.kind == 'list' and 'integer' or 'string'
        common.keyLabel = schema.kind == 'list' and 'Position' or 'Key'
        common.valueLabel = 'Value (JSON or text)'
        common.addRowLabel = 'Add row'
        common.removeRowLabel = 'Delete row'
        return { common }
    end
    if schema.kind == 'vector2' or schema.kind == 'vector3' or schema.kind == 'vector4' then
        common.type = 'vector'
        common.dimensions = schema.kind == 'vector2' and 2 or schema.kind == 'vector3' and 3 or 4
        common.default = type(value) == 'table' and {
            x = value.x,
            y = value.y,
            z = value.z,
            w = value.w,
        } or { x = '', y = '', z = '', w = '' }
        common.required = true
        return { common }
    end

    common.type = 'textarea'
    common.default = encodeFieldValue(value)
    common.required = true
    common.rows = 8
    return { common }
end

local function fieldFor(setting)
    return fieldForSchema(setting.schema, setting.configured, 'value')
end

local function trimmed(value)
    return value:match('^%s*(.-)%s*$') or ''
end

local function decodeRowValue(raw, rowIndex)
    if type(raw) ~= 'string' or trimmed(raw) == '' then
        error(('Row %d needs a value.'):format(rowIndex), 0)
    end

    local ok, decoded = pcall(json.decode, raw)
    if ok and decoded ~= nil then return decoded end

    local draft = trimmed(raw)
    local first = draft:sub(1, 1)
    if first == '{' or first == '[' or first == '"' or draft == 'true' or draft == 'false'
        or draft == 'null' or tonumber(draft) ~= nil then
        error(('Row %d contains invalid JSON.'):format(rowIndex), 0)
    end
    return raw
end

local function inputTableValue(kind, rows)
    if type(rows) ~= 'table' then error('Enter one or more key and value rows.', 0) end

    local output, seen = {}, {}
    for index = 1, #rows do
        local row = rows[index]
        if type(row) ~= 'table' or type(row.key) ~= 'string' then
            error(('Row %d is invalid.'):format(index), 0)
        end
        local key = trimmed(row.key)
        if key == '' then error(('Row %d needs a key.'):format(index), 0) end
        if kind == 'list' then
            key = tonumber(key)
            if not key or key < 1 or key % 1 ~= 0 then
                error(('Row %d needs a positive whole-number position.'):format(index), 0)
            end
        end
        if seen[key] then error(('Key %q is used more than once.'):format(tostring(key)), 0) end
        seen[key] = true
        output[key] = decodeRowValue(row.value, index)
    end

    if kind == 'list' then
        for index = 1, #rows do
            if output[index] == nil then
                error('List positions must run consecutively from 1. Reorder the position values and try again.', 0)
            end
        end
    end
    return output
end

local function inputValueForSchema(schema, values, id)
    local kind = schema.kind
    if kind == 'optional' then
        if values[id .. 'Enabled'] ~= true then return nil end
        return inputValueForSchema(schema.inner, values, id)
    end
    if kind == 'enum' then
        local raw = values[id]
        local index = type(raw) == 'string' and raw:sub(1, #ENUM_OPTION_PREFIX) == ENUM_OPTION_PREFIX
            and tonumber(raw:sub(#ENUM_OPTION_PREFIX + 1)) or nil
        local option = index and (schema.options or {})[index] or nil
        if option == nil then error('Choose one of the available options.', 0) end
        return type(option) == 'table' and option.value or option
    end
    if kind == 'string' or kind == 'color' or kind == 'boolean' or kind == 'number'
        or kind == 'integer' or kind == 'vector2' or kind == 'vector3' or kind == 'vector4' then
        return values[id]
    end
    if kind == 'list' or kind == 'map' then return inputTableValue(kind, values[id]) end
    local ok, decoded = pcall(json.decode, values[id] or '')
    if not ok or decoded == nil then error('Enter a valid JSON value.', 0) end
    return decoded
end

local function inputValue(setting, values)
    return inputValueForSchema(setting.schema, values, 'value')
end

local function setCatalog(entries)
    catalog = entries or {}
    table.sort(catalog, function(a, b) return a.resource < b.resource end)
    entriesByResource = {}
    resourcesByView = {}
    for _, entry in ipairs(catalog) do
        entriesByResource[entry.resource] = entry
        resourcesByView[resourceViewId(entry.resource)] = entry.resource
    end
end

local function replaceEntry(entry)
    local replaced = false
    for index = 1, #catalog do
        if catalog[index].resource == entry.resource then
            catalog[index] = entry
            replaced = true
            break
        end
    end
    if not replaced then catalog[#catalog + 1] = entry end
    setCatalog(catalog)
end

local function settingsContent(entry)
    if entry.unavailable then
        return {
            title = entry.resource,
            description = 'This resource registered configuration, but its current values could not be read.',
            blocks = { { type = 'empty', title = 'Configuration unavailable',
                description = entry.error or 'Restart the resource and reopen the editor.' } },
        }
    end

    if not entry.loaded then
        return {
            title = entry.resource,
            description = ('%d editable configuration option%s.'):format(#settingsFor(entry),
                #settingsFor(entry) == 1 and '' or 's'),
            blocks = { { type = 'empty', title = 'Loading configuration',
                description = 'The latest saved and running values are being requested from this resource.' } },
        }
    end

    local rows = {}
    for _, setting in ipairs(settingsFor(entry)) do
        rows[#rows + 1] = {
            id = pathId(setting.schema.path),
            label = {
                label = setting.schema.label,
                description = ('Key: %s'):format(displayPath(setting.schema.path)),
            },
            key = displayPath(setting.schema.path),
            description = setting.schema.description,
            value = displayValue(setting.configured),
            status = { label = setting.schema.live and 'Applies now' or 'Restart required', badge = true,
                tone = setting.schema.live and 'success' or 'warning' },
            scope = setting.schema.scope,
        }
    end

    local content = {
        title = entry.resource,
        description = ('%d editable configuration option%s.'):format(#rows, #rows == 1 and '' or 's'),
        blocks = { {
            id = 'config-settings', type = 'table', searchable = true, pageSize = 20,
            searchPlaceholder = 'Search settings…',
            columns = {
                { key = 'label', label = 'Setting', sortable = true, width = '18%' },
                { key = 'description', label = 'Description', width = '34%' },
                { key = 'value', label = 'Saved value', width = '26%' },
                { key = 'scope', label = 'Scope', width = '9%' },
                { key = 'status', label = 'Effect', width = '9%' },
            },
            rows = rows,
            empty = 'This resource has no editable settings.',
            action = 'config:setting',
            idKey = 'id',
        } },
    }
    local needsRestart = false
    for _, setting in ipairs(settingsFor(entry)) do
        if not setting.schema.live then needsRestart = true break end
    end
    if needsRestart and entry.resource ~= 'qblib' then
        content.actions = { {
            id = 'config:restart', label = 'Restart resource to apply saved changes', icon = 'refresh-cw',
            variant = 'outline',
            confirm = ('Restart %s now? Active scripts in this resource will briefly stop and connected players may notice the interruption.'):format(entry.resource),
        } }
    end
    return content
end

local function editContent(entry, setting)
    local appliesNow = setting.schema.live == true
    local actions = {
        { id = 'config:reset', label = 'Reset to authored default', icon = 'rotate-ccw', variant = 'outline',
            confirm = 'Remove this in-game override?' },
        { id = 'config:back', label = ('Back to %s'):format(entry.resource), icon = 'arrow-left', variant = 'ghost' },
    }
    if not appliesNow and entry.resource ~= 'qblib' then
        table.insert(actions, 2, {
            id = 'config:restart', label = 'Restart resource now', icon = 'refresh-cw', variant = 'outline',
            confirm = ('Restart %s now? Active scripts in this resource will briefly stop and connected players may notice the interruption.'):format(entry.resource),
        })
    end
    return {
        title = setting.schema.label,
        description = setting.schema.description or displayPath(setting.schema.path),
        blocks = {
            {
                id = 'config-edit-details', type = 'details', columns = 3,
                items = {
                    { label = 'Configuration key', value = displayPath(setting.schema.path) },
                    { label = 'Saved value', value = displayValue(setting.configured) },
                    { label = 'Running value', value = displayValue(setting.running) },
                    { label = 'Scope', value = setting.schema.scope },
                    { label = 'Effect', value = appliesNow and 'Applies immediately' or 'Restart required',
                        tone = appliesNow and 'success' or 'warning' },
                },
            },
            {
                -- AppShell retains drafts by block id. Include the resource
                -- revision so save/reset rebuilds the form from the freshly
                -- read value instead of leaving the previous draft visible.
                id = 'config-edit-form-' .. tostring(entry.revision), type = 'form',
                title = appliesNow and 'New value' or 'New value (applies after restart)',
                description = appliesNow and 'This change applies immediately.'
                    or 'This change is saved and applies when the resource restarts.',
                fields = fieldFor(setting),
                action = { id = 'config:save', label = 'Save setting', icon = 'save', variant = 'primary' },
                submitLabel = appliesNow and 'Save setting' or 'Save for restart',
            },
        },
        actions = actions,
    }
end

local function buildDefinition()
    local rows = {}
    local navigation = {
        {
            id = 'resources', label = 'Overview', icon = 'boxes', content = {
                title = 'Registered resources',
                description = 'Choose a resource here or directly from the sidebar.',
                blocks = { {
                    id = 'config-resources', type = 'table', searchable = true, pageSize = 18,
                    searchPlaceholder = 'Search resources…',
                    columns = {
                        { key = 'resource', label = 'Resource', sortable = true },
                        { key = 'settings', label = 'Settings', align = 'right', sortable = true },
                        { key = 'status', label = 'Status' },
                    },
                    rows = rows,
                    empty = 'No resource has registered configuration yet.',
                    action = 'config:resource', idKey = 'id',
                } },
            },
        },
    }

    for _, entry in ipairs(catalog) do
        local count = #settingsFor(entry)
        rows[#rows + 1] = {
            id = entry.resource,
            resource = entry.resource,
            settings = count,
            status = {
                label = entry.unavailable and 'Unavailable' or entry.loaded and 'Ready' or 'Registered',
                tone = entry.unavailable and 'warning' or 'success',
                badge = true,
            },
        }

        local content = settingsContent(entry)
        if activeEdit and activeEdit.resource == entry.resource then
            local setting = findSetting(entry, activeEdit.settingId)
            if setting then content = editContent(entry, setting) else activeEdit = nil end
        end

        navigation[#navigation + 1] = {
            id = resourceViewId(entry.resource),
            label = entry.resource,
            description = entry.unavailable and 'Configuration unavailable' or ('%d editable settings'):format(count),
            icon = 'sliders-horizontal',
            badge = entry.unavailable and '!' or count,
            group = 'Resources',
            onOpen = 'config:resource',
            disabled = entry.unavailable == true,
            content = content,
        }
    end

    return {
        id = 'qblib:config',
        title = 'Configuration',
        icon = 'settings',
        defaultView = 'resources',
        description = 'Edit registered resource settings without replacing their authored config.lua files.',
        footer = 'Live changes apply now. Other changes are saved for the next resource restart.',
        navigation = navigation,
    }
end

local function updateNavigation(notice, viewId)
    return {
        update = { navigation = buildDefinition().navigation },
        navigate = viewId and { viewId = viewId, replace = true } or nil,
        notice = notice,
    }
end

local function readResource(resource)
    local entry, readError = triggerCallback('qblib:configRead', resource)
    if not entry then return nil, readError or 'Could not read resource configuration.' end
    replaceEntry(entry)
    return entry
end

local function handleAction(action, context)
    context = context or {}

    if action == 'config:resource' then
        local resource = resourcesByView[context.itemId] or context.itemId
        if type(resource) ~= 'string' then
            return updateNavigation({ tone = 'destructive', message = 'That resource is no longer available.' })
        end
        local entry, readError = readResource(resource)
        if not entry then return updateNavigation({ tone = 'destructive', message = readError }) end
        activeEdit = nil
        return updateNavigation(nil, resourceViewId(entry.resource))
    end

    if action == 'config:setting' then
        local resource = resourcesByView[context.viewId]
        local entry = resource and entriesByResource[resource] or nil
        local setting = entry and findSetting(entry, context.itemId)
        if not setting then
            return updateNavigation({ tone = 'destructive', message = 'That setting is no longer available.' }, context.viewId)
        end
        activeEdit = { resource = resource, settingId = pathId(setting.schema.path) }
        return updateNavigation(nil, context.viewId)
    end

    if action == 'config:back' then
        activeEdit = nil
        return updateNavigation(nil, context.viewId)
    end

    if action == 'config:restart' then
        local resource = resourcesByView[context.viewId]
        if not resource or resource == 'qblib' then
            return updateNavigation({ tone = 'destructive',
                message = 'That resource cannot be restarted from this editor.' }, context.viewId)
        end
        local response, restartError = triggerCallback('qblib:configRestart', resource)
        if not response or not response.ok then
            return updateNavigation({ tone = 'destructive',
                message = (response and response.error) or restartError or 'The resource could not be restarted.' }, context.viewId)
        end
        local refreshed, refreshError = readResource(resource)
        if not refreshed then
            activeEdit = nil
            return updateNavigation({ tone = 'warning', message = refreshError
                or 'The resource restarted, but its refreshed configuration is not available yet.' }, context.viewId)
        end
        return updateNavigation({ tone = 'success',
            message = ('%s restarted and loaded its saved configuration.'):format(resource) }, context.viewId)
    end

    if action == 'config:save' or action == 'config:reset' then
        local resource = activeEdit and activeEdit.resource
        local entry = resource and entriesByResource[resource] or nil
        local setting = entry and findSetting(entry, activeEdit.settingId)
        if not setting or context.viewId ~= resourceViewId(resource) then
            return updateNavigation({ tone = 'destructive', message = 'That setting is no longer available.' }, context.viewId)
        end

        local request = { resource = resource, path = setting.schema.path, revision = entry.revision }
        local response, requestError
        if action == 'config:save' then
            local valid, value = pcall(inputValue, setting, context.value or {})
            if not valid then
                return updateNavigation({ tone = 'destructive', message = tostring(value) }, context.viewId)
            end
            request.value = value
            response, requestError = triggerCallback('qblib:configCommit', request)
        else
            response, requestError = triggerCallback('qblib:configReset', request)
        end

        if not response or not response.ok then
            return updateNavigation({ tone = 'destructive',
                message = (response and response.error) or requestError or 'Configuration change failed.' }, context.viewId)
        end

        local refreshed, refreshError = readResource(resource)
        if not refreshed then
            return updateNavigation({ tone = 'warning',
                message = refreshError or 'The setting saved, but its refreshed value is unavailable.' }, context.viewId)
        end

        activeEdit = { resource = resource, settingId = pathId(request.path) }
        local verb = action == 'config:reset' and 'reset' or 'updated'
        local message = response.applied and ('Configuration %s live.'):format(verb)
            or ('Configuration %s; restart %s to apply it.'):format(verb, resource)
        return updateNavigation({ tone = response.applied and 'success' or 'warning', message = message }, context.viewId)
    end

    return updateNavigation({ tone = 'destructive', message = 'That configuration action is no longer available.' }, context.viewId)
end

local function openEditor(resource)
    local result, err = triggerCallback('qblib:configCatalog')
    if not result then
        return QB.notify.send({ type = 'error', message = err or 'You do not have access to configuration.' })
    end

    activeEdit = nil
    setCatalog(result)

    local viewId
    if resource then
        local entry = entriesByResource[resource]
        if not entry or not entry.loaded or entry.unavailable then
            local refreshed, readError = readResource(resource)
            if not refreshed then
                QB.notify.send({ type = 'error', message = readError or 'Could not read resource configuration.' })
            end
            entry = refreshed
        end
        if entry and not entry.unavailable then viewId = resourceViewId(entry.resource) end
    end

    local definition = buildDefinition()
    definition.onAction = handleAction
    QB.nui.registerApp(definition)
    QB.nui.openApp('qblib:config', { viewId = viewId })
end

function QB.config.open(resource)
    assert(resource == nil or type(resource) == 'string', 'Configuration resource must be a string.')
    openEditor(resource)
end

RegisterNetEvent('qblib:client:configOpened', function(resource)
    QB.config.open(resource)
end)
