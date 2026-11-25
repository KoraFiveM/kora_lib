function Kora.bridge.sendNotify(payload)
    if not payload.message then return end
    if not payload.type then payload.type = 'info' end
    if not payload.time then payload.time = 5000 end
    exports.wasabi_notify:notify(payload.title, payload.message,payload.time, payload.type)
end
exports('bridge_sendNotify', Kora.bridge.sendNotify)
exports('bridge_notify', Kora.bridge.sendNotify)
