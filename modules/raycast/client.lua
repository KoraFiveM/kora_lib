-- Plain { x, y, z } tables, not glm.vec3 -- the `glm` global isn't
-- guaranteed to exist on every FiveM client build, and this file never needs
-- vector-math operators (subtraction, scalar multiply, etc.), only field
-- access and construction, so there's nothing glm buys here.
local function toVec3(v)
    assert(v and QB.util.isFiniteNumber(v.x) and QB.util.isFiniteNumber(v.y) and QB.util.isFiniteNumber(v.z),
        "Coordinates must have finite x, y, and z values.")
    return { x = v.x, y = v.y, z = v.z }
end

local function assertDistance(maxDistance)
    assert(QB.util.isFiniteNumber(maxDistance) and maxDistance > 0,
        "Raycast maxDistance must be a positive finite number.")
end

local function assertInteger(value, name)
    assert(QB.util.isInteger(value), name .. " must be a finite integer.")
end

---@param rot table Euler angles in degrees, { x = pitch, y = roll, z = yaw } (GetGameplayCamRot's shape).
local function rotationToDirection(rot)
    local z = math.rad(rot.z)
    local x = math.rad(rot.x)
    local flatLength = math.abs(math.cos(x))

    return { x = -math.sin(z) * flatLength, y = math.cos(z) * flatLength, z = math.sin(x) }
end

-- Shape tests are asynchronous even though the public helper returns a
-- settled result. Reading once immediately after StartShapeTestRay can return
-- status 1 (pending); its other output slots are not valid yet and have been
-- observed to surface as stale entity handles. Keep the wait bounded so a
-- broken/invalid test can never strand its caller.
local SHAPE_TEST_TIMEOUT_MS = 1000
local COORD_GRABBER_CONTROLS = { 38, 174, 175, 177 }
local COORD_GRABBER_DISTANCE = 50.0
local COORD_GRABBER_ROTATION_SPEED = 60.0
local COORD_GRABBER_PREVIEW_ALPHA = 100

local activeCoordGrabber

local function awaitShapeTest(rayHandle)
    local deadline = GetGameTimer() + SHAPE_TEST_TIMEOUT_MS
    local status, hit, hitCoords, surfaceNormal, entityHit = GetShapeTestResult(rayHandle)

    while status == 1 and GetGameTimer() < deadline do
        Wait(0)
        status, hit, hitCoords, surfaceNormal, entityHit = GetShapeTestResult(rayHandle)
    end

    if status ~= 2 then return false, nil, nil, nil end
    if hit == 0 then return false, nil, nil, nil end
    return true, toVec3(hitCoords), entityHit, toVec3(surfaceNormal)
end

local function camDestination(camCoord, rot, maxDistance)
    local direction = rotationToDirection(rot)

    return {
        x = camCoord.x + direction.x * maxDistance,
        y = camCoord.y + direction.y * maxDistance,
        z = camCoord.z + direction.z * maxDistance,
    }
end

---Fires a world-geometry raycast between two points.
---@param startCoords table vector3-like { x, y, z }
---@param endCoords table vector3-like { x, y, z }
---@param flags? number `StartShapeTestRay` intersect flags; defaults to `-1` (everything).
---@param ignoreEntity? number Entity handle to exclude from the test; defaults to `PlayerPedId()`.
---@return boolean hit
---@return table? coords {x, y, z} table, only present when hit is true
---@return number? entityHit Entity handle the ray struck, only present when hit is true
---@return table? surfaceNormal {x, y, z} table, only present when hit is true
function QB.raycast.fromCoords(startCoords, endCoords, flags, ignoreEntity)
    return awaitShapeTest(QB.raycast.start(startCoords, endCoords, flags, ignoreEntity))
end

---Fires a shape test WITHOUT waiting for it, returning its raw handle for a
---later `QB.raycast.await`/`QB.raycast.poll`.
---
---Shape tests are resolved by the engine once per frame, so a caller that
---needs several rays in the same logical "look" (e.g. a targeting resource
---firing a broad world mask and a narrow entity mask) should start all of
---them first and await them afterwards. Awaiting each one before starting the
---next serialises them and costs one extra frame of latency per ray, plus one
---extra thread wake-up per ray, for no additional information.
---@param startCoords table vector3-like { x, y, z }
---@param endCoords table vector3-like { x, y, z }
---@param flags? number `StartShapeTestRay` intersect flags; defaults to `-1` (everything).
---@param ignoreEntity? number Entity handle to exclude from the test; defaults to `PlayerPedId()`.
---@return number rayHandle Pass to `QB.raycast.await` or `QB.raycast.poll`.
function QB.raycast.start(startCoords, endCoords, flags, ignoreEntity)
    startCoords = toVec3(startCoords)
    endCoords = toVec3(endCoords)
    if flags == nil then flags = -1 else assertInteger(flags, "Raycast flags") end
    if ignoreEntity == nil then ignoreEntity = PlayerPedId() else assertInteger(ignoreEntity, "Ignored entity") end

    return StartShapeTestRay(
        startCoords.x, startCoords.y, startCoords.z,
        endCoords.x, endCoords.y, endCoords.z,
        flags, ignoreEntity, 0
    )
end

---Starts a camera ray without waiting for it. See `QB.raycast.start`.
---@param maxDistance number
---@param flags? number
---@param ignoreEntity? number
---@return number rayHandle
function QB.raycast.startFromCamera(maxDistance, flags, ignoreEntity)
    assertDistance(maxDistance)
    local camCoord = toVec3(GetGameplayCamCoord())

    return QB.raycast.start(camCoord, camDestination(camCoord, GetGameplayCamRot(2), maxDistance), flags, ignoreEntity)
end

---Blocks (yielding a frame at a time, bounded to one second) until a handle
---from `QB.raycast.start`/`startFromCamera` has settled, then reports it in
---the same shape `fromCoords` returns. A handle that has already settled --
---because another ray started in the same frame was awaited first -- returns
---immediately without yielding at all.
---@param rayHandle number
---@return boolean hit
---@return table? coords
---@return number? entityHit
---@return table? surfaceNormal
function QB.raycast.await(rayHandle)
    assertInteger(rayHandle, "Raycast handle")
    return awaitShapeTest(rayHandle)
end

---Non-blocking read of a started shape test. `settled` is false while the
---engine is still resolving it; every other value is meaningless until it is
---true. Unlike `await` this never yields, so a caller driving its own tick
---loop can start a ray on one tick and consume it on the next without ever
---spending a frame parked inside qblib.
---@param rayHandle number
---@return boolean settled
---@return boolean hit
---@return table? coords
---@return number? entityHit
---@return table? surfaceNormal
function QB.raycast.poll(rayHandle)
    assertInteger(rayHandle, "Raycast handle")
    local status, hit, hitCoords, surfaceNormal, entityHit = GetShapeTestResult(rayHandle)
    if status == 1 then return false, false, nil, nil, nil end
    if status ~= 2 or hit == 0 then return true, false, nil, nil, nil end

    return true, true, toVec3(hitCoords), entityHit, toVec3(surfaceNormal)
end

---Aims from the gameplay camera and raycasts against world geometry, so
---"look at it" is enough to know what a player is aiming at -- no coordinate
---typing required.
---@param maxDistance number
---@param flags? number `StartShapeTestRay` intersect flags; defaults to `-1` (everything).
---@param ignoreEntity? number Entity handle to exclude from the test; defaults to `PlayerPedId()`.
---@return boolean hit
---@return table? coords {x, y, z} table, only present when hit is true
---@return number? entityHit Entity handle the ray struck, only present when hit is true
---@return table? surfaceNormal {x, y, z} table, only present when hit is true
function QB.raycast.fromCamera(maxDistance, flags, ignoreEntity)
    return awaitShapeTest(QB.raycast.startFromCamera(maxDistance, flags, ignoreEntity))
end

---Aims from a scripted camera and raycasts against world geometry, for a
---caller that manages its own camera (e.g. a freecam) instead of the
---gameplay camera.
---@param cam number Scripted camera handle, e.g. from `CreateCam`/`CreateCamWithParams`.
---@param maxDistance number
---@param flags? number `StartShapeTestRay` intersect flags; defaults to `-1` (everything).
---@param ignoreEntity? number Entity handle to exclude from the test; defaults to `PlayerPedId()`.
---@return boolean hit
---@return table? coords {x, y, z} table, only present when hit is true
---@return number? entityHit Entity handle the ray struck, only present when hit is true
---@return table? surfaceNormal {x, y, z} table, only present when hit is true
function QB.raycast.fromCam(cam, maxDistance, flags, ignoreEntity)
    assertInteger(cam, "Scripted camera handle")
    assertDistance(maxDistance)
    local camCoord = toVec3(GetCamCoord(cam))

    return QB.raycast.fromCoords(camCoord, camDestination(camCoord, GetCamRot(cam, 2), maxDistance), flags, ignoreEntity)
end

local function roundToTwoPlaces(value)
    return tonumber(("%.2f"):format(value))
end

local function removeEntity(ent)
    if not ent then return end

    local ok, result, err = pcall(QB.entities.remove, ent)
    if not ok or result == false then
    end

    if DoesEntityExist(ent) then
        SetEntityAsMissionEntity(ent, true, true)
        DeleteEntity(ent)
    end
end

local function releaseCoordGrabber(state)
    if state.released then return end
    state.released = true

    if activeCoordGrabber == state then activeCoordGrabber = nil end
    if state.controlLease then pcall(QB.compat.releaseControlLease, state.controlLease, state.owner) end
    if state.textui then pcall(QB.textui.hide, state.textui) end

    removeEntity(state.entity)
    state.entity = nil
end

local function coordGrabberResult(coords, heading, model)
    local resultCoords = {
        x = roundToTwoPlaces(coords.x),
        y = roundToTwoPlaces(coords.y),
        z = roundToTwoPlaces(coords.z),
    }

    if model then resultCoords.w = roundToTwoPlaces(heading) end

    return {
        coords = resultCoords,
        object = model or false,
    }
end

local function drawCoordMarker(coords)
    DrawMarker(28, coords.x, coords.y, coords.z,
        0.0, 0.0, 0.0, 0.0, 180.0, 0.0,
        0.1, 0.1, 0.1, 255, 255, 255, 255,
        false, true, 2, false, false, false, false)
end


local function runCoordGrabber(state)
    state.controlLease = QB.compat.acquireControls(COORD_GRABBER_CONTROLS, nil, state.owner)
    state.textui = QB.textui.show(state.model
        and "**Left / Right:** rotate  ·  **E:** confirm  ·  **Backspace:** cancel"
        or "**E:** confirm  ·  **Backspace:** cancel", {
        icon = state.model and "Box" or "Crosshair",
    }, state.owner)
    while activeCoordGrabber == state do
        local hit, coords = QB.raycast.fromCamera(state.maxDistance, state.flags,
            state.entity or state.playerPed)

        if hit and coords then
            if state.model then
                if not state.entity then
                    local ent, createErr = QB.entities.create(state.model, coords, {
                        preset = "static",
                        heading = state.heading,
                    })
                    assert(ent, createErr or "Failed to create coordinate preview.")

                    state.entity = ent
                    SetEntityCollision(ent, false, false)
                    SetEntityAlpha(ent, COORD_GRABBER_PREVIEW_ALPHA, false)
                else
                    SetEntityCoordsNoOffset(state.entity, coords.x, coords.y, coords.z, false, false, false)
                end

                if IsDisabledControlPressed(0, 174) then
                    state.heading = (state.heading - COORD_GRABBER_ROTATION_SPEED * GetFrameTime()) % 360.0
                elseif IsDisabledControlPressed(0, 175) then
                    state.heading = (state.heading + COORD_GRABBER_ROTATION_SPEED * GetFrameTime()) % 360.0
                end
                SetEntityHeading(state.entity, state.heading)
            else
                drawCoordMarker(coords)
            end

            if IsDisabledControlJustReleased(0, 38) then
                return coordGrabberResult(coords, state.heading, state.model)
            end
        end

        if IsDisabledControlJustReleased(0, 177) then
            return nil
        end
        Wait(0)
    end
    return nil
end

---Captures coordinates under the gameplay-camera crosshair. With no options,
---a small orb marks the current hit. Passing `{ type = "object", object = model }`
---uses a temporary heading-only prop preview instead. The preview is always
---removed; this function only returns where a future object could be created.
---@param data? { type?: 'object', object?: string|number, heading?: number, maxDistance?: number, flags?: number }
---@return { coords: { x: number, y: number, z: number, w?: number }, object: string|number|false }? result
function QB.raycast.getCoords(data)
    if data == nil then data = {} end
    assert(type(data) == "table", "Coordinate grabber options must be a table.")
    assert(data.type == nil or data.type == "object", "Coordinate grabber type must be 'object' when provided.")
    assert(data.type ~= "object" or type(data.object) == "string" or QB.util.isInteger(data.object),
        "Coordinate grabber object must be a model name or finite integer hash.")
    assert(data.heading == nil or QB.util.isFiniteNumber(data.heading),
        "Coordinate grabber heading must be a finite number.")
    assert(data.maxDistance == nil or QB.util.isFiniteNumber(data.maxDistance) and data.maxDistance > 0,
        "Coordinate grabber maxDistance must be a positive finite number.")
    assert(data.flags == nil or QB.util.isInteger(data.flags), "Coordinate grabber flags must be a finite integer.")
    assert(not activeCoordGrabber, "A coordinate grabber is already active.")

    local state = {
        owner = GetInvokingResource() or GetCurrentResourceName(),
        playerPed = PlayerPedId(),
        model = data.type == "object" and data.object or nil,
        heading = (data.heading or 180.0) % 360.0,
        maxDistance = data.maxDistance or COORD_GRABBER_DISTANCE,
        flags = data.flags,
    }
    activeCoordGrabber = state

    local ok, result = pcall(runCoordGrabber, state)
    releaseCoordGrabber(state)
    if not ok then error(result, 0) end
    return result
end

AddEventHandler("onClientResourceStop", function(resourceName)
    local state = activeCoordGrabber
    if state and (resourceName == state.owner or resourceName == GetCurrentResourceName()) then
        releaseCoordGrabber(state)
    end
end)
