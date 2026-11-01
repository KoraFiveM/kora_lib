local pendingRequests = {}
local nextRequestId = 0
local registeredApps = {}
local activeApp
local appOwnership
local requestOwnership
local focusOwnership
local focusLeases = {}
local nextFocusLease = 0
local focusBaseKeepInput

local APP_LABEL_FALLBACKS = {
    cancel = 'Cancel', confirm = 'Confirm', working = 'Working…', run_action = 'Run action',
    search = 'Search…', previous = 'Previous', next = 'Next', no_records = 'No records',
    nothing_here = 'Nothing here', empty_title = 'Nothing here yet',
    empty_description = 'This section is ready for its application content.', close = 'Close',
    select = 'Select…', required = 'Required.', invalid_format = 'Invalid format.',
    min_value = 'Must be at least %{value}.', max_value = 'Must be at most %{value}.',
    min_length = 'Must be at least %{value} characters.', max_length = 'Must be at most %{value} characters.',
    page = 'Page %{current} of %{total}', recenter = 'Recenter map', clear = 'Clear', backspace = 'Backspace',
    back = 'Back', open = 'Open', yes = 'Yes', no = 'No', map = 'Map', zoom_in = 'Zoom in', zoom_out = 'Zoom out',
    value = 'value', decrease = 'Decrease %{field}', increase = 'Increase %{field}',
}
local MENU_ITEM_STRING_FIELDS = { 'description', 'icon', 'image' }
local MENU_SIZE_FIELDS = { 'maxWidth', 'maxHeight' }
local MENU_OFFSET_FIELDS = { 'offsetX', 'offsetY' }
local ALERT_STRING_FIELDS = { 'title', 'image', 'confirmLabel', 'cancelLabel' }
local ALERT_BOOLEAN_FIELDS = {
    'cancellable', 'showCancel', 'showClose', 'dismissOnBackdrop', 'destructive', 'centered', 'overflow',
}

local function nextId()
    nextRequestId = nextRequestId + 1
    return nextRequestId
end

-- Random per-request token the NUI must echo back: NUI callback routing isn't scoped to the issuing frame, so another resource's page could otherwise forge a response for a guessable requestId.
local generateToken = Kora.compat.generateToken

-- FXServer passes functions across exports as callable tables, so accept both shapes.
local isCallable = Kora.compat.isCallable

local function assertAppId(id)
    assert(type(id) == "string" and id ~= "" and id:match("^[%w_:%.%-]+$"),
        "App id must be a non-empty namespaced string without whitespace.")
end

local function translateAppLabel(key)
    if Kora.locale and Kora.locale.translate then return Kora.locale.translate('kora_lib', 'app.' .. key) end
    return APP_LABEL_FALLBACKS[key]
end

-- Handlers can't be JSON-encoded into SendNUIMessage; keep them in the private registry.
local function appLabels()
    return {
        cancel = translateAppLabel('cancel'), confirm = translateAppLabel('confirm'), working = translateAppLabel('working'),
        runAction = translateAppLabel('run_action'), search = translateAppLabel('search'), previous = translateAppLabel('previous'),
        next = translateAppLabel('next'), noRecords = translateAppLabel('no_records'), nothingHere = translateAppLabel('nothing_here'),
        emptyTitle = translateAppLabel('empty_title'), emptyDescription = translateAppLabel('empty_description'),
        close = translateAppLabel('close'), select = translateAppLabel('select'), required = translateAppLabel('required'),
        invalidFormat = translateAppLabel('invalid_format'), minValue = translateAppLabel('min_value'),
        maxValue = translateAppLabel('max_value'), minLength = translateAppLabel('min_length'),
        maxLength = translateAppLabel('max_length'), page = translateAppLabel('page'), recenter = translateAppLabel('recenter'),
        clear = translateAppLabel('clear'), backspace = translateAppLabel('backspace'),
        back = translateAppLabel('back'), open = translateAppLabel('open'), yes = translateAppLabel('yes'), no = translateAppLabel('no'),
        map = translateAppLabel('map'), zoomIn = translateAppLabel('zoom_in'), zoomOut = translateAppLabel('zoom_out'),
        value = translateAppLabel('value'), decrease = translateAppLabel('decrease'), increase = translateAppLabel('increase'),
    }
end

local function browserApp(definition)
    local result = {}
    for key, value in pairs(definition) do
        if key ~= "onAction" and key ~= "onChange" and key ~= "labels" then result[key] = value end
    end
    result.onChange = definition.onChange ~= nil or nil
    result.labels = appLabels()
    return result
end

local VALID_FIELD_TYPES = {
    text = true, password = true, textarea = true, number = true, checkbox = true,
    select = true, multiselect = true, range = true, combobox = true,
    date = true, ['date-range'] = true, time = true, color = true,
    ['key-value'] = true, vector = true,
}

local VALID_TONES = { neutral = true, primary = true, success = true, warning = true, destructive = true }
local VALID_ACTION_VARIANTS = { primary = true, secondary = true, outline = true, ghost = true, destructive = true }
local VALID_IMAGE_ASPECTS = { square = true, wide = true }
local VALID_IMAGE_FITS = { cover = true, contain = true, fill = true, none = true, ["scale-down"] = true }

local function assertPositiveInteger(value, message)
    assert(type(value) == "number" and value > 0 and value % 1 == 0, message)
end

local function assertOptions(options, location)
    assert(type(options) == "table", location .. " must be a table.")
    local values = {}
    for index = 1, #options do
        local option = options[index]
        local optionLocation = ("%s option %d"):format(location, index)
        assert(type(option) == "table", optionLocation .. " must be a table.")
        assert((type(option.value) == "string" or type(option.value) == "number")
            and tostring(option.value) ~= "", optionLocation .. " requires a value.")
        assert(type(option.label) == "string" and option.label ~= "", optionLocation .. " requires a label.")
        assert(option.disabled == nil or type(option.disabled) == "boolean", optionLocation .. " disabled must be a boolean.")
        local value = tostring(option.value)
        assert(not values[value], ("%s option value '%s' is duplicated."):format(location, value))
        values[value] = true
    end
end

local function assertMetadata(items, location)
    assert(type(items) == "table", location .. " metadata must be a table.")
    for index = 1, #items do
        local item = items[index]
        local itemLocation = ("%s metadata item %d"):format(location, index)
        assert(type(item) == "table" and type(item.label) == "string" and item.label ~= "",
            itemLocation .. " requires a label.")
        assert(type(item.value) == "string" or type(item.value) == "number" or type(item.value) == "boolean",
            itemLocation .. " requires a scalar value.")
        assert(item.tone == nil or VALID_TONES[item.tone], itemLocation .. " has an invalid tone.")
    end
end

local function assertCollectionOptions(block, location)
    assert(block.searchable == nil or type(block.searchable) == "boolean", location .. " searchable must be a boolean.")
    assert(block.searchPlaceholder == nil or type(block.searchPlaceholder) == "string", location .. " searchPlaceholder must be a string.")
    if block.pageSize ~= nil then assertPositiveInteger(block.pageSize, location .. " pageSize must be a positive integer.") end
end

local function assertPoint(point, location)
    assert(type(point) == "table" and Kora.util.isFiniteNumber(point.x) and Kora.util.isFiniteNumber(point.y),
        location .. " requires finite x and y values.")
end

