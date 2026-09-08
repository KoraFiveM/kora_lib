---@class QBBlipsCreateOptions
---@field sprite? number Blip sprite id. Defaults to `Config.blips.defaultSprite`.
---@field color? number Blip color index. Defaults to `Config.blips.defaultColor`.
---@field scale? number Blip scale. Defaults to `Config.blips.defaultScale`.
---@field label? string Blip name shown on the map/legend. Left as the sprite's own default label when omitted.
---@field shortRange? boolean Whether the blip only shows near the player. Defaults to `Config.blips.defaultShortRange`.
---@field category? number | string Numeric native category, or a named custom category shared by blips with the same string. Left unset (engine default) when omitted.
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
local renderedRevision = nil
local renderedImageReady = false

-- blipRegistry tracks every blip this module has created, keyed by the
-- resource that invoked `create` -- see local/resources/AGENTS.md. Cleanup on
-- resource stop guards with DoesBlipExist since RemoveBlip on an
-- already-gone handle is undefined behavior, not a no-op.
local blipRegistry = QB.resources.registry(function(blip)
    infoByBlip[blip] = nil
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
    for index, row in ipairs(info.rows or {}) do
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
---@param info QBBlipInfo
local function storeInfo(blip, info)
    local previous = infoByBlip[blip]
    local normalised = normaliseInfo(info)
    normalised.revision = previous and previous.revision + 1 or 1
    infoByBlip[blip] = normalised
    if normalised.image then RequestStreamedTextureDict(normalised.image.dictionary) end
    SetBlipAsMissionCreatorBlip(blip, true)
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

-- GTA reserves categories 12-133 for named custom legend groups. Allocate
-- those centrally so callers can group by a stable name without coordinating
-- numeric ids across resources. The mapping lives for qblib's lifetime, which
-- also prevents a later resource restart from relabelling an existing group.
local namedCategories = {}
local nextNamedCategory = Config.blips.namedCategoryStart

---@param category number | string | nil
---@return number? category
local function resolveCategory(category)
    if category == nil or type(category) == "number" then return category end

    assert(type(category) == "string" and category ~= "",
        "Invalid category: expected a number or non-empty string.")

    local existing = namedCategories[category]
    if existing then return existing end

    assert(nextNamedCategory <= Config.blips.namedCategoryEnd,
        "No named blip categories remain; GTA supports categories 12 through 133.")

    local resolved = nextNamedCategory
    nextNamedCategory = nextNamedCategory + 1
    namedCategories[category] = resolved
    AddTextEntry(("BLIP_CAT_%d"):format(resolved), category)

    return resolved
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

---@param text string
---@param blip number
---@param slot string
local function pushLabel(text, blip, slot)
    local label = ("QBLIB_BLIP_%d_%s"):format(blip, slot)
    AddTextEntry(label, text)
    BeginTextCommandScaleformString(label)
    EndTextCommandScaleformString()
end

---@param visible boolean
local function setDisplayVisible(visible)
    if not BeginScaleformMovieMethodOnFrontend("SHOW_COLUMN") then return end
    ScaleformMovieMethodAddParamInt(displayColumn)
    ScaleformMovieMethodAddParamBool(visible)
    EndScaleformMovieMethod()
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
        pushLabel(row.label, blip, ("%d_label"):format(index))
        pushLabel(row.value, blip, ("%d_value"):format(index))
        ScaleformMovieMethodAddParamInt(row.icon)
        ScaleformMovieMethodAddParamInt(row.color)
        ScaleformMovieMethodAddParamBool(row.checked)
    else
        ScaleformMovieMethodAddParamInt(INFO_ROW_STYLE[row.kind])
        ScaleformMovieMethodAddParamInt(0)
        ScaleformMovieMethodAddParamInt(0)
        pushLabel(row.label, blip, ("%d_label"):format(index))
        pushLabel(row.value, blip, ("%d_value"):format(index))
    end

    EndScaleformMovieMethod()
end

---@param blip number
---@param info QBBlipInfo
local function renderInfo(blip, info)
    clearDisplay()

    if BeginScaleformMovieMethodOnFrontend("SET_COLUMN_TITLE") then
        ScaleformMovieMethodAddParamInt(displayColumn)
        BeginTextCommandScaleformString("")
        EndTextCommandScaleformString()
        pushLabel(info.title, blip, "title")
        ScaleformMovieMethodAddParamInt(info.verified and 1 or 0)

        local image = info.image
        if image and HasStreamedTextureDictLoaded(image.dictionary) then
            RequestStreamedTextureDict(image.dictionary)
            PushScaleformMovieFunctionParameterString(image.dictionary)
            PushScaleformMovieFunctionParameterString(image.texture)
        else
            PushScaleformMovieFunctionParameterString("")
            PushScaleformMovieFunctionParameterString("")
        end

        ScaleformMovieMethodAddParamInt(0)
        ScaleformMovieMethodAddParamInt(0)

        if info.rp ~= "" then
            pushLabel(info.rp, blip, "rp")
        else
            ScaleformMovieMethodAddParamBool(false)
        end

        if info.money ~= "" then
            pushLabel(info.money, blip, "money")
        else
            ScaleformMovieMethodAddParamBool(false)
        end

        EndScaleformMovieMethod()
    end

    for index, row in ipairs(info.rows) do renderRow(blip, index - 1, row) end

    setDisplayVisible(true)
    updateDisplay()
end

CreateThread(function()
    while true do
        local sleep = 1000

        if IsFrontendReadyForControl() then
            sleep = 50
            local blip = GetNewSelectedMissionCreatorBlip()

            if IsHoveringOverMissionCreatorBlip() and DoesBlipExist(blip) then
                local info = infoByBlip[blip]
                local imageReady = info and (not info.image or HasStreamedTextureDictLoaded(info.image.dictionary))
                if info and not imageReady then RequestStreamedTextureDict(info.image.dictionary) end

                if info and (selectedBlip ~= blip or renderedRevision ~= info.revision or renderedImageReady ~= imageReady) then
                    selectedBlip = blip
                    renderedRevision = info.revision
                    renderedImageReady = imageReady
                    renderInfo(blip, info)
                elseif not info and selectedBlip then
                    selectedBlip = nil
                    renderedRevision = nil
                    renderedImageReady = false
                    setDisplayVisible(false)
                end
            elseif selectedBlip then
                selectedBlip = nil
                renderedRevision = nil
                renderedImageReady = false
                setDisplayVisible(false)
            end
        end

        Wait(sleep)
    end
end)

---Creates a map blip at `coords`, visible only to the calling client, and
---tracks it against whichever resource invoked `create` (via
---`GetInvokingResource`, falling back to the current resource when called
---directly rather than through an export) so it is automatically removed if
---that resource stops.
---@param coords vector3 | vector4 | {x: number, y: number, z: number} World coordinates to place the blip at.
---@param options? QBBlipsCreateOptions
---@return number | false blip The created blip handle, or false if it failed to create.
---@return string? error
function QB.blips.create(coords, options)
    -- Must be captured before any native calls below -- the invoking-resource
    -- context is only valid at this call boundary, same reasoning as
    -- modules/entities.
    local invokingResource = GetInvokingResource() or GetCurrentResourceName()

    options = options or {}

    assert(coords and type(coords.x) == "number" and type(coords.y) == "number" and type(coords.z) == "number",
        "Invalid coords: expected a vector3/vector4 or {x, y, z} table.")

    local category = resolveCategory(options.category)

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)

    if not blip or blip == 0 then
        return false, "Failed to create blip."
    end

    SetBlipSprite(blip, options.sprite or Config.blips.defaultSprite)
    SetBlipColour(blip, options.color or Config.blips.defaultColor)
    SetBlipScale(blip, options.scale or Config.blips.defaultScale)

    local shortRange = options.shortRange
    if shortRange == nil then shortRange = Config.blips.defaultShortRange end
    SetBlipAsShortRange(blip, shortRange)

    if category then SetBlipCategory(blip, category) end
    if options.label then applyLabel(blip, options.label) end

    if options.route then
        SetBlipRoute(blip, true)
        if options.color then SetBlipRouteColour(blip, options.color) end
    end

    blipRegistry.track(invokingResource, blip)
    if options.info then storeInfo(blip, options.info) end

    return blip
