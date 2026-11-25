function Kora.bridge.sendNotification(payload)
    return Kora.notify.send(payload)
end

exports("bridge_sendNotification", Kora.bridge.sendNotification)
