local MOD_FIELDS = {
    modSpoilers = 0, modFrontBumper = 1, modRearBumper = 2, modSideSkirt = 3,
    modExhaust = 4, modFrame = 5, modGrille = 6, modHood = 7,
    modFender = 8, modRightFender = 9, modRoof = 10, modEngine = 11,
    modBrakes = 12, modTransmission = 13, modHorns = 14, modSuspension = 15,
    modArmor = 16, modKit17 = 17, modKit19 = 19, modKit21 = 21,
    modPlateHolder = 25, modVanityPlate = 26, modTrimA = 27, modOrnaments = 28,
    modDashboard = 29, modDial = 30, modDoorSpeaker = 31, modSeats = 32,
    modSteeringWheel = 33, modShifterLeavers = 34, modAPlate = 35,
    modSpeakers = 36, modTrunk = 37, modHydrolic = 38, modEngineBlock = 39,
    modAirFilter = 40, modStruts = 41, modArchCover = 42, modAerials = 43,
    modTrimB = 44, modTank = 45, modWindows = 46, modKit47 = 47,
    modKit49 = 49,
}

local SCALAR_NUMBER_FIELDS = {
    'plateIndex', 'bodyHealth', 'engineHealth', 'tankHealth', 'fuelLevel', 'dirtLevel', 'oilLevel',
    'pearlescentColor', 'dashboardColor', 'wheelColor', 'interiorColor', 'wheels', 'wheelSize', 'wheelWidth', 'windowTint',
    'modFrontWheels', 'modBackWheels', 'modLivery', 'liveryRoof',
}
for field in pairs(MOD_FIELDS) do SCALAR_NUMBER_FIELDS[#SCALAR_NUMBER_FIELDS + 1] = field end

local isFiniteNumber = Kora.util.isFiniteNumber
local isInteger = Kora.util.isInteger

local function validVehicle(vehicle)
    return isInteger(vehicle) and vehicle > 0
        and DoesEntityExist(vehicle) and IsEntityAVehicle(vehicle)
end

local function rounded(value)
    if type(value) ~= 'number' then return value end
    local scaled = value * 10
    return (scaled >= 0 and math.floor(scaled + 0.5) or math.ceil(scaled - 0.5)) / 10
end

local function colorComponents(color)
    return color[1] or color['1'] or color.r,
        color[2] or color['2'] or color.g,
        color[3] or color['3'] or color.b
end

local function colorTable(red, green, blue)
    return { r = red, g = green, b = blue }
end

local function indexed(values, index)
    if not values then return nil end
    local value = values[index]
    if value == nil then value = values[tostring(index)] end
    return value
end

local function boolResult(value)
    return value == true or value == 1
end

local function assertFiniteColor(color, label)
    local red, green, blue = colorComponents(color)
    assert(isFiniteNumber(red) and isFiniteNumber(green) and isFiniteNumber(blue),
        ('Vehicle %s must have finite red, green, and blue values.'):format(label))
end

local function assertIndexedProperties(values, label, maximum)
    assert(type(values) == 'table', ('Vehicle %s must be a table.'):format(label))
    for key in pairs(values) do
        local index = tonumber(key)
        assert(isInteger(index) and index >= 0 and index <= maximum,
            ('Vehicle %s keys must be integer indices from 0 to %d.'):format(label, maximum))
    end
end

local function assertBooleanIndexedProperties(values, label, maximum)
    assertIndexedProperties(values, label, maximum)
    for _, value in pairs(values) do
        assert(type(value) == 'boolean', ('Vehicle %s values must be booleans.'):format(label))
    end
end

local function assertProperties(props)
    for index = 1, #SCALAR_NUMBER_FIELDS do
        local field = SCALAR_NUMBER_FIELDS[index]
        assert(props[field] == nil or isFiniteNumber(props[field]),
            ('Vehicle %s must be a finite number.'):format(field))
    end
    assert(props.plate == nil or type(props.plate) == 'string', 'Vehicle plate must be a string.')

    for _, field in ipairs({ 'color1', 'color2', 'xenonColor' }) do
        local value = props[field]
        if type(value) == 'table' then
            assertFiniteColor(value, field)
        elseif value ~= nil then
            assert(isFiniteNumber(value), ('Vehicle %s must be a finite number or RGB table.'):format(field))
        end
    end
    for _, field in ipairs({ 'neonColor', 'tyreSmokeColor' }) do
        if props[field] ~= nil then
            assert(type(props[field]) == 'table', ('Vehicle %s must be an RGB table.'):format(field))
            assertFiniteColor(props[field], field)
        end
    end
    if props.tireHealth ~= nil then
        assertIndexedProperties(props.tireHealth, 'tire health', 5)
        for _, health in pairs(props.tireHealth) do
            assert(isFiniteNumber(health), 'Vehicle tire health values must be finite numbers.')
        end
    end
    if props.extras ~= nil then assertBooleanIndexedProperties(props.extras, 'extras', 20) end
    if props.tireBurstState ~= nil then assertBooleanIndexedProperties(props.tireBurstState, 'tire burst state', 5) end
    if props.tireBurstCompletely ~= nil then assertBooleanIndexedProperties(props.tireBurstCompletely, 'complete tire burst state', 5) end
    if props.windowStatus ~= nil then assertBooleanIndexedProperties(props.windowStatus, 'window status', 7) end
    if props.doorStatus ~= nil then assertBooleanIndexedProperties(props.doorStatus, 'door status', 5) end
    if props.neonEnabled ~= nil then
        assertBooleanIndexedProperties(props.neonEnabled, 'neon enabled', 4)
        for key in pairs(props.neonEnabled) do
            assert(tonumber(key) >= 1, 'Vehicle neon enabled indices must be from 1 to 4.')
        end
    end
    for _, field in ipairs({ 'modTurbo', 'modSmokeEnabled', 'modXenon', 'modCustomTiresF', 'modCustomTiresR' }) do
        assert(props[field] == nil or type(props[field]) == 'boolean',
            ('Vehicle %s must be a boolean.'):format(field))
    end
end

---Requests control of a networked entity before mutating it.
---@param entity number
---@param timeout? integer
---@return boolean controlled
---@return string? error
function Kora.vehicle.requestControl(entity, timeout)
    return Kora.entities.requestControl(entity, timeout)
end

---Safely deletes a vehicle after obtaining control. Call this only after the
---owning resource's server-side authorization has succeeded.
---@param vehicle number
---@param options? KoraVehicleDeleteOptions
---@return boolean deleted
---@return string? error
function Kora.vehicle.delete(vehicle, options)
    assert(isInteger(vehicle) and vehicle > 0, 'Kora.vehicle.delete requires a positive integer vehicle handle.')
    assert(options == nil or type(options) == 'table', 'Kora.vehicle.delete options must be a table.')
    options = options or {}
    if not DoesEntityExist(vehicle) then return false, 'Vehicle does not exist.' end
    if not IsEntityAVehicle(vehicle) then return false, 'Entity is not a vehicle.' end

    local controlled, err = Kora.vehicle.requestControl(vehicle, options.timeout)
    if not controlled then return false, err or 'Could not acquire vehicle control.' end

    SetEntityAsMissionEntity(vehicle, true, true)
    DeleteVehicle(vehicle)
    return not DoesEntityExist(vehicle), DoesEntityExist(vehicle) and 'Vehicle deletion failed.' or nil
end

---@param vehicle number
---@return boolean
function Kora.vehicle.isDriver(vehicle)
    return validVehicle(vehicle) and GetPedInVehicleSeat(vehicle, -1) == PlayerPedId()
end

---@param vehicle number
---@return number|false modelHash
function Kora.vehicle.model(vehicle)
    if not validVehicle(vehicle) then return false end
    return GetEntityModel(vehicle)
end

---Returns the trimmed number plate for a valid vehicle.
---@param vehicle number
---@return string|false plate
function Kora.vehicle.plate(vehicle)
    if not validVehicle(vehicle) then return false end
    local value = GetVehicleNumberPlateText(vehicle)
    if type(value) ~= 'string' then return false end
    return value:match('^%s*(.-)%s*$')
end

---Returns the localized vehicle label, falling back to its display name.
---@param vehicle number
---@return string|false label
function Kora.vehicle.label(vehicle)
    if not validVehicle(vehicle) then return false end
    local display = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    local label = GetLabelText(display)
    if type(label) ~= 'string' or label == '' or label == 'NULL' then return display end
    return label
end

---Reads a QBCore-compatible vehicle property snapshot.
---@param vehicle number
---@return table|false properties
---@return string? error
function Kora.vehicle.getProperties(vehicle)
    if not validVehicle(vehicle) then return false, 'Entity is not a vehicle.' end

    local pearlescentColor, wheelColor = GetVehicleExtraColours(vehicle)
    local colorPrimary, colorSecondary = GetVehicleColours(vehicle)
    if GetIsVehiclePrimaryColourCustom(vehicle) then
        colorPrimary = colorTable(GetVehicleCustomPrimaryColour(vehicle))
    end
    if GetIsVehicleSecondaryColourCustom(vehicle) then
        colorSecondary = colorTable(GetVehicleCustomSecondaryColour(vehicle))
    end

    local extras = {}
    for id = 0, 20 do
        if DoesExtraExist(vehicle, id) then
            extras[tostring(id)] = boolResult(IsVehicleExtraTurnedOn(vehicle, id))
        end
    end

    local tireHealth, tireBurstState, tireBurstCompletely = {}, {}, {}
    for id = 0, 5 do
        tireHealth[id] = GetVehicleWheelHealth(vehicle, id)
        tireBurstState[id] = IsVehicleTyreBurst(vehicle, id, false)
        tireBurstCompletely[id] = IsVehicleTyreBurst(vehicle, id, true)
    end

    local windowStatus, doorStatus = {}, {}
    for id = 0, 7 do windowStatus[id] = boolResult(IsVehicleWindowIntact(vehicle, id)) end
    for id = 0, 5 do doorStatus[id] = boolResult(IsVehicleDoorDamaged(vehicle, id)) end

    local xenonColor
    local customXenon, xr, xg, xb = GetVehicleXenonLightsCustomColor(vehicle)
    if customXenon then xenonColor = colorTable(xr, xg, xb) else xenonColor = GetVehicleXenonLightsColor(vehicle) end

    local modLivery = GetVehicleMod(vehicle, 48)
    if modLivery == -1 and GetVehicleLivery(vehicle) ~= 0 then modLivery = GetVehicleLivery(vehicle) end

    local properties = {
        model = GetEntityModel(vehicle),
        plate = Kora.vehicle.plate(vehicle),
        plateIndex = GetVehicleNumberPlateTextIndex(vehicle),
        bodyHealth = rounded(GetVehicleBodyHealth(vehicle)),
        engineHealth = rounded(GetVehicleEngineHealth(vehicle)),
        tankHealth = rounded(GetVehiclePetrolTankHealth(vehicle)),
        fuelLevel = rounded(GetVehicleFuelLevel(vehicle)),
        dirtLevel = rounded(GetVehicleDirtLevel(vehicle)),
        oilLevel = rounded(GetVehicleOilLevel(vehicle)),
        color1 = colorPrimary,
        color2 = colorSecondary,
        pearlescentColor = pearlescentColor,
        dashboardColor = GetVehicleDashboardColour(vehicle),
        wheelColor = wheelColor,
        wheels = GetVehicleWheelType(vehicle),
        wheelSize = GetVehicleWheelSize(vehicle),
        wheelWidth = GetVehicleWheelWidth(vehicle),
        tireHealth = tireHealth,
        tireBurstState = tireBurstState,
        tireBurstCompletely = tireBurstCompletely,
        windowTint = GetVehicleWindowTint(vehicle),
        windowStatus = windowStatus,
        doorStatus = doorStatus,
        neonEnabled = {
            IsVehicleNeonLightEnabled(vehicle, 0), IsVehicleNeonLightEnabled(vehicle, 1),
            IsVehicleNeonLightEnabled(vehicle, 2), IsVehicleNeonLightEnabled(vehicle, 3),
        },
        neonColor = colorTable(GetVehicleNeonLightsColour(vehicle)),
        interiorColor = GetVehicleInteriorColour(vehicle),
        extras = extras,
        tyreSmokeColor = colorTable(GetVehicleTyreSmokeColor(vehicle)),
        xenonColor = xenonColor,
        modTurbo = IsToggleModOn(vehicle, 18),
        modSmokeEnabled = IsToggleModOn(vehicle, 20),
        modXenon = IsToggleModOn(vehicle, 22),
        modFrontWheels = GetVehicleMod(vehicle, 23),
        modBackWheels = GetVehicleMod(vehicle, 24),
        modCustomTiresF = GetVehicleModVariation(vehicle, 23),
        modCustomTiresR = GetVehicleModVariation(vehicle, 24),
        modLivery = modLivery,
        liveryRoof = GetVehicleRoofLivery(vehicle),
    }

    for field, index in pairs(MOD_FIELDS) do properties[field] = GetVehicleMod(vehicle, index) end
    return properties
end

---Applies QBCore-compatible properties after obtaining network control.
---@param vehicle number
---@param props table
---@param opts? KoraVehicleSetPropertiesOptions
---@return boolean success
---@return string? error
function Kora.vehicle.setProperties(vehicle, props, opts)
    if not validVehicle(vehicle) then return false, 'Entity is not a vehicle.' end
    assert(type(props) == 'table', 'Vehicle properties must be a table.')
    assert(opts == nil or type(opts) == 'table', 'Vehicle property options must be a table.')
    opts = opts or {}
    assertProperties(props)

    local controlled, err = Kora.vehicle.requestControl(vehicle, opts.timeout)
    if not controlled then return false, err or 'Could not acquire vehicle control.' end

    local colorPrimary, colorSecondary = GetVehicleColours(vehicle)
    local pearlescentColor, wheelColor = GetVehicleExtraColours(vehicle)
    SetVehicleModKit(vehicle, 0)

    if props.plate ~= nil then SetVehicleNumberPlateText(vehicle, props.plate) end
    if props.plateIndex ~= nil then SetVehicleNumberPlateTextIndex(vehicle, props.plateIndex) end
    if props.bodyHealth ~= nil then SetVehicleBodyHealth(vehicle, props.bodyHealth + 0.0) end
    if props.engineHealth ~= nil then SetVehicleEngineHealth(vehicle, props.engineHealth + 0.0) end
    if props.tankHealth ~= nil then SetVehiclePetrolTankHealth(vehicle, props.tankHealth + 0.0) end
    if props.fuelLevel ~= nil then SetVehicleFuelLevel(vehicle, props.fuelLevel + 0.0) end
    if props.dirtLevel ~= nil then SetVehicleDirtLevel(vehicle, props.dirtLevel + 0.0) end
    if props.oilLevel ~= nil then SetVehicleOilLevel(vehicle, props.oilLevel + 0.0) end

    if props.color1 ~= nil then
        if type(props.color1) == 'number' then
            ClearVehicleCustomPrimaryColour(vehicle)
            SetVehicleColours(vehicle, props.color1, colorSecondary)
            colorPrimary = props.color1
        else
            SetVehicleCustomPrimaryColour(vehicle, colorComponents(props.color1))
        end
    end
    if props.color2 ~= nil then
        if type(props.color2) == 'number' then
            ClearVehicleCustomSecondaryColour(vehicle)
            SetVehicleColours(vehicle, type(props.color1) == 'number' and props.color1 or colorPrimary, props.color2)
        else
            SetVehicleCustomSecondaryColour(vehicle, colorComponents(props.color2))
        end
    end
    if props.pearlescentColor ~= nil then
        pearlescentColor = props.pearlescentColor
        SetVehicleExtraColours(vehicle, pearlescentColor, wheelColor)
    end
    if props.wheelColor ~= nil then SetVehicleExtraColours(vehicle, pearlescentColor, props.wheelColor) end
    if props.dashboardColor ~= nil then SetVehicleDashboardColour(vehicle, props.dashboardColor) end
    if props.interiorColor ~= nil then SetVehicleInteriorColour(vehicle, props.interiorColor) end
    if props.wheels ~= nil then SetVehicleWheelType(vehicle, props.wheels) end
    if props.wheelSize ~= nil then SetVehicleWheelSize(vehicle, props.wheelSize) end
    if props.wheelWidth ~= nil then SetVehicleWheelWidth(vehicle, props.wheelWidth) end

    if props.extras ~= nil then
        for id = 0, 20 do
            local enabled = props.extras[id]
            if enabled == nil then enabled = props.extras[tostring(id)] end
            if enabled ~= nil and DoesExtraExist(vehicle, id) then SetVehicleExtra(vehicle, id, enabled and 0 or 1) end
        end
    end
    if props.tireHealth ~= nil then
        for id, health in pairs(props.tireHealth) do SetVehicleWheelHealth(vehicle, tonumber(id), health) end
    end
    if props.tireBurstState ~= nil or props.tireBurstCompletely ~= nil then
        for id = 0, 5 do
            local burst = indexed(props.tireBurstState, id)
            local complete = indexed(props.tireBurstCompletely, id)
            if complete == true then
                SetVehicleTyreBurst(vehicle, id, true, 1000.0)
            elseif burst == true then
                SetVehicleTyreBurst(vehicle, id, false, 1000.0)
            elseif burst == false or complete == false then
                SetVehicleTyreFixed(vehicle, id)
            end
        end
    end
    if props.windowTint ~= nil then SetVehicleWindowTint(vehicle, props.windowTint) end
    if props.windowStatus ~= nil then
        for id, intact in pairs(props.windowStatus) do
            if intact then FixVehicleWindow(vehicle, tonumber(id)) else SmashVehicleWindow(vehicle, tonumber(id)) end
        end
    end
    if props.doorStatus ~= nil then
        for id, broken in pairs(props.doorStatus) do
            if broken then SetVehicleDoorBroken(vehicle, tonumber(id), true)
            else SetVehicleDoorShut(vehicle, tonumber(id), true) end
        end
    end
    if props.neonEnabled ~= nil then
        for id = 0, 3 do
            local enabled = indexed(props.neonEnabled, id + 1)
            if enabled ~= nil then SetVehicleNeonLightEnabled(vehicle, id, enabled) end
        end
    end
    if props.neonColor ~= nil then SetVehicleNeonLightsColour(vehicle, colorComponents(props.neonColor)) end
    if props.tyreSmokeColor ~= nil then SetVehicleTyreSmokeColor(vehicle, colorComponents(props.tyreSmokeColor)) end

    for field, index in pairs(MOD_FIELDS) do
        if props[field] ~= nil then SetVehicleMod(vehicle, index, props[field], false) end
    end
    if props.modTurbo ~= nil then ToggleVehicleMod(vehicle, 18, props.modTurbo) end
    if props.modSmokeEnabled ~= nil then ToggleVehicleMod(vehicle, 20, props.modSmokeEnabled) end
    if props.modXenon ~= nil then ToggleVehicleMod(vehicle, 22, props.modXenon) end
    if props.modFrontWheels ~= nil or props.modCustomTiresF ~= nil then
        SetVehicleMod(vehicle, 23, props.modFrontWheels or GetVehicleMod(vehicle, 23), props.modCustomTiresF == true)
    end
    if props.modBackWheels ~= nil or props.modCustomTiresR ~= nil then
        SetVehicleMod(vehicle, 24, props.modBackWheels or GetVehicleMod(vehicle, 24), props.modCustomTiresR == true)
    end
    if props.modLivery ~= nil then
        SetVehicleMod(vehicle, 48, props.modLivery, false)
        SetVehicleLivery(vehicle, props.modLivery)
    end
    if props.liveryRoof ~= nil then SetVehicleRoofLivery(vehicle, props.liveryRoof) end
    if props.xenonColor ~= nil then
        if type(props.xenonColor) == 'table' then
            SetVehicleXenonLightsCustomColor(vehicle, colorComponents(props.xenonColor))
        else
            SetVehicleXenonLightsColor(vehicle, props.xenonColor)
        end
    end

    return true
end
