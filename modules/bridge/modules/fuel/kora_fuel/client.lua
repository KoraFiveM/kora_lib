Kora.bridge.getFuel = function(vehicle)
    return exports.kora_fuel:GetFuel(vehicle)
end
Kora.bridge.setFuel = function(vehicle, level)
    return exports.kora_fuel:SetFuel(vehicle, level)
end
Kora.bridge.isElectricVehicle = function(vehicle)
    return exports.kora_fuel:isElectricVehicle(vehicle)
end
