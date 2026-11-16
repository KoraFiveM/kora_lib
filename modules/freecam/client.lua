local active
local ownership

local isFinite = Kora.util.isFiniteNumber

local function copyCoords(value, label)
    assert((type(value) == 'table' or type(value) == 'vector3' or type(value) == 'vector4')
        and isFinite(value.x) and isFinite(value.y) and isFinite(value.z),
        KoraLang('Modules.Freecam.coords_invalid', label))
    return { x = value.x, y = value.y, z = value.z }
end

local function optionNumber(value, fallback, label, allowZero)
    value = value == nil and fallback or value
    assert(isFinite(value) and (allowZero and value >= 0 or value > 0),
        KoraLang('Modules.Freecam.number_invalid', label, allowZero and 'non-negative ' or 'positive '))
    return value
end

local function inBounds(state, coords)
    if state.maxDistance then
        local dx, dy, dz = coords.x - state.origin.x, coords.y - state.origin.y, coords.z - state.origin.z
        if dx * dx + dy * dy + dz * dz > state.maxDistance * state.maxDistance then return false end
    end
    return not state.zone or state.zone.contains(coords)
end

local function stop(state, immediate)
    if active ~= state then return false end
    active = nil
    ownership.untrack(state)
    Kora.compat.releaseControlLease(state.lease, state.owner)
    if state.frozen then
        FreezeEntityPosition(state.ped, false)
        local currentPed = PlayerPedId()
        if currentPed ~= state.ped then FreezeEntityPosition(currentPed, false) end
    end
    if immediate then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(state.cam, false)
    else
        RenderScriptCams(false, true, state.transitionMs, true, true)
        CreateThread(function()
            Wait(state.transitionMs)
            DestroyCam(state.cam, false)
        end)
    end
    return true
end

ownership = Kora.resources.registry(function(state)
    stop(state, true)
end)

local function makeHandle(state)
    return {
        stop = function() return stop(state, false) end,
        isActive = function() return active == state end,
        getCoords = function() return active == state and { x = state.coords.x, y = state.coords.y, z = state.coords.z } or nil end,
        getRotation = function() return active == state and { pitch = state.pitch, roll = 0.0, yaw = state.yaw } or nil end,
        getCamera = function() return active == state and state.cam or nil end,
        getMovementMode = function() return active == state and state.movementMode or nil end,
        setMovementMode = function(mode)
            assert(mode == 'camera' or mode == 'grid', KoraLang('Modules.Freecam.movement_mode_invalid'))
            if active ~= state then return false end
            state.movementMode = mode
            return true
        end,
        setFocus = function(coords)
            if active ~= state then return false end
            if coords == nil then
                state.focus = nil
            else
                state.focus = copyCoords(coords, 'focusCoords')
            end
            return true
        end,
    }
end

local function run(state)
    local ok, err = pcall(function()
        while active == state do
            local lookX, lookY = GetDisabledControlNormal(0, 1), GetDisabledControlNormal(0, 2)
            if state.focus then
                local dx, dy, dz = state.focus.x - state.coords.x, state.focus.y - state.coords.y, state.focus.z - state.coords.z
                state.yaw = math.deg(math.atan(-dx, dy)) % 360.0
                state.pitch = -math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy)))
            else
                state.yaw = (state.yaw - lookX * state.lookSensitivity) % 360.0
                state.pitch = math.max(-89.0, math.min(89.0, state.pitch - lookY * state.lookSensitivity))
            end
            local yaw, pitch = math.rad(state.yaw), math.rad(state.pitch)
            local flat = math.cos(pitch)
            local forward = { x = -math.sin(yaw) * flat, y = math.cos(yaw) * flat, z = math.sin(pitch) }
            local right = { x = math.cos(yaw), y = math.sin(yaw), z = 0.0 }
            local forwardBack, strafe = -GetDisabledControlNormal(0, 31), GetDisabledControlNormal(0, 30)
            local speed = state.moveSpeed * (IsControlPressed(0, 21) and state.fastMultiplier or 1) * GetFrameTime()
            local moveForward, moveRight = forwardBack * speed, strafe * speed
            local moveUp = 0.0
            if state.upControl and IsDisabledControlPressed(0, state.upControl) then moveUp = moveUp + speed end
            if state.downControl and IsDisabledControlPressed(0, state.downControl) then moveUp = moveUp - speed end
            local candidate = {
                x = state.coords.x + forward.x * moveForward + right.x * moveRight,
                y = state.coords.y + forward.y * moveForward + right.y * moveRight,
                z = state.coords.z + (state.movementMode == 'camera' and forward.z * moveForward or 0.0) + moveUp,
            }
            if state.movementMode == 'grid' then
                candidate.x = state.coords.x + moveRight
                candidate.y = state.coords.y + moveForward
            end
            if inBounds(state, candidate) then state.coords = candidate end
            SetCamCoord(state.cam, state.coords.x, state.coords.y, state.coords.z)
            SetCamRot(state.cam, state.pitch, 0.0, state.yaw, 2)
            Wait(0)
        end
    end)
    if not ok then
        Kora.logging.error('lib.client.stopped_after_an_error', KoraLang('Modules.Freecam.stopped_after_error', tostring(err)))
        stop(state, true)
    end
