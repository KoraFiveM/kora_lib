return {
    getFuel = function(vehicle)
        return exports.kora_fuel:GetFuel(vehicle)
    end,
    setFuel = function(vehicle, level)
        return exports.kora_fuel:SetFuel(vehicle, level)
    end,
    isElectricVehicle = function(vehicle)
        return exports.kora_fuel:isElectricVehicle(vehicle)
    end,
}
