

function Kora.bridge.sendNotification(payload)
    if not payload.title then payload.title = '' end
    if not payload.message then return end
    if not payload.type then payload.type = 'info' end
    return Kora.notify.send(payload)
end

exports("bridge_sendNotification", Kora.bridge.sendNotification)
