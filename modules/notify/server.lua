---Sends a notification to a specific player.
---@param src integer Server ID of the target player, or -1 for every connected player (what sendToAll passes).
---@param payload KoraNotifyPayload
function Kora.notify.send(src, payload)
    local ok, err = pcall(function()
        assert(src == -1 or (Kora.util.isInteger(src) and src >= 1),
            "Notify target must be -1 or a positive integer server ID.")
        payload = Kora.notify.normalize(payload)
        Kora.notify.assert(payload)

        if Config.third_party_notify then
            TriggerClientEvent('kora_lib:notify:send', src, payload)
            return
        end

        Kora.events.push(src, 'notify', payload)
    end)

    if not ok then
        print(("[kora_lib:notify] send to %s failed: %s"):format(tostring(src), tostring(err)))
    end
end

---Sends a notification to every connected player.
---@param payload KoraNotifyPayload
function Kora.notify.sendToAll(payload)
    Kora.notify.send(-1, payload)
end
