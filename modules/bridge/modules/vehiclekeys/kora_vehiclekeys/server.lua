function Kora.bridge.giveKeys(src, plate, allowWhenDisabled)
    return exports.kora_vehiclekeys:giveKeys(src, plate, allowWhenDisabled)
end

function Kora.bridge.removeKeys(src, plate)
    return exports.kora_vehiclekeys:removeKeys(src, plate)
end

function Kora.bridge.hasKeys(src, plate)
    return exports.kora_vehiclekeys:hasKeys(src, plate)
end

exports("bridge_giveKeys", Kora.bridge.giveKeys)
exports("bridge_removeKeys", Kora.bridge.removeKeys)
exports("bridge_hasKeys", Kora.bridge.hasKeys)
