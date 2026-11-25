function Kora.bridge.getFuel(vehicle)
    return exports.kora_fuel:GetFuel(vehicle)
end
function Kora.bridge.setFuel(vehicle, level)
    return exports.kora_fuel:SetFuel(vehicle, level)
end
function Kora.bridge.isElectricVehicle(vehicle)
    return exports.kora_fuel:isElectricVehicle(vehicle)
end
