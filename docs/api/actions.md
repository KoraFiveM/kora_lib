---
title: "Actions"
sidebar_position: 38
---


# Actions

Use Kora.actions.run when an activity needs a progress bar or minigame and a clear start-to-finish result. Your resource still decides who may start, whether they are close enough, and whether they earn a reward.

Namespace: `Kora.actions` · Source: `modules/actions/client.lua`

## How it works

Kora.actions.run manages one client interaction from start to finish. It checks the display settings, asks your begin callback to request approval, shows the progress bar or minigame, and calls complete with the result. Your resource still owns the gameplay rules: the library does not decide who may act or grant a reward. If the interface errors after begin succeeds, the library tries to report an unsuccessful result before it rethrows the original error.

## Follow these steps

1. **Check whether the action is allowed** — In your resource, ask the server to check the player, target, distance, inventory, and cooldown. Do this before showing the progress bar or minigame.
2. **Have the server start the action** — The begin callback should contact your server. If the request is allowed, the server creates a short-lived action token and returns it. If it is not allowed, return nil and a message; the interface will not start.
3. **Show the player what is happening** — Kora.actions.run displays a progress bar by default. Set minigame to use a Kora minigame instead. When the minigame must be verified by the server, have the server also issue a proof authorization and return it from begin.
4. **Send the result back to your server** — The complete callback receives the action token and whether the player completed the interface. Send that report to your server; never award an item or make a protected change from the client report alone.
5. **Check again, then finish the action** — Your server should confirm the token belongs to this player and action, has not expired or been used, and that live rules still pass. Then consume the token once and apply the repair, payment, reward, or other change.

## Terms used on this page

| Term | Meaning |
| --- | --- |
| Action token | A short-lived, one-use value your server creates when it approves an action. It lets your server match the later completion report to the approved start. |
| Proof authorization | A server-created permission for a specific minigame attempt and its trusted settings. The server can use the proof returned by that attempt when deciding whether to accept completion. |
| Client report | Information sent by the player’s game about what happened in the interface. A modified client can lie, so the server must verify the action before changing money, inventory, or other important data. |

## run options table

Required callback and label fields are followed by optional UI settings. For progressbar actions, disable and anim use the same validation and payload format as Kora.progressbar.start. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `begin` | function | Required. Called as begin(...args) after settings pass validation. Return a one-use token, an optional message, and optionally a server-issued minigame authorization. Return nil or false as the token to stop before showing the UI. |
| `complete` | function | Required. Called once after a normal success or cancellation as complete(result, ...args). The result contains the token and completed boolean, plus minigame proof/authorization when available. |
| `label` | string | Required non-empty label used by the progressbar. |
| `duration??` | integer | Positive whole milliseconds. Progressbar default is 5000; for minigames the duration is passed to that game. |
| `minigame??` | string | Supported Kora.minigames game type. When omitted, a progressbar is used. |
| `canCancel??` | boolean | Progressbar cancellation setting; defaults to true. |
| `disable??` | table | Progressbar control-disable settings. |
| `anim??` | table | Progressbar animation settings. |

## Security boundary

Your server should create and store the action token. Tie it to the player and the specific action, give it an expiry, and accept it only once. When the player reports completion, check the token and recheck live conditions such as distance, inventory, and permissions before changing anything. A client can send a false completion report.

## Minigame proof

For a minigame that must count as proof, the server creates an authorization for the exact game and trusted settings. Return that value as the third result from begin. Kora.actions passes it to Kora.minigames.play and includes it with the completion result. Without this authorization, the minigame can still show a result to the player, but the server cannot treat that result as verified proof.

## Functions

Use run to wrap a server-authorized action in player feedback. Use isActive to guard related UI or display state.

### `Kora.actions.run(options, ...args)`

Checks the action settings, calls begin to request approval, shows a progress bar or minigame, then calls complete with the result. Extra arguments are passed to both callbacks.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `options` | table | Required action configuration. |
| `...args` | any | Optional context values forwarded to begin(...) and complete(result, ...). |

**Returns**

- **started** — boolean; false if another action is active or begin returned no token.
- **result** — complete callback result, or the begin failure reason.

**Example**

```lua
local started, result = Kora.actions.run({
    label = 'Repairing engine',
    duration = 8000,
    canCancel = true,
    disable = { move = true, combat = true },
    begin = function(vehicleNetId)
        local response = Kora.callback.trigger('mechanic:server:beginRepair', vehicleNetId)
        if not response then return nil, 'Repair was rejected.' end
        return response.token
    end,
    complete = function(action, vehicleNetId)
        TriggerServerEvent('mechanic:server:finishRepair', vehicleNetId, action.token, action.completed)
    end,
}, vehicleNetId)
```

**Representative console output**

```text
Returns true after complete is called; the server still decides whether the reported action is valid.
```

### `Kora.actions.isActive()`

Reports whether this client is currently between action begin and completion.

**Parameters**



**Returns**

- **active** — boolean.

**Example**

```lua
if Kora.actions.isActive() then return end
```

**Representative console output**

```text
Returns true only while Kora.actions.run is executing its asynchronous UI flow.
```

## Limits and related APIs

duration must be a positive integer when set; minigame must be supported; canCancel must be boolean. Malformed progressbar settings are rejected before begin runs, preventing a bad UI payload from creating a server token.

## Related guides

- [Progressbar: activity bars](./progressbar.md)
- [Minigames: verified skill checks](./minigames.md)
- [Permissions: access checks](./permissions.md)
- [Rewards: reward helpers](./rewards.md)

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/actions/docs.md` or `local/actions/docs.md`) that the reference above does not state.

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

### Server pattern for a valuable action

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