local function assertInputFields(fields, location)
    assert(type(fields) == "table", ("%s fields must be a table."):format(location))
    local ids = {}
    for index = 1, #fields do
        local field = fields[index]
        local fieldLocation = ("%s field %d"):format(location, index)
        assert(type(field) == "table", fieldLocation .. " must be a table.")
        assert(type(field.id) == "string" and field.id ~= "", fieldLocation .. " requires an id.")
        assert(not ids[field.id], ("%s field id '%s' is duplicated."):format(location, field.id))
        assert(type(field.label) == "string" and field.label ~= "", fieldLocation .. " requires a label.")
        assert(VALID_FIELD_TYPES[field.type], fieldLocation .. " has an invalid type.")
        assert(field.description == nil or type(field.description) == "string", fieldLocation .. " description must be a string.")
        assert(field.required == nil or type(field.required) == "boolean", fieldLocation .. " required must be a boolean.")
        assert(field.disabled == nil or type(field.disabled) == "boolean", fieldLocation .. " disabled must be a boolean.")
        assert(field.min == nil or Kora.util.isFiniteNumber(field.min), fieldLocation .. " min must be a finite number.")
        assert(field.max == nil or Kora.util.isFiniteNumber(field.max), fieldLocation .. " max must be a finite number.")
        assert(field.minLength == nil or (type(field.minLength) == "number" and field.minLength >= 0 and field.minLength % 1 == 0), fieldLocation .. " minLength must be a non-negative integer.")
        assert(field.maxLength == nil or (type(field.maxLength) == "number" and field.maxLength >= 0 and field.maxLength % 1 == 0), fieldLocation .. " maxLength must be a non-negative integer.")
        assert(field.min == nil or field.max == nil or field.min <= field.max, fieldLocation .. " min cannot exceed max.")
        assert(field.minLength == nil or field.maxLength == nil or field.minLength <= field.maxLength,
            fieldLocation .. " minLength cannot exceed maxLength.")
        assert(field.pattern == nil or type(field.pattern) == "string", fieldLocation .. " pattern must be a string.")
        assert(field.dateMin == nil or type(field.dateMin) == "string" or Kora.util.isFiniteNumber(field.dateMin),
            fieldLocation .. " dateMin must be a string or finite timestamp.")
        assert(field.dateMax == nil or type(field.dateMax) == "string" or Kora.util.isFiniteNumber(field.dateMax),
            fieldLocation .. " dateMax must be a string or finite timestamp.")
        assert(field.returnString == nil or type(field.returnString) == "boolean", fieldLocation .. " returnString must be a boolean.")
        assert(field.dateFormat == nil or type(field.dateFormat) == "string", fieldLocation .. " dateFormat must be a string.")
        assert(field.precision == nil or (type(field.precision) == "number" and field.precision >= 0 and field.precision % 1 == 0),
            fieldLocation .. " precision must be a non-negative integer.")
        assert(field.colorFormat == nil or field.colorFormat == "hex" or field.colorFormat == "hexa" or field.colorFormat == "rgb"
            or field.colorFormat == "rgba" or field.colorFormat == "hsl" or field.colorFormat == "hsla",
            fieldLocation .. " colorFormat is invalid.")
        assert(field.timeFormat == nil or field.timeFormat == "12" or field.timeFormat == "24", fieldLocation .. " timeFormat is invalid.")
        assert(field.clearable == nil or type(field.clearable) == "boolean", fieldLocation .. " clearable must be a boolean.")
        assert(field.searchable == nil or type(field.searchable) == "boolean", fieldLocation .. " searchable must be a boolean.")
        assert(field.maxSelectedValues == nil or (type(field.maxSelectedValues) == "number" and field.maxSelectedValues > 0
            and field.maxSelectedValues % 1 == 0), fieldLocation .. " maxSelectedValues must be a positive integer.")
        assert(field.autosize == nil or type(field.autosize) == "boolean", fieldLocation .. " autosize must be a boolean.")
        assert(field.minRows == nil or (type(field.minRows) == "number" and field.minRows > 0 and field.minRows % 1 == 0),
            fieldLocation .. " minRows must be a positive integer.")
        assert(field.maxRows == nil or (type(field.maxRows) == "number" and field.maxRows > 0 and field.maxRows % 1 == 0),
            fieldLocation .. " maxRows must be a positive integer.")
        assert(field.minRows == nil or field.maxRows == nil or field.minRows <= field.maxRows, fieldLocation .. " minRows cannot exceed maxRows.")
        assert(field.icon == nil or type(field.icon) == "string", fieldLocation .. " icon must be a string.")
        assert(field.iconColor == nil or type(field.iconColor) == "string", fieldLocation .. " iconColor must be a string.")
        assert(field.rows == nil or (type(field.rows) == "number" and field.rows > 0 and field.rows % 1 == 0),
            fieldLocation .. " rows must be a positive integer.")
        assert(field.step == nil or (Kora.util.isFiniteNumber(field.step) and field.step > 0),
            fieldLocation .. " step must be a positive finite number.")
        assert(field.dependsOn == nil or type(field.dependsOn) == "string", fieldLocation .. " dependsOn must be a string.")
        assert(field.optionsByValue == nil or type(field.optionsByValue) == "table", fieldLocation .. " optionsByValue must be a table.")
        assert(field.visibleWhen == nil or (type(field.visibleWhen) == "table"
            and type(field.visibleWhen.fieldId) == "string"
            and (type(field.visibleWhen.equals) == "string" or type(field.visibleWhen.equals) == "number"
                or type(field.visibleWhen.equals) == "boolean")),
            fieldLocation .. " visibleWhen must contain fieldId and equals.")
        assert(field.keypad == nil or type(field.keypad) == "boolean", fieldLocation .. " keypad must be a boolean.")
        assert(field.numericOnly == nil or type(field.numericOnly) == "boolean", fieldLocation .. " numericOnly must be a boolean.")
        assert(field.wholeNumber == nil or type(field.wholeNumber) == "boolean", fieldLocation .. " wholeNumber must be a boolean.")
        assert(field.dimensions == nil or field.dimensions == 2 or field.dimensions == 3 or field.dimensions == 4,
            fieldLocation .. " dimensions must be 2, 3, or 4.")
        assert(field.keyMode == nil or field.keyMode == "string" or field.keyMode == "integer"
            or field.keyMode == "integer-map" or field.keyMode == "mixed",
            fieldLocation .. " keyMode must be string, integer, integer-map, or mixed.")
        if field.requiredKeys ~= nil then
            assert(type(field.requiredKeys) == 'table', fieldLocation .. ' requiredKeys must be an array.')
            for _, key in ipairs(field.requiredKeys) do
                assert(type(key) == 'string' or type(key) == 'number', fieldLocation .. ' required keys must be strings or numbers.')
            end
        end
        if field.valueField ~= nil then
            local item = field.valueField
            assert(type(item) == 'table' and (item.type == 'text' or item.type == 'number'
                or item.type == 'checkbox' or item.type == 'select'), fieldLocation .. ' valueField must be a scalar control.')
            assert(item.valueField == nil, fieldLocation .. ' valueField cannot contain nested controls.')
            assertInputFields({ item }, fieldLocation .. ' valueField')
        end
        for _, key in ipairs({ "keyLabel", "valueLabel", "addRowLabel", "removeRowLabel" }) do
            assert(field[key] == nil or type(field[key]) == "string", fieldLocation .. " " .. key .. " must be a string.")
        end
        assert(field.type ~= "vector" or field.dimensions ~= nil, fieldLocation .. " vector requires dimensions.")
        if field.options ~= nil then assertOptions(field.options, fieldLocation .. " options") end
        if field.optionsByValue ~= nil then
            for key, options in pairs(field.optionsByValue) do
                assert(type(key) == "string" or type(key) == "number", fieldLocation .. " optionsByValue keys must be scalar values.")
                assertOptions(options, ("%s optionsByValue[%s]"):format(fieldLocation, tostring(key)))
            end
        end
        if field.presets ~= nil then
            assert(type(field.presets) == "table", fieldLocation .. " presets must be a table.")
            for presetIndex = 1, #field.presets do
                local preset = field.presets[presetIndex]
                assert(type(preset) == "table" and Kora.util.isFiniteNumber(preset.value),
                    ("%s preset %d requires a finite numeric value."):format(fieldLocation, presetIndex))
                assert(preset.label == nil or type(preset.label) == "string",
                    ("%s preset %d label must be a string."):format(fieldLocation, presetIndex))
            end
        end
        if field.type == "select" or field.type == "multiselect" then
            assert(type(field.options) == "table" or type(field.optionsByValue) == "table", fieldLocation .. " requires options.")
        end
        if field.default ~= nil then
            if field.type == "checkbox" then
                assert(type(field.default) == "boolean", fieldLocation .. " checkbox default must be a boolean.")
            elseif field.type == "number" or field.type == "range" then
                assert(Kora.util.isFiniteNumber(field.default), fieldLocation .. " numeric default must be a finite number.")
            elseif field.type == "multiselect" or field.type == "date-range" then
                assert(type(field.default) == "table", fieldLocation .. " multiselect default must be an array.")
                for defaultIndex = 1, #field.default do
                    local value = field.default[defaultIndex]
                    assert(type(value) == "string" or Kora.util.isFiniteNumber(value),
                        ("%s default item %d must be a string or number."):format(fieldLocation, defaultIndex))
                end
            elseif field.type == "key-value" then
                assert(type(field.default) == "table", fieldLocation .. " key-value default must be a row array.")
                for defaultIndex = 1, #field.default do
                    local row = field.default[defaultIndex]
                    assert(type(row) == "table" and type(row.key) == "string" and type(row.value) == "string",
                        ("%s default row %d needs string key and value fields."):format(fieldLocation, defaultIndex))
                end
            elseif field.type == "vector" then
                assert(type(field.default) == "table", fieldLocation .. " vector default must be a component table.")
                local axes = { "x", "y", "z", "w" }
                for axisIndex = 1, field.dimensions do
                    assert(Kora.util.isFiniteNumber(field.default[axes[axisIndex]]),
                        ("%s vector default %s must be a finite number."):format(fieldLocation, axes[axisIndex]))
                end
            else
                assert(type(field.default) == "string" or type(field.default) == "number",
                    fieldLocation .. " default must be a string or number.")
            end
        end
        ids[field.id] = true
    end
    for index = 1, #fields do
        local field = fields[index]
        assert(field.dependsOn == nil or ids[field.dependsOn], ("%s field %d depends on an unknown field."):format(location, index))
        assert(field.visibleWhen == nil or ids[field.visibleWhen.fieldId], ("%s field %d visibility depends on an unknown field."):format(location, index))
    end
end

local function declareAction(actions, id, closeBeforeAction, location)
    assert(type(id) == "string" and id ~= "", location .. " action id must be a non-empty string.")
    local existing = actions[id]
    if existing ~= nil then
        assert(existing.closeBeforeAction == (closeBeforeAction == true), ("Action '%s' has conflicting closeBeforeAction settings."):format(id))
    else
        actions[id] = { closeBeforeAction = closeBeforeAction == true }
    end
end

local function assertAppAction(action, location, actionIds)
    assert(type(action) == "table", ("%s must contain action tables."):format(location))
    assert(type(action.id) == "string" and action.id ~= "", ("%s action id must be a non-empty string."):format(location))
    assert(type(action.label) == "string" and action.label ~= "", ("%s action label must be a non-empty string."):format(location))
    if action.fields ~= nil then assertInputFields(action.fields, location .. " action") end
    assert(action.icon == nil or type(action.icon) == "string", ("%s action icon must be a string."):format(location))
    assert(action.variant == nil or VALID_ACTION_VARIANTS[action.variant], ("%s action variant is invalid."):format(location))
    assert(action.disabled == nil or type(action.disabled) == "boolean", ("%s action disabled must be a boolean."):format(location))
    assert(action.confirm == nil or type(action.confirm) == "string", ("%s action confirm must be a string."):format(location))
    assert(action.closeBeforeAction == nil or type(action.closeBeforeAction) == "boolean", ("%s action closeBeforeAction must be a boolean."):format(location))
    declareAction(actionIds, action.id, action.closeBeforeAction, location)
    if action.fields then actionIds[action.id].form = true end
end

