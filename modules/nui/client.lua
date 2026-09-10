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

local function nextId()
    nextRequestId = nextRequestId + 1
    return nextRequestId
end

-- Per-request secret the NUI must echo back in its response. FiveM's NUI
-- callback routing (the `https://<resource>/<callback>` fetch every NUI page
-- uses) isn't scoped to the frame that issued a given request -- any other
-- installed resource's own NUI page could in principle POST a response to
-- "qblib:nui:response" for a guessable sequential requestId. A random token,
-- known only to this client and echoed back only by the legitimate response,
-- closes that gap the same way local/callback's per-player token does for the
-- client<->server boundary.
--
local generateToken = QB.compat.generateToken

-- FXServer represents a function passed through an exports boundary as a
-- callable table rather than a plain Lua function. App action handlers are
-- registered by consumer resources, so accept both shapes.
local isCallable = QB.compat.isCallable

local function assertAppId(id)
    assert(type(id) == "string" and id ~= "" and id:match("^[%w_:%.%-]+$"),
        "App id must be a non-empty namespaced string without whitespace.")
end

-- Handlers belong in Lua and cannot be JSON-encoded into SendNUIMessage. Keep
-- the callable in the private registry and copy only the browser definition.
local function appLabels()
    local fallbacks = {
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
    local translate = function(key)
        if QB.locale and QB.locale.translate then return QB.locale.translate('qblib', 'app.' .. key) end
        return fallbacks[key]
    end
    return {
        cancel = translate('cancel'), confirm = translate('confirm'), working = translate('working'),
        runAction = translate('run_action'), search = translate('search'), previous = translate('previous'),
        next = translate('next'), noRecords = translate('no_records'), nothingHere = translate('nothing_here'),
        emptyTitle = translate('empty_title'), emptyDescription = translate('empty_description'),
        close = translate('close'), select = translate('select'), required = translate('required'),
        invalidFormat = translate('invalid_format'), minValue = translate('min_value'),
        maxValue = translate('max_value'), minLength = translate('min_length'),
        maxLength = translate('max_length'), page = translate('page'), recenter = translate('recenter'),
        clear = translate('clear'), backspace = translate('backspace'),
        back = translate('back'), open = translate('open'), yes = translate('yes'), no = translate('no'),
        map = translate('map'), zoomIn = translate('zoom_in'), zoomOut = translate('zoom_out'), value = translate('value'),
        decrease = translate('decrease'), increase = translate('increase'),
    }
end

local function browserApp(definition)
    local result = {}
    for key, value in pairs(definition) do
        if key ~= "onAction" and key ~= "labels" then result[key] = value end
    end
    result.labels = appLabels()
    return result
end

local validFieldTypes = {
    text = true, password = true, textarea = true, number = true, checkbox = true,
    select = true, multiselect = true, range = true, combobox = true,
    date = true, ['date-range'] = true, time = true, color = true,
}

local validTones = { neutral = true, primary = true, success = true, warning = true, destructive = true }
local validActionVariants = { primary = true, secondary = true, outline = true, ghost = true, destructive = true }

local function assertPositiveInteger(value, message)
    assert(type(value) == "number" and value > 0 and value % 1 == 0, message)
end

local function assertOptions(options, location)
    assert(type(options) == "table", location .. " must be a table.")
    local values = {}
    for index, option in ipairs(options) do
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
    for index, item in ipairs(items) do
        local itemLocation = ("%s metadata item %d"):format(location, index)
        assert(type(item) == "table" and type(item.label) == "string" and item.label ~= "",
            itemLocation .. " requires a label.")
        assert(type(item.value) == "string" or type(item.value) == "number" or type(item.value) == "boolean",
            itemLocation .. " requires a scalar value.")
        assert(item.tone == nil or validTones[item.tone], itemLocation .. " has an invalid tone.")
    end
end

local function assertCollectionOptions(block, location)
    assert(block.searchable == nil or type(block.searchable) == "boolean", location .. " searchable must be a boolean.")
    assert(block.searchPlaceholder == nil or type(block.searchPlaceholder) == "string", location .. " searchPlaceholder must be a string.")
    if block.pageSize ~= nil then assertPositiveInteger(block.pageSize, location .. " pageSize must be a positive integer.") end
end

local function assertPoint(point, location)
    assert(type(point) == "table" and type(point.x) == "number" and type(point.y) == "number",
        location .. " requires numeric x and y values.")
end

local function assertInputFields(fields, location)
    assert(type(fields) == "table", ("%s fields must be a table."):format(location))
    local ids = {}
    for index, field in ipairs(fields) do
        local fieldLocation = ("%s field %d"):format(location, index)
        assert(type(field) == "table", fieldLocation .. " must be a table.")
        assert(type(field.id) == "string" and field.id ~= "", fieldLocation .. " requires an id.")
        assert(not ids[field.id], ("%s field id '%s' is duplicated."):format(location, field.id))
        assert(type(field.label) == "string" and field.label ~= "", fieldLocation .. " requires a label.")
        assert(validFieldTypes[field.type], fieldLocation .. " has an invalid type.")
        assert(field.description == nil or type(field.description) == "string", fieldLocation .. " description must be a string.")
        assert(field.required == nil or type(field.required) == "boolean", fieldLocation .. " required must be a boolean.")
        assert(field.disabled == nil or type(field.disabled) == "boolean", fieldLocation .. " disabled must be a boolean.")
        assert(field.min == nil or type(field.min) == "number", fieldLocation .. " min must be a number.")
        assert(field.max == nil or type(field.max) == "number", fieldLocation .. " max must be a number.")
        assert(field.minLength == nil or (type(field.minLength) == "number" and field.minLength >= 0 and field.minLength % 1 == 0), fieldLocation .. " minLength must be a non-negative integer.")
        assert(field.maxLength == nil or (type(field.maxLength) == "number" and field.maxLength >= 0 and field.maxLength % 1 == 0), fieldLocation .. " maxLength must be a non-negative integer.")
        assert(field.min == nil or field.max == nil or field.min <= field.max, fieldLocation .. " min cannot exceed max.")
        assert(field.minLength == nil or field.maxLength == nil or field.minLength <= field.maxLength,
            fieldLocation .. " minLength cannot exceed maxLength.")
        assert(field.pattern == nil or type(field.pattern) == "string", fieldLocation .. " pattern must be a string.")
        assert(field.dateMin == nil or type(field.dateMin) == "string" or (type(field.dateMin) == "number"
            and field.dateMin == field.dateMin and field.dateMin ~= math.huge and field.dateMin ~= -math.huge),
            fieldLocation .. " dateMin must be a string or finite timestamp.")
        assert(field.dateMax == nil or type(field.dateMax) == "string" or (type(field.dateMax) == "number"
            and field.dateMax == field.dateMax and field.dateMax ~= math.huge and field.dateMax ~= -math.huge),
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
        assert(field.step == nil or (type(field.step) == "number" and field.step > 0), fieldLocation .. " step must be positive.")
        assert(field.dependsOn == nil or type(field.dependsOn) == "string", fieldLocation .. " dependsOn must be a string.")
        assert(field.optionsByValue == nil or type(field.optionsByValue) == "table", fieldLocation .. " optionsByValue must be a table.")
        assert(field.visibleWhen == nil or (type(field.visibleWhen) == "table"
            and type(field.visibleWhen.fieldId) == "string"
            and (type(field.visibleWhen.equals) == "string" or type(field.visibleWhen.equals) == "number"
                or type(field.visibleWhen.equals) == "boolean")),
            fieldLocation .. " visibleWhen must contain fieldId and equals.")
        assert(field.keypad == nil or type(field.keypad) == "boolean", fieldLocation .. " keypad must be a boolean.")
        assert(field.numericOnly == nil or type(field.numericOnly) == "boolean", fieldLocation .. " numericOnly must be a boolean.")
        if field.options ~= nil then assertOptions(field.options, fieldLocation .. " options") end
        if field.optionsByValue ~= nil then
            for key, options in pairs(field.optionsByValue) do
                assert(type(key) == "string" or type(key) == "number", fieldLocation .. " optionsByValue keys must be scalar values.")
                assertOptions(options, ("%s optionsByValue[%s]"):format(fieldLocation, tostring(key)))
            end
        end
        if field.presets ~= nil then
            assert(type(field.presets) == "table", fieldLocation .. " presets must be a table.")
            for presetIndex, preset in ipairs(field.presets) do
                assert(type(preset) == "table" and type(preset.value) == "number",
                    ("%s preset %d requires a numeric value."):format(fieldLocation, presetIndex))
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
                assert(type(field.default) == "number", fieldLocation .. " numeric default must be a number.")
            elseif field.type == "multiselect" or field.type == "date-range" then
                assert(type(field.default) == "table", fieldLocation .. " multiselect default must be an array.")
                for defaultIndex, value in ipairs(field.default) do
                    assert(type(value) == "string" or type(value) == "number",
                        ("%s default item %d must be a string or number."):format(fieldLocation, defaultIndex))
                end
            else
                assert(type(field.default) == "string" or type(field.default) == "number",
                    fieldLocation .. " default must be a string or number.")
            end
        end
        ids[field.id] = true
    end
    for index, field in ipairs(fields) do
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
    assert(action.variant == nil or validActionVariants[action.variant], ("%s action variant is invalid."):format(location))
    assert(action.disabled == nil or type(action.disabled) == "boolean", ("%s action disabled must be a boolean."):format(location))
    assert(action.confirm == nil or type(action.confirm) == "string", ("%s action confirm must be a string."):format(location))
    assert(action.closeBeforeAction == nil or type(action.closeBeforeAction) == "boolean", ("%s action closeBeforeAction must be a boolean."):format(location))
    declareAction(actionIds, action.id, action.closeBeforeAction, location)
end

local function assertListItems(items, location, actionIds)
    assert(type(items) == "table", location .. " requires an items table.")
    local ids = {}
    for index, item in ipairs(items) do
        local itemLocation = ("%s item %d"):format(location, index)
        assert(type(item) == "table" and type(item.id) == "string" and item.id ~= "", itemLocation .. " requires an id.")
        assert(not ids[item.id], ("%s item id '%s' is duplicated."):format(location, item.id))
        assert(type(item.label) == "string" and item.label ~= "", itemLocation .. " requires a label.")
        assert(item.description == nil or type(item.description) == "string", itemLocation .. " description must be a string.")
        assert(item.image == nil or type(item.image) == "string", itemLocation .. " image must be a string.")
        assert(item.tone == nil or validTones[item.tone], itemLocation .. " has an invalid tone.")
        if item.metadata ~= nil then assertMetadata(item.metadata, itemLocation) end
        if item.action ~= nil then
            if type(item.action) == "table" then assertAppAction(item.action, itemLocation, actionIds)
            else declareAction(actionIds, item.action, false, itemLocation) end
        end
        if item.actions ~= nil then
            assert(type(item.actions) == "table", itemLocation .. " actions must be a table.")
            for _, action in ipairs(item.actions) do assertAppAction(action, itemLocation, actionIds) end
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
        for _, action in ipairs(content.actions) do assertAppAction(action, location, actionIds) end
    end

    if content.blocks == nil then return end
    assert(type(content.blocks) == "table", ("%s blocks must be a table."):format(location))
    local blockTypes = { text = true, stats = true, progress = true, table = true, list = true, actions = true,
        form = true, details = true, timeline = true, map = true, empty = true }

    local blockIds = {}
    for index, block in ipairs(content.blocks) do
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
            for itemIndex, item in ipairs(block.items) do
                assert(type(item) == "table" and type(item.label) == "string" and item.label ~= ""
                    and (type(item.value) == "string" or type(item.value) == "number"),
                    ("%s item %d is invalid."):format(blockLocation, itemIndex))
                assert(item.description == nil or type(item.description) == "string",
                    ("%s item %d description must be a string."):format(blockLocation, itemIndex))
                assert(item.icon == nil or type(item.icon) == "string",
                    ("%s item %d icon must be a string."):format(blockLocation, itemIndex))
                assert(item.tone == nil or validTones[item.tone], ("%s item %d has an invalid tone."):format(blockLocation, itemIndex))
            end
        elseif block.type == "progress" then
            assert(type(block.items) == "table", blockLocation .. " requires an items table.")
            for itemIndex, item in ipairs(block.items) do
                assert(type(item) == "table" and type(item.label) == "string" and item.label ~= ""
                    and type(item.value) == "number" and type(item.max) == "number" and item.max > 0,
                    ("%s item %d requires a label, numeric value, and positive max."):format(blockLocation, itemIndex))
                assert(item.value >= 0 and item.value <= item.max,
                    ("%s item %d value must be between zero and max."):format(blockLocation, itemIndex))
                assert(item.description == nil or type(item.description) == "string",
                    ("%s item %d description must be a string."):format(blockLocation, itemIndex))
                assert(item.detail == nil or type(item.detail) == "string",
                    ("%s item %d detail must be a string."):format(blockLocation, itemIndex))
                assert(item.icon == nil or type(item.icon) == "string",
                    ("%s item %d icon must be a string."):format(blockLocation, itemIndex))
                assert(item.tone == nil or validTones[item.tone], ("%s item %d has an invalid tone."):format(blockLocation, itemIndex))
            end
        elseif block.type == "details" then
            assert(type(block.items) == "table", blockLocation .. " requires an items table.")
            assert(block.columns == nil or (type(block.columns) == "number" and block.columns >= 1 and block.columns <= 3 and block.columns % 1 == 0),
                blockLocation .. " columns must be an integer from 1 to 3.")
            for itemIndex, item in ipairs(block.items) do
                assert(type(item) == "table" and type(item.label) == "string" and item.label ~= "",
                    ("%s item %d requires a label."):format(blockLocation, itemIndex))
                assert(item.value == nil or type(item.value) == "string" or type(item.value) == "number" or type(item.value) == "boolean",
                    ("%s item %d value must be scalar."):format(blockLocation, itemIndex))
                assert(item.tone == nil or validTones[item.tone], ("%s item %d has an invalid tone."):format(blockLocation, itemIndex))
            end
        elseif block.type == "list" then
            assert(block.layout == nil or block.layout == "list" or block.layout == "grid" or block.layout == "cards",
                blockLocation .. " layout must be 'list', 'grid', or 'cards'.")
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
            for columnIndex, column in ipairs(block.columns) do
                local columnLocation = ("%s column %d"):format(blockLocation, columnIndex)
                assert(type(column) == "table" and type(column.key) == "string" and column.key ~= ""
                    and type(column.label) == "string" and column.label ~= "", columnLocation .. " is invalid.")
                assert(not columnKeys[column.key], ("%s column key '%s' is duplicated."):format(blockLocation, column.key))
                assert(column.align == nil or column.align == "left" or column.align == "center" or column.align == "right",
                    columnLocation .. " align is invalid.")
                assert(column.sortable == nil or type(column.sortable) == "boolean", columnLocation .. " sortable must be a boolean.")
                columnKeys[column.key] = true
            end
            for rowIndex, row in ipairs(block.rows) do assert(type(row) == "table", ("%s row %d must be a table."):format(blockLocation, rowIndex)) end
            assert(block.idKey == nil or type(block.idKey) == "string", blockLocation .. " idKey must be a string.")
            if block.action ~= nil then declareAction(actionIds, block.action, false, blockLocation) end
        elseif block.type == "actions" then
            assert(type(block.actions) == "table", blockLocation .. " requires an actions table.")
            for _, action in ipairs(block.actions) do assertAppAction(action, blockLocation, actionIds) end
        elseif block.type == "form" then
            assert(type(block.id) == "string" and block.id ~= "", blockLocation .. " requires an id.")
            assert(block.submitLabel == nil or type(block.submitLabel) == "string", blockLocation .. " submitLabel must be a string.")
            assertInputFields(block.fields, blockLocation)
            assertAppAction(block.action, blockLocation, actionIds)
        elseif block.type == "timeline" then
            assert(type(block.items) == "table", blockLocation .. " requires an items table.")
            assert(block.empty == nil or type(block.empty) == "string", blockLocation .. " empty must be a string.")
            local itemIds = {}
            for itemIndex, item in ipairs(block.items) do
                assert(type(item) == "table" and type(item.id) == "string" and item.id ~= ""
                    and type(item.title) == "string" and item.title ~= "",
                    ("%s item %d is invalid."):format(blockLocation, itemIndex))
                assert(not itemIds[item.id], ("%s item id '%s' is duplicated."):format(blockLocation, item.id))
                assert(item.description == nil or type(item.description) == "string",
                    ("%s item %d description must be a string."):format(blockLocation, itemIndex))
                assert(item.timestamp == nil or type(item.timestamp) == "string",
                    ("%s item %d timestamp must be a string."):format(blockLocation, itemIndex))
                assert(item.tone == nil or validTones[item.tone], ("%s item %d has an invalid tone."):format(blockLocation, itemIndex))
                if item.metadata ~= nil then assertMetadata(item.metadata, blockLocation .. " timeline") end
                if item.actions ~= nil then
                    assert(type(item.actions) == "table", blockLocation .. " timeline actions must be a table.")
                    for _, action in ipairs(item.actions) do assertAppAction(action, blockLocation, actionIds) end
                end
                itemIds[item.id] = true
            end
        elseif block.type == "map" then
            assert(type(block.tiles) == "table" and type(block.tiles.url) == "string" and block.tiles.url ~= "",
                blockLocation .. " requires a tile URL template.")
            assert(type(block.markers) == "table", blockLocation .. " requires a markers table.")
            assert(block.empty == nil or type(block.empty) == "string", blockLocation .. " empty must be a string.")
            assert(block.tiles.tileSize == nil or (type(block.tiles.tileSize) == "number" and block.tiles.tileSize > 0),
                blockLocation .. " tileSize must be positive.")
            assert(block.follow == nil or type(block.follow) == "boolean", blockLocation .. " follow must be a boolean.")
            assert(block.fadeDuration == nil or (type(block.fadeDuration) == "number" and block.fadeDuration >= 0),
                blockLocation .. " fadeDuration must be non-negative.")
            assert(block.minZoom == nil or type(block.minZoom) == "number", blockLocation .. " minZoom must be a number.")
            assert(block.maxZoom == nil or type(block.maxZoom) == "number", blockLocation .. " maxZoom must be a number.")
            assert(block.minZoom == nil or block.maxZoom == nil or block.minZoom <= block.maxZoom,
                blockLocation .. " minZoom cannot exceed maxZoom.")
            assert(block.initialZoom == nil or type(block.initialZoom) == "number", blockLocation .. " initialZoom must be a number.")
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
            assert(block.now == nil or type(block.now) == "number", blockLocation .. " now must be a number.")
            assert(block.selectedId == nil or type(block.selectedId) == "string", blockLocation .. " selectedId must be a string.")
            if block.action ~= nil then declareAction(actionIds, block.action, false, blockLocation) end
            local markerIds = {}
            for markerIndex, marker in ipairs(block.markers) do
                assert(type(marker) == "table" and type(marker.id) == "string" and marker.id ~= ""
                    and type(marker.x) == "number" and type(marker.y) == "number" and type(marker.label) == "string",
                    ("%s marker %d is invalid."):format(blockLocation, markerIndex))
                assert(not markerIds[marker.id], ("%s marker id '%s' is duplicated."):format(blockLocation, marker.id))
                assert(marker.description == nil or type(marker.description) == "string",
                    ("%s marker %d description must be a string."):format(blockLocation, markerIndex))
                assert(marker.heading == nil or type(marker.heading) == "number",
                    ("%s marker %d heading must be a number."):format(blockLocation, markerIndex))
                assert(marker.expiresAt == nil or type(marker.expiresAt) == "number",
                    ("%s marker %d expiresAt must be a number."):format(blockLocation, markerIndex))
                assert(marker.fadeDuration == nil or (type(marker.fadeDuration) == "number" and marker.fadeDuration >= 0),
                    ("%s marker %d fadeDuration must be non-negative."):format(blockLocation, markerIndex))
                assert(marker.tone == nil or validTones[marker.tone], ("%s marker %d has an invalid tone."):format(blockLocation, markerIndex))
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
    for viewIndex, view in ipairs(definition.navigation) do
        local location = ("App navigation item %d"):format(viewIndex)
        assert(type(view) == "table", location .. " must be a table.")
        assert(type(view.id) == "string" and view.id ~= "", location .. " requires an id.")
        assert(not viewIds[view.id], ("App navigation id '%s' is duplicated."):format(view.id))
        assert(type(view.label) == "string" and view.label ~= "", location .. " requires a label.")
        assert(view.disabled == nil or type(view.disabled) == "boolean", location .. " disabled must be a boolean.")
        viewIds[view.id] = true
        if not view.disabled then hasEnabledView = true end
        assertAppContent(view.content, ("App view '%s'"):format(view.id), actionIds)

        if view.tabs ~= nil then
            assert(type(view.tabs) == "table" and #view.tabs > 0,
                ("App view '%s' tabs must contain at least one tab."):format(view.id))
            local tabIds = {}
            for tabIndex, tab in ipairs(view.tabs) do
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
        assert(key ~= "labels", "App labels are owned by qblib's locale system.")
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
function QB.nui.send(action, data)
    -- SendNUIMessage (capital NUI) is the runtime wrapper that takes a table
    -- and json-encodes it; the similarly-named SendNuiMessage native takes a
    -- pre-encoded JSON *string* and would stringify a table into garbage.

    SendNUIMessage({ action = action, data = data })
end

---Sets NUI focus directly. Prefer `QB.nui.withFocus` when the caller can scope
---focus to a single operation -- this exists for the rarer case (e.g. a HUD
---that needs to hold focus across several unrelated calls) where that doesn't fit.
---@param mouse boolean
---@param keyboard boolean
function QB.nui.setFocus(mouse, keyboard)
    SetNuiFocus(mouse, keyboard)
end

-- Interactive surfaces take leases instead of independently toggling the
-- global NUI focus native. Closing a child dialog therefore reveals the app
-- beneath it without stealing that app's mouse and keyboard input.
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
---The returned release function is intended to stay inside qblib; ordinary
---resources should use withFocus or an open* helper.
---@param mouse boolean
---@param keyboard boolean
---@param keepInput? boolean
---@param owner? string
---@return function release
function QB.nui.acquireFocus(mouse, keyboard, keepInput, owner)
    assert(type(mouse) == 'boolean' and type(keyboard) == 'boolean', 'acquireFocus requires boolean mouse and keyboard values.')
    assert(keepInput == nil or type(keepInput) == 'boolean', 'acquireFocus keepInput must be a boolean.')
    assert(owner == nil or (type(owner) == 'string' and owner ~= ''), 'acquireFocus owner must be a non-empty string.')
    return acquireFocus(mouse, keyboard, owner, keepInput)
end

---Releases a lease returned by QB.nui.acquireFocus.
---@param release function
function QB.nui.releaseFocus(release)
    assert(isCallable(release), 'releaseFocus requires a focus release function.')
    release()
end

---Runs `fn` with NUI focus set, guaranteeing focus is released afterward even
---if `fn` errors -- the headless-UI rule (AGENTS.md) is that focus never
---outlives the interaction that requested it, and this is the one place that
---guarantee is enforced instead of every caller hand-rolling it.
---@param mouse boolean
---@param keyboard boolean
---@param fn fun(): any
---@param owner? string Internal owner override for qblib modules whose operation continues in a new coroutine.
---@return any
function QB.nui.withFocus(mouse, keyboard, fn, owner)
    local release = acquireFocus(mouse, keyboard, owner)

    local ok, result = pcall(fn)

    release()

    if not ok then error(result, 0) end

    return result
end

---Registers an NUI callback, wrapping RegisterNUICallback's raw `(data, cb)`
---signature so handlers just return a value (or nil) like a normal function.
---A handler that errors is logged and responds with an empty table rather than
---leaving the NUI's fetch promise hanging.
---@param name string
---@param handler fun(data: any): any
function QB.nui.registerCallback(name, handler)
    RegisterNUICallback(name, function(data, cb)
        local ok, result = pcall(handler, data)

        if not ok then
            print(("[qblib:nui] callback '%s' errored: %s"):format(name, tostring(result)))
            cb({})
            return
        end

        cb(result == nil and {} or result)
    end)
end

---The single shared response channel every `QB.nui.request` call resolves
---through, keyed by requestId -- one registered callback rather than a
---dynamically-named one per request. `data.token` must match the token this
---request was issued with (see generateToken above); a mismatched or missing
---token is silently ignored rather than resolving/rejecting anything.
QB.nui.registerCallback("qblib:nui:response", function(data)
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

-- Interactive request surfaces can report non-terminal changes (for example,
-- an ox_lib menu changing its selected row, checkbox, or side-scroll value)
-- without resolving the request. The same per-request token used by the final
-- response authenticates these messages.
QB.nui.registerCallback("qblib:nui:event", function(data)
    local pending = pendingRequests[data.requestId]
    if not pending or type(data.token) ~= "string" or data.token ~= pending.token then return {} end
    if not pending.onEvent then return {} end

    local ok, err = pcall(pending.onEvent, data.event, data.data)
    if not ok then
        print(("[qblib:nui] request event '%s' errored: %s"):format(tostring(data.event), tostring(err)))
    end
    return {}
end)

-- A promise object doesn't survive crossing a real cross-resource exports()
-- call back to the caller: only METHOD CALLS on it (:next(), used below)
-- reach the real promise inside qblib, while plain field reads (.state,
-- .value -- what Citizen.Await itself checks) on the crossed reference never
-- reflect the real remote promise's settlement, so the caller's own
-- Citizen.Await silently resolves nil regardless of the real outcome.
-- GetInvokingResource() is nil for a same-VM call (qblib's own modules,
-- every dofile()'d smoke test) and the real calling resource's name for a
-- genuine cross-resource exports() call (same signal modules/zones already
-- relies on for ownership tracking -- see its AGENTS.md's "Resource
-- ownership" note) -- exactly the distinction that matters here. Same-VM
-- callers get the real promise back unchanged, so `Citizen.Await(QB.nui.X(...))`
-- keeps working exactly as before for internal callers and every smoke test.
-- A genuine cross-resource caller gets the already-awaited plain value (or a
-- raised error on rejection/timeout, which -- like every other qblib error --
-- surfaces to that caller as a printed export-call error and a nil return,
-- not a catchable Lua error) instead of a promise it can't usefully await.
-- Deliberately duplicated per-file -- see local/callback/{client,server}.lua
-- and modules/zones/client.lua for the other copies.
local function settleForExport(p)
    if GetInvokingResource() then
        return Citizen.Await(p)
    end
    return p
end

---Sends `action` to the NUI and returns a promise that resolves with whatever
---the NUI eventually posts back to the shared `qblib:nui:response` callback
---for this request's id (carrying the matching token). This is the core
---primitive menus, input dialogs, and `QB.nui.copyToClipboard` are all built on.
---@param action string
---@param data any
---@param timeout? integer | false Milliseconds before the promise rejects. Defaults to 30000; pass false to disable.
---@param owner? string Internal owner override for qblib operations that continue in a new coroutine.
---@return promise promise
local function requestPromise(action, data, timeout, owner, onEvent)
    local requestId = nextId()
    local token = generateToken()
    local p = promise.new()
    owner = owner or GetInvokingResource() or GetCurrentResourceName()
    -- Private metadata used by the long-lived app shell callbacks. Keeping it
    -- on the local promise avoids changing the public wire envelope or return
    -- value of QB.nui.request.
    p.qblibNuiRequestId = requestId
    p.qblibNuiToken = token
    p.qblibNuiOwner = owner
    pendingRequests[requestId] = { promise = p, token = token, onEvent = onEvent }
    requestOwnership.track(owner, requestId)

    QB.nui.send(action, { requestId = requestId, token = token, payload = data })

    if timeout ~= false then
        timeout = timeout or 30000

        -- A one-shot native timer rather than a CreateThread+Wait coroutine --
        -- this timeout almost never actually fires (the response callback
        -- above settles it first), so it shouldn't cost a whole thread per
        -- request. Same idiom local/callback/server.lua already uses for the
        -- same "cheap deadline that's usually beaten by a real response" shape.
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

-- Settles one known local request without waiting for a browser round trip.
-- App-owner shutdown and app supersession use this after telling the browser
-- to hide: focus must be released immediately even if the frame disappears
-- before it gets a chance to answer normally.
local function settlePendingRequest(p, ok, value)
    local requestId = p and p.qblibNuiRequestId
    local pending = requestId and pendingRequests[requestId]
    if not pending or pending.promise ~= p then return false end

    pendingRequests[requestId] = nil
    requestOwnership.untrack(requestId)
    if ok then p:resolve(value) else p:reject(value) end
    return true
end

---Public wrapper over the same primitive above, for callers sending a custom
---NUI action qblib doesn't have a dedicated wrapper for.
---@param action string
---@param data any
---@param timeout? integer | false
---@param owner? string Internal owner override for qblib operations that continue in a new coroutine.
---@return promise|any result A promise for a same-VM caller (unchanged, awaitable as before); the
---already-settled result value directly for a genuine cross-resource caller (see settleForExport above).
function QB.nui.request(action, data, timeout, owner)
    return settleForExport(requestPromise(action, data, timeout, owner))
end

local focusUntilSettled

---Starts a request without awaiting it across an enclosing export call.
---This is an internal composition primitive for qblib modules that need to
---retain a cancellable request handle while preserving the original consumer
---as owner. Ordinary resources should use QB.nui.request/open* instead.
---@param action string
---@param data any
---@param timeout? integer | false
---@param owner? string
---@param focused? boolean
---@param onEvent? fun(event: string, data: any) Internal handler for authenticated, non-terminal browser events.
---@return promise request
function QB.nui.requestAsync(action, data, timeout, owner, focused, onEvent)
    assert(type(action) == 'string' and action ~= '', 'requestAsync action must be a non-empty string.')
    assert(owner == nil or (type(owner) == 'string' and owner ~= ''), 'requestAsync owner must be a non-empty string.')
    assert(focused == nil or type(focused) == 'boolean', 'requestAsync focused must be a boolean.')
    assert(onEvent == nil or isCallable(onEvent), 'requestAsync onEvent must be callable.')

    local request = requestPromise(action, data, timeout, owner, onEvent)
    return focused and focusUntilSettled(request) or request
end

-- Grants mouse+keyboard focus for the lifetime of an interactive request and
-- releases it the moment the promise settles -- answered, cancelled, or timed
-- out (the request timeout doubles as the guarantee focus can't get stuck).
-- This is what makes the open* wrappers below actually clickable/typable
-- in-game; without focus the NUI renders but can never receive input.
function focusUntilSettled(p)
    local release = acquireFocus(true, true, p.qblibNuiOwner)
    p:next(release, release)

    return p
end

---Settles and dismisses a request created by QB.nui.requestAsync. The token is
---sent to the browser before the local promise is settled, so the component
---cannot answer the abandoned request afterward.
---@param request promise
---@param result? any
---@param rejection? string
---@return boolean cancelled
function QB.nui.cancelRequest(request, result, rejection)
    assert(type(request) == 'table', 'cancelRequest requires a qblib NUI request.')
    assert(rejection == nil or type(rejection) == 'string', 'cancelRequest rejection must be a string.')

    local requestId = request.qblibNuiRequestId
    local token = request.qblibNuiToken
    local pending = requestId and pendingRequests[requestId]
    if not pending or pending.promise ~= request then return false end

    QB.nui.send('cancelNuiRequest', { requestId = requestId, token = token })
    return settlePendingRequest(request, rejection == nil, rejection or result)
end

---Updates a still-pending request surface without replacing its promise or
---focus lease. Compatibility providers use this for live registry refreshes.
---@param request promise
---@param action string
---@param data any
---@return boolean updated
function QB.nui.updateRequest(request, action, data)
    assert(type(request) == 'table', 'updateRequest requires a qblib NUI request.')
    assert(type(action) == 'string' and action ~= '', 'updateRequest action must be a non-empty string.')
    local requestId = request.qblibNuiRequestId
    local pending = requestId and pendingRequests[requestId]
    if not pending or pending.promise ~= request then return false end

    QB.nui.send(action, { requestId = requestId, token = request.qblibNuiToken, payload = data })
    return true
end

---Copies `text` to the system clipboard via the NUI (the only place with
---access to a real clipboard API). Never takes focus -- the operation is
---invisible.
---@param text string
---@return promise|any result See QB.nui.request's return doc.
function QB.nui.copyToClipboard(text)
    assert(type(text) == "string", "copyToClipboard requires a string.")
    return settleForExport(requestPromise("copyToClipboard", { text = text }))
end

local function isFiniteNumber(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

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

    for index, item in ipairs(items) do
        assert(type(item) == "table", ("%s item %d must be a table."):format(context, index))
        assert(type(item.id) == "string" and item.id ~= "",
            ("%s item %d requires a non-empty string id."):format(context, index))
        assert(type(item.label) == "string" and item.label ~= "",
            ("%s item %d requires a non-empty string label."):format(context, index))
        for _, field in ipairs({ "description", "icon", "image" }) do
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
            for valueIndex, value in ipairs(item.values) do
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

    for _, field in ipairs({ "maxWidth", "maxHeight" }) do
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
        for _, field in ipairs({ "offsetX", "offsetY" }) do
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
---@return promise|any result Resolves/returns `{ selectedId: string, path: string[] }` or `{ cancelled: true }`. See QB.nui.request's return doc.
function QB.nui.openMenu(items, title, opts)
    assertMenuItems(items, "openMenu")
    assertMenuGeometry(title, opts)
    -- timeout = false: these three wait on a HUMAN, and there's no sensible
    -- deadline for "how long until they pick something" -- a player can open a
    -- dialog, get shot at, and come back to it. A timeout here doesn't fail
    -- safe either: it rejects a dialog that's still on screen, so the player
    -- goes on to answer a request nothing is listening for any more. They're
    -- all dismissable (Escape/backdrop/Cancel), so cancelling is always
    -- available as the way out -- see modules/nui/docs.md.
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
---@return promise|any result Resolves/returns `{ selectedId: string, path: string[] }` or `{ cancelled: true }`. See QB.nui.request's return doc.
function QB.nui.openContextMenu(items, x, y)
    assertMenuItems(items, "openContextMenu")
    assert(x == nil or isFiniteNumber(x), "openContextMenu x must be a finite number.")
    assert(y == nil or isFiniteNumber(y), "openContextMenu y must be a finite number.")
    -- No timeout, same reasoning as openMenu above.
    return settleForExport(focusUntilSettled(requestPromise("openContextMenu", { items = items, x = x, y = y }, false)))
end

---Opens a radial menu, always centred on screen. Items share openMenu's
---schema, including nested submenus; the NUI handles navigation and returns
---one MenuResult.
---@param items table[] Same shape as openMenu's `items`.
---@param opts? table `{ radius?: number }`
---@return promise|any result Resolves/returns `{ selectedId: string, path: string[] }` or `{ cancelled: true }`. See QB.nui.request's return doc.
function QB.nui.openRadialMenu(items, opts)
    assertMenuItems(items, "openRadialMenu")
    assert(opts == nil or type(opts) == "table", "openRadialMenu options must be a table.")

    opts = opts or {}
    assert(opts.radius == nil or (isFiniteNumber(opts.radius) and opts.radius > 0),
        "openRadialMenu radius must be a positive number.")

    -- No timeout, same reasoning as openMenu: a human owns dismissal, and
    -- timing out would leave a still-visible radial with no awaiting caller.
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
---See QB.nui.request's return doc for the promise-vs-value distinction.
function QB.nui.openAlert(opts)
    assert(type(opts) == "table", "openAlert requires an options table.")
    assert(type(opts.message) == "string" and #opts.message > 0, "openAlert requires a message string.")
    for _, field in ipairs({ "title", "image", "confirmLabel", "cancelLabel" }) do
        assert(opts[field] == nil or type(opts[field]) == "string",
            ("openAlert %s must be a string."):format(field))
    end
    for _, field in ipairs({ "cancellable", "showCancel", "showClose", "dismissOnBackdrop", "destructive", "centered", "overflow" }) do
        assert(opts[field] == nil or type(opts[field]) == "boolean",
            ("openAlert %s must be a boolean."):format(field))
    end
    assert(opts.size == nil or opts.size == "xs" or opts.size == "sm" or opts.size == "md"
        or opts.size == "lg" or opts.size == "xl", "openAlert size is invalid.")

    -- No timeout, same reasoning as openMenu -- and a non-cancellable alert
    -- MUST NOT have one: timing it out would resolve a dialog that's still on
    -- screen demanding an answer, which is what it was set up to prevent.
    return settleForExport(focusUntilSettled(requestPromise("openAlert", opts, false)))
end

---Opens a schema-driven input form. Grants NUI focus while open and releases
---it when the dialog closes (submit or cancel).
---@param fields table[] QBInputField[] -- see modules/nui/docs.md for the full shared field contract.
---@param title? string
---@param description? string
---@return promise|any result Resolves/returns `{ values: table<string, any> }` or `{ cancelled: true }`. See QB.nui.request's return doc.
function QB.nui.openInputDialog(fields, title, description)
    assertInputFields(fields, "openInputDialog")
    assert(title == nil or type(title) == "string", "openInputDialog title must be a string.")
    assert(description == nil or type(description) == "string", "openInputDialog description must be a string.")
    -- No timeout, same reasoning as openMenu above -- and most acute here,
    -- since filling in a multi-field form is the slowest thing the NUI asks
    -- anyone to do.
    return settleForExport(focusUntilSettled(requestPromise("openInputDialog", {
        title = title,
        description = description,
        fields = fields,
        labels = appLabels(),
    }, false)))
end

-- App registrations are owner-tracked like callbacks, zones, and keybinds.
-- If a consumer stops while its app is open, ask the browser to settle the
-- request first (which releases focus) and then remove the definition.
local function applyAppAccent(registration)
    -- Go through the imported bridge instead of clearing the browser override
    -- directly. The bridge combines an app-owned accent with the player's
    -- saved /theme preference, so an app without an accent keeps that choice
    -- and closing an explicitly themed app restores it.
    QBTheme.apply(registration and registration.browser.accent or nil)
end

appOwnership = QB.resources.registry(function(id)
    local current = activeApp
    if current and current.id == id then
        QB.nui.send("closeApp", {
            appId = id,
            token = current.token,
            reason = "resourceStop",
        })
        settlePendingRequest(current.promise, true, { closed = true, reason = "resourceStop" })
    end
    registeredApps[id] = nil
end)

-- Human-driven requests intentionally have no arbitrary timeout, so their
-- caller owns their lifetime instead. If that resource stops, reject the Lua
-- promise and tell the shared browser hook to unmount the matching surface;
-- the promise's focus callback then releases only this request's lease.
requestOwnership = QB.resources.registry(function(requestId)
    local pending = pendingRequests[requestId]
    if not pending then return end

    pendingRequests[requestId] = nil
    QB.nui.send("cancelNuiRequest", { requestId = requestId, token = pending.token })
    pending.promise:reject("The resource that opened this NUI request stopped.")
end)

-- withFocus is also used around multi-step module operations (minigames and
-- editors), not only request promises. Owner tracking guarantees an abandoned
-- coroutine cannot leave a stale aggregate focus lease behind.
focusOwnership = QB.resources.registry(function(id)
    if not focusLeases[id] then return end
    focusLeases[id] = nil
    refreshFocus()
end)

---Registers a declarative full-screen application shell. The definition owns
---navigation, tabs, standard content blocks, and an optional Lua action
---handler. Registrations are automatically removed when their owner stops.
---@param definition table QBAppDefinition
---@return string id
function QB.nui.registerApp(definition)
    assert(type(definition) == "table", "registerApp requires a definition table.")
    assert(definition.onAction == nil or isCallable(definition.onAction), "App onAction must be callable.")

    local publicDefinition = browserApp(definition)
    local actionIds = assertBrowserApp(publicDefinition)

    local owner = GetInvokingResource() or GetCurrentResourceName()
    local previousOwner = appOwnership.owner(definition.id)
    if previousOwner and previousOwner ~= owner then
        print(("^3[qblib:nui]^7 app '%s' was registered by '%s' and is being overwritten by '%s' -- namespace app ids.")
            :format(definition.id, previousOwner, owner))
    end

    registeredApps[definition.id] = {
        browser = publicDefinition,
        actionIds = actionIds,
        onAction = definition.onAction,
        owner = owner,
    }
    appOwnership.track(owner, definition.id)

    local current = activeApp
    if current and current.id == definition.id then
        applyAppAccent(registeredApps[definition.id])
        QB.nui.send("updateApp", {
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
function QB.nui.unregisterApp(id)
    assertAppId(id)
    local registration = registeredApps[id]
    if not registration then return false end

    local invoker = GetInvokingResource()
    assert(not invoker or invoker == registration.owner,
        ("App '%s' is owned by resource '%s'."):format(id, registration.owner))

    local current = activeApp
    if current and current.id == id then
        QB.nui.send("closeApp", { appId = id, token = current.token, reason = "unregister" })
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
function QB.nui.openApp(id, opts)
    assertAppId(id)
    assert(opts == nil or type(opts) == "table", "openApp options must be a table.")

    local registration = registeredApps[id]
    assert(registration, ("App '%s' is not registered."):format(id))

    -- Settle an old app before granting the new one focus. If this were left
    -- to the browser's asynchronous supersede response, the old promise's
    -- focus-release callback could run after the new request granted focus,
    -- leaving the newly visible app unable to receive input.
    if activeApp then
        local previous = activeApp
        -- Reopening/replacing an app is normal control flow (notably when an
        -- admin runs /admin again). Resolve the old caller as closed instead
        -- of rejecting its cross-resource export call, which would otherwise
        -- print a misleading SCRIPT ERROR in the resource that opened it.
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
        token = p.qblibNuiToken,
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
---@param update table Partial QBAppDefinition (id/onAction excluded).
---@return boolean updated
function QB.nui.updateApp(id, update)
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
        QB.nui.send("updateApp", {
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
function QB.nui.closeApp(id)
    if id ~= nil then assertAppId(id) end
    local current = activeApp
    if not current or (id and current.id ~= id) then return false end

    QB.nui.send("closeApp", {
        appId = current.id,
        token = current.token,
        reason = "api",
    })
    return true
end

---@param id? string
---@return boolean open
function QB.nui.isAppOpen(id)
    if id ~= nil then assertAppId(id) end
    return activeApp ~= nil and (id == nil or activeApp.id == id)
end

local appTones = { neutral = true, primary = true, success = true, warning = true, destructive = true }

local function notifyClosedAppError(message)
    if QB.notify and QB.notify.send then QB.notify.send({ type = "error", message = message }) end
end

local function validateActionResult(registration, result)
    if result == nil then return {} end
    assert(type(result) == "table", "App action results must be a table.")
    assert(result.close == nil or type(result.close) == "boolean", "App action result close must be a boolean.")

    if result.navigate ~= nil then
        assert(type(result.navigate) == "table" and type(result.navigate.viewId) == "string",
            "App action result navigate requires a viewId.")
        local view
        for _, candidate in ipairs(registration.browser.navigation) do
            if candidate.id == result.navigate.viewId and not candidate.disabled then view = candidate break end
        end
        assert(view, "App action result navigate references an unknown or disabled view.")
        if result.navigate.tabId ~= nil then
            local found = false
            for _, tab in ipairs(view.tabs or {}) do
                if tab.id == result.navigate.tabId then found = true break end
            end
            assert(found, "App action result navigate references an unknown tab.")
        end
        assert(result.navigate.replace == nil or type(result.navigate.replace) == "boolean",
            "App action result navigate replace must be a boolean.")
    end

    if result.notice ~= nil then
        assert(type(result.notice) == "table" and appTones[result.notice.tone]
            and type(result.notice.message) == "string" and result.notice.message ~= "",
            "App action result notice requires a valid tone and message.")
    end

    return result
end

-- One authenticated route for every button/list/table action emitted by the
-- AppShell. The per-open token prevents another NUI page from invoking a
-- registered application's privileged action handler by guessing its id.
QB.nui.registerCallback("qblib:app:action", function(data)
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

    -- World editors and other focused UIs cannot safely open beneath the
    -- shell. Settle its request first so its focus lease is gone before the
    -- owning handler starts the next interaction.
    if declared.closeBeforeAction then
        QB.nui.send("closeApp", {
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
        print(("[qblib:nui] app '%s' action '%s' errored: %s")
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
            print(("[qblib:nui] app '%s' action '%s' returned an invalid update: %s")
                :format(current.id, data.actionId, tostring(updateError)))
            if declared.closeBeforeAction then notifyClosedAppError("The app returned an invalid update.") end
            return { ok = false, error = "The app returned an invalid update." }
        end
    end

    local resultOk, validated = pcall(validateActionResult, registration, result)
    if not resultOk then
        registration.browser, registration.actionIds = previousBrowser, previousActionIds
        print(("[qblib:nui] app '%s' action '%s' returned an invalid result: %s")
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

    if (declared.closeBeforeAction or result.close) and result.notice and QB.notify and QB.notify.send then
        local notifyType = result.notice.tone
        if notifyType == "destructive" then notifyType = "error" end
        if notifyType == "primary" or notifyType == "neutral" then notifyType = "info" end
        QB.notify.send({
            type = notifyType,
            message = result.notice.message,
        })
    end

    return { ok = true, result = result }
end)
