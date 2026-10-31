---Sends a notification to the local player.
---@param payload QBNotifyPayload
function Kora.notify.send(payload)
    -- pcall'd because a notification is incidental to whatever the caller was
    -- actually doing -- a malformed payload shouldn't take that down with it.
    -- The failure is LOGGED rather than swallowed, though: a silent return
    -- here makes "bad payload" and "the NUI is dead" look identical from
    -- in-game, which is exactly the ambiguity that made a real NUI outage
    -- hard to pin down.
    local ok, err = pcall(function()
        payload = Kora.notify.normalize(payload)
        Kora.notify.assert(payload)

        if Config.third_party_notify then
            -- Forwarded as given: a third-party notify resource has its own
            -- defaults, and shouldn't have kora_lib's substituted underneath it.
            TriggerEvent('kora_lib:notify:send', payload)
            -- Deprecated alias: third-party handlers may still listen on the old name.
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