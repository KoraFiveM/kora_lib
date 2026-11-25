
function Kora.bridge.sendNotify(source, payload)
    if not payload.title then payload.title = '' end
    if not payload.message then return end
    if not payload.type then payload.type = 'info' end
    return Kora.notify.send(source, payload)
end