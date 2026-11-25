function Kora.bridge.notify(payload)
    if not payload.message then return end
    if not payload.type then payload.type = 'info' end
    if not payload.time then payload.time = 5000 end
    exports.ox_lib:notify({
        title = payload.title,
        description = payload.message,
        type = payload.type,
    })
end
