local adapter
if IsDuplicityVersion() then
    adapter = {
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
else
    adapter = {
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
end

Kora.bridge.register('doorlock', 'kora_doorlock', adapter)