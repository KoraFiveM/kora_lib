---@class QBActionsOptions
---@field begin fun(...): any, string?, string? Starts the server-authorized action and returns an opaque action token, optional failure reason, and optional minigame proof authorization.
---@field complete fun(result: {token: any, completed: boolean, proof?: string, authorization?: string}, ...): any Reports the UX result to the owning resource.
---@field label string
---@field duration? integer
---@field minigame? string
---@field canCancel? boolean
---@field disable? QBProgressBarDisable
---@field anim? QBProgressBarAnim

local active = false

local isCallable = QB.compat.isCallable

-- QB.minigames.play returns a promise to same-resource callers, but settles
-- that promise before returning across a real exports boundary because Cfx
-- cannot faithfully marshal a promise's state. Accept both shapes so actions
-- compose correctly whether they are called inside qblib or by another
-- resource through exports.
local function awaitIfPromise(value)
    if type(value) ~= 'table' or not isCallable(value.next) then return value end
    return Citizen.Await(value)
end

---Runs one server-authorized player action. `begin` and `complete` are kept
---resource-owned so the library never defines a resource's security contract;
---it only owns the exclusive progressbar/minigame UX in between them.
---@param options QBActionsOptions
---@param ... any Values forwarded unchanged to `begin` and `complete`.
---@return boolean started False when another action is already active or begin declined.
---@return any result The value returned by `complete`, or the begin failure reason.
function QB.actions.run(options, ...)
    assert(type(options) == 'table', 'QB.actions.run requires an options table.')
    assert(isCallable(options.begin), 'QB.actions.run requires a begin function.')
    assert(isCallable(options.complete), 'QB.actions.run requires a complete function.')
    assert(type(options.label) == 'string' and #options.label > 0, 'QB.actions.run requires a label.')

    if active then return false, 'Another action is already active.' end
    active = true

    local args = { ... }
    local token, authorization
    local began, completionAttempted = false, false
    local ok, started, result = pcall(function()
        local beginErr
        token, beginErr, authorization = options.begin(table.unpack(args))
        if not token then return false, beginErr end
        began = true

        local uxCompleted, proof
        if options.minigame then
            local minigame = awaitIfPromise(QB.minigames.play(options.minigame,
                { duration = options.duration }, authorization))
            uxCompleted = minigame and minigame.success == true
            proof = uxCompleted and minigame.proof or nil
        else
            uxCompleted = QB.progressbar.start({
                label = options.label,
                duration = options.duration or 5000,
                canCancel = options.canCancel ~= false,
                disable = options.disable,
                anim = options.anim,
            })
        end

        completionAttempted = true
        return true, options.complete({
            token = token,
            completed = uxCompleted == true,
            proof = proof,
            authorization = authorization,
        }, table.unpack(args))
    end)

    active = false
    if not ok then
        if began and not completionAttempted then
            local abortOk, abortErr = pcall(options.complete, {
                token = token,
                completed = false,
                authorization = authorization,
            }, table.unpack(args))
            if not abortOk then
                print(('^1[qblib:actions]^7 action abort callback failed: %s'):format(tostring(abortErr)))
            end
        end
        error(started, 0)
    end
    return started, result
end

---@return boolean
function QB.actions.isActive()
    return active
end
