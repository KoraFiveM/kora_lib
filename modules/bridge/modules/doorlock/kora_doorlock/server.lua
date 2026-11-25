return {
    getDoorState = function(id)
        return exports.kora_doorlock:getDoorState(id)
    end,
    setDoorState = function(id, state)
        return exports.kora_doorlock:setDoorState(id, state)
    end,
    createDoor = function(raw)
        return exports.kora_doorlock:createDoor(raw)
    end,
    registerDoorPolicy = function(id, callback)
        return exports.kora_doorlock:RegisterDoorPolicy(id, callback)
    end,
}