end

---@param options? KoraFreecamOptions
---@return KoraFreecamHandle|false, string?
function Kora.freecam.start(options)
    if active then return false, KoraLang('Modules.Freecam.already_active') end
    options = options or {}
    assert(type(options) == 'table', KoraLang('Modules.Freecam.options_invalid'))
    assert(options.maxDistance == nil or (isFinite(options.maxDistance) and options.maxDistance > 0), KoraLang('Modules.Freecam.max_distance_invalid'))
    assert(options.movementMode == nil or options.movementMode == 'camera' or options.movementMode == 'grid', KoraLang('Modules.Freecam.movement_mode_invalid'))
    assert(options.zone == nil or (type(options.zone) == 'table' and Kora.compat.isCallable(options.zone.contains)), KoraLang('Modules.Freecam.zone_invalid'))
    assert(options.freezePlayer == nil or type(options.freezePlayer) == 'boolean', KoraLang('Modules.Freecam.freeze_player_invalid'))
    assert(options.upControl == nil or Kora.util.isInteger(options.upControl) and options.upControl >= 0, KoraLang('Modules.Freecam.up_control_invalid'))
    assert(options.downControl == nil or Kora.util.isInteger(options.downControl) and options.downControl >= 0, KoraLang('Modules.Freecam.down_control_invalid'))
    local gameplayCoords, gameplayRot = GetGameplayCamCoord(), GetGameplayCamRot(2)
    local coords = options.coords and copyCoords(options.coords, 'coords') or copyCoords(gameplayCoords, 'gameplay coords')
    local rotation = options.rotation and copyCoords(options.rotation, 'rotation') or copyCoords(gameplayRot, 'gameplay rotation')
    local fov = options.fov or GetGameplayCamFov()
    assert(isFinite(fov) and fov >= 10.0 and fov <= 120.0, KoraLang('Modules.Freecam.fov_invalid'))
    local state = {
        coords = coords, origin = { x = coords.x, y = coords.y, z = coords.z }, pitch = rotation.x, yaw = rotation.z,
        maxDistance = options.maxDistance, zone = options.zone, focus = options.focusCoords and copyCoords(options.focusCoords, 'focusCoords') or nil,
        movementMode = options.movementMode or 'camera', ped = PlayerPedId(),
        owner = GetInvokingResource() or GetCurrentResourceName(),
        moveSpeed = optionNumber(options.moveSpeed, Config.freecam.cameraMoveSpeed, 'moveSpeed'),
        lookSensitivity = optionNumber(options.lookSensitivity, Config.freecam.cameraLookSensitivity, 'lookSensitivity'),
        fastMultiplier = optionNumber(options.fastMultiplier, Config.freecam.shiftMultiplier, 'fastMultiplier'),
        transitionMs = optionNumber(options.transitionMs, Config.freecam.cameraTransitionMs, 'transitionMs', true),
        upControl = options.upControl,
        downControl = options.downControl,
        freezePlayer = options.freezePlayer == nil and Config.freecam.freezePlayer ~= false or options.freezePlayer == true,
    }
    state.cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', coords.x, coords.y, coords.z, state.pitch, 0.0, state.yaw, fov, false, 0)
    assert(state.cam and state.cam ~= 0 and DoesCamExist(state.cam), KoraLang('Modules.Freecam.create_failed'))
    local controls = { 1, 2, 30, 31 }
    if state.upControl then controls[#controls + 1] = state.upControl end
    if state.downControl then controls[#controls + 1] = state.downControl end
    state.lease = Kora.compat.acquireControls(controls, nil, state.owner)
    if state.freezePlayer and not (IsPedFalling(state.ped) or IsPedJumping(state.ped) or IsPedRagdoll(state.ped)
        or IsEntityInAir(state.ped) or IsPedInParachuteFreeFall(state.ped)) then
        FreezeEntityPosition(state.ped, true)
        state.frozen = true
    end
    SetCamActive(state.cam, true)
    RenderScriptCams(true, true, state.transitionMs, true, true)
    active = state
    ownership.track(state.owner, state)
    CreateThread(function() run(state) end)
    return makeHandle(state)
end

---@return boolean
function Kora.freecam.isActive()
    return active ~= nil
end

AddEventHandler('onClientResourceStop', function(resource)
    if active and resource == GetCurrentResourceName() then stop(active, true) end
end)
