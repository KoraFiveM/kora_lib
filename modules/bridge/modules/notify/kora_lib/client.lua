

function Kora.bridge.sendNotify(payload)
    if not payload.title then payload.title = '' end
    if not payload.message then return end
    if not payload.type then payload.type = 'info' end
    return Kora.notify.send(payload)
end

exports("bridge_sendNotify", Kora.bridge.sendNotify)
exports('bridge_notify', Kora.bridge.sendNotify)
