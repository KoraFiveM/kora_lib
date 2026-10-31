-- qbcore-framework/progressbar @ 6e9381de6637bd443a8eaf1a6da0d339d8cebb15.
-- Keep callbacks in the native bar's loop so there is only one timer/owner.
local active, manuallyBusy
local isCallable = Kora.compat.isCallable
local controls = {
    disableMovement = { 30, 31, 36, 21, 75 },
    disableCarMovement = { 63, 64, 71, 72 },
    disableMouse = { 1, 2, 106 },
    disableCombat = { 24, 25, 37, 47, 58, 140, 141, 142, 143, 263, 264, 257 },
}

local function release(session)
    if session.released then return end
    session.released = true
    for _, lease in ipairs(session.leases) do Kora.compat.releaseControlLease(lease, session.owner) end
    LocalPlayer.state:set('inv_busy', session.previousBusy == true, true)
    if active == session then active = nil end
end

local function start(action, onStart, onTick, onFinish, owner)
    onStart, onTick, onFinish = onStart or nil, onTick or nil, onFinish or nil
    if active or manuallyBusy or Kora.progressbar.isActive() then return end
    if type(action) ~= 'table' or (IsEntityDead(PlayerPedId()) and not action.useWhileDead) then return end
    for _, callback in pairs({ onStart = onStart, onTick = onTick, onFinish = onFinish }) do
        assert(isCallable(callback), 'Progressbar callbacks must be callable.')
    end
    local payload = {
        label = action.label == '' and ' ' or action.label,
        duration = action.duration == 0 and 1 or action.duration,
        maxDuration = false, canCancel = action.canCancel == true, cancelControls = { 200 },
        useWhileDead = action.useWhileDead == true,
        allowRagdoll = true, allowCuffed = true, allowFalling = true, allowSwimming = true,
        props = {},
    }
    local animation = action.animation
    if animation and animation.task then
        payload.scenario = { name = animation.task }
    elseif animation and animation.animDict and animation.anim then
        payload.anim = { dict = animation.animDict, clip = animation.anim, flag = animation.flags,
            blendIn = 3.0, blendOut = 3.0, stopBlendOut = 1.0 }
    end
    for _, prop in ipairs({ action.prop or {}, action.propTwo or {} }) do
        if prop.model then
            payload.props[#payload.props + 1] = { model = prop.model, bone = prop.bone,
                offset = prop.coords, rotation = prop.rotation, softPinning = true,
                collision = false, rotationOrder = 0, syncRotation = true }
        end
    end
    Kora.progressbar.validate(payload)
    local invoker = GetInvokingResource() or GetCurrentResourceName()
    -- Only the core may forward ownership across its additional export boundary.
    owner = invoker == 'kora_core' and owner or nil
    assert(owner == nil or (type(owner) == 'string' and owner ~= ''), 'Progressbar owner must be a resource name.')
    local session = { owner = owner or invoker, leases = {},
        previousBusy = LocalPlayer.state.inv_busy }
    active = session
    LocalPlayer.state:set('inv_busy', true, true)
    CreateThread(function()
        if session.stopped or session.released or active ~= session then return end
        if session.cancelRequested then
            release(session)
            if onFinish then onFinish(true) end
            return
        end
        local ok, completed = pcall(function()
            for name, list in pairs(controls) do
                if action.controlDisables and action.controlDisables[name] then
                    session.leases[#session.leases + 1] = Kora.compat.acquireControls(list,
                        name == 'disableCombat' and { disablePlayerFiring = true } or nil, session.owner)
                end
            end
            return Kora.progressbar.start(payload, session.owner, {
                networkedProps = true,
                onStart = onStart,
                onTick = onTick,
                isFinished = function() return session.finished == true end,
            })
        end)
        release(session)
        if not ok then print(('[kora_lib:progressbar] %s'):format(completed)) end
        if onFinish and not session.stopped then onFinish(not ok or completed ~= true) end
    end)
end

local function progress(action, finish, owner) start(action, nil, nil, finish, owner) end
local function withStart(action, begin, finish) start(action, begin, nil, finish) end
local function withTick(action, tick, finish) start(action, nil, tick, finish) end
local function withStartAndTick(action, begin, tick, finish) start(action, begin, tick, finish) end
local function isDoingSomething() return active ~= nil or manuallyBusy == true or Kora.progressbar.isActive() end

for name, callback in pairs({ Progress = progress, ProgressWithStartEvent = withStart,
    ProgressWithTickEvent = withTick, ProgressWithStartAndTick = withStartAndTick,
    isDoingSomething = isDoingSomething }) do
    Kora.compat.provideExport('progressbar', name, callback)
end
RegisterNetEvent('progressbar:client:progress', progress)
RegisterNetEvent('progressbar:client:ProgressWithStartEvent', withStart)
RegisterNetEvent('progressbar:client:ProgressWithTickEvent', withTick)
RegisterNetEvent('progressbar:client:ProgressWithStartAndTick', withStartAndTick)
RegisterNetEvent('progressbar:client:cancel', function()
    manuallyBusy = false
    if active then
        active.cancelRequested = true
        Kora.progressbar.cancel(active.owner)
    end
end)
RegisterNetEvent('progressbar:client:ToggleBusyness', function(value)
    manuallyBusy = value == true
    if not manuallyBusy and active then active.finished = true end
end)
AddEventHandler('onClientResourceStop', function(resource)
    if active and (resource == active.owner or resource == GetCurrentResourceName()) then
        active.stopped = true
        release(active)
    end
end)
