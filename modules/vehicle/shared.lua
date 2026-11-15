---Normalizes a vehicle plate into the canonical uppercase form used for lookups.
---@param value any
---@param options? KoraVehicleNormalizePlateOptions
---@return string|nil plate
---@return string|nil reason
function Kora.vehicle.normalizePlate(value, options)
    assert(options == nil or type(options) == "table", KoraLang('Modules.Vehicle.vehicle_normalizeplate_o'))
    options = options or {}
    assert(
        options.maxLength == nil or Kora.util.isInteger(options.maxLength) and options.maxLength > 0,
        KoraLang('Modules.Vehicle.vehicle_normalizeplate_m')
    )
    assert(
        options.whitespace == nil or options.whitespace == "collapse" or options.whitespace == "remove"
        or options.whitespace == "preserve",
        KoraLang('Modules.Vehicle.vehicle_normalizeplate_w')
    )
    assert(
        options.characters == nil or options.characters == "alphanumeric" or options.characters == "any",
        KoraLang('Modules.Vehicle.vehicle_normalizeplate_c')
    )

    if type(value) ~= "string" then return nil, "invalid_type" end

    local plate = Kora.util.trim(value):upper()
    if options.whitespace == "remove" then
        plate = plate:gsub("%s+", "")
    elseif options.whitespace ~= "preserve" then
        plate = plate:gsub("%s+", " ")
    end

    if plate == "" then return nil, "empty" end
    if #plate > (options.maxLength or 8) then return nil, "too_long" end
    if (options.characters or "alphanumeric") == "alphanumeric" and not plate:match("^[A-Z0-9 ]+$") then
        return nil, "invalid_characters"
    end

    return plate
end
