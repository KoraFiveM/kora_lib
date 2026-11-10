---Normalizes a vehicle plate into the canonical uppercase form used for lookups.
---@param value any
---@param options? KoraVehicleNormalizePlateOptions
---@return string|nil plate
---@return string|nil reason
function Kora.vehicle.normalizePlate(value, options)
    assert(options == nil or type(options) == "table", "Kora.vehicle.normalizePlate options must be a table.")
    options = options or {}
    assert(options.maxLength == nil or Kora.util.isInteger(options.maxLength) and options.maxLength > 0,
        "Kora.vehicle.normalizePlate maxLength must be a positive integer.")
    assert(options.whitespace == nil or options.whitespace == "collapse" or options.whitespace == "remove"
        or options.whitespace == "preserve",
        "Kora.vehicle.normalizePlate whitespace must be 'collapse', 'remove', or 'preserve'.")
    assert(options.characters == nil or options.characters == "alphanumeric" or options.characters == "any",
        "Kora.vehicle.normalizePlate characters must be 'alphanumeric' or 'any'.")

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
