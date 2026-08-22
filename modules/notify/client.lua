---Sends a notification to the local player.
---@param payload QBNotifyPayload
function QB.notify.send(payload)
    -- pcall'd because a notification is incidental to whatever the caller was
    -- actually doing -- a malformed payload shouldn't take that down with it.
    -- The failure is LOGGED rather than swallowed, though: a silent return
    -- here makes "bad payload" and "the NUI is dead" look identical from
    -- in-game, which is exactly the ambiguity that made a real NUI outage
    -- hard to pin down.
    local ok, err = pcall(function()
        QB.notify.assert(payload)

        if Config.third_party_notify then
            -- Forwarded as given: a third-party notify resource has its own
            -- defaults, and shouldn't have qblib's substituted underneath it.
            TriggerEvent('qblib:notify:send', payload)
            return
        end

        QB.nui.send("notify", QB.notify.withDefaults(payload))
    end)

    if not ok then
        print(("[qblib:notify] send failed: %s"):format(tostring(err)))
    end
end

QB.events.onPush('notify', QB.notify.send)