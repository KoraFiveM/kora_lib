---@class QBActionsOptions
---@field begin fun(...): any, string? Starts the server-authorized action and returns an opaque token or `nil, reason`.
---@field complete fun(result: {token: any, completed: boolean, proof?: string}, ...): any Reports the UX result to the owning resource.
---@field label string
---@field duration? integer
---@field minigame? string
---@field canCancel? boolean
---@field disable? QBProgressBarDisable
---@field anim? QBProgressBarAnim

local active = false

local function isCallable(value)
    if type(value) == 'function' then return true end
    local mt = type(value) == 'table' and getmetatable(value) or nil
    return mt ~= nil and mt.__call ~= nil
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
    local ok, started, result = pcall(function()
        local token, beginErr = options.begin(table.unpack(args))
        if not token then return false, beginErr end

        local completed, proof
        if options.minigame then
            local minigame = Citizen.Await(QB.minigames.play(options.minigame, { duration = options.duration }))
            completed = minigame and minigame.success == true
            proof = completed and minigame.proof or nil
        else
            completed = QB.progressbar.start({
                label = options.label,
                duration = options.duration or 5000,
                canCancel = options.canCancel ~= false,
                disable = options.disable,
                anim = options.anim,
            })
        end

        return true, options.complete({ token = token, completed = completed == true, proof = proof }, table.unpack(args))
    end)

    active = false
    if not ok then error(started, 0) end
    return started, result
end

---@return boolean
function QB.actions.isActive()
    return active
end
