local active = false

local isCallable = Kora.compat.isCallable

local function isPositiveInteger(value)
    return type(value) == 'number' and value == value and value < math.huge and value > 0 and value % 1 == 0
end

---Runs one server-authorized player action. `begin` and `complete` are kept
---resource-owned so the library never defines a resource's security contract;
---it only owns the exclusive progressbar/minigame UX in between them.
---@param options KoraActionsOptions
---@param ... any Values forwarded unchanged to `begin` and `complete`.
---@return boolean started False when another action is already active or begin declined.
---@return any result The value returned by `complete`, or the begin failure reason.
function Kora.actions.run(options, ...)
    assert(type(options) == 'table', KoraLang('Modules.Actions.options_table'))
    assert(isCallable(options.begin), KoraLang('Modules.Actions.begin_function'))
    assert(isCallable(options.complete), KoraLang('Modules.Actions.complete_function'))
    assert(type(options.label) == 'string' and #options.label > 0, KoraLang('Modules.Actions.label_required'))
    assert(options.duration == nil or isPositiveInteger(options.duration),
        KoraLang('Modules.Actions.duration_positive_integer'))
    assert(options.minigame == nil or type(options.minigame) == 'string'
        and Kora.minigames.GAME_TYPES[options.minigame],
        KoraLang('Modules.Actions.minigame_unsupported'))
    assert(options.canCancel == nil or type(options.canCancel) == 'boolean',
        KoraLang('Modules.Actions.can_cancel_boolean'))

    local progressPayload
    if not options.minigame then
        progressPayload = {
            label = options.label,
            duration = options.duration == nil and 5000 or options.duration,
            canCancel = options.canCancel ~= false,
            disable = options.disable,
            anim = options.anim,
        }
        Kora.progressbar.validate(progressPayload)
    end

    if active then return false, KoraLang('Modules.Actions.already_active') end
    active = true

    local args = table.pack(...)
    local token, authorization
    local began, completionAttempted = false, false
    local ok, started, result = pcall(function()
        local beginErr
        token, beginErr, authorization = options.begin(table.unpack(args, 1, args.n))
        if not token then return false, beginErr end
        began = true

        local uxCompleted, proof
        if options.minigame then
            local minigame = Kora.minigames.play(options.minigame,
                { duration = options.duration }, authorization)
            uxCompleted = minigame and minigame.success == true
            proof = uxCompleted and minigame.proof or nil
        else
            uxCompleted = Kora.progressbar.start(progressPayload)
        end

        completionAttempted = true
        return true, options.complete({
            token = token,
            completed = uxCompleted == true,
            proof = proof,
            authorization = authorization,
        }, table.unpack(args, 1, args.n))
    end)

    active = false
    if not ok then
        if began and not completionAttempted then
            local abortOk, abortErr = pcall(options.complete, {
                token = token,
                completed = false,
                authorization = authorization,
            }, table.unpack(args, 1, args.n))
            if not abortOk then
                Kora.logging.error('lib.client.action_abort_callback_failed', KoraLang(
                    'Modules.Actions.abort_callback_failed', tostring(abortErr)))
            end
        end
        error(started, 0)
    end
    return started, result
end

---@return boolean
function Kora.actions.isActive()
    return active
end
