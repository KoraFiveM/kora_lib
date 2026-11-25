
function Kora.bridge.hasKeys(vehicle)
    return exports.MrNewbVehicleKeys:HaveKeys(vehicle)
end

exports("bridge_hasKeys", Kora.bridge.hasKeys)
