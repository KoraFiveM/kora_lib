Kora.bridge.createCall = function(payload)
    return exports.kora_dispatch:createCall(payload)
end
Kora.bridge.updateCall = function(id, patch)
    return exports.kora_dispatch:updateCall(id, patch)
end
Kora.bridge.closeCall = function(id, reason)
    return exports.kora_dispatch:closeCall(id, reason)
end
Kora.bridge.getCalls = function(filter)
    return exports.kora_dispatch:getCalls(filter)
end
Kora.bridge.registerPlayerAlert = function(key, definition)
    return exports.kora_dispatch:registerPlayerAlert(key, definition)
end
Kora.bridge.createPlayerCall = function(src, key)
    return exports.kora_dispatch:createPlayerCall(src, key)
end
