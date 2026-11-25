
function Kora.bridge.sendNotify(source, payload)
    if not payload.message then return end
    if not payload.type then payload.type = 'info' end
    if not payload.time then payload.time = 5000 end
    TriggerClientEvent('lation_ui:notify', source, {
        title = payload.title,
        message = payload.message,
        type = payload.type,
        duration = payload.time
    })
end
exports('bridge_sendNotify', Kora.bridge.sendNotify)
exports('bridge_notify', Kora.bridge.sendNotify)
