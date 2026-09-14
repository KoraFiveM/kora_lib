---@class QBVehicleNormalizePlateOptions
---@field maxLength? integer Defaults to 8.
---@field whitespace? 'collapse'|'remove'|'preserve' Keeps single internal spaces, removes all whitespace, or preserves internal whitespace. Defaults to collapse.
---@field characters? 'alphanumeric'|'any' Restricts the result to A-Z, 0-9, and optional spaces by default.

---Normalizes a vehicle plate into the canonical uppercase form used for lookups.
---@param value any
---@param options? QBVehicleNormalizePlateOptions
---@return string|nil plate
---@return string|nil reason
function QB.vehicle.normalizePlate(value, options)
    options = options or {}

    assert(type(options) == "table", "QB.vehicle.normalizePlate options must be a table.")
    assert(options.maxLength == nil or QB.util.isInteger(options.maxLength) and options.maxLength > 0,
        "QB.vehicle.normalizePlate maxLength must be a positive integer.")
    assert(options.whitespace == nil or options.whitespace == "collapse" or options.whitespace == "remove"
        or options.whitespace == "preserve",
        "QB.vehicle.normalizePlate whitespace must be 'collapse', 'remove', or 'preserve'.")
    assert(options.characters == nil or options.characters == "alphanumeric" or options.characters == "any",
        "QB.vehicle.normalizePlate characters must be 'alphanumeric' or 'any'.")

    if type(value) ~= "string" then return nil, "invalid_type" end

    local plate = QB.util.trim(value):upper()
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
