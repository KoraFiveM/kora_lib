-- AppShell presentation for qblib's configuration service. The server owns
-- authorization; this client file never treats a locally opened app as access.

local catalog = {}
local selected

local function pathId(path) return table.concat(path, '\31') end
local function displayPath(path) return table.concat(path, '.') end

local function displayValue(value)
    if type(value) == 'table' then
        local ok, encoded = pcall(json.encode, value)
        return ok and encoded or '[complex value]'
    end
    return value == nil and 'Default / nil' or tostring(value)
end

local function schemaLeaves(schema, configured, running, out)
    if type(schema) ~= 'table' or schema.sensitive then return end
    if schema.kind == 'object' then
        for key, child in pairs(schema.fields or {}) do schemaLeaves(child, configured and configured[key], running and running[key], out) end
        return
    end
    out[#out + 1] = { schema = schema, configured = configured, running = running }
end

local function fieldFor(setting)
    local schema, value = setting.schema, setting.configured
    if schema.kind == 'boolean' then return { { id = 'value', label = schema.label, type = 'checkbox', default = value == true } } end
    if schema.kind == 'number' or schema.kind == 'integer' then
        return { { id = 'value', label = schema.label, type = 'number', default = value, min = schema.min, max = schema.max,
            step = schema.step or (schema.kind == 'integer' and 1 or 0.1), required = true } }
    end
    if schema.kind == 'enum' then
        local options = {}
        for _, option in ipairs(schema.options or {}) do
            options[#options + 1] = type(option) == 'table' and { value = option.value, label = option.label or tostring(option.value) }
                or { value = option, label = tostring(option) }
        end
        return { { id = 'value', label = schema.label, type = 'select', default = value, options = options, required = true } }
    end
    local text = type(value) == 'string' and value or json.encode(value)
    return { { id = 'value', label = schema.label, description = schema.description or 'Enter structured values as JSON.',
        type = (schema.kind == 'string' or schema.kind == 'color') and 'text' or 'textarea', default = text, required = schema.kind ~= 'optional' } }
end

local function inputValue(setting, values)
    local kind = setting.schema.kind
    if kind == 'string' or kind == 'color' or kind == 'boolean' or kind == 'number' or kind == 'integer' or kind == 'enum' then return values.value end
    if values.value == '' and kind == 'optional' then return nil end
    local ok, decoded = pcall(json.decode, values.value or '')
    assert(ok and decoded ~= nil, 'Enter a valid JSON value.')
    return decoded
end

local function baseDefinition()
    local rows = {}
    for _, entry in ipairs(catalog) do rows[#rows + 1] = { id = entry.resource, resource = entry.resource, fields = 'Open editor' } end
    return {
        id = 'qblib:config', title = 'Configuration', icon = 'settings', defaultView = 'resources',
        description = 'Saved edits preserve each resource’s authored config.lua.',
        footer = 'Live changes apply now. Other changes are saved for the next resource restart.',
        navigation = { { id = 'resources', label = 'Resources', icon = 'boxes', content = { title = 'Registered Resources',
            blocks = { { id = 'config-resources', type = 'table', searchable = true, pageSize = 18,
                columns = { { key = 'resource', label = 'Resource', sortable = true }, { key = 'fields', label = 'Configuration' } },
                rows = rows, empty = 'No resource has registered configuration yet.', action = 'config:resource', idKey = 'id' } } } } },
    }
end

local function addSettingsView(definition, entry)
    local leaves, rows = {}, {}
    schemaLeaves(entry.schema, entry.configured, entry.values, leaves)
    table.sort(leaves, function(a, b) return displayPath(a.schema.path) < displayPath(b.schema.path) end)
    for _, setting in ipairs(leaves) do
        rows[#rows + 1] = { id = pathId(setting.schema.path), path = displayPath(setting.schema.path), value = displayValue(setting.configured),
            status = { label = setting.schema.live and 'Applies now' or 'Restart required', badge = true, tone = setting.schema.live and 'success' or 'warning' },
            scope = setting.schema.scope }
    end
    definition.navigation[#definition.navigation + 1] = { id = 'settings', label = entry.resource, icon = 'sliders-horizontal', content = {
        title = entry.resource, blocks = { { id = 'config-settings', type = 'table', searchable = true, pageSize = 20,
            columns = { { key = 'path', label = 'Setting', sortable = true }, { key = 'value', label = 'Saved value' }, { key = 'scope', label = 'Scope' }, { key = 'status', label = 'Effect' } },
            rows = rows, empty = 'This resource has no editable settings.', action = 'config:setting', idKey = 'id' } } } }
end

local function addSelectedView(definition, setting)
    definition.navigation[#definition.navigation + 1] = { id = 'edit', label = 'Edit', icon = 'pencil', content = { title = setting.schema.label,
        description = setting.schema.description or displayPath(setting.schema.path), blocks = { { id = 'config-edit-details', type = 'details', columns = 2,
            items = { { label = 'Saved value', value = displayValue(setting.configured) }, { label = 'Running value', value = displayValue(setting.running) } } } },
        actions = { { id = 'config:save', label = 'Save setting', icon = 'save', variant = 'primary', fields = fieldFor(setting),
            confirm = setting.schema.live and nil or 'Save this change for the next resource restart?' },
            { id = 'config:reset', label = 'Reset to authored default', icon = 'rotate-ccw', variant = 'outline', confirm = 'Remove this in-game override?' },
            { id = 'config:back', label = 'Back to settings', icon = 'arrow-left', variant = 'ghost' } } } }
end

local function openEditor(resource)
    local result, err = QB.callback.trigger('qblib:configCatalog')
    if not result then return QB.notify.send({ type = 'error', message = err or 'You do not have access to configuration.' }) end
    catalog, selected = result, nil
    local definition = baseDefinition()
    definition.onAction = function(action, context)
        if action == 'config:resource' then
            local entry, readError = QB.callback.trigger('qblib:configRead', context.itemId)
            if not entry then error(readError or 'Could not read resource configuration.') end
            selected = { entry = entry }
            local updated = baseDefinition(); addSettingsView(updated, entry)
            return { update = { navigation = updated.navigation }, navigate = { viewId = 'settings' } }
        end
        if action == 'config:setting' and selected and selected.entry then
            local leaves = {}; schemaLeaves(selected.entry.schema, selected.entry.configured, selected.entry.values, leaves)
            for _, setting in ipairs(leaves) do
                if pathId(setting.schema.path) == context.itemId then
                    selected.setting = setting
                    local updated = baseDefinition(); addSettingsView(updated, selected.entry); addSelectedView(updated, setting)
                    return { update = { navigation = updated.navigation }, navigate = { viewId = 'edit' } }
                end
            end
        end
        if action == 'config:back' and selected and selected.entry then
            local updated = baseDefinition(); addSettingsView(updated, selected.entry)
            return { update = { navigation = updated.navigation }, navigate = { viewId = 'settings' } }
        end
        if (action == 'config:save' or action == 'config:reset') and selected and selected.setting and selected.entry then
            local request = { resource = selected.entry.resource, path = selected.setting.schema.path, revision = selected.entry.revision }
            local response, requestError
            if action == 'config:save' then request.value = inputValue(selected.setting, context.value or {}); response, requestError = QB.callback.trigger('qblib:configCommit', request)
            else response, requestError = QB.callback.trigger('qblib:configReset', request) end
            if not response or not response.ok then error((response and response.error) or requestError or 'Configuration change failed.') end
            QB.notify.send({ type = 'success', message = response.applied and 'Configuration updated live.' or 'Configuration saved; restart the resource to apply it.' })
            local refreshed, refreshError = QB.callback.trigger('qblib:configRead', selected.entry.resource)
            if not refreshed then error(refreshError or 'The setting saved, but could not be refreshed.') end
            selected.entry = refreshed
            local leaves = {}; schemaLeaves(refreshed.schema, refreshed.configured, refreshed.values, leaves)
            for _, setting in ipairs(leaves) do if pathId(setting.schema.path) == pathId(request.path) then selected.setting = setting break end end
            local updated = baseDefinition(); addSettingsView(updated, refreshed); addSelectedView(updated, selected.setting)
            return { update = { navigation = updated.navigation }, navigate = { viewId = 'edit' } }
        end
        error('That configuration action is no longer available.')
    end
    local viewId
    if resource then
        local entry, readError = QB.callback.trigger('qblib:configRead', resource)
        if not entry then return QB.notify.send({ type = 'error', message = readError or 'Could not read resource configuration.' }) end
        selected = { entry = entry }
        addSettingsView(definition, entry)
        viewId = 'settings'
    end
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