local function assertListItems(items, location, actionIds)
    assert(type(items) == "table", location .. " requires an items table.")
    local ids = {}
    for index = 1, #items do
        local item = items[index]
        local itemLocation = ("%s item %d"):format(location, index)
        assert(type(item) == "table" and type(item.id) == "string" and item.id ~= "", itemLocation .. " requires an id.")
        assert(not ids[item.id], ("%s item id '%s' is duplicated."):format(location, item.id))
        assert(type(item.label) == "string" and item.label ~= "", itemLocation .. " requires a label.")
        assert(item.description == nil or type(item.description) == "string", itemLocation .. " description must be a string.")
        assert(item.image == nil or type(item.image) == "string", itemLocation .. " image must be a string.")
        assert(item.imageFit == nil or VALID_IMAGE_FITS[item.imageFit], itemLocation .. " imageFit is invalid.")
        assert(item.imageAspect == nil or VALID_IMAGE_ASPECTS[item.imageAspect], itemLocation .. " imageAspect is invalid.")
        assert(item.tone == nil or VALID_TONES[item.tone], itemLocation .. " has an invalid tone.")
        if item.metadata ~= nil then assertMetadata(item.metadata, itemLocation) end
        if item.action ~= nil then
            if type(item.action) == "table" then assertAppAction(item.action, itemLocation, actionIds)
            else declareAction(actionIds, item.action, false, itemLocation) end
        end
        if item.actions ~= nil then
            assert(type(item.actions) == "table", itemLocation .. " actions must be a table.")
            for actionIndex = 1, #item.actions do
                assertAppAction(item.actions[actionIndex], itemLocation, actionIds)
            end
        end
        if item.children ~= nil then assertListItems(item.children, itemLocation .. " children", actionIds) end
        ids[item.id] = true
    end
end

local function assertAppContent(content, location, actionIds)
    if content == nil then return end
    assert(type(content) == "table", ("%s content must be a table."):format(location))
    assert(content.title == nil or type(content.title) == "string", location .. " title must be a string.")
    assert(content.description == nil or type(content.description) == "string", location .. " description must be a string.")
    assert(content.scrollable == nil or type(content.scrollable) == "boolean",
        location .. " scrollable must be a boolean.")

    if content.actions ~= nil then
        assert(type(content.actions) == "table", ("%s actions must be a table."):format(location))
        for actionIndex = 1, #content.actions do
            assertAppAction(content.actions[actionIndex], location, actionIds)
        end
    end

    if content.blocks == nil then return end
    assert(type(content.blocks) == "table", ("%s blocks must be a table."):format(location))
    local blockTypes = { text = true, stats = true, progress = true, table = true, list = true, actions = true,
        form = true, details = true, timeline = true, map = true, empty = true }

    local blockIds = {}
    for index = 1, #content.blocks do
        local block = content.blocks[index]
        local blockLocation = ("%s block %d"):format(location, index)
        assert(type(block) == "table" and blockTypes[block.type], blockLocation .. " has an invalid type.")
        if block.id ~= nil then
            assert(type(block.id) == "string" and block.id ~= "", blockLocation .. " id must be a non-empty string.")
            assert(not blockIds[block.id], ("%s block id '%s' is duplicated."):format(location, block.id))
            blockIds[block.id] = true
        end
        if block.type == "text" then
            assert(type(block.text) == "string", blockLocation .. " requires text.")
        elseif block.type == "stats" then
            assert(type(block.items) == "table", blockLocation .. " requires an items table.")
            for itemIndex = 1, #block.items do
                local item = block.items[itemIndex]
                assert(type(item) == "table" and type(item.label) == "string" and item.label ~= ""
                    and (type(item.value) == "string" or type(item.value) == "number"),
                    ("%s item %d is invalid."):format(blockLocation, itemIndex))
                assert(item.description == nil or type(item.description) == "string",
                    ("%s item %d description must be a string."):format(blockLocation, itemIndex))
                assert(item.icon == nil or type(item.icon) == "string",
                    ("%s item %d icon must be a string."):format(blockLocation, itemIndex))
                assert(item.tone == nil or VALID_TONES[item.tone], ("%s item %d has an invalid tone."):format(blockLocation, itemIndex))
            end
        elseif block.type == "progress" then
            assert(type(block.items) == "table", blockLocation .. " requires an items table.")
            for itemIndex = 1, #block.items do
                local item = block.items[itemIndex]
                assert(type(item) == "table" and type(item.label) == "string" and item.label ~= ""
                    and Kora.util.isFiniteNumber(item.value) and Kora.util.isFiniteNumber(item.max) and item.max > 0,
                    ("%s item %d requires a label, finite numeric value, and positive max."):format(blockLocation, itemIndex))
                assert(item.value >= 0 and item.value <= item.max,
                    ("%s item %d value must be between zero and max."):format(blockLocation, itemIndex))
                assert(item.description == nil or type(item.description) == "string",
                    ("%s item %d description must be a string."):format(blockLocation, itemIndex))
                assert(item.detail == nil or type(item.detail) == "string",
                    ("%s item %d detail must be a string."):format(blockLocation, itemIndex))
                assert(item.icon == nil or type(item.icon) == "string",
                    ("%s item %d icon must be a string."):format(blockLocation, itemIndex))
                assert(item.tone == nil or VALID_TONES[item.tone], ("%s item %d has an invalid tone."):format(blockLocation, itemIndex))
            end
        elseif block.type == "details" then
            assert(type(block.items) == "table", blockLocation .. " requires an items table.")
            assert(block.columns == nil or (type(block.columns) == "number" and block.columns >= 1 and block.columns <= 3 and block.columns % 1 == 0),
                blockLocation .. " columns must be an integer from 1 to 3.")
            for itemIndex = 1, #block.items do
                local item = block.items[itemIndex]
                assert(type(item) == "table" and type(item.label) == "string" and item.label ~= "",
                    ("%s item %d requires a label."):format(blockLocation, itemIndex))
                assert(item.value == nil or type(item.value) == "string" or type(item.value) == "number" or type(item.value) == "boolean",
                    ("%s item %d value must be scalar."):format(blockLocation, itemIndex))
                assert(item.tone == nil or VALID_TONES[item.tone], ("%s item %d has an invalid tone."):format(blockLocation, itemIndex))
            end
        elseif block.type == "list" then
            assert(block.layout == nil or block.layout == "list" or block.layout == "grid" or block.layout == "cards",
                blockLocation .. " layout must be 'list', 'grid', or 'cards'.")
            assert(block.cardStyle == nil or block.cardStyle == "compact" or block.cardStyle == "media",
                blockLocation .. " cardStyle must be 'compact' or 'media'.")
            assert(block.imageFit == nil or VALID_IMAGE_FITS[block.imageFit], blockLocation .. " imageFit is invalid.")
            assert(block.imageAspect == nil or VALID_IMAGE_ASPECTS[block.imageAspect], blockLocation .. " imageAspect is invalid.")
            assert(block.columns == nil or (type(block.columns) == "number" and block.columns >= 1 and block.columns <= 4 and block.columns % 1 == 0),
                blockLocation .. " columns must be an integer from 1 to 4.")
            assert(block.empty == nil or type(block.empty) == "string", blockLocation .. " empty must be a string.")
            assert(block.scrollable == nil or type(block.scrollable) == "boolean",
                blockLocation .. " scrollable must be a boolean.")
            assertCollectionOptions(block, blockLocation)
            assertListItems(block.items, blockLocation, actionIds)
        elseif block.type == "table" then
            assert(type(block.columns) == "table" and type(block.rows) == "table",
                blockLocation .. " requires columns and rows tables.")
            assert(block.empty == nil or type(block.empty) == "string", blockLocation .. " empty must be a string.")
            assertCollectionOptions(block, blockLocation)
            local columnKeys = {}
            for columnIndex = 1, #block.columns do
                local column = block.columns[columnIndex]
                local columnLocation = ("%s column %d"):format(blockLocation, columnIndex)
                assert(type(column) == "table" and type(column.key) == "string" and column.key ~= ""
                    and type(column.label) == "string" and column.label ~= "", columnLocation .. " is invalid.")
                assert(not columnKeys[column.key], ("%s column key '%s' is duplicated."):format(blockLocation, column.key))
                assert(column.align == nil or column.align == "left" or column.align == "center" or column.align == "right",
                    columnLocation .. " align is invalid.")
                assert(column.sortable == nil or type(column.sortable) == "boolean", columnLocation .. " sortable must be a boolean.")
                columnKeys[column.key] = true
            end
            for rowIndex = 1, #block.rows do
                assert(type(block.rows[rowIndex]) == "table",
                    ("%s row %d must be a table."):format(blockLocation, rowIndex))
            end
            assert(block.idKey == nil or type(block.idKey) == "string", blockLocation .. " idKey must be a string.")
            if block.action ~= nil then declareAction(actionIds, block.action, false, blockLocation) end
        elseif block.type == "actions" then
            assert(type(block.actions) == "table", blockLocation .. " requires an actions table.")
            for actionIndex = 1, #block.actions do
                assertAppAction(block.actions[actionIndex], blockLocation, actionIds)
            end
        elseif block.type == "form" then
            assert(type(block.id) == "string" and block.id ~= "", blockLocation .. " requires an id.")
            assert(block.submitLabel == nil or type(block.submitLabel) == "string", blockLocation .. " submitLabel must be a string.")
            assertInputFields(block.fields, blockLocation)
            assertAppAction(block.action, blockLocation, actionIds)
            actionIds[block.action.id].form = true
        elseif block.type == "timeline" then
            assert(type(block.items) == "table", blockLocation .. " requires an items table.")
            assert(block.empty == nil or type(block.empty) == "string", blockLocation .. " empty must be a string.")
            local itemIds = {}
            for itemIndex = 1, #block.items do
                local item = block.items[itemIndex]
                assert(type(item) == "table" and type(item.id) == "string" and item.id ~= ""
                    and type(item.title) == "string" and item.title ~= "",
                    ("%s item %d is invalid."):format(blockLocation, itemIndex))
                assert(not itemIds[item.id], ("%s item id '%s' is duplicated."):format(blockLocation, item.id))
                assert(item.description == nil or type(item.description) == "string",
                    ("%s item %d description must be a string."):format(blockLocation, itemIndex))
                assert(item.timestamp == nil or type(item.timestamp) == "string",
                    ("%s item %d timestamp must be a string."):format(blockLocation, itemIndex))
                assert(item.tone == nil or VALID_TONES[item.tone], ("%s item %d has an invalid tone."):format(blockLocation, itemIndex))
                if item.metadata ~= nil then assertMetadata(item.metadata, blockLocation .. " timeline") end
                if item.actions ~= nil then
                    assert(type(item.actions) == "table", blockLocation .. " timeline actions must be a table.")
                    for actionIndex = 1, #item.actions do
                        assertAppAction(item.actions[actionIndex], blockLocation, actionIds)
                    end
                end
                itemIds[item.id] = true
            end
        elseif block.type == "map" then
            assert(type(block.tiles) == "table" and type(block.tiles.url) == "string" and block.tiles.url ~= "",
                blockLocation .. " requires a tile URL template.")
            assert(type(block.markers) == "table", blockLocation .. " requires a markers table.")
            assert(block.empty == nil or type(block.empty) == "string", blockLocation .. " empty must be a string.")
            assert(block.tiles.tileSize == nil or (Kora.util.isFiniteNumber(block.tiles.tileSize) and block.tiles.tileSize > 0),
                blockLocation .. " tileSize must be a positive finite number.")
            assert(block.follow == nil or type(block.follow) == "boolean", blockLocation .. " follow must be a boolean.")
            assert(block.fadeDuration == nil or (Kora.util.isFiniteNumber(block.fadeDuration) and block.fadeDuration >= 0),
                blockLocation .. " fadeDuration must be a non-negative finite number.")
            assert(block.minZoom == nil or Kora.util.isFiniteNumber(block.minZoom), blockLocation .. " minZoom must be a finite number.")
            assert(block.maxZoom == nil or Kora.util.isFiniteNumber(block.maxZoom), blockLocation .. " maxZoom must be a finite number.")
            assert(block.minZoom == nil or block.maxZoom == nil or block.minZoom <= block.maxZoom,
                blockLocation .. " minZoom cannot exceed maxZoom.")
            assert(block.initialZoom == nil or Kora.util.isFiniteNumber(block.initialZoom),
                blockLocation .. " initialZoom must be a finite number.")
            if block.tiles.grid ~= nil then
                assertPoint(block.tiles.grid, blockLocation .. " tile grid")
                assert(block.tiles.grid.x > 0 and block.tiles.grid.y > 0, blockLocation .. " tile grid values must be positive.")
            end
            if block.tiles.calibration ~= nil then
                assert(type(block.tiles.calibration) == "table" and type(block.tiles.calibration.a) == "table"
                    and type(block.tiles.calibration.b) == "table", blockLocation .. " calibration requires a and b points.")
                assertPoint(block.tiles.calibration.a.world, blockLocation .. " calibration a.world")
                assertPoint(block.tiles.calibration.a.image, blockLocation .. " calibration a.image")
                assertPoint(block.tiles.calibration.b.world, blockLocation .. " calibration b.world")
                assertPoint(block.tiles.calibration.b.image, blockLocation .. " calibration b.image")
            end
            if block.recenter ~= nil then
                assertPoint(block.recenter, blockLocation .. " recenter")
            end
            assert(block.now == nil or Kora.util.isFiniteNumber(block.now), blockLocation .. " now must be a finite number.")
            assert(block.selectedId == nil or type(block.selectedId) == "string", blockLocation .. " selectedId must be a string.")
            if block.action ~= nil then declareAction(actionIds, block.action, false, blockLocation) end
            local markerIds = {}
            for markerIndex = 1, #block.markers do
                local marker = block.markers[markerIndex]
                assert(type(marker) == "table" and type(marker.id) == "string" and marker.id ~= ""
                    and Kora.util.isFiniteNumber(marker.x) and Kora.util.isFiniteNumber(marker.y) and type(marker.label) == "string",
                    ("%s marker %d is invalid."):format(blockLocation, markerIndex))
                assert(not markerIds[marker.id], ("%s marker id '%s' is duplicated."):format(blockLocation, marker.id))
                assert(marker.description == nil or type(marker.description) == "string",
                    ("%s marker %d description must be a string."):format(blockLocation, markerIndex))
                assert(marker.heading == nil or Kora.util.isFiniteNumber(marker.heading),
                    ("%s marker %d heading must be a finite number."):format(blockLocation, markerIndex))
                assert(marker.expiresAt == nil or Kora.util.isFiniteNumber(marker.expiresAt),
                    ("%s marker %d expiresAt must be a finite number."):format(blockLocation, markerIndex))
                assert(marker.fadeDuration == nil or (Kora.util.isFiniteNumber(marker.fadeDuration) and marker.fadeDuration >= 0),
                    ("%s marker %d fadeDuration must be a non-negative finite number."):format(blockLocation, markerIndex))
                assert(marker.tone == nil or VALID_TONES[marker.tone], ("%s marker %d has an invalid tone."):format(blockLocation, markerIndex))
                if marker.action ~= nil then declareAction(actionIds, marker.action, false, blockLocation) end
                markerIds[marker.id] = true
            end
        elseif block.type == "empty" then
            assert(type(block.title) == "string" and block.title ~= "", blockLocation .. " requires a title.")
        end
    end