end

---Sets or replaces the detail panel shown when a qblib-created blip is
---highlighted in the pause map. Only the resource that created the blip may
---change its panel.
---@param blip number
---@param info QBBlipInfo
---@return boolean success
---@return string? error
function QB.blips.setInfo(blip, info)
    assert(type(blip) == "number", ("Invalid blip: %s"):format(blip))

    local caller = GetInvokingResource() or GetCurrentResourceName()
    local canManage, err = canManageInfo(blip, caller)
    if not canManage then return false, err end

    storeInfo(blip, info)
    return true
end

---Removes a detail panel from a qblib-created blip. Only the resource that
---created the blip may remove its panel.
---@param blip number
---@return boolean success
---@return string? error
function QB.blips.clearInfo(blip)
    assert(type(blip) == "number", ("Invalid blip: %s"):format(blip))

    local caller = GetInvokingResource() or GetCurrentResourceName()
    local canManage, err = canManageInfo(blip, caller)
    if not canManage then return false, err end

    infoByBlip[blip] = nil
    SetBlipAsMissionCreatorBlip(blip, false)
    return true
end

---Removes one tracked blip created with QB.blips.create and drops it from
---tracking, without waiting for its owning resource to stop. Refuses blips
---this module didn't create -- exports.qblib:blips_remove is callable from
---any resource, and an untracked-handle gate is what stops it doubling as a
---remove-anything primitive against blips owned by other resources.
---@param blip number The blip handle to remove.
---@return boolean success
---@return string? error
function QB.blips.remove(blip)
    assert(type(blip) == "number", ("Invalid blip: %s"):format(blip))

    local owner = blipRegistry.untrack(blip)

    if not owner then
        return false, "Blip is not tracked by QB.blips."
    end

    if not DoesBlipExist(blip) then
        return false, "Blip does not exist."
    end

    infoByBlip[blip] = nil
    RemoveBlip(blip)

    return true
end
