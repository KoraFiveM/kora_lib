function Kora.bridge.getFuel(vehicle)
    return Entity(vehicle).state.fuel or 0
end

function Kora.bridge.setFuel(vehicle, level)
    Entity(vehicle).state.fuel = level
end

function Kora.bridge.isElectricVehicle(vehicle)
    -- ox_fuel does not provide a direct method to check if a vehicle is electric
    return false -- Assume non-electric by defaults
    --return exports.LegacyFuel:isElectricVehicle(vehicle)
end

exports("bridge_getFuel", Kora.bridge.getFuel)
exports("bridge_setFuel", Kora.bridge.setFuel)
exports("bridge_isElectricVehicle", Kora.bridge.isElectricVehicle)
