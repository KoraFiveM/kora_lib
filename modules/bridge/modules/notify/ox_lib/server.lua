
function Kora.bridge.sendNotify(source, payload)
    TriggerClientEvent('ox_lib:notify', source, {
        title = payload.title,
        description = payload.message,
        type = payload.type,
        duration = payload.time
    })
end
exports('bridge_sendNotify', Kora.bridge.sendNotify)
exports('bridge_notify', Kora.bridge.sendNotify)
