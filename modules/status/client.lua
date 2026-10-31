-- name -> {def, severity, expiresAt, rendered = {screenHandle?, ptfxHandle?, animEntity?}}
local active = {}
local changeListeners = {}
local nextListenerId = 0
local movementMultiplier = 1.0
local movementLoopRunning = false
local isInteger = Kora.util.isInteger

-- The private bootstrap helper normalizes native functions and every Cfx
-- cross-resource funcref proxy shape consistently across kora_lib modules.
local isCallable = Kora.compat.isCallable

local statusRegistry = Kora.resources.registry(function(name)
    Kora.status.remove(name)
end)

local listenerRegistry = Kora.resources.registry(function(listenerId)
    changeListeners[listenerId] = nil
end)

local function startMovementLoop()
    if movementLoopRunning or movementMultiplier == 1.0 then return end

    movementLoopRunning = true
    CreateThread(function()
        while movementMultiplier ~= 1.0 do
            SetPedMoveRateOverride(PlayerPedId(), movementMultiplier)
            Wait(0)
        end
        movementLoopRunning = false
    end)
end

local function reconcileMovement()
    movementMultiplier = 1.0
    for _, entry in pairs(active) do
        local movement = entry.def.movement
        if movement and movement.speedMultiplier then
            movementMultiplier = movementMultiplier * movement.speedMultiplier
        end
    end
    SetPedMoveRateOverride(PlayerPedId(), movementMultiplier)
    startMovementLoop()
end

local function notifyChange(name, applied)
    for _, listener in pairs(changeListeners) do
        pcall(listener, name, applied)
    end
end

---Plays `def`'s fx/anim/movement on the local ped and returns everything
---needed to tear it back down again. A shallow per-call copy of `def.fx.ptfx`
---is built rather than passing the registered def's own table straight into
---Kora.fx.playPtfx -- that function is documented to accept caller-owned option
---tables, and mutating the SAME table object every application (to default
---`entity`, force `looped = true`) would leak this call's ped/looped flag
---into the shared, registry-wide def for every future application.
---@param def QBStatusEffectDef
---@return table rendered
local clearRender

local function renderEffect(def)
    local ped = PlayerPedId()
    local rendered = {}

    local ok, err = pcall(function()
        if def.fx then
            if def.fx.screen then
                rendered.screenHandle = Kora.fx.screenEffect(def.fx.screen, nil, true)
            end

            if def.fx.ptfx then
                local src = def.fx.ptfx
                local ptfxCall = {
                    dict = src.dict, name = src.name, bone = src.bone,
                    entity = src.entity, coords = src.coords,
                    offset = src.offset, rot = src.rot, scale = src.scale,
                    looped = true,
                }
                if not ptfxCall.entity and not ptfxCall.coords then ptfxCall.entity = ped end

                local handle = Kora.fx.playPtfx(ptfxCall)
                if handle then rendered.ptfxHandle = handle end
            end
        end

        if def.anim then
            local handle = Kora.anim.play(ped, def.anim.dict, def.anim.clip)
            if handle then rendered.animHandle = handle end
        end

        if def.movement and def.movement.speedMultiplier then
            rendered.appliedMovement = true
        end
    end)
    if not ok then
        clearRender(rendered, def)
        error(err, 0)
    end

    return rendered
end

---@param rendered table
---@param def QBStatusEffectDef
clearRender = function(rendered, def)
    if rendered.screenHandle then Kora.fx.stopScreenEffect(rendered.screenHandle) end
    if rendered.ptfxHandle then Kora.fx.stop(rendered.ptfxHandle) end
    if rendered.animHandle then
        if Kora.anim.stopHandle then Kora.anim.stopHandle(rendered.animHandle)
        else Kora.anim.stop(rendered.animHandle.entity) end
    end
end

local function dropActive(name, entry)
    active[name] = nil
    statusRegistry.untrack(name)
    clearRender(entry.rendered, entry.def)
end

