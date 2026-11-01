---@class QBBlipsCreateOptions
---@field sprite? number Blip sprite id. Defaults to `Config.blips.defaultSprite`.
---@field color? number Blip color index. Defaults to `Config.blips.defaultColor`.
---@field scale? number Blip scale. Defaults to `Config.blips.defaultScale`.
---@field name? string Location/name shown after GTA's category heading.
---@field label? string Backwards-compatible explicit map-label override.
---@field shortRange? boolean Whether the blip only shows near the player. Defaults to `Config.blips.defaultShortRange`.
---@field category? number | string Fixed category name/alias or numeric native category. Defaults to `Other`.
---@field display? integer Native blip display mode restored after the blip/category is shown. Defaults to `Config.blips.defaultDisplay`.
---@field route? boolean Draws a waypoint route line to the blip. Defaults to `false`.
---@field info? QBBlipInfo Optional detail panel shown when this blip is highlighted in the pause map.

local INFO_ROW_STYLE = {
    text = 1,
    icon = 2,
    name = 3,
    header = 4,
    wrappedText = 5,
}

local infoByBlip = {}
local displayColumn = 1
local selectedBlip = nil
local renderedInfo = nil
local missedSelectionPolls = 0
local SELECTION_GRACE_POLLS = 3
local textureRefcounts = {}
local categoryCatalog = assert(Kora.blips._categoryCatalog, 'Kora.blips category catalogue did not load.')
local registeredByBlip = {}
local categoryVisibility = {}
local infoThreadRunning = false
local ensureInfoThread

local function retainTexture(dictionary)
    local refs = textureRefcounts[dictionary] or 0
    textureRefcounts[dictionary] = refs + 1
    if refs == 0 then RequestStreamedTextureDict(dictionary) end
end

local function releaseTexture(dictionary)
    local refs = textureRefcounts[dictionary]
    if not refs then return end
    if refs > 1 then
        textureRefcounts[dictionary] = refs - 1
        return
    end

    textureRefcounts[dictionary] = nil
    SetStreamedTextureDictAsNoLongerNeeded(dictionary)
end

local function clearStoredInfo(blip)
    local info = infoByBlip[blip]
    if info and info.image then releaseTexture(info.image.dictionary) end
    infoByBlip[blip] = nil
end

-- Cleanup on resource stop guards with DoesBlipExist: RemoveBlip on an
-- already-gone handle is undefined behavior, not a no-op.
local blipRegistry = Kora.resources.registry(function(blip)
    registeredByBlip[blip] = nil
    clearStoredInfo(blip)
    if DoesBlipExist(blip) then RemoveBlip(blip) end
end)

---@param value string | number | nil
---@param field string
---@return string
local function normaliseText(value, field)
    assert(value == nil or type(value) == "string" or type(value) == "number",
        ("Invalid %s: expected a string or number."):format(field))
    return value == nil and "" or tostring(value)
end

