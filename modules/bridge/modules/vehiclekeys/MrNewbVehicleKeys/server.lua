function Kora.bridge.giveKeys(src, plate, allowWhenDisabled)
    return exports.MrNewbVehicleKeys:GiveKeysByPlate(src, plate, allowWhenDisabled)
end

function Kora.bridge.removeKeys(src, plate)
    return exports.MrNewbVehicleKeys:RemoveKeysByPlate(src, plate)
end

function Kora.bridge.hasKeys(src, plate)
    return exports.MrNewbVehicleKeys:HaveKeysByPlate(src, plate)
end

exports("bridge_giveKeys", Kora.bridge.giveKeys)
exports("bridge_removeKeys", Kora.bridge.removeKeys)
exports("bridge_hasKeys", Kora.bridge.hasKeys)
