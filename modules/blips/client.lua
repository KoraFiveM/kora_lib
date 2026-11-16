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
local PAUSE_MENU_READY = 15
local hoverBlip = nil
local hoverSince = 0
local legendSuppressUntil = 0
local textureRefcounts = {}
local categoryCatalog = assert(Kora.blips._categoryCatalog, KoraLang('Modules.Blips.category_catalog_missing'))
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

local function notifyBlipsChanged()
    TriggerEvent('kora_lib:blips:changed')
end

local blipRegistry = Kora.resources.registry(function(blip)
    registeredByBlip[blip] = nil
    clearStoredInfo(blip)
    if DoesBlipExist(blip) then RemoveBlip(blip) end
    notifyBlipsChanged()
end)

---@param value string | number | nil
---@param field string
---@return string
local function normaliseText(value, field)
    assert(value == nil or type(value) == "string" or type(value) == "number",
        KoraLang('Modules.Blips.text_invalid', field))
    return value == nil and "" or tostring(value)
end

---@param info KoraBlipInfo
---@return KoraBlipInfo
local function normaliseInfo(info)
    assert(type(info) == "table", KoraLang('Modules.Blips.info_table_invalid'))

    local normalised = {
        title = normaliseText(info.title, "info.title"),
        verified = info.verified == true,
        rp = normaliseText(info.rp, "info.rp"),
        money = normaliseText(info.money, "info.money"),
        rows = {},
    }

    if info.image then
        assert(type(info.image) == "table", KoraLang('Modules.Blips.image_table_invalid'))
        assert(type(info.image.dictionary) == "string" and info.image.dictionary ~= "",
            KoraLang('Modules.Blips.image_dictionary_invalid'))
        assert(type(info.image.texture) == "string" and info.image.texture ~= "",
            KoraLang('Modules.Blips.image_texture_invalid'))
        normalised.image = { dictionary = info.image.dictionary, texture = info.image.texture }
    end

    assert(info.rows == nil or type(info.rows) == "table", KoraLang('Modules.Blips.rows_invalid'))
    local rows = info.rows or {}
    for index = 1, #rows do
        local row = rows[index]
        assert(type(row) == "table", KoraLang('Modules.Blips.row_table_invalid', index))
        local style = INFO_ROW_STYLE[row.kind]
        assert(style, KoraLang('Modules.Blips.row_kind_invalid', index))

        local normalisedRow = {
            kind = row.kind,
            label = normaliseText(row.label, ("info.rows[%d].label"):format(index)),
            value = normaliseText(row.value, ("info.rows[%d].value"):format(index)),
        }

        if row.kind == "icon" then
            assert(row.icon == nil or type(row.icon) == "number",
                KoraLang('Modules.Blips.row_icon_invalid', index))
            assert(row.color == nil or type(row.color) == "number",
                KoraLang('Modules.Blips.row_color_invalid', index))
            assert(row.checked == nil or type(row.checked) == "boolean",
                KoraLang('Modules.Blips.row_checked_invalid', index))
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
---@param info KoraBlipInfo
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
---@param info KoraBlipInfo
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
    if not DoesBlipExist(blip) then return false, KoraLang('Modules.Blips.missing') end
    if blipRegistry.owner(blip) ~= caller then
        return false, KoraLang('Modules.Blips.not_owned')
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
    return ('kora_lib:blips:category:%d'):format(category.id)
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
    notifyBlipsChanged()
    return visible
end

---@param options KoraBlipsCreateOptions
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

local function nativeTrue(value)
    return value == true or (type(value) == "number" and value ~= 0)
end

local function frontendReadyForCard()
    if not IsFrontendReadyForControl() then return false end
    if not IsPauseMenuActive() or IsPauseMenuRestarting() then return false end
    if infoConfig().requirePauseReady == false then return true end
    return GetPauseMenuState() == PAUSE_MENU_READY
end

local function cursorOverLegend(cfg)
    local minX = cfg.legendMinX
    if type(minX) ~= "number" or minX <= 0 or minX > 1 then return false end
    if IsUsingKeyboard and not IsUsingKeyboard(2) then return false end
    local x = math.max(GetControlNormal(2, 239) or 0.0, GetDisabledControlNormal(2, 239) or 0.0)
    return x >= minX
end

local function legendHasFocus(cfg)
    if cfg.showOnLegendSelect == true then return false end
    if cfg.blockWhileNavigatingContent ~= false and nativeTrue(IsNavigatingMenuContent()) then return true end
    return cursorOverLegend(cfg)
end

local function legendNavigated(cfg, now)
    local holdMs = cfg.legendSuppressMs
    if type(holdMs) ~= "number" or holdMs <= 0 then return false end
    if nativeTrue(HasMenuLayoutChangedEventOccurred()) then legendSuppressUntil = now + holdMs end
    return now < legendSuppressUntil
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
---@param row KoraBlipInfoRow
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
---@param info KoraBlipInfo
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

    if infoConfig().forceShowColumn ~= false then setDisplayVisible(true) end
    updateDisplay()
end

