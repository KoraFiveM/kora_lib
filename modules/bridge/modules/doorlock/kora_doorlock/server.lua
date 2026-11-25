function Kora.bridge.getDoorState(id)
    return exports.kora_doorlock:getDoorState(id)
end

function Kora.bridge.setDoorState(id, state)
    return exports.kora_doorlock:setDoorState(id, state)
end

function Kora.bridge.createDoor(raw)
    return exports.kora_doorlock:createDoor(raw)
end

function Kora.bridge.registerDoorPolicy(id, callback)
    return exports.kora_doorlock:RegisterDoorPolicy(id, callback)
end
