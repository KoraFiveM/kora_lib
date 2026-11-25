function Kora.bridge.createCall(payload)
    return exports.kora_dispatch:createCall(payload)
end
function Kora.bridge.updateCall(id, patch)
    return exports.kora_dispatch:updateCall(id, patch)
end
function Kora.bridge.closeCall(id, reason)
    return exports.kora_dispatch:closeCall(id, reason)
end
function Kora.bridge.getCalls(filter)
    return exports.kora_dispatch:getCalls(filter)
end
function Kora.bridge.registerPlayerAlert(key, definition)
    return exports.kora_dispatch:registerPlayerAlert(key, definition)
end
function Kora.bridge.createPlayerCall(src, key)
    return exports.kora_dispatch:createPlayerCall(src, key)
end