end

local function assertBrowserApp(definition)
    assertAppId(definition.id)
    assert(type(definition.title) == "string" and definition.title ~= "", "App title must be a non-empty string.")
    assert(definition.description == nil or type(definition.description) == "string", "App description must be a string.")
    assert(definition.icon == nil or type(definition.icon) == "string", "App icon must be a string.")
    assert(definition.footer == nil or type(definition.footer) == "string", "App footer must be a string.")
    assert(definition.accent == nil or (type(definition.accent) == "string"
        and definition.accent:match("^#%x%x%x%x%x%x$") ~= nil),
        "App accent must be a #RRGGBB hex colour.")
    assert(type(definition.navigation) == "table" and #definition.navigation > 0,
        "App navigation must contain at least one view.")
    assert(definition.layout == nil or definition.layout == "standard" or definition.layout == "compact",
        "App layout must be 'standard' or 'compact'.")
    assert(definition.placement == nil or definition.placement == "center" or definition.placement == "right",
        "App placement must be 'center' or 'right'.")
    assert(definition.width == nil or (type(definition.width) == "number" and definition.width > 0),
        "App width must be a positive number.")
    assert(definition.height == nil or (type(definition.height) == "number" and definition.height > 0),
        "App height must be a positive number.")

    local viewIds, actionIds = {}, {}
    local hasEnabledView = false
    for viewIndex = 1, #definition.navigation do
        local view = definition.navigation[viewIndex]
        local location = ("App navigation item %d"):format(viewIndex)
        assert(type(view) == "table", location .. " must be a table.")
        assert(type(view.id) == "string" and view.id ~= "", location .. " requires an id.")
        assert(not viewIds[view.id], ("App navigation id '%s' is duplicated."):format(view.id))
        assert(type(view.label) == "string" and view.label ~= "", location .. " requires a label.")
        assert(view.disabled == nil or type(view.disabled) == "boolean", location .. " disabled must be a boolean.")
        if view.onOpen ~= nil then declareAction(actionIds, view.onOpen, false, location) end
        viewIds[view.id] = true
        if not view.disabled then hasEnabledView = true end
        assertAppContent(view.content, ("App view '%s'"):format(view.id), actionIds)

        if view.tabs ~= nil then
            assert(type(view.tabs) == "table" and #view.tabs > 0,
                ("App view '%s' tabs must contain at least one tab."):format(view.id))
            local tabIds = {}
            for tabIndex = 1, #view.tabs do
                local tab = view.tabs[tabIndex]
                local tabLocation = ("App view '%s' tab %d"):format(view.id, tabIndex)
                assert(type(tab) == "table", tabLocation .. " must be a table.")
                assert(type(tab.id) == "string" and tab.id ~= "", tabLocation .. " requires an id.")
                assert(not tabIds[tab.id], ("App view '%s' tab id '%s' is duplicated."):format(view.id, tab.id))
                assert(type(tab.label) == "string" and tab.label ~= "", tabLocation .. " requires a label.")
                tabIds[tab.id] = true
                assertAppContent(tab.content, ("App view '%s' tab '%s'"):format(view.id, tab.id), actionIds)
            end
            assert(view.defaultTab == nil or tabIds[view.defaultTab],
                ("App view '%s' defaultTab must reference a declared tab."):format(view.id))
        else
            assert(view.defaultTab == nil, ("App view '%s' cannot set defaultTab without tabs."):format(view.id))
        end
    end
    assert(hasEnabledView, "App navigation must contain at least one enabled view.")
    assert(definition.defaultView == nil or viewIds[definition.defaultView], "App defaultView must reference a declared view.")
    return actionIds
end

local function mergeAppUpdate(registration, update)
    assert(type(update) == "table", "App update must be a table.")

    local candidate = {}
    for key, value in pairs(registration.browser) do candidate[key] = value end
    for key, value in pairs(update) do
        assert(key ~= "id", "App id cannot be changed by updateApp.")
        assert(key ~= "onAction", "Use registerApp to replace an app action handler.")
        assert(key ~= "onChange", "Use registerApp to replace an app change handler.")
        assert(key ~= "labels", "App labels are owned by kora_lib's locale system.")
        candidate[key] = value
    end
    registration.actionIds = assertBrowserApp(candidate)
    registration.browser = candidate
end

