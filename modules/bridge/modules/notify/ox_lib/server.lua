
function Kora.bridge.sendNotify(source, payload)
    TriggerClientEvent('ox_lib:notify', source, {
        title = payload.title,
        description = payload.message,
        type = payload.type
    })
end