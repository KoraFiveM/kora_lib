function Kora.bridge.getFuel(vehicle)
    return exports.LegacyFuel:GetFuel(vehicle)
end

function Kora.bridge.setFuel(vehicle, level)
    return exports.LegacyFuel:SetFuel(vehicle, level)
end

function Kora.bridge.isElectricVehicle(vehicle)
    -- LegacyFuel does not provide a direct method to check if a vehicle is electric
    return false -- Assume non-electric by defaults
    --return exports.LegacyFuel:isElectricVehicle(vehicle)
end

exports("bridge_getFuel", Kora.bridge.getFuel)
exports("bridge_setFuel", Kora.bridge.setFuel)
exports("bridge_isElectricVehicle", Kora.bridge.isElectricVehicle)