---Sends a message to the NUI. Every module should go through this (and the
---request/response helpers below) instead of talking to the NUI natives
---directly, so the message contract stays in one place.
---@param action string
---@param data any
function Kora.nui.send(action, data)
    SendNUIMessage({ action = action, data = data })
end

---Sets NUI focus directly. Prefer `Kora.nui.withFocus` when the caller can scope
---focus to a single operation -- this exists for the rarer case (e.g. a HUD
---that needs to hold focus across several unrelated calls) where that doesn't fit.
---@param mouse boolean
---@param keyboard boolean
function Kora.nui.setFocus(mouse, keyboard)
    SetNuiFocus(mouse, keyboard)
end

-- Surfaces take focus leases so closing a child dialog doesn't steal input from the app beneath it.
local function refreshFocus()
    local mouse, keyboard, keepInput, hasLease = false, false, false, false
    for _, lease in pairs(focusLeases) do
        hasLease = true
        mouse = mouse or lease.mouse
        keyboard = keyboard or lease.keyboard
        keepInput = keepInput or lease.keepInput
    end
    SetNuiFocus(mouse, keyboard)
    if hasLease then
        SetNuiFocusKeepInput(keepInput)
        return
    end

    SetNuiFocusKeepInput(focusBaseKeepInput == true)
    focusBaseKeepInput = nil
end

local function acquireFocus(mouse, keyboard, owner, keepInput)
    if next(focusLeases) == nil then
        focusBaseKeepInput = type(IsNuiFocusKeepingInput) == 'function' and IsNuiFocusKeepingInput() or false
    end
    nextFocusLease = nextFocusLease + 1
    local id = nextFocusLease
    focusLeases[id] = { mouse = mouse == true, keyboard = keyboard == true, keepInput = keepInput == true }
    focusOwnership.track(owner or GetInvokingResource() or GetCurrentResourceName(), id)
    refreshFocus()

    local released = false
    return function()
        if released then return end
        released = true
        focusOwnership.untrack(id)
        focusLeases[id] = nil
        refreshFocus()
    end
end

---Acquires an owner-tracked focus lease for a composed compatibility surface.
---The returned release function is intended to stay inside kora_lib; ordinary
---resources should use withFocus or an open* helper.
---@param mouse boolean
---@param keyboard boolean
---@param keepInput? boolean
---@param owner? string
---@return function release
function Kora.nui.acquireFocus(mouse, keyboard, keepInput, owner)
    assert(type(mouse) == 'boolean' and type(keyboard) == 'boolean', 'acquireFocus requires boolean mouse and keyboard values.')
    assert(keepInput == nil or type(keepInput) == 'boolean', 'acquireFocus keepInput must be a boolean.')
    assert(owner == nil or (type(owner) == 'string' and owner ~= ''), 'acquireFocus owner must be a non-empty string.')
    return acquireFocus(mouse, keyboard, owner, keepInput)
end

---Releases a lease returned by Kora.nui.acquireFocus.
---@param release function
function Kora.nui.releaseFocus(release)
    assert(isCallable(release), 'releaseFocus requires a focus release function.')
    release()
end

---Runs `fn` with NUI focus set and always releases it afterward, even if `fn` errors.
---@param mouse boolean
---@param keyboard boolean
---@param fn fun(): any
---@param owner? string Internal owner override for kora_lib modules whose operation continues in a new coroutine.
---@return any
function Kora.nui.withFocus(mouse, keyboard, fn, owner)
    assert(type(mouse) == 'boolean' and type(keyboard) == 'boolean', 'withFocus requires boolean mouse and keyboard values.')
    assert(isCallable(fn), 'withFocus requires a callable function.')
    assert(owner == nil or (type(owner) == 'string' and owner ~= ''), 'withFocus owner must be a non-empty string.')
    local release = acquireFocus(mouse, keyboard, owner)

    local results = table.pack(pcall(fn))

    release()

    if not results[1] then error(results[2], 0) end

    return table.unpack(results, 2, results.n)
end

local LEGACY_ALIASED_CALLBACKS = {
    ['kora_lib:dispatchfeed:ready'] = true,
    ['kora_lib:nui:response'] = true,
    ['kora_lib:nui:event'] = true,
    ['kora_lib:nui:theme'] = true,
    ['kora_lib:app:change'] = true,
    ['kora_lib:app:action'] = true,
    ['kora_lib:oxLocale'] = true,
}

