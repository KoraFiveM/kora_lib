if IsDuplicityVersion() then
    Kora.bridge.register('dispatch', 'kora_dispatch', {
        createCall = function(payload)
            return exports.kora_dispatch:createCall(payload)
        end,
        updateCall = function(id, patch)
            return exports.kora_dispatch:updateCall(id, patch)
        end,
        closeCall = function(id, reason)
            return exports.kora_dispatch:closeCall(id, reason)
        end,
        getCalls = function(filter)
            return exports.kora_dispatch:getCalls(filter)
        end,
        registerPlayerAlert = function(key, definition)
            return exports.kora_dispatch:registerPlayerAlert(key, definition)
        end,
        createPlayerCall = function(src, key)
            return exports.kora_dispatch:createPlayerCall(src, key)
        end,
    })
end