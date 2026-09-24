---@class QBTeleportOptions
---@field fade? boolean|number Fade around the move. `false` disables it; `true` and omitted use 500ms.

---@class QBWaypointTeleportOptions : QBTeleportOptions
---@field entity? number Entity to move. Defaults to the current vehicle when driving, otherwise the player ped.
---@field launchHeight? number Initial Z used while collision is loaded.
---@field collisionTimeout? integer Maximum milliseconds to wait for world collision.
---@field groundAttempts? integer Maximum ground probes.
---@field groundRetryDelay? integer Milliseconds between ground probes.

local function assertCoords(coords)
    assert(type(coords) == 'table' or type(coords) == 'vector3' or type(coords) == 'vector4',
        'Teleport coordinates must be vector-like.')
    assert(QB.util.isFiniteNumber(coords.x) and QB.util.isFiniteNumber(coords.y) and QB.util.isFiniteNumber(coords.z),
        'Teleport coordinates require finite x, y, and z.')
end

local function finiteOrDefault(value, default, label)
    if value == nil then return default end
    assert(QB.util.isFiniteNumber(value), ('%s must be a finite number.'):format(label))
    return value
end

---Moves an existing local entity to coordinates, optionally fading around the move.
---@param entity number
---@param coords vector3|vector4|{x:number,y:number,z:number,w?:number,heading?:number}
---@param opts? QBTeleportOptions
---@return boolean success
function QB.teleport.entity(entity, coords, opts)
    assert(QB.util.isInteger(entity) and entity > 0 and DoesEntityExist(entity), ('Invalid entity: %s'):format(entity))
    assertCoords(coords)
    assert(opts == nil or type(opts) == 'table', 'Teleport options must be a table.')
    opts = opts or {}
    assert(opts.fade == nil or opts.fade == false or opts.fade == true or QB.util.isFiniteNumber(opts.fade),
        'Teleport fade must be false, true, or a finite number.')
    local heading = coords.w
    if heading == nil then heading = coords.heading end
    if heading ~= nil then
        assert(QB.util.isFiniteNumber(heading), 'Teleport heading must be a finite number.')
    end

    local function move()
        SetEntityCoords(entity, coords.x, coords.y, coords.z)
        if type(heading) == 'number' then SetEntityHeading(entity, heading) end
    end

    local fade = opts.fade
    if fade ~= false then
        QB.visuals.fade(type(fade) == 'number' and fade or 500, move)
    else
        move()
    end
    return true
end

---Moves the local player ped. Equivalent to `QB.teleport.entity(QB.cache.ped(), ...)`.
---@param coords vector3|vector4|{x:number,y:number,z:number,w?:number,heading?:number}
---@param opts? QBTeleportOptions
---@return boolean success
function QB.teleport.player(coords, opts)
    return QB.teleport.entity(QB.cache.ped(), coords, opts)
end

local function waypointEntity(options)
    if options.entity ~= nil then return options.entity end
    local vehicle = QB.cache.vehicle()
    if vehicle and QB.cache.seat() == -1 then return vehicle end
    return QB.cache.ped()
end

---Moves the player (or their driven vehicle) to the active map waypoint.
---Every failure restores the original position and the cleanup path always
---unfreezes the entity, clears streaming focus, and fades the display back in.
---@param opts? QBWaypointTeleportOptions
---@return boolean success
---@return string? error
function QB.teleport.toWaypoint(opts)
    assert(opts == nil or type(opts) == 'table', 'Waypoint teleport options must be a table.')
    opts = opts or {}
    assert(opts.fade == nil or opts.fade == false or opts.fade == true or QB.util.isFiniteNumber(opts.fade),
        'Waypoint teleport fade must be false, true, or a finite number.')

    local waypoint, waypointError = QB.world.getWaypointCoords()
    if not waypoint then return false, waypointError end

    local entity = waypointEntity(opts)
    if not QB.util.isInteger(entity) or entity <= 0 or not DoesEntityExist(entity) then
        return false, ('Invalid teleport entity: %s'):format(tostring(entity))
    end

    local launchHeight = finiteOrDefault(opts.launchHeight, Config.teleport.waypointLaunchHeight, 'launchHeight')
    local collisionTimeout = math.max(0, math.floor(finiteOrDefault(opts.collisionTimeout,
        Config.teleport.waypointCollisionTimeout, 'collisionTimeout')))
    local groundAttempts = math.floor(finiteOrDefault(opts.groundAttempts,
        Config.teleport.waypointGroundAttempts, 'groundAttempts'))
    local groundRetryDelay = math.max(0, math.floor(finiteOrDefault(opts.groundRetryDelay,
        Config.teleport.waypointGroundRetryDelay, 'groundRetryDelay')))
    if groundAttempts < 1 then return false, 'groundAttempts must be a positive integer.' end

    local original = GetEntityCoords(entity)
    original = { x = original.x, y = original.y, z = original.z }
    local originalHeading = GetEntityHeading(entity)
    local moved = false
    local frozen = false
    local focused = false
    local faded = false
    local fade = opts.fade
    local fadeTime = type(fade) == 'number' and math.max(0, math.floor(finiteOrDefault(fade, 0, 'fade')))
        or Config.teleport.fadeTime

    local success, failure
    local ok, runtimeError = pcall(function()
        if fade ~= false then
            DoScreenFadeOut(fadeTime)
            faded = true
            local fadeDeadline = GetGameTimer() + fadeTime + 1000
            while not IsScreenFadedOut() and GetGameTimer() < fadeDeadline do Wait(10) end
        end

        FreezeEntityPosition(entity, true)
        frozen = true
        moved = true
        SetEntityCoords(entity, waypoint.x, waypoint.y, launchHeight)

        if SetFocusPosAndVel then
            SetFocusPosAndVel(waypoint.x, waypoint.y, launchHeight, 0.0, 0.0, 0.0)
            focused = true
        end
        RequestCollisionAtCoord(waypoint.x, waypoint.y, launchHeight)

        local collisionDeadline = GetGameTimer() + collisionTimeout
        while IsEntityWaitingForWorldCollision(entity) and GetGameTimer() < collisionDeadline do
            RequestCollisionAtCoord(waypoint.x, waypoint.y, launchHeight)
            Wait(10)
        end

        if IsEntityWaitingForWorldCollision(entity) then
            failure = ('World collision did not load within %dms.'):format(collisionTimeout)
            return
        end

        local ground, groundError = QB.world.getGroundCoords(waypoint, {
            height = launchHeight,
            attempts = groundAttempts,
            retryDelay = groundRetryDelay,
        })
        if not ground then
            failure = groundError
            return
        end

        SetEntityCoords(entity, ground.x, ground.y, ground.z)
        success = true
    end)

    if not ok then failure = tostring(runtimeError) end

    if not success and moved then
        local restored, restoreError = pcall(function()
            SetEntityCoords(entity, original.x, original.y, original.z)
            SetEntityHeading(entity, originalHeading)
        end)
        if not restored then
            failure = ('%s (failed to restore origin: %s)'):format(failure or 'Teleport failed.', tostring(restoreError))
        end
    end

    if focused and ClearFocus then pcall(ClearFocus) end
    if frozen then pcall(FreezeEntityPosition, entity, false) end
    if faded then pcall(DoScreenFadeIn, fadeTime) end

    if success then return true end
    return false, failure or 'Waypoint teleport failed.'
end