---Registers an NUI callback, wrapping RegisterNUICallback's raw `(data, cb)`
---signature so handlers just return a value (or nil) like a normal function.
---A handler that errors is logged and responds with an empty table rather than
---leaving the NUI's fetch promise hanging.
---@param name string
---@param handler fun(data: any): any
function Kora.nui.registerCallback(name, handler)
    assert(type(name) == 'string' and name ~= '', 'registerCallback requires a non-empty callback name.')
    assert(isCallable(handler), 'registerCallback requires a callable handler.')
    local function register(callbackName)
        RegisterNUICallback(callbackName, function(data, cb)
            local ok, result = pcall(handler, data)

            if not ok then
                print(("[kora_lib:nui] callback '%s' errored: %s"):format(callbackName, tostring(result)))
                cb({})
                return
            end

            cb(result == nil and {} or result)
        end)
    end

    register(name)
    -- Deprecated qblib: names stay answered for cached older web builds and external callers.
    if LEGACY_ALIASED_CALLBACKS[name] then register('qblib:' .. name:sub(#'kora_lib:' + 1)) end
end

local feedPayload = false
local feedUpdatedAt = 0
local feedOwnership = Kora.resources.registry(function()
    feedPayload = false
    Kora.nui.send('qbdispatch:feed', false)
end)

---Updates kora_dispatch's display-only feed without taking focus.
---@param payload table|false false clears the caller-owned surface.
---@return boolean accepted
function Kora.nui.setDispatchFeed(payload)
    assert(payload == false or (type(payload) == 'table' and Kora.util.isFiniteNumber(payload.now)),
        'Dispatch feed requires a payload with a finite now timestamp or false.')
    local caller = GetInvokingResource() or GetCurrentResourceName()
    local owner = feedOwnership.owner('feed')
    if owner and owner ~= caller then return false end
    if payload == false then feedOwnership.untrack('feed')
    else
        feedOwnership.track(caller, 'feed')
        feedUpdatedAt = GetGameTimer()
    end
    feedPayload = payload
    Kora.nui.send('qbdispatch:feed', payload)
    return true
end

-- Persistent state may arrive before the browser subscribes; re-emit into this frame.
Kora.nui.registerCallback('kora_lib:dispatchfeed:ready', function()
    local payload = feedPayload
    if payload then
        payload = {}
        for key, value in pairs(feedPayload) do payload[key] = value end
        payload.now = feedPayload.now + (GetGameTimer() - feedUpdatedAt)
    end
    Kora.nui.send('qbdispatch:feed', payload)
    return true
end)

---Shared response channel for every `Kora.nui.request`, keyed by requestId. A missing or mismatched `data.token` is ignored.
Kora.nui.registerCallback("kora_lib:nui:response", function(data)
    if type(data) ~= "table" then return {} end

    local pending = pendingRequests[data.requestId]
    if not pending then return {} end
    if type(data.token) ~= "string" or data.token ~= pending.token then return {} end

    pendingRequests[data.requestId] = nil
    requestOwnership.untrack(data.requestId)

    if data.ok then
        pending.promise:resolve(data.result)
    else
        pending.promise:reject(data.error or "NUI request failed.")
    end

    return {}
end)

-- Non-terminal events (e.g. menu selection change) don't resolve the request; the same per-request token validates them.
Kora.nui.registerCallback("kora_lib:nui:event", function(data)
    if type(data) ~= "table" then return {} end

    local pending = pendingRequests[data.requestId]
    if not pending or type(data.token) ~= "string" or data.token ~= pending.token then return {} end
    if not pending.onEvent then return {} end

    local ok, err = pcall(pending.onEvent, data.event, data.data)
    if not ok then
        print(("[kora_lib:nui] request event '%s' errored: %s"):format(tostring(data.event), tostring(err)))
    end
    return {}
end)

-- A promise doesn't survive a real cross-resource exports() call (field reads like .state never reflect the remote promise, so Citizen.Await resolves nil).
-- GetInvokingResource() is nil for same-VM callers, who get the promise unchanged; cross-resource callers get the awaited value.
-- Deliberately duplicated per-file; see local/callback/{client,server}.lua and modules/zones/client.lua.
local function settleForExport(p)
    if GetInvokingResource() then
        return Citizen.Await(p)
    end
    return p
end

---Sends `action` to the NUI and returns a promise that resolves with whatever
---the NUI eventually posts back to the shared `kora_lib:nui:response` callback
---for this request's id (carrying the matching token). This is the core
---primitive menus, input dialogs, and `Kora.nui.copyToClipboard` are all built on.
---@param action string
---@param data any
---@param timeout? integer | false Milliseconds before the promise rejects. Defaults to 30000; pass false to disable.
---@param owner? string Internal owner override for kora_lib operations that continue in a new coroutine.
---@return promise promise
local function requestPromise(action, data, timeout, owner, onEvent)
    if timeout ~= false then
        timeout = timeout or 30000
        assert(Kora.util.isInteger(timeout) and timeout >= 0,
            "NUI request timeout must be a non-negative finite integer or false.")
    end

    local requestId = nextId()
    local token = generateToken()
    local p = promise.new()
    owner = owner or GetInvokingResource() or GetCurrentResourceName()
    -- Private metadata for the app shell callbacks; kept off the wire envelope and the public return value.
    p.koraLibNuiRequestId = requestId
    p.koraLibNuiToken = token
    p.koraLibNuiOwner = owner
    pendingRequests[requestId] = { promise = p, token = token, onEvent = onEvent }
    requestOwnership.track(owner, requestId)

    Kora.nui.send(action, { requestId = requestId, token = token, payload = data })

    if timeout ~= false then
        -- One-shot native timer: this almost never fires, so it shouldn't cost a thread per request.
        SetTimeout(timeout, function()
            if pendingRequests[requestId] then
                pendingRequests[requestId] = nil
                requestOwnership.untrack(requestId)
                p:reject("NUI request timed out.")
            end
        end)
    end

    return p
end

-- Settles a known local request without a browser round trip, so focus is released even if the frame vanishes first.
local function settlePendingRequest(p, ok, value)
    local requestId = p and p.koraLibNuiRequestId
    local pending = requestId and pendingRequests[requestId]
    if not pending or pending.promise ~= p then return false end

    pendingRequests[requestId] = nil
    requestOwnership.untrack(requestId)
    if ok then p:resolve(value) else p:reject(value) end
    return true
end

---Public wrapper over the same primitive above, for callers sending a custom
---NUI action kora_lib doesn't have a dedicated wrapper for.
---@param action string
---@param data any
---@param timeout? integer | false
---@param owner? string Internal owner override for kora_lib operations that continue in a new coroutine.
---@return promise|any result A promise for a same-VM caller (unchanged, awaitable as before); the
---already-settled result value directly for a genuine cross-resource caller (see settleForExport above).
function Kora.nui.request(action, data, timeout, owner)
    return settleForExport(requestPromise(action, data, timeout, owner))
end

local focusUntilSettled

---Starts a request without awaiting it across an enclosing export call.
---This is an internal composition primitive for kora_lib modules that need to
---retain a cancellable request handle while preserving the original consumer
---as owner. Ordinary resources should use Kora.nui.request/open* instead.
---@param action string
---@param data any
---@param timeout? integer | false
---@param owner? string
---@param focused? boolean
---@param onEvent? fun(event: string, data: any) Internal handler for token-validated, non-terminal browser events.
---@return promise request
function Kora.nui.requestAsync(action, data, timeout, owner, focused, onEvent)
    assert(type(action) == 'string' and action ~= '', 'requestAsync action must be a non-empty string.')
    assert(owner == nil or (type(owner) == 'string' and owner ~= ''), 'requestAsync owner must be a non-empty string.')
    assert(focused == nil or type(focused) == 'boolean', 'requestAsync focused must be a boolean.')
    assert(onEvent == nil or isCallable(onEvent), 'requestAsync onEvent must be callable.')

    local request = requestPromise(action, data, timeout, owner, onEvent)
    return focused and focusUntilSettled(request) or request
end

-- Holds mouse+keyboard focus until the request settles; the timeout guarantees focus can't get stuck.
function focusUntilSettled(p)
    local release = acquireFocus(true, true, p.koraLibNuiOwner)
    p:next(release, release)

    return p
end

---Settles and dismisses a request created by Kora.nui.requestAsync. The token is
---sent to the browser before the local promise is settled, so the component
---cannot answer the abandoned request afterward.
---@param request promise
---@param result? any
---@param rejection? string
---@return boolean cancelled
function Kora.nui.cancelRequest(request, result, rejection)
    assert(type(request) == 'table', 'cancelRequest requires a kora_lib NUI request.')
    assert(rejection == nil or type(rejection) == 'string', 'cancelRequest rejection must be a string.')

    local requestId = request.koraLibNuiRequestId
    local token = request.koraLibNuiToken
    local pending = requestId and pendingRequests[requestId]
    if not pending or pending.promise ~= request then return false end

    Kora.nui.send('cancelNuiRequest', { requestId = requestId, token = token })
    return settlePendingRequest(request, rejection == nil, rejection or result)
end

---Updates a still-pending request surface without replacing its promise or
---focus lease. Compatibility providers use this for live registry refreshes.
---@param request promise
---@param action string
---@param data any
---@return boolean updated
function Kora.nui.updateRequest(request, action, data)
    assert(type(request) == 'table', 'updateRequest requires a kora_lib NUI request.')
    assert(type(action) == 'string' and action ~= '', 'updateRequest action must be a non-empty string.')
    local requestId = request.koraLibNuiRequestId
    local pending = requestId and pendingRequests[requestId]
    if not pending or pending.promise ~= request then return false end

    Kora.nui.send(action, { requestId = requestId, token = request.koraLibNuiToken, payload = data })
    return true
end

---Copies `text` to the system clipboard via the NUI (the only place with
---access to a real clipboard API). While the browser copies it holds a brief
---input-passthrough NUI focus lease (Config.nui.clipboardFocus), because CEF
---refuses to copy without document focus. Never errors on a failed copy.
---@param text string
---@return promise|boolean copied true when the clipboard was written; false on failure or timeout. Exports return the settled boolean.
function Kora.nui.copyToClipboard(text)
    assert(type(text) == "string", "copyToClipboard requires a string.")
    local request = requestPromise("copyToClipboard", { text = text })

    local release
    if not (Config and Config.nui and Config.nui.clipboardFocus == false) then
        release = acquireFocus(true, false, request.koraLibNuiOwner, true)
    end

    local result = promise.new()
    request:next(function(value)
        if release then release() end
        result:resolve(value == true)
    end, function()
        if release then release() end
        result:resolve(false)
    end)
    return settleForExport(result)
end

local isFiniteNumber = Kora.util.isFiniteNumber

local function assertMenuItems(items, context, visited)
    assert(type(items) == "table", ("%s requires an items table."):format(context))
    visited = visited or {}
    assert(not visited[items], ("%s must not contain a recursive submenu."):format(context))
    visited[items] = true
    local itemCount = 0
    for key in pairs(items) do
        assert(type(key) == "number" and key >= 1 and key % 1 == 0 and key <= #items,
            ("%s items must be a dense array."):format(context))
        itemCount = itemCount + 1
    end
    assert(itemCount == #items, ("%s items must be a dense array."):format(context))

    for index = 1, #items do
        local item = items[index]
        assert(type(item) == "table", ("%s item %d must be a table."):format(context, index))
        assert(type(item.id) == "string" and item.id ~= "",
            ("%s item %d requires a non-empty string id."):format(context, index))
        assert(type(item.label) == "string" and item.label ~= "",
            ("%s item %d requires a non-empty string label."):format(context, index))
        for fieldIndex = 1, #MENU_ITEM_STRING_FIELDS do
            local field = MENU_ITEM_STRING_FIELDS[fieldIndex]
            assert(item[field] == nil or type(item[field]) == "string",
                ("%s item %d %s must be a string."):format(context, index, field))
        end
        assert(item.disabled == nil or type(item.disabled) == "boolean",
            ("%s item %d disabled must be a boolean."):format(context, index))
        assert(item.checked == nil or type(item.checked) == "boolean",
            ("%s item %d checked must be a boolean."):format(context, index))
        assert(item.close == nil or type(item.close) == "boolean",
            ("%s item %d close must be a boolean."):format(context, index))
        assert(item.progress == nil or (isFiniteNumber(item.progress) and item.progress >= 0 and item.progress <= 100),
            ("%s item %d progress must be between 0 and 100."):format(context, index))
        assert(item.colorScheme == nil or type(item.colorScheme) == "string",
            ("%s item %d colorScheme must be a string."):format(context, index))
        assert(item.iconColor == nil or type(item.iconColor) == "string",
            ("%s item %d iconColor must be a string."):format(context, index))
        if item.values ~= nil then
            assert(type(item.values) == "table" and #item.values > 0,
                ("%s item %d values must be a non-empty array."):format(context, index))
            for valueIndex = 1, #item.values do
                local value = item.values[valueIndex]
                assert(type(value) == "string" or (type(value) == "table" and type(value.label) == "string"
                    and (value.description == nil or type(value.description) == "string")),
                    ("%s item %d value %d must be a string or label/description table."):format(context, index, valueIndex))
            end
            assert(item.defaultIndex == nil or (type(item.defaultIndex) == "number" and item.defaultIndex % 1 == 0
                and item.defaultIndex >= 1 and item.defaultIndex <= #item.values),
                ("%s item %d defaultIndex must reference a value."):format(context, index))
        else
            assert(item.defaultIndex == nil, ("%s item %d cannot have defaultIndex without values."):format(context, index))
        end

        if item.submenu ~= nil then
            assert(type(item.submenu) == "table", ("%s item %d submenu must be a table."):format(context, index))
            assert(item.submenu.title == nil or type(item.submenu.title) == "string",
                ("%s item %d submenu title must be a string."):format(context, index))
            assertMenuItems(item.submenu.items, ("%s item %d submenu"):format(context, index), visited)
        end
    end
    visited[items] = nil
end

local function assertMenuGeometry(title, opts)
    assert(title == nil or type(title) == "string", "Menu title must be a string.")
    assert(opts == nil or type(opts) == "table", "Menu options must be a table.")
    if not opts then return end

    assert(opts.canClose == nil or type(opts.canClose) == "boolean", "Menu canClose must be a boolean.")
    assert(opts.presentation == nil or opts.presentation == "dialog" or opts.presentation == "panel",
        "Menu presentation must be dialog or panel.")
    assert(opts.startIndex == nil or (type(opts.startIndex) == "number" and opts.startIndex > 0 and opts.startIndex % 1 == 0),
        "Menu startIndex must be a positive integer.")

    for i = 1, #MENU_SIZE_FIELDS do
        local field = MENU_SIZE_FIELDS[i]
        assert(opts[field] == nil or (isFiniteNumber(opts[field]) and opts[field] > 0),
            ("Menu %s must be a positive finite number."):format(field))
    end
    if opts.position then
        local position = opts.position
        assert(type(position) == "table", "Menu position must be a table.")
        assert(position.horizontal == nil or position.horizontal == "left" or position.horizontal == "center" or position.horizontal == "right",
            "Menu horizontal position must be left, center, or right.")
        assert(position.vertical == nil or position.vertical == "top" or position.vertical == "center" or position.vertical == "bottom",
            "Menu vertical position must be top, center, or bottom.")
        for i = 1, #MENU_OFFSET_FIELDS do
            local field = MENU_OFFSET_FIELDS[i]
            assert(position[field] == nil or (isFiniteNumber(position[field]) and position[field] >= 0),
                ("Menu position %s must be a non-negative finite number."):format(field))
        end
    end
end

---Opens a searchable list menu. Grants NUI focus while open and releases it
---when the menu closes (selection, cancel, or timeout).
---@param items table[] `{ id: string, label: string, description?: string, icon?: string, disabled?: boolean, submenu?: { title?: string, items: table[] } }[]`
---@param title? string
---@param opts? table `{ position?: { horizontal?: 'left'|'center'|'right', vertical?: 'top'|'center'|'bottom', offsetX?: positive number, offsetY?: positive number }, maxWidth?: positive number, maxHeight?: positive number }` Geometry in screen pixels; defaults to the existing centred menu.
---@return promise|any result Resolves/returns `{ selectedId: string, path: string[] }` or `{ cancelled: true }`. See Kora.nui.request's return doc.
function Kora.nui.openMenu(items, title, opts)
    assertMenuItems(items, "openMenu")
    assertMenuGeometry(title, opts)
    -- timeout = false: these wait on a human, and timing out would reject a dialog still on screen. All are dismissable.
    return settleForExport(focusUntilSettled(requestPromise("openMenu", {
        title = title,
        items = items,
        position = opts and opts.position,
        maxWidth = opts and opts.maxWidth,
        maxHeight = opts and opts.maxHeight,
        canClose = opts and opts.canClose,
        startIndex = opts and opts.startIndex,
        presentation = opts and opts.presentation,
    }, false)))
end

---Opens a context menu anchored at (x, y) -- or centered, if omitted. Grants
---NUI focus while open and releases it when the menu closes.
---@param items table[] Same shape as openMenu's `items`; submenus are ignored because a context menu is one level only.
---@param x? number
---@param y? number
---@return promise|any result Resolves/returns `{ selectedId: string, path: string[] }` or `{ cancelled: true }`. See Kora.nui.request's return doc.
function Kora.nui.openContextMenu(items, x, y)
    assertMenuItems(items, "openContextMenu")
    assert(x == nil or isFiniteNumber(x), "openContextMenu x must be a finite number.")
    assert(y == nil or isFiniteNumber(y), "openContextMenu y must be a finite number.")
    -- No timeout, see openMenu.
    return settleForExport(focusUntilSettled(requestPromise("openContextMenu", { items = items, x = x, y = y }, false)))
end

---Opens a radial menu, always centred on screen. Items share openMenu's
---schema, including nested submenus; the NUI handles navigation and returns
---one MenuResult.
---@param items table[] Same shape as openMenu's `items`.
---@param opts? table `{ radius?: number }`
---@return promise|any result Resolves/returns `{ selectedId: string, path: string[] }` or `{ cancelled: true }`. See Kora.nui.request's return doc.
function Kora.nui.openRadialMenu(items, opts)
    assertMenuItems(items, "openRadialMenu")
    assert(opts == nil or type(opts) == "table", "openRadialMenu options must be a table.")

    opts = opts or {}
    assert(opts.radius == nil or (isFiniteNumber(opts.radius) and opts.radius > 0),
        "openRadialMenu radius must be a positive number.")

    -- No timeout, see openMenu.
    return settleForExport(focusUntilSettled(requestPromise("openRadialMenu", {
        items = items,
        radius = opts.radius,
    }, false)))
end

---Opens a confirmation dialog. Grants NUI focus while open and releases it
---when the dialog closes.
---@param opts table `{ message: string, title?: string, image?: string, confirmLabel?: string, cancelLabel?: string, cancellable?: boolean, destructive?: boolean }`
---@return promise|any result Resolves/returns `{ confirmed: boolean }` -- `confirmed = false` covers
---the cancel button, Escape and the backdrop alike. With `cancellable = false` there is no cancel
---button and neither Escape nor the backdrop dismisses it, so it can only resolve `true`.
---See Kora.nui.request's return doc for the promise-vs-value distinction.
function Kora.nui.openAlert(opts)
    assert(type(opts) == "table", "openAlert requires an options table.")
    assert(type(opts.message) == "string" and #opts.message > 0, "openAlert requires a message string.")
    for i = 1, #ALERT_STRING_FIELDS do
        local field = ALERT_STRING_FIELDS[i]
        assert(opts[field] == nil or type(opts[field]) == "string",
            ("openAlert %s must be a string."):format(field))
    end
    for i = 1, #ALERT_BOOLEAN_FIELDS do
        local field = ALERT_BOOLEAN_FIELDS[i]
        assert(opts[field] == nil or type(opts[field]) == "boolean",
            ("openAlert %s must be a boolean."):format(field))
    end
    assert(opts.size == nil or opts.size == "xs" or opts.size == "sm" or opts.size == "md"
        or opts.size == "lg" or opts.size == "xl", "openAlert size is invalid.")

    -- No timeout, see openMenu; a non-cancellable alert must not time out while still on screen.
    return settleForExport(focusUntilSettled(requestPromise("openAlert", opts, false)))
end

---Opens a schema-driven input form. Grants NUI focus while open and releases
---it when the dialog closes (submit or cancel).
---@param fields table[] QBInputField[] -- see modules/nui/docs.md for the full shared field contract.
---@param title? string
---@param description? string
---@return promise|any result Resolves/returns `{ values: table<string, any> }` or `{ cancelled: true }`. See Kora.nui.request's return doc.
function Kora.nui.openInputDialog(fields, title, description)
    assertInputFields(fields, "openInputDialog")
    assert(title == nil or type(title) == "string", "openInputDialog title must be a string.")
    assert(description == nil or type(description) == "string", "openInputDialog description must be a string.")
    -- No timeout, see openMenu.
    return settleForExport(focusUntilSettled(requestPromise("openInputDialog", {
        title = title,
        description = description,
        fields = fields,
        labels = appLabels(),
    }, false)))
end

-- App registrations are owner-tracked; if the consumer stops mid-open, settle the request (releasing focus) then remove the definition.
local function applyAppAccent(registration)
    -- Go through the theme bridge so an app without an accent keeps the player's saved /theme preference.
    QBTheme.apply(registration and registration.browser.accent or nil)
end

appOwnership = Kora.resources.registry(function(id)
    local current = activeApp
    if current and current.id == id then
        Kora.nui.send("closeApp", {
            appId = id,
            token = current.token,
            reason = "resourceStop",
        })
        settlePendingRequest(current.promise, true, { closed = true, reason = "resourceStop" })
    end
    registeredApps[id] = nil
end)

-- Human-driven requests have no timeout; if the owning resource stops, reject the promise and unmount the surface so its lease is released.
requestOwnership = Kora.resources.registry(function(requestId)
    local pending = pendingRequests[requestId]
    if not pending then return end

    pendingRequests[requestId] = nil
    Kora.nui.send("cancelNuiRequest", { requestId = requestId, token = pending.token })
    pending.promise:reject("The resource that opened this NUI request stopped.")
end)

-- withFocus also wraps multi-step operations; owner tracking stops an abandoned coroutine leaving a stale lease.
focusOwnership = Kora.resources.registry(function(id)
    if not focusLeases[id] then return end
    focusLeases[id] = nil
    refreshFocus()
end)

---Registers a declarative full-screen application shell. The definition owns
---navigation, tabs, standard content blocks, and an optional Lua action
---handler. Registrations are automatically removed when their owner stops.
---@param definition table QBAppDefinition
---@return string id
function Kora.nui.registerApp(definition)
    assert(type(definition) == "table", "registerApp requires a definition table.")
    assert(definition.onAction == nil or isCallable(definition.onAction), "App onAction must be callable.")
    assert(definition.onChange == nil or isCallable(definition.onChange), "App onChange must be callable.")

    local publicDefinition = browserApp(definition)
    local actionIds = assertBrowserApp(publicDefinition)

    local owner = GetInvokingResource() or GetCurrentResourceName()
    local previousOwner = appOwnership.owner(definition.id)
    assert(not previousOwner or previousOwner == owner,
        ("App '%s' is owned by resource '%s'."):format(definition.id, previousOwner))

    registeredApps[definition.id] = {
        browser = publicDefinition,
        actionIds = actionIds,
        onAction = definition.onAction,
        onChange = definition.onChange,
        owner = owner,
    }
    appOwnership.track(owner, definition.id)

    local current = activeApp
    if current and current.id == definition.id then
        applyAppAccent(registeredApps[definition.id])
        Kora.nui.send("updateApp", {
            appId = definition.id,
            token = current.token,
            app = publicDefinition,
        })
    end
    return definition.id
end

---Unregisters an application. An open instance is closed before its
---definition is removed so the awaiting openApp call and NUI focus settle.
---@param id string
---@return boolean removed
function Kora.nui.unregisterApp(id)
    assertAppId(id)
    local registration = registeredApps[id]
    if not registration then return false end

    local invoker = GetInvokingResource()
    assert(not invoker or invoker == registration.owner,
        ("App '%s' is owned by resource '%s'."):format(id, registration.owner))

    local current = activeApp
    if current and current.id == id then
        Kora.nui.send("closeApp", { appId = id, token = current.token, reason = "unregister" })
        settlePendingRequest(current.promise, true, { closed = true, reason = "unregister" })
    end

    registeredApps[id] = nil
    appOwnership.untrack(id)
    return true
end

---Opens a registered application and holds mouse/keyboard focus until the
---player closes it. Only one registered app shell can be active at a time;
---opening another supersedes the current one through useNuiRequest.
---@param id string
---@param opts? table `{ data?: any, viewId?: string, tabId?: string }`
---@return promise|any result `{ closed: true, reason: string, viewId?: string, tabId?: string }`
function Kora.nui.openApp(id, opts)
    assertAppId(id)
    assert(opts == nil or type(opts) == "table", "openApp options must be a table.")
    assert(opts == nil or opts.viewId == nil or type(opts.viewId) == 'string', 'openApp viewId must be a string.')
    assert(opts == nil or opts.tabId == nil or type(opts.tabId) == 'string', 'openApp tabId must be a string.')

    local registration = registeredApps[id]
    assert(registration, ("App '%s' is not registered."):format(id))

    -- Settle the old app before granting focus, or its late focus-release could strip the new app's input.
    if activeApp then
        local previous = activeApp
        -- Replacing an app is normal flow; resolve the old caller as closed rather than rejecting its export call.
        settlePendingRequest(previous.promise, true, { closed = true, reason = "superseded" })
    end

    opts = opts or {}
    applyAppAccent(registration)
    local p = requestPromise("openApp", {
        app = registration.browser,
        data = opts.data,
        viewId = opts.viewId,
        tabId = opts.tabId,
    }, false)

    local instance = {
        id = id,
        token = p.koraLibNuiToken,
        promise = p,
        data = opts.data,
    }
    activeApp = instance

    local function clear()
        if activeApp ~= instance then return end
        activeApp = nil
        applyAppAccent(nil)
    end
    p:next(clear, clear)

    return settleForExport(focusUntilSettled(p))
end

---Replaces fields on a registered app definition. Navigation is replaced as
---a whole when supplied; active instances receive the updated definition
---immediately without losing their selected view/tab when those still exist.
---@param id string
---@param update table Partial QBAppDefinition (id/onAction/onChange excluded).
---@return boolean updated
function Kora.nui.updateApp(id, update)
    assertAppId(id)
    local registration = registeredApps[id]
    if not registration then return false end

    local invoker = GetInvokingResource()
    assert(not invoker or invoker == registration.owner,
        ("App '%s' is owned by resource '%s'."):format(id, registration.owner))

    mergeAppUpdate(registration, update)

    local current = activeApp
    if current and current.id == id then
        applyAppAccent(registration)
        Kora.nui.send("updateApp", {
            appId = id,
            token = current.token,
            app = registration.browser,
        })
    end

    return true
end

---Closes the active app shell. The browser response settles openApp and the
---normal focus-until-settled path releases NUI focus.
---@param id? string Omit to close whichever registered app is active.
---@return boolean closing
function Kora.nui.closeApp(id)
    if id ~= nil then assertAppId(id) end
    local current = activeApp
    if not current or (id and current.id ~= id) then return false end

    local registration = registeredApps[current.id]
    local invoker = GetInvokingResource()
    assert(not invoker or (registration and invoker == registration.owner),
        ("App '%s' is owned by resource '%s'."):format(current.id, registration and registration.owner or "unknown"))

    Kora.nui.send("closeApp", {
        appId = current.id,
        token = current.token,
        reason = "api",
    })
    return true
end

---@param id? string
---@return boolean open
function Kora.nui.isAppOpen(id)
    if id ~= nil then assertAppId(id) end
    return activeApp ~= nil and (id == nil or activeApp.id == id)
end

-- Form edits don't submit, close or take focus; yielding handlers must not overwrite newer edits.
Kora.nui.registerCallback("kora_lib:app:change", function(data)
    local current = activeApp
    if not current or type(data) ~= "table" then
        return { ok = false, error = "No app is open." }
    end
    if data.appId ~= current.id or type(data.token) ~= "string" or data.token ~= current.token then
        return { ok = false, error = "Invalid app session." }
    end
    local registration = registeredApps[current.id]
    local declared = type(data.actionId) == "string" and registration and registration.actionIds[data.actionId]
    if not declared or not declared.form or type(data.value) ~= "table" then
        return { ok = false, error = "Invalid app form change." }
    end
    if not registration.onChange then
        return { ok = false, error = "This app has no change handler." }
    end

    current.changeVersion = (current.changeVersion or 0) + 1
    local version = current.changeVersion
    local ok, update = pcall(registration.onChange, data.actionId, {
        appId = current.id, viewId = data.viewId, tabId = data.tabId,
        itemId = data.itemId, value = data.value, data = current.data,
    })
    if not ok then
        print(("[kora_lib:nui] app '%s' change '%s' errored: %s"):format(current.id, data.actionId, tostring(update)))
        return { ok = false, error = "The app change failed." }
    end
    if activeApp ~= current or registeredApps[current.id] ~= registration or current.changeVersion ~= version then
        return { ok = true }
    end
    if update == nil then return { ok = true } end

    local updated, err = pcall(mergeAppUpdate, registration, update)
    if not updated then
        print(("[kora_lib:nui] app '%s' change '%s' returned an invalid update: %s"):format(current.id, data.actionId, tostring(err)))
        return { ok = false, error = "The app returned an invalid update." }
    end
    applyAppAccent(registration)
    return { ok = true, result = { app = registration.browser } }
end)

local function notifyClosedAppError(message)
    if Kora.notify and Kora.notify.send then Kora.notify.send({ type = "error", message = message }) end
end

local function validateActionResult(registration, result)
    if result == nil then return {} end
    assert(type(result) == "table", "App action results must be a table.")
    assert(result.close == nil or type(result.close) == "boolean", "App action result close must be a boolean.")

    if result.navigate ~= nil then
        assert(type(result.navigate) == "table" and type(result.navigate.viewId) == "string",
            "App action result navigate requires a viewId.")
        local view
        for candidateIndex = 1, #registration.browser.navigation do
            local candidate = registration.browser.navigation[candidateIndex]
            if candidate.id == result.navigate.viewId and not candidate.disabled then view = candidate break end
        end
        assert(view, "App action result navigate references an unknown or disabled view.")
        if result.navigate.tabId ~= nil then
            local found = false
            local tabs = view.tabs or {}
            for tabIndex = 1, #tabs do
                local tab = tabs[tabIndex]
                if tab.id == result.navigate.tabId then found = true break end
            end
            assert(found, "App action result navigate references an unknown tab.")
        end
        assert(result.navigate.replace == nil or type(result.navigate.replace) == "boolean",
            "App action result navigate replace must be a boolean.")
    end

    if result.notice ~= nil then
        assert(type(result.notice) == "table" and VALID_TONES[result.notice.tone]
            and type(result.notice.message) == "string" and result.notice.message ~= "",
            "App action result notice requires a valid tone and message.")
    end

    return result
end

-- Token-validated route for AppShell actions; the per-open token stops another NUI page invoking privileged handlers by guessing an id.
Kora.nui.registerCallback("kora_lib:app:action", function(data)
    local current = activeApp
    if not current or type(data) ~= "table" then
        return { ok = false, error = "No app is open." }
    end
    if data.appId ~= current.id or type(data.token) ~= "string" or data.token ~= current.token then
        return { ok = false, error = "Invalid app session." }
    end
    if type(data.actionId) ~= "string" or data.actionId == "" then
        return { ok = false, error = "Invalid app action." }
    end

    local registration = registeredApps[current.id]
    if not registration or not registration.onAction then
        return { ok = false, error = "This app has no action handler." }
    end
    local declared = registration.actionIds[data.actionId]
    if not declared then
        return { ok = false, error = "This action is not declared by the active app." }
    end
    current.changeVersion = (current.changeVersion or 0) + 1

    -- Settle the shell first so its focus lease is gone before the handler starts a focused UI.
    if declared.closeBeforeAction then
        Kora.nui.send("closeApp", {
            appId = current.id,
            token = current.token,
            reason = "action",
        })
        settlePendingRequest(current.promise, true, {
            closed = true,
            reason = "action",
            viewId = data.viewId,
            tabId = data.tabId,
        })
    end

    local ok, result = pcall(registration.onAction, data.actionId, {
        appId = current.id,
        viewId = data.viewId,
        tabId = data.tabId,
        itemId = data.itemId,
        value = data.value,
        data = current.data,
    })
    if not ok then
        print(("[kora_lib:nui] app '%s' action '%s' errored: %s")
            :format(current.id, data.actionId, tostring(result)))
        if declared.closeBeforeAction then notifyClosedAppError("The app action failed.") end
        return { ok = false, error = "The app action failed." }
    end

    if result == nil then result = {} end
    if type(result) ~= "table" then
        if declared.closeBeforeAction then notifyClosedAppError("The app returned an invalid result.") end
        return { ok = false, error = "The app returned an invalid result." }
    end

    local previousBrowser, previousActionIds = registration.browser, registration.actionIds
    if result.update ~= nil then
        local updateOk, updateError = pcall(mergeAppUpdate, registration, result.update)
        if not updateOk then
            print(("[kora_lib:nui] app '%s' action '%s' returned an invalid update: %s")
                :format(current.id, data.actionId, tostring(updateError)))
            if declared.closeBeforeAction then notifyClosedAppError("The app returned an invalid update.") end
            return { ok = false, error = "The app returned an invalid update." }
        end
    end

    local resultOk, validated = pcall(validateActionResult, registration, result)
    if not resultOk then
        registration.browser, registration.actionIds = previousBrowser, previousActionIds
        print(("[kora_lib:nui] app '%s' action '%s' returned an invalid result: %s")
            :format(current.id, data.actionId, tostring(validated)))
        if declared.closeBeforeAction then notifyClosedAppError("The app returned an invalid result.") end
        return { ok = false, error = "The app returned an invalid result." }
    end
    result = validated

    if result.update ~= nil then
        applyAppAccent(registration)
        result.app = registration.browser
        result.update = nil
    end

    if (declared.closeBeforeAction or result.close) and result.notice and Kora.notify and Kora.notify.send then
        local notifyType = result.notice.tone
        if notifyType == "destructive" then notifyType = "error" end
        if notifyType == "primary" or notifyType == "neutral" then notifyType = "info" end
        Kora.notify.send({
            type = notifyType,
            message = result.notice.message,
        })
    end

    return { ok = true, result = result }
end)
