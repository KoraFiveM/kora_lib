-- Plain { x, y, z } tables, not glm.vec3 -- the `glm` global isn't
-- guaranteed to exist on every FiveM client build, and this file never needs
-- vector-math operators (subtraction, scalar multiply, etc.), only field
-- access and construction, so there's nothing glm buys here.
local function toVec3(v)
    assert(type(v.x) == "number" and type(v.y) == "number" and type(v.z) == "number",
        "Coordinates must be a vector3, glm.vec3, or {x=,y=,z=} table.")
    return { x = v.x, y = v.y, z = v.z }
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
    flags = flags or -1
    ignoreEntity = ignoreEntity or PlayerPedId()

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
    local camCoord = toVec3(GetCamCoord(cam))

    return QB.raycast.fromCoords(camCoord, camDestination(camCoord, GetCamRot(cam, 2), maxDistance), flags, ignoreEntity)
end
