function Kora.bridge.getClosestDoor()
    return exports.kora_doorlock:getClosestDoor()
end

function Kora.bridge.getDoorState(id)
    return exports.kora_doorlock:getDoorState(id)
end

function Kora.bridge.pickClosestDoor()
    return exports.kora_doorlock:pickClosestDoor()
end

exports("bridge_getClosestDoor", Kora.bridge.getClosestDoor)
exports("bridge_getDoorState", Kora.bridge.getDoorState)
exports("bridge_pickClosestDoor", Kora.bridge.pickClosestDoor)
