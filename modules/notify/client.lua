---Sends a notification to the local player.
---@param payload QBNotifyPayload
function Kora.notify.send(payload)
    local ok, err = pcall(function()
        payload = Kora.notify.normalize(payload)
        Kora.notify.assert(payload)

        if Config.third_party_notify then
            TriggerEvent('kora_lib:notify:send', payload)
            TriggerEvent('qblib:notify:send', payload)
            return
        end

        Kora.nui.send("notify", Kora.notify.withDefaults(payload))
    end)

    if not ok then
        print(("[kora_lib:notify] send failed: %s"):format(tostring(err)))
    end
end

Kora.events.onPush('notify', Kora.notify.send)