ensureInfoThread = function()
    if infoThreadRunning then return end
    infoThreadRunning = true

    CreateThread(function()
        while next(infoByBlip) ~= nil or selectedBlip ~= nil do
            local sleep = 1000
            local hasInfo = next(infoByBlip) ~= nil
            local frontendReady = hasInfo and frontendReadyForCard()
            local blip
            local info
            local legendFocused = false

            if frontendReady then
                local cfg = infoConfig()
                local now = GetGameTimer()
                sleep = 50
                if (cfg.legendSuppressMs or 0) > 0 then sleep = 0 end
                legendFocused = legendNavigated(cfg, now)

                local candidate
                if IsHoveringOverMissionCreatorBlip() then
                    blip = GetNewSelectedMissionCreatorBlip()
                    if DoesBlipExist(blip) then candidate = infoByBlip[blip] end
                end
                if not legendFocused and (candidate or selectedBlip ~= nil) then
                    legendFocused = legendHasFocus(cfg)
                end
                if candidate and not legendFocused then info = candidate end

                if info then
                    if hoverBlip ~= blip then
                        hoverBlip = blip
                        hoverSince = now
                    end
                    if selectedBlip ~= blip and now - hoverSince < (cfg.hoverStableMs or 0) then
                        info = nil
                        sleep = 0
                    end
                else
                    hoverBlip = nil
                end
            else
                hoverBlip = nil
            end

            if info then
                local imageReady = not info.image or HasStreamedTextureDictLoaded(info.image.dictionary)
                if not imageReady then RequestStreamedTextureDict(info.image.dictionary) end

                sleep = 0
                missedSelectionPolls = 0
                local contentChanged = selectedBlip ~= blip or renderedInfo ~= info
                selectedBlip = blip
                renderedInfo = info
                renderInfo(blip, info, contentChanged)
            elseif selectedBlip then
                sleep = math.min(sleep, 50)
                missedSelectionPolls = missedSelectionPolls + 1
                if legendFocused or missedSelectionPolls >= SELECTION_GRACE_POLLS then
                    selectedBlip = nil
                    renderedInfo = nil
                    missedSelectionPolls = 0
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
---@param options? KoraBlipsCreateOptions
---@return number | false blip The created blip handle, or false if it failed to create.
---@return string? error
function Kora.blips.create(coords, options)
    local invokingResource = GetInvokingResource() or GetCurrentResourceName()

    if options == nil then options = {} end
    assert(type(options) == "table", KoraLang('Modules.Blips.options_table'))

    assert(coords and Kora.util.isFiniteNumber(coords.x) and Kora.util.isFiniteNumber(coords.y) and Kora.util.isFiniteNumber(coords.z),
        KoraLang('Modules.Blips.coords_invalid'))

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

    assert(Kora.util.isInteger(sprite) and sprite >= 0, KoraLang('Modules.Blips.sprite_invalid'))
    assert(Kora.util.isInteger(color) and color >= 0, KoraLang('Modules.Blips.color_invalid'))
    assert(Kora.util.isFiniteNumber(scale) and scale > 0, KoraLang('Modules.Blips.scale_invalid'))
    assert(Kora.util.isInteger(display) and display >= 0,
        KoraLang('Modules.Blips.display_invalid'))
    assert(type(shortRange) == 'boolean', KoraLang('Modules.Blips.short_range_boolean'))
    assert(options.route == nil or type(options.route) == 'boolean', KoraLang('Modules.Blips.route_boolean'))
    assert(options.info == nil or type(options.info) == 'table', KoraLang('Modules.Blips.info_table'))

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)

    if not blip or blip == 0 then
        return false, KoraLang('Modules.Blips.create_failed')
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
---@return KoraBlipCategory
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
---@return KoraBlipCategory[] categories
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
---@return KoraBlipCategory category
function Kora.blips.getCategory(category)
    return publicCategory(resolveCategory(category))
end

---Returns plain snapshots of kora_lib-created blips. The `handle` remains the
---actual native handle returned by `create`; kora_lib never replaces it with an
---object wrapper.
---@return KoraRegisteredBlip[] blips
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
    assert(type(blip) == 'number', KoraLang('Modules.Blips.invalid_handle', blip))
    local record = registeredByBlip[blip]
    if not record then return false, KoraLang('Modules.Blips.not_tracked') end
    if blipRegistry.owner(blip) ~= (GetInvokingResource() or GetCurrentResourceName()) then
        return false, KoraLang('Modules.Blips.not_owned')
    end
    if not DoesBlipExist(blip) then return false, KoraLang('Modules.Blips.missing') end
    record.hidden = true
    applyVisibility(record)
    return true
end

---@param blip integer Native handle returned by Kora.blips.create.
---@return boolean success
---@return string? error
function Kora.blips.show(blip)
    assert(type(blip) == 'number', KoraLang('Modules.Blips.invalid_handle', blip))
    local record = registeredByBlip[blip]
    if not record then return false, KoraLang('Modules.Blips.not_tracked') end
    if blipRegistry.owner(blip) ~= (GetInvokingResource() or GetCurrentResourceName()) then
        return false, KoraLang('Modules.Blips.not_owned')
    end
    if not DoesBlipExist(blip) then return false, KoraLang('Modules.Blips.missing') end
    record.hidden = false
    applyVisibility(record)
    return true
end

---Sets or replaces the detail panel shown when a kora_lib-created blip is
---highlighted in the pause map. Only the resource that created the blip may
---change its panel.
---@param blip number
---@param info KoraBlipInfo
---@return boolean success
---@return string? error
function Kora.blips.setInfo(blip, info)
    assert(type(blip) == "number", KoraLang('Modules.Blips.invalid_handle', blip))

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
    assert(type(blip) == "number", KoraLang('Modules.Blips.invalid_handle', blip))

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
    assert(type(blip) == "number", KoraLang('Modules.Blips.invalid_handle', blip))

    if not blipRegistry.owner(blip) then
        return false, KoraLang('Modules.Blips.not_tracked')
    end
    if blipRegistry.owner(blip) ~= (GetInvokingResource() or GetCurrentResourceName()) then
        return false, KoraLang('Modules.Blips.not_owned')
    end

    blipRegistry.untrack(blip)

    registeredByBlip[blip] = nil
    clearStoredInfo(blip)

    local exists = DoesBlipExist(blip)
    if exists then RemoveBlip(blip) end
    notifyBlipsChanged()
    if not exists then return false, KoraLang('Modules.Blips.missing') end
    return true
end
