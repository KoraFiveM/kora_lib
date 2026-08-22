---Sends a notification to a specific player.
---@param src integer Server ID of the target player, or -1 for every connected player (what sendToAll passes).
---@param payload QBNotifyPayload
function QB.notify.send(src, payload)
    -- Mirrors the client-side send: pcall'd so a malformed notification can't
    -- take down the caller, but the failure is logged rather than swallowed --
    -- see modules/notify/client.lua for why silence here is actively harmful.
    local ok, err = pcall(function()
        QB.notify.assert(payload)

        if Config.third_party_notify then
            TriggerClientEvent('qblib:notify:send', src, payload)
            return
        end

        QB.events.push(src, 'notify', payload)
    end)

    if not ok then
        print(("[qblib:notify] send to %s failed: %s"):format(tostring(src), tostring(err)))
    end
end

---Sends a notification to every connected player.
---@param payload QBNotifyPayload
function QB.notify.sendToAll(payload)
    QB.notify.send(-1, payload)
end