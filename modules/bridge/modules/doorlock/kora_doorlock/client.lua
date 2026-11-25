return {
    getClosestDoor = function()
        return exports.kora_doorlock:getClosestDoor()
    end,
    getDoorState = function(id)
        return exports.kora_doorlock:getDoorState(id)
    end,
    pickClosestDoor = function()
        return exports.kora_doorlock:pickClosestDoor()
    end,
}
