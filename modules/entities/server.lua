---@alias QBServerVehicleType "automobile" | "bike" | "boat" | "heli" | "plane" | "submarine" | "trailer" | "train"

local isFiniteNumber = Kora.util.isFiniteNumber

local vehicleTypes = {
    automobile = true,
    bike = true,
    boat = true,
    heli = true,
    plane = true,
    submarine = true,
    trailer = true,
    train = true,
}

---@param model string | number
---@return number
local function resolveModel(model)
    assert(type(model) == 'string' or type(model) == 'number', 'Vehicle model must be a name or hash.')
    return type(model) == 'string' and joaat(model) or model
end

---@param coords table
---@return number, number, number, number
local function resolveCoords(coords)
    assert(type(coords) == 'table', 'Vehicle coords must be a table.')
    assert(isFiniteNumber(coords.x) and isFiniteNumber(coords.y) and isFiniteNumber(coords.z),
        'Vehicle coords must contain finite x, y, and z values.')

    local heading = coords.w or coords.heading or 0.0
    assert(isFiniteNumber(heading), 'Vehicle heading must be finite.')
    return coords.x, coords.y, coords.z, heading
end

---Creates a networked vehicle on the server for OneSync strict entity lockdown.
---Returns the network id, which can be passed to clients or stored by a garage.
---@param model string | number Vehicle model name or hash.
---@param coords table Coordinates with x, y, z, and optional w/heading.
---@param vehicleType QBServerVehicleType? Server setter type; defaults to automobile.
---@return number | false, string?
function Kora.entities.createVehicle(model, coords, vehicleType)
    local modelHash = resolveModel(model)
    local typeName = vehicleType or 'automobile'
    assert(vehicleTypes[typeName], ('Invalid server vehicle type: %s'):format(tostring(typeName)))

    local x, y, z, heading = resolveCoords(coords)
    if not Kora.lookup.vehicle(modelHash) then
        return false, 'Vehicle model is invalid.'
    end

    local vehicle = CreateVehicleServerSetter(modelHash, typeName, x, y, z, heading)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return false, 'Vehicle creation failed.'
    end

    return NetworkGetNetworkIdFromEntity(vehicle)
end