---Applies a registered status effect locally: renders its fx/anim/movement
---and starts its expiry timer. Also reachable via a server-side
---`Kora.status.apply(target, ...)` push -- this is the function that push
---dispatches into (see `Kora.events.onPush` below), and is equally valid to
---call directly for a purely client-local effect that never needs
---server-side tracking.
---@param name string
---@param opts? QBStatusApplyOptions
---@return boolean success
function Kora.status.apply(name, opts)
    Kora.status.assertName(name)
    assert(opts == nil or type(opts) == "table", "Kora.status.apply options must be a table.")
    opts = opts or {}
    assert(opts.duration == nil or (isInteger(opts.duration) and opts.duration >= 0),
        "duration must be a non-negative integer.")
    assert(opts.severity == nil or (isInteger(opts.severity) and opts.severity >= 1),
        "severity must be a positive integer.")

    local def = Kora.status.getEffectDef(name)
    assert(def, ("Unknown status effect: %s"):format(name))

    local invokingResource = GetInvokingResource()
    local owner = invokingResource or GetCurrentResourceName()

    local existing = active[name]
    local now = GetGameTimer()
    if existing and existing.expiresAt and existing.expiresAt <= now then
        clearRender(existing.rendered, existing.def)
        active[name] = nil
        statusRegistry.untrack(name)
        existing = nil
    end
    if existing and invokingResource and statusRegistry.owner(name) ~= owner then return false end
    if existing then clearRender(existing.rendered, existing.def) end

    local stacking = def.stacking or "replace"
    local appliedDuration = opts.duration or def.duration
    local expiresAt
    if appliedDuration then
        if stacking == "extend" and existing and existing.expiresAt then
            expiresAt = existing.expiresAt + appliedDuration
        else
            expiresAt = now + appliedDuration
        end
    end
    local remainingDuration = expiresAt and math.max(0, expiresAt - now) or nil

    local severity = def.severityLevels and opts.severity or nil
    if severity == nil then severity = existing and existing.severity end
    if severity ~= nil and stacking == "stack" and existing and existing.severity then
        severity = math.min(def.severityLevels, existing.severity + severity)
    end

    active[name] = {
        def = def,
        severity = severity,
        expiresAt = expiresAt,
        rendered = renderEffect(def),
    }
    statusRegistry.track(owner, name)
    reconcileMovement()

    notifyChange(name, true)

    if remainingDuration then
        CreateThread(function()
            Wait(remainingDuration)
            local current = active[name]
            -- Only remove if this is still the SAME application (not
            -- superseded by a later apply/remove in the meantime) and it's
            -- actually due -- a "replace" re-application resets expiresAt,
            -- which this check honors rather than removing early.
            if current and current.expiresAt and current.expiresAt <= GetGameTimer() then
                Kora.status.remove(name)
            end
        end)
    end

    return true
end

---@param name string
---@return boolean removed False if `name` wasn't active.
local function removeStatus(name, owner)
    local entry = active[name]
    if not entry then return false end
    if owner and statusRegistry.owner(name) ~= owner then return false end

    dropActive(name, entry)
    reconcileMovement()
    notifyChange(name, false)

    return true
end

---@param name string
---@return boolean removed False if `name` wasn't active or is owned by another resource.
function Kora.status.remove(name)
    Kora.status.assertName(name)
    return removeStatus(name, GetInvokingResource())
end

---@param name string
---@return boolean
function Kora.status.isActive(name)
    Kora.status.assertName(name)
    local entry = active[name]
    if not entry then return false end
    if entry.expiresAt and entry.expiresAt <= GetGameTimer() then
        removeStatus(name)
        return false
    end
    return true
end

---@return QBStatusActiveEntry[]
function Kora.status.getActive()
    local result = {}
    local expired = {}
    local now = GetGameTimer()
    for name, entry in pairs(active) do
        if entry.expiresAt and entry.expiresAt <= now then
            expired[#expired + 1] = { name = name, entry = entry }
        else
            result[#result + 1] = { name = name, severity = entry.severity, expiresAt = entry.expiresAt }
        end
    end
    for index = 1, #expired do
        local entry = expired[index]
        dropActive(entry.name, entry.entry)
    end
    if #expired > 0 then
        reconcileMovement()
        for index = 1, #expired do notifyChange(expired[index].name, false) end
    end
    return result
end

---Registers a handler called every time a status effect is applied or
---removed, locally or via a server push. Automatically unregistered if the
---calling resource stops.
---@param handler fun(name: string, applied: boolean)
---@return integer listenerId Pass to Kora.status.offChange to unregister.
function Kora.status.onChange(handler)
    assert(isCallable(handler), "Kora.status.onChange requires a function.")
    local owner = GetInvokingResource() or GetCurrentResourceName()
    nextListenerId = nextListenerId + 1
    changeListeners[nextListenerId] = handler
    listenerRegistry.track(owner, nextListenerId)
    return nextListenerId
end

---@param listenerId integer
---@return boolean removed
function Kora.status.offChange(listenerId)
    local invoker = GetInvokingResource()
    if invoker and listenerRegistry.owner(listenerId) ~= invoker then return false end

    changeListeners[listenerId] = nil
    listenerRegistry.untrack(listenerId)
    return true
end

Kora.events.onPush("kora_lib:status:apply", function(name, opts)
    Kora.status.apply(name, opts)
end)

Kora.events.onPush("kora_lib:status:remove", function(name)
    Kora.status.remove(name)
end)