---@param info QBBlipInfo
---@return QBBlipInfo
local function normaliseInfo(info)
    assert(type(info) == "table", "Invalid info: expected a table.")

    local normalised = {
        title = normaliseText(info.title, "info.title"),
        verified = info.verified == true,
        rp = normaliseText(info.rp, "info.rp"),
        money = normaliseText(info.money, "info.money"),
        rows = {},
    }

    if info.image then
        assert(type(info.image) == "table", "Invalid info.image: expected a table.")
        assert(type(info.image.dictionary) == "string" and info.image.dictionary ~= "",
            "Invalid info.image.dictionary: expected a non-empty string.")
        assert(type(info.image.texture) == "string" and info.image.texture ~= "",
            "Invalid info.image.texture: expected a non-empty string.")
        normalised.image = { dictionary = info.image.dictionary, texture = info.image.texture }
    end

    assert(info.rows == nil or type(info.rows) == "table", "Invalid info.rows: expected an array.")
    local rows = info.rows or {}
    for index = 1, #rows do
        local row = rows[index]
        assert(type(row) == "table", ("Invalid info.rows[%d]: expected a table."):format(index))
        local style = INFO_ROW_STYLE[row.kind]
        assert(style, ("Invalid info.rows[%d].kind: expected text, icon, name, header, or wrappedText."):format(index))

        local normalisedRow = {
            kind = row.kind,
            label = normaliseText(row.label, ("info.rows[%d].label"):format(index)),
            value = normaliseText(row.value, ("info.rows[%d].value"):format(index)),
        }

        if row.kind == "icon" then
            assert(row.icon == nil or type(row.icon) == "number",
                ("Invalid info.rows[%d].icon: expected a number."):format(index))
            assert(row.color == nil or type(row.color) == "number",
                ("Invalid info.rows[%d].color: expected a number."):format(index))
            assert(row.checked == nil or type(row.checked) == "boolean",
                ("Invalid info.rows[%d].checked: expected a boolean."):format(index))
            normalisedRow.icon = row.icon or 0
            normalisedRow.color = row.color or 0
            normalisedRow.checked = row.checked == true
        end

        normalised.rows[#normalised.rows + 1] = normalisedRow
    end

    return normalised
end

---@param blip number
---@param slot string
---@return string
local function infoLabelName(blip, slot)
    return ("KORA_LIB_BLIP_%d_%s"):format(blip, slot)
end

---@param blip number
---@param info QBBlipInfo
local function registerInfoLabels(blip, info)
    AddTextEntry(infoLabelName(blip, "title"), info.title)
    if info.rp ~= "" then AddTextEntry(infoLabelName(blip, "rp"), info.rp) end
    if info.money ~= "" then AddTextEntry(infoLabelName(blip, "money"), info.money) end

    for index = 1, #info.rows do
        local row = info.rows[index]
        local slot = index - 1
        AddTextEntry(infoLabelName(blip, ("%d_label"):format(slot)), row.label)
        AddTextEntry(infoLabelName(blip, ("%d_value"):format(slot)), row.value)
    end
end

---@param blip number
---@param info QBBlipInfo
local function storeInfo(blip, info)
    local previous = infoByBlip[blip]
    local normalised = normaliseInfo(info)
    local previousDictionary = previous and previous.image and previous.image.dictionary
    local nextDictionary = normalised.image and normalised.image.dictionary
    if previousDictionary ~= nextDictionary then
        if previousDictionary then releaseTexture(previousDictionary) end
        if nextDictionary then retainTexture(nextDictionary) end
    end
    infoByBlip[blip] = normalised
    registerInfoLabels(blip, normalised)
    SetBlipAsMissionCreatorBlip(blip, true)
    ensureInfoThread()
end

---@param blip number
---@param caller string
---@return boolean, string?
local function canManageInfo(blip, caller)
    if not DoesBlipExist(blip) then return false, "Blip does not exist." end
    if blipRegistry.owner(blip) ~= caller then
        return false, "Blip is not owned by the calling resource."
    end
    return true
end

for index = 1, #categoryCatalog.definitions do
    local category = categoryCatalog.definitions[index]
    AddTextEntry(('BLIP_CAT_%d'):format(category.id), category.label)
end

---@param category table
---@return string
local function categoryKvp(category)
    return ('kora_lib:blips:category:%d'):format(category.id)
end

---Deprecated pre-rename key, read only as a fallback so saved visibility survives.
---@param category table
---@return string
local function legacyCategoryKvp(category)
    return ('qblib:blips:category:%d'):format(category.id)
end

---@param category table
---@return boolean
local function categoryIsVisible(category)
    local visible = categoryVisibility[category.id]
    if visible ~= nil then return visible end

    local stored = GetResourceKvpString(categoryKvp(category))
    if stored == nil then stored = GetResourceKvpString(legacyCategoryKvp(category)) end
    visible = stored ~= '0'
    categoryVisibility[category.id] = visible
    return visible
end

local resolveCategory = categoryCatalog.resolve

---@param record table
---@return boolean visible
local function applyVisibility(record)
    local visible = not record.hidden and categoryIsVisible(record.categoryDefinition)
    SetBlipDisplay(record.handle, visible and record.display or 0)
    SetBlipRoute(record.handle, visible and record.route or false)
    if visible and record.routeColor ~= nil then SetBlipRouteColour(record.handle, record.routeColor) end
    record.visible = visible
    return visible
end

---@param options QBBlipsCreateOptions
---@param category table
---@return string name
---@return string label
local function resolveNameAndLabel(options, category)
    local explicitLabel = options.label and categoryCatalog.normaliseLabel(options.label) or nil
    local name = options.name and categoryCatalog.normaliseLabel(options.name) or explicitLabel or category.label
    if explicitLabel then return name, explicitLabel end
    if name:lower() == category.label:lower() then return name, '' end
    return name, name
end

---Applies `label` as the blip's display name via the text-command trio FiveM
---requires for setting blip names (there's no single-call native for it).
---@param blip number
---@param label string
local function applyLabel(blip, label)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(blip)
end

---@param blip number
---@param slot string
local function pushLabel(blip, slot)
    BeginTextCommandScaleformString(infoLabelName(blip, slot))
    EndTextCommandScaleformString()
end

---@param visible boolean
local function setDisplayVisible(visible)
    if not BeginScaleformMovieMethodOnFrontend("SHOW_COLUMN") then return end
    ScaleformMovieMethodAddParamInt(displayColumn)
    ScaleformMovieMethodAddParamBool(visible)
    EndScaleformMovieMethod()
end

local function infoConfig()
    return Config.blips.info or {}
end

-- Clicking a legend entry makes IsHoveringOverMissionCreatorBlip report that blip exactly
-- like a map hover does, and no frontend native tells the two apart. The legend lives on
-- the right of the screen, so the mouse cursor (INPUT_CURSOR_X, always readable) being
-- over that region means the selection came from the legend, not from the map.
local function legendHasFocus()
    local cfg = infoConfig()
    if cfg.showOnLegendSelect == true then return false end
    return GetControlNormal(2, 239) >= (cfg.legendMinX or 0.66)
end

local function clearDisplay()
    if not BeginScaleformMovieMethodOnFrontend("SET_DATA_SLOT_EMPTY") then return end
    ScaleformMovieMethodAddParamInt(displayColumn)
    EndScaleformMovieMethod()
end

local function updateDisplay()
    if not BeginScaleformMovieMethodOnFrontend("DISPLAY_DATA_SLOT") then return end
    ScaleformMovieMethodAddParamInt(displayColumn)
    EndScaleformMovieMethod()
end

---@param blip number
---@param index integer
---@param row QBBlipInfoRow
local function renderRow(blip, index, row)
    if not BeginScaleformMovieMethodOnFrontend("SET_DATA_SLOT") then return end

    ScaleformMovieMethodAddParamInt(displayColumn)
    ScaleformMovieMethodAddParamInt(index)
    ScaleformMovieMethodAddParamInt(65)
    ScaleformMovieMethodAddParamInt(3)

    if row.kind == "icon" then
        ScaleformMovieMethodAddParamInt(INFO_ROW_STYLE.icon)
        ScaleformMovieMethodAddParamInt(0)
        ScaleformMovieMethodAddParamInt(1)
        pushLabel(blip, ("%d_label"):format(index))
        pushLabel(blip, ("%d_value"):format(index))
        ScaleformMovieMethodAddParamInt(row.icon)
        ScaleformMovieMethodAddParamInt(row.color)
        ScaleformMovieMethodAddParamBool(row.checked)
    else
        ScaleformMovieMethodAddParamInt(INFO_ROW_STYLE[row.kind])
        ScaleformMovieMethodAddParamInt(0)
        ScaleformMovieMethodAddParamInt(0)
        pushLabel(blip, ("%d_label"):format(index))
        pushLabel(blip, ("%d_value"):format(index))
    end

    EndScaleformMovieMethod()
end

---@param blip number
---@param info QBBlipInfo
---@param clearExisting boolean
local function renderInfo(blip, info, clearExisting)
    if clearExisting then clearDisplay() end

    if BeginScaleformMovieMethodOnFrontend("SET_COLUMN_TITLE") then
        ScaleformMovieMethodAddParamInt(displayColumn)
        BeginTextCommandScaleformString("")
        EndTextCommandScaleformString()
        pushLabel(blip, "title")
        ScaleformMovieMethodAddParamInt(info.verified and 1 or 0)

        local image = info.image
        if image and HasStreamedTextureDictLoaded(image.dictionary) then
            PushScaleformMovieFunctionParameterString(image.dictionary)
            PushScaleformMovieFunctionParameterString(image.texture)
        else
            PushScaleformMovieFunctionParameterString("")
            PushScaleformMovieFunctionParameterString("")
        end

        ScaleformMovieMethodAddParamInt(0)
        ScaleformMovieMethodAddParamInt(0)

        if info.rp ~= "" then
            pushLabel(blip, "rp")
        else
            ScaleformMovieMethodAddParamBool(false)
        end

        if info.money ~= "" then
            pushLabel(blip, "money")
        else
            ScaleformMovieMethodAddParamBool(false)
        end

        EndScaleformMovieMethod()
    end

    for index = 1, #info.rows do renderRow(blip, index - 1, info.rows[index]) end

    setDisplayVisible(true)
    updateDisplay()
end

ensureInfoThread = function()
    if infoThreadRunning then return end
    infoThreadRunning = true

    CreateThread(function()
        while next(infoByBlip) ~= nil or selectedBlip ~= nil do
            local sleep = 1000
            local hasInfo = next(infoByBlip) ~= nil
            local frontendReady = hasInfo and IsFrontendReadyForControl()
            local blip
            local info

            if frontendReady then
                sleep = 50
                if IsHoveringOverMissionCreatorBlip() then
                    blip = GetNewSelectedMissionCreatorBlip()
                    if DoesBlipExist(blip) and not legendHasFocus() then info = infoByBlip[blip] end
                end
            end

            if info then
                local imageReady = not info.image or HasStreamedTextureDictLoaded(info.image.dictionary)
                if not imageReady then RequestStreamedTextureDict(info.image.dictionary) end

                -- The pause-map frontend rebuilds its columns continuously and can
                -- discard a one-shot update. Reassert the populated slots every
                -- frame, but only empty the column when its content actually
                -- changes; clearing a stable column every frame makes it flash.
                sleep = 0
                missedSelectionPolls = 0
                local contentChanged = selectedBlip ~= blip or renderedInfo ~= info
                selectedBlip = blip
                renderedInfo = info
                renderInfo(blip, info, contentChanged)
            elseif selectedBlip then
                -- Frontend selection natives can report a transient false result
                -- while the pause map refreshes. Require consecutive misses so a
                -- single bad frame cannot repeatedly hide and show the column.
                sleep = 50
                missedSelectionPolls = missedSelectionPolls + 1
                if missedSelectionPolls >= SELECTION_GRACE_POLLS then
                    selectedBlip = nil
                    renderedInfo = nil
                    missedSelectionPolls = 0
                    -- Empty only the card we drew; SHOW_COLUMN(false) would hide the legend
                    -- the game keeps in this column.
                    clearDisplay()
                end
            end

            Wait(sleep)
        end

        infoThreadRunning = false
    end)
end

---Creates a map blip at `coords`, visible only to the calling client, and
---tracks it against whichever resource invoked `create` (via
---`GetInvokingResource`, falling back to the current resource when called
---directly rather than through an export) so it is automatically removed if
---that resource stops.
---@param coords vector3 | vector4 | {x: number, y: number, z: number} World coordinates to place the blip at.
---@param options? QBBlipsCreateOptions
---@return number | false blip The created blip handle, or false if it failed to create.
---@return string? error
function Kora.blips.create(coords, options)
    -- Capture before any native calls: the invoking resource is only valid at the call boundary.
    local invokingResource = GetInvokingResource() or GetCurrentResourceName()

    if options == nil then options = {} end
    assert(type(options) == "table", "Blip options must be a table.")

    assert(coords and Kora.util.isFiniteNumber(coords.x) and Kora.util.isFiniteNumber(coords.y) and Kora.util.isFiniteNumber(coords.z),
        "Invalid coords: expected a vector3/vector4 or {x, y, z} table.")

    local category = resolveCategory(options.category)
    local name, label = resolveNameAndLabel(options, category)
    local sprite = options.sprite
    if sprite == nil then sprite = Config.blips.defaultSprite end
    local color = options.color
    if color == nil then color = Config.blips.defaultColor end
    local scale = options.scale
    if scale == nil then scale = Config.blips.defaultScale end
    local display = options.display
    if display == nil then display = Config.blips.defaultDisplay or 4 end
    local shortRange = options.shortRange
    if shortRange == nil then shortRange = Config.blips.defaultShortRange end

    assert(Kora.util.isInteger(sprite) and sprite >= 0, 'Blip sprite must be a non-negative integer.')
    assert(Kora.util.isInteger(color) and color >= 0, 'Blip color must be a non-negative integer.')
    assert(Kora.util.isFiniteNumber(scale) and scale > 0, 'Blip scale must be a positive finite number.')
    assert(Kora.util.isInteger(display) and display >= 0,
        'Blip display must be a non-negative integer.')
    assert(type(shortRange) == 'boolean', 'Blip shortRange must be a boolean.')
    assert(options.route == nil or type(options.route) == 'boolean', 'Blip route must be a boolean.')
    assert(options.info == nil or type(options.info) == 'table', 'Blip info must be a table.')

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)

    if not blip or blip == 0 then
        return false, "Failed to create blip."
    end

    SetBlipSprite(blip, sprite)
    SetBlipColour(blip, color)
    SetBlipScale(blip, scale)
    SetBlipAsShortRange(blip, shortRange)

    SetBlipCategory(blip, category.id)
    applyLabel(blip, label)

    local record = {
        handle = blip,
        resource = invokingResource,
        category = category.id,
        categoryKey = category.key,
        categoryDefinition = category,
        name = name,
        label = label,
        sprite = sprite,
        color = color,
        display = display,
        route = options.route == true,
        routeColor = options.route == true and options.color or nil,
        hidden = false,
        visible = true,
    }
    registeredByBlip[blip] = record
    blipRegistry.track(invokingResource, blip)
    applyVisibility(record)
    if options.info ~= nil then storeInfo(blip, options.info) end

    return blip
end

---@param category table
---@param count? integer
---@return QBBlipCategory
local function publicCategory(category, count)
    if count == nil then
        count = 0
        for _, record in pairs(registeredByBlip) do
            if record.category == category.id then count = count + 1 end
        end
    end

    return {
        key = category.key,
        name = category.name,
        label = category.label,
        id = category.id,
        visible = categoryIsVisible(category),
        count = count,
    }
end

---Returns the fixed category catalogue ordered by native id.
---@return QBBlipCategory[] categories
function Kora.blips.getCategories()
    local result = {}
    local counts = {}
    for _, record in pairs(registeredByBlip) do
        counts[record.category] = (counts[record.category] or 0) + 1
    end
    for index = 1, #categoryCatalog.definitions do
        local category = categoryCatalog.definitions[index]
        result[#result + 1] = publicCategory(category, counts[category.id] or 0)
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

---@param category string|number Category name, alias, or native id.
---@return QBBlipCategory category
function Kora.blips.getCategory(category)
    return publicCategory(resolveCategory(category))
end

---Returns plain snapshots of kora_lib-created blips. The `handle` remains the
---actual native handle returned by `create`; kora_lib never replaces it with an
---object wrapper.
---@return QBRegisteredBlip[] blips
function Kora.blips.getRegistered()
    local result = {}
    for _, record in pairs(registeredByBlip) do
        result[#result + 1] = {
            handle = record.handle,
            resource = record.resource,
            category = record.category,
            categoryKey = record.categoryKey,
            name = record.name,
            label = record.label,
            sprite = record.sprite,
            color = record.color,
            display = record.display,
            route = record.route,
            visible = record.visible,
        }
    end
    table.sort(result, function(a, b) return a.handle < b.handle end)
    return result
end

---@param category string|number Category name, alias, or native id.
---@return boolean visible
function Kora.blips.isCategoryVisible(category)
    return categoryIsVisible(resolveCategory(category))
end

---@param category string|number Category name, alias, or native id.
---@param visible boolean
---@return boolean changed
local function setCategoryVisible(category, visible)
    local resolved = resolveCategory(category)
    local changed = categoryIsVisible(resolved) ~= visible
    if not changed then return false end

    categoryVisibility[resolved.id] = visible
    SetResourceKvp(categoryKvp(resolved), visible and '1' or '0')

    for _, record in pairs(registeredByBlip) do
        if record.category == resolved.id and DoesBlipExist(record.handle) then applyVisibility(record) end
    end
    return changed
end

---@param category string|number Category name, alias, or native id.
---@return boolean changed
function Kora.blips.hideCategory(category)
    return setCategoryVisible(category, false)
end

---@param category string|number Category name, alias, or native id.
---@return boolean changed
function Kora.blips.showCategory(category)
    return setCategoryVisible(category, true)
end

---@param blip integer Native handle returned by Kora.blips.create.
---@return boolean success
---@return string? error
function Kora.blips.hide(blip)
    assert(type(blip) == 'number', ('Invalid blip: %s'):format(blip))
    local record = registeredByBlip[blip]
    if not record then return false, 'Blip is not tracked by Kora.blips.' end
    if blipRegistry.owner(blip) ~= (GetInvokingResource() or GetCurrentResourceName()) then
        return false, 'Blip is not owned by the calling resource.'
    end
    if not DoesBlipExist(blip) then return false, 'Blip does not exist.' end
    record.hidden = true
    applyVisibility(record)
    return true
end

---@param blip integer Native handle returned by Kora.blips.create.
---@return boolean success
---@return string? error
function Kora.blips.show(blip)
    assert(type(blip) == 'number', ('Invalid blip: %s'):format(blip))
    local record = registeredByBlip[blip]
    if not record then return false, 'Blip is not tracked by Kora.blips.' end
    if blipRegistry.owner(blip) ~= (GetInvokingResource() or GetCurrentResourceName()) then
        return false, 'Blip is not owned by the calling resource.'
    end
    if not DoesBlipExist(blip) then return false, 'Blip does not exist.' end
    record.hidden = false
    applyVisibility(record)
    return true
end

---Sets or replaces the detail panel shown when a kora_lib-created blip is
---highlighted in the pause map. Only the resource that created the blip may
---change its panel.
---@param blip number
---@param info QBBlipInfo
---@return boolean success
---@return string? error
function Kora.blips.setInfo(blip, info)
    assert(type(blip) == "number", ("Invalid blip: %s"):format(blip))

    local caller = GetInvokingResource() or GetCurrentResourceName()
    local canManage, err = canManageInfo(blip, caller)
    if not canManage then return false, err end

    storeInfo(blip, info)
    return true
end

---Removes a detail panel from a kora_lib-created blip. Only the resource that
---created the blip may remove its panel.
---@param blip number
---@return boolean success
---@return string? error
function Kora.blips.clearInfo(blip)
    assert(type(blip) == "number", ("Invalid blip: %s"):format(blip))

    local caller = GetInvokingResource() or GetCurrentResourceName()
    local canManage, err = canManageInfo(blip, caller)
    if not canManage then return false, err end

    clearStoredInfo(blip)
    SetBlipAsMissionCreatorBlip(blip, false)
    return true
end

---Removes one tracked blip created by the calling resource, without waiting
---for that resource to stop.
---@param blip number The blip handle to remove.
---@return boolean success
---@return string? error
function Kora.blips.remove(blip)
    assert(type(blip) == "number", ("Invalid blip: %s"):format(blip))

    if not blipRegistry.owner(blip) then
        return false, "Blip is not tracked by Kora.blips."
    end
    if blipRegistry.owner(blip) ~= (GetInvokingResource() or GetCurrentResourceName()) then
        return false, "Blip is not owned by the calling resource."
    end

    blipRegistry.untrack(blip)

    registeredByBlip[blip] = nil
    clearStoredInfo(blip)

    if not DoesBlipExist(blip) then
        return false, "Blip does not exist."
    end

    RemoveBlip(blip)

    return true
end
