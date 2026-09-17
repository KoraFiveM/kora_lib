-- Consumer-local configuration runtime.
--
-- This file is loaded by @qblib/init.lua into the consuming resource's own
-- Lua environment. That is intentional: Config and SaveResourceFile are
-- resource-local, so qblib can coordinate configuration without needing (or
-- being granted) permission to write another resource's files.

return function(library)
    local RESOURCE = GetCurrentResourceName()
    local isServer = type(IsDuplicityVersion) == 'function' and IsDuplicityVersion() == true
    local MARKER = '__qblibConfigDescriptor'
    local STORAGE_MARKER = '__qblibConfigType'
    local config = {}
    local state
    local changeHandlers = {}
    local validateHandlers = {}
    local applyHandlers = {}
    local bindings = {}
    local remoteValues = {}
    local readyResources = {}

    local function requestSnapshot()
        if not isServer and type(TriggerServerEvent) == 'function' then
            TriggerServerEvent('qblib:server:configRequested', RESOURCE)
        end
    end

    local function requestResourceSnapshot(resource)
        if not isServer and type(TriggerServerEvent) == 'function' then
            TriggerServerEvent('qblib:server:configRequested', resource)
        end
    end

    local function pathKey(path)
        return table.concat(path, '\0')
    end

    local function displayPath(path)
        return table.concat(path, '.')
    end

    local function normalizedBindingPath(path)
        if path == nil then return {} end
        if type(path) == 'string' then
            local out = {}
            for key in path:gmatch('[^.]+') do out[#out + 1] = key end
            return out
        end
        assert(type(path) == 'table', 'Configuration path must be a string or array.')
        local out = {}
        for index = 1, #path do
            assert(type(path[index]) == 'string' or type(path[index]) == 'number', 'Configuration path entries must be strings or numbers.')
            out[index] = tostring(path[index])
        end
        return out
    end

    local function copy(value, seen)
        local kind = type(value)
        if kind ~= 'table' then return value end

        seen = seen or {}
        if seen[value] then return seen[value] end

        local out = {}
        seen[value] = out
        for key, child in pairs(value) do out[copy(key, seen)] = copy(child, seen) end
        return out
    end

    local function isArray(value)
        if type(value) ~= 'table' then return false end
        local highest, count = 0, 0
        for key in pairs(value) do
            if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then return false end
            if key > highest then highest = key end
            count = count + 1
        end
        return highest == count
    end

    local function descriptor(kind, value, options)
        assert(type(options) == 'table' or options == nil, 'Configuration field options must be a table.')
        return { [MARKER] = true, kind = kind, value = value, options = options or {} }
    end

    local function checkOptions(options)
        local scope = options.scope
        assert(scope == nil or scope == 'shared' or scope == 'client' or scope == 'server',
            'Configuration scope must be shared, client, or server.')
        assert(options.live == nil or type(options.live) == 'boolean', 'Configuration live must be a boolean.')
        assert(options.advanced == nil or type(options.advanced) == 'boolean', 'Configuration advanced must be a boolean.')
        assert(options.label == nil or type(options.label) == 'string', 'Configuration label must be a string.')
        assert(options.description == nil or type(options.description) == 'string', 'Configuration description must be a string.')
        assert(options.min == nil or type(options.min) == 'number', 'Configuration min must be a number.')
        assert(options.max == nil or type(options.max) == 'number', 'Configuration max must be a number.')
        assert(options.step == nil or type(options.step) == 'number', 'Configuration step must be a number.')
        assert(options.minLength == nil or type(options.minLength) == 'number', 'Configuration minLength must be a number.')
        assert(options.maxLength == nil or type(options.maxLength) == 'number', 'Configuration maxLength must be a number.')
        assert(options.pattern == nil or type(options.pattern) == 'string', 'Configuration pattern must be a string.')
        assert(options.options == nil or type(options.options) == 'table', 'Configuration options must be a table.')
        assert(options.sensitive == nil or type(options.sensitive) == 'boolean', 'Configuration sensitive must be a boolean.')
        assert(options.keyType == nil or options.keyType == 'string' or options.keyType == 'integer'
            or options.keyType == 'mixed', 'Configuration keyType must be string, integer, or mixed.')
        assert(options.requiredKeys == nil or type(options.requiredKeys) == 'table',
            'Configuration requiredKeys must be a table.')
        assert(options.min == nil or (options.min == options.min and options.min ~= math.huge and options.min ~= -math.huge),
            'Configuration min must be finite.')
        assert(options.max == nil or (options.max == options.max and options.max ~= math.huge and options.max ~= -math.huge),
            'Configuration max must be finite.')
        assert(options.step == nil or (options.step == options.step and options.step > 0 and options.step ~= math.huge),
            'Configuration step must be a positive finite number.')
        assert(options.min == nil or options.max == nil or options.min <= options.max,
            'Configuration min cannot exceed max.')
        assert(options.minLength == nil or (options.minLength >= 0 and options.minLength % 1 == 0),
            'Configuration minLength must be a non-negative integer.')
        assert(options.maxLength == nil or (options.maxLength >= 0 and options.maxLength % 1 == 0),
            'Configuration maxLength must be a non-negative integer.')
        assert(options.minLength == nil or options.maxLength == nil or options.minLength <= options.maxLength,
            'Configuration minLength cannot exceed maxLength.')
        if options.pattern then
            assert(pcall(string.match, '', options.pattern), 'Configuration pattern must be a valid Lua pattern.')
        end
    end

    local function inferKind(value)
        local kind = type(value)
        if kind == 'boolean' or kind == 'string' then return kind end
        if kind == 'number' then
            if math.type and math.type(value) == 'integer' then return 'integer' end
            return 'number'
        end
        if kind == 'vector2' or kind == 'vector3' or kind == 'vector4' then return kind end
        if kind == 'table' then return isArray(value) and 'list' or 'object' end
        error(('Unsupported configuration value type %q. Use an explicit QB.config field or keep it out of the editor.'):format(kind))
    end

    local function humanizeLabel(value)
        local text = tostring(value):gsub('([%l%d])([%u])', '%1 %2'):gsub('[_%-]+', ' '):gsub('%s+', ' ')
        text = text:match('^%s*(.-)%s*$') or ''
        if text == '' then return 'Setting' end

        local acronyms = {
            ace = 'ACE', api = 'API', bolo = 'BOLO', id = 'ID', ids = 'IDs', kvp = 'KVP',
            mdt = 'MDT', npc = 'NPC', nui = 'NUI', qb = 'QB', qbcore = 'QB Core', sql = 'SQL',
            ttl = 'TTL', ui = 'UI', url = 'URL', urls = 'URLs', xp = 'XP',
        }
        local words = {}
        for word in text:gmatch('%S+') do
            local acronym = acronyms[word:lower()]
            words[#words + 1] = acronym or (word:sub(1, 1):upper() .. word:sub(2))
        end
        return table.concat(words, ' ')
    end

    local function pathLabel(path)
        local parts = {}
        for index = 1, #path do
            local part = path[index]
            if part ~= '*' and not tostring(part):match('^%d+$') then
                parts[#parts + 1] = humanizeLabel(part)
            end
        end
        return #parts > 0 and table.concat(parts, ' ') or 'Setting'
    end

    local function defaultDescription(label, kind, path)
        local key = displayPath(path)
        if key == '' then key = 'the root configuration table' end
        if kind == 'boolean' then
            return ('Enables or disables %s for %s. This true/false value is read from %s.'):format(label, RESOURCE, key)
        end
        if kind == 'enum' then
            return ('Selects %s for %s. Only the authored choices are accepted for %s, preventing an unsupported mode from being saved.'):format(label, RESOURCE, key)
        end
        if kind == 'number' or kind == 'integer' then
            return ('Sets %s for %s. Minimum and maximum limits are checked when saved; the step controls the input buttons, not the allowed precision. Ask the resource developer to document the units and gameplay effect for %s before changing it.'):format(label, RESOURCE, key)
        end
        if kind == 'vector2' or kind == 'vector3' or kind == 'vector4' then
            return ('Defines the world coordinates used by %s for %s. Enter each coordinate component stored at %s as a finite number.'):format(RESOURCE, label, key)
        end
        if kind == 'list' then
            return ('Defines the ordered entries used by %s for %s. Add, remove, or edit numbered rows; every row is checked against the resource schema before %s is saved.'):format(RESOURCE, label, key)
        end
        if kind == 'map' then
            return ('Defines the keyed entries used by %s for %s. Each key identifies one entry, and every value is checked against the resource schema before %s is saved.'):format(RESOURCE, label, key)
        end
        if kind == 'object' then
            return ('Groups the related %s settings used by %s. Child values are edited separately and remain stored beneath %s.'):format(label, RESOURCE, key)
        end
        if kind == 'color' then
            return ('Sets the colour used by %s for %s. The value stored at %s must remain a six-digit hexadecimal colour.'):format(RESOURCE, label, key)
        end
        if kind == 'optional' then
            return ('Sets the optional %s value used by %s at %s. Leave it empty to disable the override, or provide a value matching the documented format.'):format(label, RESOURCE, key)
        end
        return ('Sets the text used by %s for %s. The saved value is read from %s whenever the owning feature is loaded.'):format(RESOURCE, label, key)
    end

    local function containsSensitive(schema)
        if not schema then return false end
        if schema.sensitive then return true end
        if containsSensitive(schema.inner) or containsSensitive(schema.item) then return true end
        for _, branch in pairs(schema.fields or {}) do
            if containsSensitive(branch) then return true end
        end
        for _, branch in pairs(schema.items or {}) do
            if containsSensitive(branch) then return true end
        end
        for _, branch in pairs(schema.values or {}) do
            if containsSensitive(branch) then return true end
        end
        return false
    end

    local function makeSchema(node, path, inheritedScope, skipUnsupported, inheritedAdvanced)
        local wrapped = type(node) == 'table' and node[MARKER] == true and node or nil
        local options = wrapped and wrapped.options or {}
        checkOptions(options)
        local value = node
        if wrapped then value = wrapped.value end
        local valueType = type(value)
        if not wrapped and skipUnsupported and #path > 0 and valueType == 'table' and next(value) == nil then
            -- Empty untyped tables in legacy Config files are generally
            -- resource-populated registries. Explicit object/list/map fields
            -- remain available for intentional editable empty collections.
            return nil
        end
        if not wrapped and skipUnsupported and valueType ~= 'boolean' and valueType ~= 'string'
            and valueType ~= 'number' and valueType ~= 'table' and valueType ~= 'vector2'
            and valueType ~= 'vector3' and valueType ~= 'vector4' then
            return nil
        end
        local kind = wrapped and wrapped.kind or inferKind(value)
        local advanced = options.advanced
        if advanced == nil then advanced = inheritedAdvanced end
        if advanced == nil and kind ~= 'object' and kind ~= 'optional' then
            advanced = kind == 'list' or kind == 'map' or kind:match('^vector') ~= nil
        end
        local scope = options.scope or inheritedScope or 'shared'
        -- A leaf name such as `max`, `enabled`, or `timeout` is meaningless in
        -- isolation in the editor. Keep its owning path in the inferred label;
        -- explicitly authored labels remain untouched.
        local label = options.label or pathLabel(path)
        local schema = {
            kind = kind,
            path = copy(path),
            label = label,
            description = options.description or defaultDescription(label, kind, path),
            scope = scope,
            live = options.live == true,
            advanced = advanced,
            min = options.min,
            max = options.max,
            step = options.step,
            minLength = options.minLength,
            maxLength = options.maxLength,
            pattern = options.pattern,
            options = copy(options.options),
            sensitive = options.sensitive == true,
            keyType = options.keyType,
            requiredKeys = copy(options.requiredKeys),
        }

        if kind == 'object' then
            assert(type(value) == 'table', 'A configuration object must be a table.')
            schema.fields = {}
            schema.fieldKeys = {}
            local values = {}
            for key, child in pairs(value) do
                assert(type(key) == 'string' or type(key) == 'number', 'Configuration object keys must be strings or numbers.')
                local childPath = copy(path)
                childPath[#childPath + 1] = tostring(key)
                local childSchema, childValue = makeSchema(child, childPath, scope, skipUnsupported, advanced)
                if childSchema then
                    schema.fields[tostring(key)] = childSchema
                    schema.fieldKeys[tostring(key)] = key
                    values[key] = childValue
                end
            end
            return schema, values
        end

        if kind == 'list' then
            assert(type(value) == 'table', 'A configuration list must be a table.')
            schema.items = {}
            local values = {}
            if wrapped and wrapped.item then
                local itemPath = copy(path)
                itemPath[#itemPath + 1] = '*'
                schema.item = select(1, makeSchema(wrapped.item, itemPath, scope, skipUnsupported))
                if containsSensitive(schema.item) then schema.sensitive = true end
            end
            for index = 1, #value do
                local child = value[index]
                local childPath = copy(path)
                childPath[#childPath + 1] = tostring(index)
                local childSchema, childValue = makeSchema(child, childPath, scope, skipUnsupported)
                if not childSchema then return nil end
                schema.items[index] = childSchema
                values[index] = childValue
                if containsSensitive(childSchema) then schema.sensitive = true end
            end
            return schema, values
        end

        if kind == 'map' then
            assert(type(value) == 'table', 'A configuration map must be a table.')
            local keyType = options.keyType or 'string'
            schema.keyType = keyType
            schema.values = {}
            local values = {}
            if wrapped and wrapped.item then
                local itemPath = copy(path)
                itemPath[#itemPath + 1] = '*'
                schema.item = select(1, makeSchema(wrapped.item, itemPath, scope, skipUnsupported))
                if containsSensitive(schema.item) then schema.sensitive = true end
            end
            local seenKeys = {}
            for key, child in pairs(value) do
                local actualKeyType = type(key)
                local validKey = keyType == 'mixed' and (actualKeyType == 'string'
                    or (actualKeyType == 'number' and key % 1 == 0))
                    or keyType == 'integer' and actualKeyType == 'number' and key % 1 == 0
                    or keyType == 'string' and actualKeyType == 'string'
                assert(validKey, ('Configuration %s map keys do not accept %s keys.'):format(keyType, actualKeyType))
                local serializedKey = tostring(key)
                assert(not seenKeys[serializedKey], ('Configuration map key %q is ambiguous.'):format(serializedKey))
                seenKeys[serializedKey] = true
                local childPath = copy(path)
                childPath[#childPath + 1] = serializedKey
                local childSchema, childValue = makeSchema(child, childPath, scope, skipUnsupported)
                if not childSchema then return nil end
                schema.values[serializedKey] = childSchema
                values[key] = childValue
                if containsSensitive(childSchema) then schema.sensitive = true end
            end
            for _, requiredKey in ipairs(schema.requiredKeys or {}) do
                assert(type(requiredKey) == 'string' or type(requiredKey) == 'number',
                    'Configuration required map keys must be strings or numbers.')
                assert(values[requiredKey] ~= nil,
                    ('Configuration required map key %q needs an authored default.'):format(tostring(requiredKey)))
            end
            return schema, values
        end

        if kind == 'optional' then
            local innerSchema, innerDefault = makeSchema(wrapped.inner, path, scope, skipUnsupported, advanced)
            assert(innerSchema, 'A configuration optional field needs a supported inner field.')
            assert(innerSchema.kind ~= 'optional', 'Nested optional configuration fields are not supported.')
            schema.inner = innerSchema
            if schema.advanced == nil then schema.advanced = innerSchema.advanced end
            schema.innerDefault = copy(innerDefault)
            if containsSensitive(innerSchema) then schema.sensitive = true end
            return schema, copy(value)
        end

        if kind == 'enum' then
            assert(type(options.options) == 'table' and #options.options > 0, 'Configuration enum needs non-empty options.')
            local seenOptions = {}
            for index = 1, #options.options do
                local option = options.options[index]
                local candidate = type(option) == 'table' and option.value or option
                assert(type(candidate) == 'string' or type(candidate) == 'number',
                    'Configuration enum option values must be strings or numbers.')
                if type(option) == 'table' then
                    assert(option.label == nil or type(option.label) == 'string',
                        'Configuration enum option labels must be strings.')
                end
                local key = type(candidate) .. ':' .. tostring(candidate)
                assert(not seenOptions[key], 'Configuration enum option values must be unique.')
                seenOptions[key] = true
            end
        end

        return schema, copy(value)
    end

    local function vectorParts(value, kind)
        local values = { x = value.x, y = value.y, z = value.z, w = value.w }
        local expected = kind == 'vector2' and 2 or kind == 'vector3' and 3 or 4
        for index = 1, expected do
            local key = ({ 'x', 'y', 'z', 'w' })[index]
            assert(type(values[key]) == 'number', ('Expected %s.%s to be a number.'):format(kind, key))
        end
        return values
    end

    local function encodeStorage(value, seen)
        local kind = type(value)
        if kind == 'nil' or kind == 'boolean' or kind == 'number' or kind == 'string' then return value end
        if kind == 'vector2' or kind == 'vector3' or kind == 'vector4' then
            local parts = vectorParts(value, kind)
            parts[STORAGE_MARKER] = kind
            return parts
        end
        assert(kind == 'table', ('Cannot store configuration value of type %s.'):format(kind))

        seen = seen or {}
        assert(not seen[value], 'Cannot store circular configuration tables.')
        seen[value] = true
        local out = {}
        for key, child in pairs(value) do
            assert(type(key) == 'string' or type(key) == 'number', 'Configuration table keys must be strings or numbers.')
            out[key] = encodeStorage(child, seen)
        end
        seen[value] = nil
        return out
    end

    local function decodeStorage(value)
        if type(value) ~= 'table' then return value end
        local marker = rawget(value, STORAGE_MARKER)
        if marker == 'vector2' or marker == 'vector3' or marker == 'vector4' then
            local constructor = rawget(_G, marker)
            if type(constructor) == 'function' then
                if marker == 'vector2' then return constructor(value.x, value.y) end
                if marker == 'vector3' then return constructor(value.x, value.y, value.z) end
                return constructor(value.x, value.y, value.z, value.w)
            end
        end
        local out = {}
        for key, child in pairs(value) do
            if key ~= STORAGE_MARKER then out[key] = decodeStorage(child) end
        end
        return out
    end

    local function objectTableKey(schema, key)
        return schema.fieldKeys and schema.fieldKeys[key] or key
    end

    local function listChildSchema(schema, index)
        if schema.item then return schema.item end
        local items = schema.items or {}
        return items[index] or items[1]
    end

    local function quote(value)
        return string.format('%q', value)
    end

    local function serialize(value, indent, seen)
        local kind = type(value)
        if kind == 'nil' then return 'nil' end
        if kind == 'boolean' then return value and 'true' or 'false' end
        if kind == 'number' then
            assert(value == value and value ~= math.huge and value ~= -math.huge, 'Configuration numbers must be finite.')
            return tostring(value)
        end
        if kind == 'string' then return quote(value) end
        assert(kind == 'table', ('Cannot serialize configuration value of type %s.'):format(kind))

        seen = seen or {}
        assert(not seen[value], 'Cannot serialize circular configuration tables.')
        seen[value] = true
        local nextIndent = indent .. '    '
        local entries, numeric = {}, {}
        for key in pairs(value) do
            if type(key) == 'number' then numeric[#numeric + 1] = key else entries[#entries + 1] = key end
        end
        table.sort(numeric)
        table.sort(entries, function(a, b) return tostring(a) < tostring(b) end)
        local lines = {}
        for keyIndex = 1, #numeric do
            local key = numeric[keyIndex]
            lines[#lines + 1] = nextIndent .. '[' .. serialize(key, nextIndent, seen) .. '] = '
                .. serialize(value[key], nextIndent, seen) .. ','
        end
        for keyIndex = 1, #entries do
            local key = entries[keyIndex]
            lines[#lines + 1] = nextIndent .. '[' .. serialize(key, nextIndent, seen) .. '] = ' .. serialize(value[key], nextIndent, seen) .. ','
        end
        seen[value] = nil
        if #lines == 0 then return '{}' end
        return '{\n' .. table.concat(lines, '\n') .. '\n' .. indent .. '}'
    end

    local function validate(schema, value)
        if schema.kind == 'optional' then
            if value == nil then return true, nil end
            return validate(schema.inner, value)
        end
        if schema.kind == 'boolean' then
            if type(value) ~= 'boolean' then return false, 'must be true or false' end
        elseif schema.kind == 'string' then
            if type(value) ~= 'string' then return false, 'must be text' end
            if schema.minLength and #value < schema.minLength then return false, 'is too short' end
            if schema.maxLength and #value > schema.maxLength then return false, 'is too long' end
            if schema.pattern and not value:match(schema.pattern) then return false, 'has an invalid format' end
        elseif schema.kind == 'number' or schema.kind == 'integer' then
            if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then return false, 'must be a finite number' end
            if schema.kind == 'integer' and value % 1 ~= 0 then return false, 'must be a whole number' end
            if schema.min and value < schema.min then return false, ('must be at least %s'):format(schema.min) end
            if schema.max and value > schema.max then return false, ('must be at most %s'):format(schema.max) end
        elseif schema.kind == 'enum' then
            local found = false
            local options = schema.options or {}
            for optionIndex = 1, #options do
                local option = options[optionIndex]
                local candidate = type(option) == 'table' and option.value or option
                if candidate == value then found = true break end
            end
            if not found then return false, 'must be one of the configured options' end
        elseif schema.kind == 'color' then
            if type(value) ~= 'string' or not value:match('^#%x%x%x%x%x%x$') then return false, 'must be a #RRGGBB colour' end
        elseif schema.kind == 'vector2' or schema.kind == 'vector3' or schema.kind == 'vector4' then
            local kind = type(value)
            if kind ~= schema.kind and kind ~= 'table' then return false, ('must be a %s'):format(schema.kind) end
            local ok = pcall(vectorParts, value, schema.kind)
            if not ok then return false, ('must be a valid %s'):format(schema.kind) end
            if kind == 'table' then
                local constructor = rawget(_G, schema.kind)
                if type(constructor) == 'function' then
                    if schema.kind == 'vector2' then return true, constructor(value.x, value.y) end
                    if schema.kind == 'vector3' then return true, constructor(value.x, value.y, value.z) end
                    return true, constructor(value.x, value.y, value.z, value.w)
                end
            end
        elseif schema.kind == 'object' then
            if type(value) ~= 'table' then return false, 'must be an object' end
            for key, child in pairs(schema.fields) do
                local tableKey = objectTableKey(schema, key)
                local ok, err = validate(child, value[tableKey])
                if not ok then return false, ('%s %s'):format(key, err) end
            end
        elseif schema.kind == 'list' then
            if not isArray(value) then return false, 'must be a list' end
            for index = 1, #value do
                local child = value[index]
                local item = listChildSchema(schema, index)
                if not item then return false, 'contains an unsupported item' end
                local ok, err = validate(item, child)
                if not ok then return false, ('item %d %s'):format(index, err) end
            end
        elseif schema.kind == 'map' then
            if type(value) ~= 'table' then return false, 'must be a map' end
            for _, requiredKey in ipairs(schema.requiredKeys or {}) do
                if value[requiredKey] == nil then
                    return false, ('must include the %s key'):format(tostring(requiredKey))
                end
            end
            for key, child in pairs(value) do
                local keyType = type(key)
                local validKey = schema.keyType == 'mixed' and (keyType == 'string'
                    or (keyType == 'number' and key % 1 == 0))
                    or schema.keyType == 'integer' and keyType == 'number' and key % 1 == 0
                    or (schema.keyType == nil or schema.keyType == 'string') and keyType == 'string'
                if not validKey then return false, ('keys must match the %s key type'):format(schema.keyType or 'string') end
                local item = schema.item or schema.values[tostring(key)]
                if not item then return false, ('key %s is not allowed'):format(key) end
                local ok, err = validate(item, child)
                if not ok then return false, ('%s %s'):format(key, err) end
            end
        end
        return true, copy(value)
    end

    local function mergeKnown(schema, target, override)
        if type(override) ~= 'table' then return end
        if schema.kind == 'object' then
            for key, child in pairs(schema.fields) do
                local tableKey = objectTableKey(schema, key)
                if override[tableKey] ~= nil then
                    if child.kind == 'object' and type(target[tableKey]) == 'table' then
                        mergeKnown(child, target[tableKey], override[tableKey])
                    else
                        local ok, value = validate(child, decodeStorage(override[tableKey]))
                        if ok then target[tableKey] = value end
                    end
                end
            end
        else
            local ok, value = validate(schema, decodeStorage(override))
            if ok then return value end
        end
    end

    local function loadOverrides(fileName)
        local raw = LoadResourceFile(RESOURCE, fileName)
        if raw == nil or raw == '' then return nil, 'missing' end
        local chunk, compileError = load(raw, ('@@%s/%s'):format(RESOURCE, fileName), 't', {})
        if not chunk then
            return nil, compileError
        end
        local ok, result = pcall(chunk)
        if not ok or type(result) ~= 'table' then
            return nil, 'it must return a table'
        end
        return result
    end

    local function readOverrides(fileName)
        local values, errorMessage = loadOverrides(fileName)
        if values then return values end
        if errorMessage == 'missing' then return {} end

        print(('[qblib:config] Ignoring invalid %s/%s: %s'):format(RESOURCE, fileName, errorMessage))
        local backup = loadOverrides(fileName .. '.bak')
        if backup then
            print(('[qblib:config] Restoring %s/%s from its backup.'):format(RESOURCE, fileName))
            return backup
        end
        return {}
    end

    local function equal(a, b, seen)
        if type(a) ~= type(b) then return false end
        if type(a) ~= 'table' then return a == b end
        seen = seen or {}
        if seen[a] == b then return true end
        seen[a] = b
        for key, value in pairs(a) do if not equal(value, b[key], seen) then return false end end
        for key in pairs(b) do if a[key] == nil then return false end end
        return true
    end

    local function pruneOverrides(schema, current, defaults)
        if schema.kind ~= 'object' then
            if equal(current, defaults) then return nil end
            return encodeStorage(current)
        end
        local out = {}
        for key, child in pairs(schema.fields) do
            local tableKey = objectTableKey(schema, key)
            local encoded = pruneOverrides(child, current[tableKey], defaults[tableKey])
            if encoded ~= nil then out[tableKey] = encoded end
        end
        return next(out) and out or nil
    end

    local function findSchema(schema, path, index)
        if not schema then return nil end
        if index > #path then return schema end
        if schema.kind == 'optional' then return findSchema(schema.inner, path, index) end
        if schema.kind == 'object' then return findSchema(schema.fields[path[index]], path, index + 1) end
        if schema.kind == 'map' then return findSchema(schema.item or schema.values[path[index]], path, index + 1) end
        if schema.kind == 'list' then return findSchema(listChildSchema(schema, tonumber(path[index])), path, index + 1) end
    end

    local function unwrapOptional(schema)
        while schema and schema.kind == 'optional' do schema = schema.inner end
        return schema
    end

    local function childSchema(schema, key)
        schema = unwrapOptional(schema)
        if not schema then return nil end
        if schema.kind == 'object' then return schema.fields[key] end
        if schema.kind == 'map' then return schema.item or schema.values[key] end
        if schema.kind == 'list' then return listChildSchema(schema, tonumber(key)) end
    end

    local function pathTableKey(schema, key)
        schema = unwrapOptional(schema)
        if schema and schema.kind == 'list' then return tonumber(key) end
        if schema and schema.kind == 'object' then return objectTableKey(schema, key) end
        if schema and schema.kind == 'map' and schema.keyType == 'integer' then return tonumber(key) end
        if schema and schema.kind == 'map' and schema.keyType == 'mixed' and key:match('^-?%d+$') then return tonumber(key) end
        return key
    end

    local function readPath(root, path, schema)
        local current = root
        for keyIndex = 1, #path do
            local key = path[keyIndex]
            if type(current) ~= 'table' then return nil end
            current = current[pathTableKey(schema, key)]
            schema = childSchema(schema, key)
        end
        return current
    end

    local function readPlainPath(root, path)
        local current = root
        for index = 1, #path do
            if type(current) ~= 'table' then return nil end
            current = current[path[index]]
        end
        return current
    end

    local function notifyBindings(resource, changedPath, previous, change)
        local resourceBindings = bindings[resource]
        if not resourceBindings then return end
        for _, binding in ipairs(resourceBindings) do
            local value = resource == RESOURCE and state and readPath(state.values, binding.path, state.schema)
                or readPlainPath(remoteValues[resource], binding.path)
            local wasAffected = #changedPath == 0
            if not wasAffected then
                wasAffected = true
                local common = math.min(#binding.path, #changedPath)
                for index = 1, common do
                    if binding.path[index] ~= changedPath[index] then wasAffected = false break end
                end
            end
            if wasAffected then
                local ok, err = pcall(binding.handler, copy(value), copy(previous), change)
                if not ok then print(('[qblib:config] Binding for %s failed: %s'):format(resource, err)) end
            end
        end
    end

    local function markReady(resource)
        readyResources[resource] = true
    end

    local function writePath(root, path, value, schema)
        local current = root
        for index = 1, #path - 1 do
            local key = path[index]
            current = current[pathTableKey(schema, key)]
            schema = childSchema(schema, key)
        end
        current[pathTableKey(schema, path[#path])] = value
    end

    local function clientProjection(schema, configured)
        if schema.scope == 'server' then return nil end
        if schema.kind == 'optional' then
            if configured == nil then return nil end
            return clientProjection(schema.inner, configured)
        end
        if schema.kind == 'object' then
            local out = {}
            for key, child in pairs(schema.fields) do
                local tableKey = objectTableKey(schema, key)
                local rawValue
                if type(configured) == 'table' then rawValue = configured[tableKey] end
                local childValue = clientProjection(child, rawValue)
                if childValue ~= nil then out[tableKey] = childValue end
            end
            return out
        end
        if schema.kind == 'list' then
            local out = {}
            if type(configured) ~= 'table' then return out end
            for index, value in pairs(configured) do
                local child = listChildSchema(schema, index)
                local childValue
                if child then childValue = clientProjection(child, value) end
                if childValue ~= nil then out[index] = childValue end
            end
            return out
        end
        if schema.kind == 'map' then
            local out = {}
            if type(configured) ~= 'table' then return out end
            for key, value in pairs(configured) do
                local child = schema.item or (schema.values or {})[tostring(key)]
                local childValue
                if child then childValue = clientProjection(child, value) end
                if childValue ~= nil then out[key] = childValue end
            end
            return out
        end
        return encodeStorage(configured)
    end

    -- `adopt` deliberately leaves unsupported legacy members (for example,
    -- callbacks and resource-populated registries) on the resource's public
    -- Config table. Only project the registered schema when returning running
    -- values to qblib; otherwise one such member makes the whole editor read
    -- fail even though it was correctly omitted from the editable catalog.
    local function projectValues(schema, value)
        if schema.kind == 'optional' then
            if value == nil then return nil end
            return projectValues(schema.inner, value)
        end

        if schema.kind == 'object' then
            local out = {}
            for key, child in pairs(schema.fields) do
                local tableKey = objectTableKey(schema, key)
                local rawValue
                if type(value) == 'table' then rawValue = value[tableKey] end
                local projected = projectValues(child, rawValue)
                if projected ~= nil then out[tableKey] = projected end
            end
            return out
        end

        if schema.kind == 'list' then
            local out = {}
            for index, child in pairs(schema.items or {}) do
                local rawValue
                if type(value) == 'table' then rawValue = value[index] end
                local projected = projectValues(child, rawValue)
                if projected ~= nil then out[index] = projected end
            end
            local fallback = schema.item or (schema.items or {})[1]
            if fallback and type(value) == 'table' then
                for index, childValue in pairs(value) do
                    if out[index] == nil then out[index] = projectValues(fallback, childValue) end
                end
            end
            return out
        end

        if schema.kind == 'map' then
            local out = {}
            if type(value) ~= 'table' then return out end
            for key, childValue in pairs(value) do
                local child = schema.item or (schema.values or {})[tostring(key)]
                if child then
                    local projected = projectValues(child, childValue)
                    if projected ~= nil then out[key] = projected end
                end
            end
            return out
        end

        return copy(value)
    end

    local function metadata(schema)
        local out = {
            kind = schema.kind, path = copy(schema.path), label = schema.label, description = schema.description,
            scope = schema.scope, live = schema.live, min = schema.min, max = schema.max, step = schema.step,
            minLength = schema.minLength, maxLength = schema.maxLength, pattern = schema.pattern,
            options = copy(schema.options), sensitive = schema.sensitive,
            advanced = schema.advanced,
            keyType = schema.keyType,
            requiredKeys = copy(schema.requiredKeys),
        }
        if schema.fields then
            out.fields = {}
            for key, child in pairs(schema.fields) do out.fields[key] = metadata(child) end
        end
        if schema.fieldKeys then out.fieldKeys = copy(schema.fieldKeys) end
        if schema.item then out.item = metadata(schema.item) end
        if schema.items then
            out.items = {}
            for index, child in pairs(schema.items) do out.items[index] = metadata(child) end
        end
        if schema.values then
            out.values = {}
            for key, child in pairs(schema.values) do out.values[key] = metadata(child) end
        end
        if schema.inner then out.inner = metadata(schema.inner) end
        if schema.innerDefault ~= nil and not schema.sensitive then
            out.innerDefault = encodeStorage(schema.innerDefault)
        end
        return out
    end

    local function announce()
        if not isServer or not state then return end
        library:config_register({
            resource = RESOURCE,
            schema = metadata(state.schema),
            configured = encodeStorage(state.configured),
            client = clientProjection(state.schema, state.values) or {},
            revision = state.revision,
        })
    end

    -- A consumer's shared config can execute while qblib is still finishing
    -- its own server bootstrap. Re-announce after the resource start event so
    -- the catalog cannot remain empty when the initial export call raced
    -- qblib's finalise step.
    if isServer and type(AddEventHandler) == 'function' then
        AddEventHandler('onResourceStart', function(resource)
            if resource ~= RESOURCE and resource ~= 'qblib' then return end
            if type(SetTimeout) == 'function' then
                SetTimeout(0, function()
                    if state then announce() end
                end)
            elseif state then
                announce()
            end
        end)
    end

    local function persist()
        local nextOverrides = pruneOverrides(state.schema, state.configured, state.defaults) or {}
        local contents = '-- Generated by qblib. Edit config.lua for documented defaults.\nreturn ' .. serialize(nextOverrides, '') .. '\n'
        local previous = LoadResourceFile(RESOURCE, state.fileName)
        if previous and previous ~= '' then SaveResourceFile(RESOURCE, state.fileName .. '.bak', previous, #previous) end
        local saved = SaveResourceFile(RESOURCE, state.fileName, contents, #contents)
        if saved == false then return false, 'Could not save configuration override.' end
        return true
    end

    local function declare(values, options)
        assert(type(values) == 'table', 'QB.config.define expects a table.')
        options = options or {}
        assert(type(options) == 'table', 'QB.config.define options must be a table.')
        local schema, plain = makeSchema(values, {}, options.scope or 'shared', options.skipUnsupported == true)
        if options.descriptions ~= nil then
            assert(type(options.descriptions) == 'table', 'QB.config.define descriptions must be a table.')
            for key, description in pairs(options.descriptions) do
                assert(type(key) == 'string' and type(description) == 'string',
                    'QB.config.define descriptions must contain strings keyed by configuration path.')
            end
            local function applyDescriptions(branch)
                local description = options.descriptions[displayPath(branch.path)]
                if description then branch.description = description end
                for _, child in pairs(branch.fields or {}) do applyDescriptions(child) end
                for _, child in pairs(branch.items or {}) do applyDescriptions(child) end
                for _, child in pairs(branch.values or {}) do applyDescriptions(child) end
                if branch.item then applyDescriptions(branch.item) end
                if branch.inner then applyDescriptions(branch.inner) end
            end
            applyDescriptions(schema)
        end
        local valid, validationError = validate(schema, plain)
        assert(valid, ('Invalid authored configuration: %s.'):format(validationError))
        local defaults = copy(plain)
        local configured = copy(plain)
        local fileName = options.fileName or 'config.local.lua'
        assert(type(fileName) == 'string' and fileName:match('^[%w_%.%-/]+$'), 'Invalid configuration override filename.')

        if isServer then mergeKnown(schema, configured, readOverrides(fileName)) end
        local runtime = copy(configured)
        if options.mutate then
            local function applyKnown(schemaBranch, target, source)
                for key, child in pairs(schemaBranch.fields or {}) do
                    local tableKey = objectTableKey(schemaBranch, key)
                    if child.kind == 'object' and type(target[tableKey]) == 'table' then
                        applyKnown(child, target[tableKey], source[tableKey])
                    else
                        target[tableKey] = copy(source[tableKey])
                    end
                end
            end

            applyKnown(schema, values, runtime)
            runtime = values
        end

        state = {
            schema = schema,
            defaults = defaults,
            configured = configured,
            values = runtime,
            fileName = fileName,
            revision = 1,
        }
        markReady(RESOURCE)
        announce()
        requestSnapshot()
        return runtime
    end

    function config.boolean(value, options) return descriptor('boolean', value, options) end
    function config.string(value, options) return descriptor('string', value, options) end
    function config.integer(value, options) return descriptor('integer', value, options) end
    function config.number(value, options) return descriptor('number', value, options) end
    function config.enum(value, options) return descriptor('enum', value, options) end
    function config.color(value, options) return descriptor('color', value, options) end
    function config.vector2(value, options) return descriptor('vector2', value, options) end
    function config.vector3(value, options) return descriptor('vector3', value, options) end
    function config.vector4(value, options) return descriptor('vector4', value, options) end
    function config.object(value, options) return descriptor('object', value, options) end
    function config.list(value, item, options)
        local field = descriptor('list', value, options)
        field.item = item
        return field
    end
    function config.map(value, item, options)
        local field = descriptor('map', value, options)
        field.item = item
        return field
    end
    function config.optional(value, inner, options)
        local field = descriptor('optional', value, options)
        field.inner = inner
        return field
    end

    function config.define(values, options)
        return declare(values, options)
    end

    ---Registers an existing plain Config table. This is the migration bridge
    ---for first-party resources; explicit QB.config.* fields can replace any
    ---inferred field over time without changing the Config shape.
    function config.adopt(values, options)
        options = options or {}
        options.mutate = true
        options.skipUnsupported = true
        return declare(values, options)
    end

    ---Adds a server-only or client-only branch after a shared Config table was
    ---registered. This is useful for the common `server/config.lua` layout:
    ---the public Config table stays whole, while the catalog keeps the new
    ---branch out of the opposite realm.
    function config.extend(values, options)
        assert(state, 'QB.config.extend requires QB.config.define/adopt first.')
        assert(type(values) == 'table', 'QB.config.extend expects a table.')
        options = options or {}
        local extensionSchema, extensionDefaults = makeSchema(values, {}, options.scope or 'shared', options.skipUnsupported == true)
        assert(extensionSchema.kind == 'object', 'QB.config.extend expects an object.')
        local valid, validationError = validate(extensionSchema, extensionDefaults)
        assert(valid, ('Invalid authored configuration extension: %s.'):format(validationError))
        local extensionConfigured = copy(extensionDefaults)
        if isServer then mergeKnown(extensionSchema, extensionConfigured, readOverrides(state.fileName)) end

        local function mergeBranch(targetSchema, targetDefaults, targetConfigured, targetValues, sourceSchema, sourceDefaults, sourceConfigured)
            for key, childSchema in pairs(sourceSchema.fields or {}) do
                local sourceTableKey = objectTableKey(sourceSchema, key)
                local targetTableKey = objectTableKey(targetSchema, key)
                local childDefaults = sourceDefaults[sourceTableKey]
                local childConfigured = sourceConfigured[sourceTableKey]
                if targetSchema.fields[key] and targetSchema.fields[key].kind == 'object' and childSchema.kind == 'object' then
                    mergeBranch(targetSchema.fields[key], targetDefaults[targetTableKey], targetConfigured[targetTableKey], targetValues[targetTableKey],
                        childSchema, childDefaults, childConfigured)
                else
                    targetSchema.fields[key] = childSchema
                    targetSchema.fieldKeys[key] = sourceTableKey
                    targetDefaults[sourceTableKey] = copy(childDefaults)
                    targetConfigured[sourceTableKey] = copy(childConfigured)
                    targetValues[sourceTableKey] = copy(childConfigured)
                end
            end
        end

        mergeBranch(state.schema, state.defaults, state.configured, state.values,
            extensionSchema, extensionDefaults, extensionConfigured)
        announce()
        requestSnapshot()
        return state.values
    end

    function config.onChange(path, handler)
        assert(type(path) == 'string' and path ~= '', 'Configuration change path must be a non-empty string.')
        assert(type(handler) == 'function', 'Configuration change handler must be a function.')
        changeHandlers[pathKey({ path })] = handler
    end

    ---Registers an owner schema. This is the named equivalent of define and
    ---keeps resources from needing a second configuration wrapper.
    function config.register(values, options)
        return declare(values, options)
    end

    ---Registers server-side validation for a complete desired snapshot.
    function config.onValidate(handler)
        assert(isServer, 'QB.config.onValidate is server-only.')
        assert(type(handler) == 'function', 'Configuration validation handler must be a function.')
        validateHandlers[#validateHandlers + 1] = handler
    end

    ---Registers a server-side reconfiguration hook for eligible live changes.
    function config.onApply(handler)
        assert(isServer, 'QB.config.onApply is server-only.')
        assert(type(handler) == 'function', 'Configuration apply handler must be a function.')
        applyHandlers[#applyHandlers + 1] = handler
    end

    ---Returns the active local snapshot for an owner/path. Tables are copied
    ---so callers cannot mutate the shared runtime cache.
    function config.get(resource, path)
        if path == nil then path, resource = resource, RESOURCE end
        assert(type(resource) == 'string' and resource ~= '', 'Configuration resource must be a non-empty string.')
        local normalized = normalizedBindingPath(path)
        local root = resource == RESOURCE and state and state.values or remoteValues[resource]
        if root == nil then return nil, 'not_ready' end
        if resource == RESOURCE then return copy(readPath(root, normalized, state.schema)) end
        return copy(readPlainPath(root, normalized))
    end

    ---Binds a consumer to an owner's active setting. The callback receives
    ---value, previous value, and change metadata; it runs immediately once a
    ---snapshot is available and again for relevant active changes.
    function config.bind(resource, path, handler)
        assert(type(resource) == 'string' and resource ~= '', 'Configuration bind needs a resource name.')
        assert(type(handler) == 'function', 'Configuration bind needs a handler.')
        local binding = { path = normalizedBindingPath(path), handler = handler }
        bindings[resource] = bindings[resource] or {}
        bindings[resource][#bindings[resource] + 1] = binding

        local value = config.get(resource, binding.path)
        if value ~= nil then
            local ok, err = pcall(handler, value, nil, { initial = true, resource = resource })
            if not ok then print(('[qblib:config] Binding for %s failed: %s'):format(resource, err)) end
        elseif resource ~= RESOURCE then
            if isServer and type(library.config_read) == 'function' then
                local ok, snapshot = pcall(function() return library:config_read(resource) end)
                if ok and type(snapshot) == 'table' and type(snapshot.values) == 'table' then
                    remoteValues[resource] = decodeStorage(snapshot.values)
                    markReady(resource)
                    local current = config.get(resource, binding.path)
                    if current ~= nil then pcall(handler, current, nil, { initial = true, resource = resource, revision = snapshot.revision }) end
                end
            else
                requestResourceSnapshot(resource)
            end
        end

        return function()
            local resourceBindings = bindings[resource]
            if not resourceBindings then return end
            for index = #resourceBindings, 1, -1 do
                if resourceBindings[index] == binding then table.remove(resourceBindings, index) break end
            end
        end
    end

    function config.whenReady(resources, handler)
        assert(type(resources) == 'table', 'QB.config.whenReady needs a resource list.')
        assert(type(handler) == 'function', 'QB.config.whenReady needs a handler.')
        local completed = false
        local function runIfReady()
            if completed then return true end
            for index = 1, #resources do
                local resource = resources[index]
                if resource == RESOURCE then
                    if not state then return false end
                elseif not readyResources[resource] then
                    return false
                end
            end
            completed = true
            handler()
            return true
        end
        if not runIfReady() then
            for index = 1, #resources do
                local resource = resources[index]
                if resource ~= RESOURCE and not readyResources[resource] then
                    config.bind(resource, {}, function() runIfReady() end)
                end
            end
        end
    end

    -- Server-side consumers such as qbadmin use the same QB.config namespace
    -- to reach qblib's catalog. Individual resources still cannot write one
    -- another's files: qblib sends every mutation back through the target's
    -- own bridge export below.
    function config.catalog()
        assert(isServer, 'QB.config.catalog is server-only.')
        return library:config_catalog()
    end

    function config.read(resource)
        assert(isServer, 'QB.config.read is server-only.')
        return library:config_read(resource)
    end

    function config.commit(resource, request)
        assert(isServer, 'QB.config.commit is server-only.')
        return library:config_commit(resource, request)
    end

    function config.reset(resource, request)
        assert(isServer, 'QB.config.reset is server-only.')
        return library:config_reset(resource, request)
    end

    local function normalizedPath(path)
        if type(path) == 'string' then
            local out = {}
            for key in path:gmatch('[^.]+') do out[#out + 1] = key end
            return out
        end
        if type(path) ~= 'table' or #path == 0 then return nil end
        local out = {}
        for index = 1, #path do
            local key = path[index]
            if type(key) ~= 'string' and type(key) ~= 'number' then return nil end
            out[index] = tostring(key)
        end
        return out
    end

    local function commit(request)
        if not state then return { ok = false, error = 'This resource has not registered a configuration.' } end
        if type(request) ~= 'table' then return { ok = false, error = 'Invalid configuration request.' } end
        if request.revision ~= state.revision then return { ok = false, error = 'This configuration changed; refresh and try again.', revision = state.revision } end
        local path = normalizedPath(request.path)
        local schema = path and findSchema(state.schema, path, 1) or nil
        if not schema or schema.kind == 'object' then return { ok = false, error = 'Unknown configuration option.' } end
        if schema.sensitive then return { ok = false, error = 'This option cannot be changed in game.' } end
        local ok, value = validate(schema, decodeStorage(request.value))
        if not ok then return { ok = false, error = ('%s %s'):format(displayPath(path), value) } end

        local oldConfigured = copy(state.configured)
        local proposedConfigured = copy(state.configured)
        writePath(proposedConfigured, path, value, state.schema)
        for index = 1, #validateHandlers do
            local worked, valid, reason = pcall(validateHandlers[index], copy(proposedConfigured), copy(oldConfigured), path)
            if not worked or valid == false then
                return { ok = false, error = worked and (reason or 'The configuration was refused by its owner.') or tostring(valid) }
            end
        end
        local oldBackup = LoadResourceFile(RESOURCE, state.fileName .. '.bak')
        writePath(state.configured, path, value, state.schema)
        local saved, saveError = persist()
        if not saved then state.configured = oldConfigured; return { ok = false, error = saveError } end

        local previousRevision = state.revision
        state.revision = state.revision + 1
        local applied = false
        if schema.live then
            local oldValue = readPath(state.values, path, state.schema)
            if schema.scope ~= 'client' then
                local handler = changeHandlers[pathKey({ displayPath(path) })]
                if handler then
                    local worked, handlerError = pcall(handler, value, oldValue)
                    if not worked or handlerError == false then
                        state.configured = oldConfigured
                        persist()
                        local backupContents = oldBackup or ''
                        SaveResourceFile(RESOURCE, state.fileName .. '.bak', backupContents, #backupContents)
                        state.revision = previousRevision
                        return {
                            ok = false, revision = state.revision,
                            error = worked and 'The live update was refused.' or tostring(handlerError),
                        }
                    end
                end
            end
            if schema.scope ~= 'client' then
                for index = 1, #applyHandlers do
                    local worked, handlerError = pcall(applyHandlers[index], copy(state.configured), copy(state.values), path)
                    if not worked or handlerError == false then
                        state.configured = oldConfigured
                        persist()
                        local backupContents = oldBackup or ''
                        SaveResourceFile(RESOURCE, state.fileName .. '.bak', backupContents, #backupContents)
                        state.revision = previousRevision
                        return { ok = false, revision = state.revision,
                            error = worked and 'The live update was refused.' or tostring(handlerError) }
                    end
                end
            end
            writePath(state.values, path, value, state.schema)
            applied = true
            markReady(RESOURCE)
            notifyBindings(RESOURCE, path, oldValue, { resource = RESOURCE, path = copy(path), revision = state.revision })
            if isServer and schema.scope ~= 'server' then
                TriggerClientEvent('qblib:client:configUpdated', -1, RESOURCE, path, encodeStorage(value), state.revision)
            end
        end
        announce()
        return { ok = true, revision = state.revision, applied = applied, restartRequired = not schema.live,
            configured = encodeStorage(state.configured), values = encodeStorage(state.values) }
    end

    local function reset(request)
        if not state then return { ok = false, error = 'This resource has not registered a configuration.' } end
        if type(request) ~= 'table' or request.revision ~= state.revision then return { ok = false, error = 'This configuration changed; refresh and try again.', revision = state.revision } end
        local path = normalizedPath(request.path)
        local schema = path and findSchema(state.schema, path, 1) or nil
        if not schema or schema.kind == 'object' then return { ok = false, error = 'Unknown configuration option.' } end
        local defaultValue = readPath(state.defaults, path, state.schema)
        return commit({ path = path, value = encodeStorage(defaultValue), revision = state.revision })
    end

    local canExport = type(exports) == 'function'
        or (type(exports) == 'table' and type(getmetatable(exports)) == 'table'
            and type(getmetatable(exports).__call) == 'function')

    if canExport then
        exports('qblib_configRead', function()
            if not state then return nil end
            return { resource = RESOURCE, schema = metadata(state.schema), configured = encodeStorage(state.configured),
                values = encodeStorage(projectValues(state.schema, state.values)),
                client = clientProjection(state.schema, state.values) or {}, revision = state.revision }
        end)
        exports('qblib_configCommit', function(request)
            local caller = GetInvokingResource()
            if isServer and caller ~= 'qblib' and not (RESOURCE == 'qblib' and caller == nil) then
                return { ok = false, error = 'Only qblib may commit configuration changes.' }
            end
            return commit(request)
        end)
        exports('qblib_configReset', function(request)
            local caller = GetInvokingResource()
            if isServer and caller ~= 'qblib' and not (RESOURCE == 'qblib' and caller == nil) then
                return { ok = false, error = 'Only qblib may reset configuration changes.' }
            end
            return reset(request)
        end)
    end

    if not isServer and type(RegisterNetEvent) == 'function' then
        RegisterNetEvent('qblib:client:configUpdated', function(resource, path, encoded, revision)
            if resource ~= RESOURCE then
                local normalizedRemote = normalizedPath(path)
                if not normalizedRemote or not bindings[resource] then return end
                local previous = readPlainPath(remoteValues[resource], normalizedRemote)
                remoteValues[resource] = remoteValues[resource] or {}
                local current = remoteValues[resource]
                for index = 1, #normalizedRemote - 1 do
                    current[normalizedRemote[index]] = current[normalizedRemote[index]] or {}
                    current = current[normalizedRemote[index]]
                end
                current[normalizedRemote[#normalizedRemote]] = decodeStorage(encoded)
                markReady(resource)
                notifyBindings(resource, normalizedRemote, previous,
                    { resource = resource, path = copy(normalizedRemote), revision = revision })
                return
            end
            if not state then return end
            local normalized = normalizedPath(path)
            local schema = normalized and findSchema(state.schema, normalized, 1) or nil
            if not schema or schema.scope == 'server' then return end
            local value = decodeStorage(encoded)
            local oldValue = readPath(state.values, normalized, state.schema)
            writePath(state.configured, normalized, value, state.schema)
            writePath(state.values, normalized, value, state.schema)
            state.revision = revision or state.revision
            local handler = changeHandlers[pathKey({ displayPath(normalized) })]
            if handler then
                local ok, err = pcall(handler, value, oldValue)
                if not ok then print(('[qblib:config] Client update %s failed: %s'):format(displayPath(normalized), err)) end
            end
            notifyBindings(RESOURCE, normalized, oldValue,
                { resource = RESOURCE, path = copy(normalized), revision = state.revision })
        end)

        RegisterNetEvent('qblib:client:configSnapshot', function(resource, encoded, revision)
            if type(encoded) ~= 'table' then return end
            if resource ~= RESOURCE then
                if not bindings[resource] then return end
                remoteValues[resource] = decodeStorage(encoded)
                markReady(resource)
                notifyBindings(resource, {}, nil, { initial = true, resource = resource, revision = revision })
                return
            end
            if not state then return end
            local values = decodeStorage(encoded)
            local function apply(schema, current, incoming, path)
                if schema.scope == 'server' or incoming == nil then return end
                if schema.kind == 'object' then
                    for key, child in pairs(schema.fields) do
                        local tableKey = objectTableKey(schema, key)
                        local childPath = copy(path)
                        childPath[#childPath + 1] = key
                        apply(child, current[tableKey], incoming[tableKey], childPath)
                    end
                    return
                end
                local oldValue = copy(current)
                local valid, value = validate(schema, incoming)
                if not valid then return end
                if #path == 0 then return end
                writePath(state.configured, path, value, state.schema)
                writePath(state.values, path, value, state.schema)
                local handler = changeHandlers[pathKey({ displayPath(path) })]
                if handler and not equal(oldValue, value) then pcall(handler, value, oldValue) end
                if not equal(oldValue, value) then
                    notifyBindings(RESOURCE, path, oldValue,
                        { initial = true, resource = RESOURCE, path = copy(path), revision = revision })
                end
            end
            apply(state.schema, state.values, values, {})
            state.revision = revision or state.revision
            markReady(RESOURCE)
        end)
    end

    if isServer and type(AddEventHandler) == 'function' then
        AddEventHandler('qblib:server:configChanged', function(resource, encoded, revision)
            if resource == RESOURCE or not bindings[resource] or type(encoded) ~= 'table' then return end
            local previous = remoteValues[resource]
            remoteValues[resource] = decodeStorage(encoded)
            markReady(resource)
            notifyBindings(resource, {}, previous, { resource = resource, revision = revision })
        end)
    end

    if not isServer and type(AddEventHandler) == 'function' then
        AddEventHandler('onClientResourceStart', function(resource)
            -- A qblib restart replaces the authoritative server registry but
            -- does not necessarily restart every consuming client resource.
            -- Re-request this owner's active snapshot in either case so a
            -- client can never remain on its authored defaults after qblib is
            -- reloaded during development or maintenance.
            if (resource == RESOURCE or resource == 'qblib') and state then requestSnapshot() end
        end)

        -- `QB.config` is consumer-local so resource-owned Config tables stay
        -- local. Keep the standalone editor reachable from that same API by
        -- forwarding this one client convenience call to qblib's export.
        function config.open(resource)
            assert(resource == nil or type(resource) == 'string', 'Configuration resource must be a string.')
            assert(type(library) == 'table' and type(library.config_open) == 'function',
                'The qblib configuration editor is unavailable.')
            return library:config_open(resource)
        end
    end

    return config
end
