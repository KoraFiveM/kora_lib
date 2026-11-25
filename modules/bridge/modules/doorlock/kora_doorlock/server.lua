Kora.bridge.getDoorState = function(id)
    return exports.kora_doorlock:getDoorState(id)
end
Kora.bridge.setDoorState = function(id, state)
    return exports.kora_doorlock:setDoorState(id, state)
end
Kora.bridge.createDoor = function(raw)
    return exports.kora_doorlock:createDoor(raw)
end
Kora.bridge.registerDoorPolicy = function(id, callback)
    return exports.kora_doorlock:RegisterDoorPolicy(id, callback)
end
