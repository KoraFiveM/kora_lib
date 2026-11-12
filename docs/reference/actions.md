---
title: "Actions module"
sidebar_position: 38
---

# Actions module

`Kora.actions.run` composes a resource-owned server authorization step with one
exclusive client progressbar or server-validated minigame. It does not grant
items, validate locations, or decide rewards: those remain in the resource's
`begin`/`complete` server handlers.

```lua
Kora.actions.run({
    label = station.label,
    duration = station.duration,
    minigame = station.minigame,
    disable = { move = true, combat = true },
    begin = function(stationId)
        -- Consumer callback calls already return the settled server result.
        local begun = Kora.callback.trigger('my-resource:server:beginAction', stationId)
        -- The server callback creates begun.authorization with
        -- Kora.minigames.authorizeProof.
        return begun.actionToken, nil, begun.authorization
    end,
    complete = function(result, stationId)
        TriggerServerEvent('my-resource:server:actionCompleted', stationId,
            result.token, result.completed, result.proof, result.authorization)
    end,
}, station.id)
```

Only one action can run at a time. A rejected `begin` returns `false, reason`;
otherwise the first return is `true` after `complete` has been called.
`duration`, when supplied, must be a positive integer; `minigame` must be one
of kora_lib's supported game types; and `canCancel` must be boolean. kora_lib
validates these before calling `begin`, so malformed UI configuration cannot
issue a server token.
For progress-bar actions this includes the forwarded `disable` and `anim`
payloads, using the same validation as `Kora.progressbar.start`.
When `minigame` is set, `begin` may return a third value containing a proof
authorization; `Kora.actions.run` forwards it to `Kora.minigames.play`. Omitting it
keeps the action flow functional but the minigame result is proof-less.
The same authorization is included in the object passed to `complete`, so the
server completion handler can call `consumeProof` with both values.

## Server pattern for a valuable action

The action token is your resource's state, not a kora_lib capability. Create it
only after validating the initial request, consume it on every outcome, and
repeat live checks after the client UI completes. This keeps a player from
replaying a token, moving away during the UI, or substituting another player's
completion.

```lua
local pending = {}
local actionTtl = 30000

Kora.callback.register('my-resource:server:beginAction', function(src, stationId)
    if not isValidStation(stationId) or not isPlayerAtStation(src, stationId) then
        return nil, 'You are not at that station.'
    end

    local token = newPendingToken()
    local authorization = Kora.minigames.authorizeProof(src, 'mash', {
        attempts = 1,
        requiredPresses = 20,
    })
    local action = {
        src = src,
        stationId = stationId,
        authorization = authorization,
        expiresAt = GetGameTimer() + actionTtl,
    }
    pending[token] = action
    SetTimeout(actionTtl, function()
        if pending[token] == action then pending[token] = nil end
    end)
    return { actionToken = token, authorization = authorization }
end, { rateLimit = { max = 3, window = 10000 } })

RegisterNetEvent('my-resource:server:actionCompleted', function(stationId, token, completed, proof, authorization)
    local src = source
    if type(token) ~= 'string' or type(completed) ~= 'boolean' or type(authorization) ~= 'string' then return end
    local action = pending[token]
    pending[token] = nil -- consume it before any later validation can yield or fail

    if not action or action.expiresAt < GetGameTimer() then return end
    if action.src ~= src or action.stationId ~= stationId then return end
    if not completed or authorization ~= action.authorization then return end
    if not Kora.minigames.consumeProof(src, proof, 'mash', authorization) then return end
    if not isPlayerAtStation(src, stationId) or not playerHasRequiredItem(src) then return end

    grantStationReward(src)
end)

AddEventHandler('playerDropped', function()
    local src = source
    for token, action in pairs(pending) do
        if action.src == src then pending[token] = nil end
    end
end)
```

`newPendingToken`, `isValidStation`, `isPlayerAtStation`,
`playerHasRequiredItem`, and `grantStationReward` belong to the gameplay
resource. Keep that policy there: kora_lib supplies the proof and callback
boundary, but cannot know an individual resource's inventory, permission,
cooldown, ownership, or location rules.
The example's one-shot timeout and `playerDropped` cleanup keep abandoned
action records out of the server table without a permanent polling loop.

`Kora.actions.isActive()` reports whether this client currently has an action in
progress.
