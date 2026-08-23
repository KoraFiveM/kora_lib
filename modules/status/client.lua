-- name -> {def, severity, expiresAt, rendered = {screenHandle?, ptfxHandle?, animEntity?}}
local active = {}
local changeListeners = {}
local nextListenerId = 0

local statusRegistry = QB.resources.registry(function(name)
    QB.status.remove(name)
end)

local listenerRegistry = QB.resources.registry(function(listenerId)
    changeListeners[listenerId] = nil
end)

local function reconcileMovement()
    local multiplier = 1.0
    for _, entry in pairs(active) do
        local movement = entry.def.movement
        if movement and movement.speedMultiplier then
            multiplier = multiplier * movement.speedMultiplier
        end
    end
    SetPedMoveRateOverride(PlayerPedId(), multiplier)
end

local function notifyChange(name, applied)
    for _, listener in pairs(changeListeners) do
        pcall(listener, name, applied)
    end
end

---Plays `def`'s fx/anim/movement on the local ped and returns everything
---needed to tear it back down again. A shallow per-call copy of `def.fx.ptfx`
---is built rather than passing the registered def's own table straight into
---QB.fx.playPtfx -- that function is documented to accept caller-owned option
---tables, and mutating the SAME table object every application (to default
---`entity`, force `looped = true`) would leak this call's ped/looped flag
---into the shared, registry-wide def for every future application.
---@param def QBStatusEffectDef
---@return table rendered
local function renderEffect(def)
    local ped = PlayerPedId()
    local rendered = {}

    if def.fx then
        if def.fx.screen then
            rendered.screenHandle = QB.fx.screenEffect(def.fx.screen, nil, true)
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

            local handle = QB.fx.playPtfx(ptfxCall)
            if handle then rendered.ptfxHandle = handle end
        end
    end

    if def.anim then
        local handle = QB.anim.play(ped, def.anim.dict, def.anim.clip)
        if handle then rendered.animHandle = handle end
    end

    if def.movement and def.movement.speedMultiplier then
        rendered.appliedMovement = true
    end

    return rendered
end

---@param rendered table
---@param def QBStatusEffectDef
local function clearRender(rendered, def)
    if rendered.screenHandle then QB.fx.stopScreenEffect(rendered.screenHandle) end
    if rendered.ptfxHandle then QB.fx.stop(rendered.ptfxHandle) end
    if rendered.animHandle then
        if QB.anim.stopHandle then QB.anim.stopHandle(rendered.animHandle)
        else QB.anim.stop(rendered.animHandle.entity) end
    end
end

---Applies a registered status effect locally: renders its fx/anim/movement
---and starts its expiry timer. Also reachable via a server-side
---`QB.status.apply(target, ...)` push -- this is the function that push
---dispatches into (see `QB.events.onPush` below), and is equally valid to
---call directly for a purely client-local effect that never needs
---server-side tracking.
---@param name string
---@param opts? QBStatusApplyOptions
---@return boolean success
function QB.status.apply(name, opts)
    local def = QB.status.getEffectDef(name)
    assert(def, ("Unknown status effect: %s"):format(name))

    local owner = GetInvokingResource() or GetCurrentResourceName()
    opts = opts or {}

    local existing = active[name]
    if existing then clearRender(existing.rendered, existing.def) end

    local duration = opts.duration or def.duration
    local expiresAt = duration and (GetGameTimer() + duration) or nil

    local severity = opts.severity
    if severity == nil then severity = existing and existing.severity end

    active[name] = {
        def = def,
        severity = severity,
        expiresAt = expiresAt,
        rendered = renderEffect(def),
    }
    statusRegistry.track(owner, name)
    reconcileMovement()

    notifyChange(name, true)

    if duration then
        CreateThread(function()
            Wait(duration)
            local current = active[name]
            -- Only remove if this is still the SAME application (not
            -- superseded by a later apply/remove in the meantime) and it's
            -- actually due -- a "replace" re-application resets expiresAt,
            -- which this check honors rather than removing early.
            if current and current.expiresAt and current.expiresAt <= GetGameTimer() then
                QB.status.remove(name)
            end
        end)
    end

    return true
end

---@param name string
---@return boolean removed False if `name` wasn't active.
function QB.status.remove(name)
    local entry = active[name]
    if not entry then return false end

    active[name] = nil
    statusRegistry.untrack(name)
    clearRender(entry.rendered, entry.def)
    reconcileMovement()
    notifyChange(name, false)

    return true
end

---@param name string
---@return boolean
function QB.status.isActive(name)
    return active[name] ~= nil
end

---@return QBStatusActiveEntry[]
function QB.status.getActive()
    local result = {}
    for name, entry in pairs(active) do
        result[#result + 1] = { name = name, severity = entry.severity, expiresAt = entry.expiresAt }
    end
    return result
end

---Registers a handler called every time a status effect is applied or
---removed, locally or via a server push. Automatically unregistered if the
---calling resource stops.
---@param handler fun(name: string, applied: boolean)
---@return integer listenerId Pass to QB.status.offChange to unregister.
function QB.status.onChange(handler)
    assert(type(handler) == "function", "QB.status.onChange requires a function.")
    local owner = GetInvokingResource() or GetCurrentResourceName()
    nextListenerId = nextListenerId + 1
    changeListeners[nextListenerId] = handler
    listenerRegistry.track(owner, nextListenerId)
    return nextListenerId
end

---@param listenerId integer
function QB.status.offChange(listenerId)
    changeListeners[listenerId] = nil
    listenerRegistry.untrack(listenerId)
end

QB.events.onPush("qblib:status:apply", function(name, opts)
    QB.status.apply(name, opts)
end)

QB.events.onPush("qblib:status:remove", function(name)
    QB.status.remove(name)
end)
