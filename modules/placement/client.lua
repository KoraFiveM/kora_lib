---@class QBPlacementRotation
---@field pitch number Rotation around X, in degrees.
---@field roll number Rotation around Y, in degrees.
---@field yaw number Rotation around Z, in degrees.

---@class QBPlacementResult
---@field model string | number Original model name/hash passed to `QB.placement.start`.
---@field coords {x: number, y: number, z: number}
---@field heading number Native entity heading, read independently from Euler yaw.
---@field rotation QBPlacementRotation

local ROTATION_ORDER = 2
local ROTATION_AXES = { "yaw", "pitch", "roll" }
local PLACEMENT_CONTROLS = {
    1, 2, 30, 31,       -- mouse look + WASD, read back through GetDisabledControlNormal
    172, 173, 174, 175, -- cellphone arrows
    187, 188, 189, 190, -- frontend arrows
    207, 208,           -- frontend Page Down / Page Up
    312, 313,           -- replay [ / ]
    191, 192,           -- Enter / Tab
    73,                 -- X
}

local activeState = nil
local startingState = nil
local teardownState = nil
local held = {}
local bindingHandles = {}

local function placementLog(message)
    print(("[qblib:placement] %s"):format(message))
end

local function plainVec3(value)
    return { x = value.x, y = value.y, z = value.z }
end

local function assertVec3(value, label)
    assert(type(value) == "table" or type(value) == "vector3", ("%s must be vector-like."):format(label))
    assert(type(value.x) == "number" and type(value.y) == "number" and type(value.z) == "number",
        ("%s must contain numeric x, y, and z values."):format(label))
end

local function normalizeSignedAngle(value)
    return (value + 180.0) % 360.0 - 180.0
end

local function formatNumber(value)
    return ("%.4f"):format(value)
end

local function quoteLuaString(value)
    value = value
        :gsub("\\", "\\\\")
        :gsub("'", "\\'")
        :gsub("\r", "\\r")
        :gsub("\n", "\\n")
    return "'" .. value .. "'"
end

local function formatModel(model)
    if type(model) == "string" then return quoteLuaString(model) end
    return tostring(model)
end

---Formats a placement result into a ready-to-paste Lua table. The public
---result retains full precision; only this copied representation is rounded.
---@param result QBPlacementResult
---@return string
function QB.placement.generateSnippet(result)
    assert(type(result) == "table", "Placement result must be a table.")
    assert(type(result.model) == "string" or type(result.model) == "number",
        "Placement result model must be a string or number.")
    assertVec3(result.coords, "Placement result coords")
    assert(type(result.heading) == "number", "Placement result heading must be a number.")
    assert(type(result.rotation) == "table", "Placement result rotation must be a table.")
    assert(type(result.rotation.pitch) == "number" and type(result.rotation.roll) == "number"
        and type(result.rotation.yaw) == "number",
        "Placement result rotation must contain numeric pitch, roll, and yaw values.")

    return ("{\n    model = %s,\n    coords = vector3(%s, %s, %s),\n    heading = %s,\n    rotation = {\n        pitch = %s,\n        roll = %s,\n        yaw = %s,\n    },\n}")
        :format(
            formatModel(result.model),
            formatNumber(result.coords.x), formatNumber(result.coords.y), formatNumber(result.coords.z),
            formatNumber(result.heading),
            formatNumber(result.rotation.pitch), formatNumber(result.rotation.roll),
            formatNumber(result.rotation.yaw)
        )
end

local function clearHeld()
    for name in pairs(held) do held[name] = false end
end

local function shiftHeld()
    local ok, pressed = pcall(function() return IsRawKeyDown(16) end)
    if ok and pressed == true then return true end
    return IsControlPressed(0, 21)
end

local function restorePlayer(state)
    if not state or not state.playerFrozen then return end
    state.playerFrozen = false

    local currentPed = PlayerPedId()
    pcall(FreezeEntityPosition, state.playerPed, false)
    if currentPed ~= state.playerPed then pcall(FreezeEntityPosition, currentPed, false) end
end

local function destroyCameraImmediately(cam, state)
    pcall(RenderScriptCams, false, false, 0, true, true)
    if cam then pcall(DestroyCam, cam, false) end
    restorePlayer(state)
end

local function finishCameraEase(cam, state)
    if not cam then
        restorePlayer(state)
        return
    end

    local token = { cam = cam, state = state }
    teardownState = token

    CreateThread(function()
        pcall(RenderScriptCams, false, true, Config.placement.cameraTransitionMs, true, true)
        Wait(Config.placement.cameraTransitionMs)

        if teardownState ~= token then return end
        pcall(DestroyCam, cam, false)
        restorePlayer(state)
        teardownState = nil
    end)
end

local function releaseStateResources(state, immediateCamera)
    clearHeld()

    if state.controlLease then
        pcall(QB.controls.release, state.controlLease)
        state.controlLease = nil
    end

    if state.entity then
        -- remove() also drops ownership tracking. It is intentionally called
        -- even if another cleanup path already deleted the underlying entity.
        pcall(QB.entities.remove, state.entity)
        state.entity = nil
    end

    pcall(QB.nui.send, "placement:hud", nil)
    -- If an owning resource stops while the summary owns NUI focus, settling
    -- the placement promise alone cannot answer that still-pending browser
    -- request. Ask the component to respond "keep editing" so QB.nui releases
    -- focus immediately; the event is a harmless no-op when no dialog is open.
    pcall(QB.nui.send, "placement:closeConfirm", nil)
    if state.radarManaged and not state.radarWasHidden then pcall(DisplayRadar, true) end

    local cam = state.cam
    state.cam = nil
    if immediateCamera then
        destroyCameraImmediately(cam, state)
    else
        finishCameraEase(cam, state)
    end
end


local function settleState(state, value, rejection, immediateCamera)
    if activeState == state then activeState = nil end
    if startingState == state then startingState = nil end
    state.aborted = true
    releaseStateResources(state, immediateCamera == true)

    if rejection then
        state.promise:reject(value)
    else
        state.promise:resolve(value)
    end
end


local function resolveState(state, value, immediateCamera)
    settleState(state, value, false, immediateCamera)
end


local function rejectState(state, message, immediateCamera)
    settleState(state, tostring(message), true, immediateCamera)
end


local function settleForCaller(promiseValue, externalCaller)
    if externalCaller then return Citizen.Await(promiseValue) end
    return promiseValue
end


local function rejectedForCaller(message, externalCaller)
    local p = promise.new()
    p:reject(message)
    return settleForCaller(p, externalCaller)
end


local function currentBinding(name, fallback)
    local handle = bindingHandles[name]
    if not handle then return fallback end
    local ok, binding = pcall(handle.getCurrentBinding)
    if ok and type(binding) == "string" and binding ~= "" then return binding end
    return fallback
end


local function bindingsPayload()
    return {
        forward = currentBinding("forward", "UP"),
        backward = currentBinding("backward", "DOWN"),
        left = currentBinding("left", "LEFT"),
        right = currentBinding("right", "RIGHT"),
        up = currentBinding("up", "PAGEUP"),
        down = currentBinding("down", "PAGEDOWN"),
        rotateLeft = currentBinding("rotateLeft", "LBRACKET"),
        rotateRight = currentBinding("rotateRight", "RBRACKET"),
        cycle = currentBinding("cycle", "TAB"),
        confirm = currentBinding("confirm", "RETURN"),
        cancel = currentBinding("cancel", "X"),
    }
end


local function hudSnapshot(state)
    return {
        coords = {
            x = state.coords.x,
            y = state.coords.y,
            z = state.coords.z,
        },
        rotation = {
            pitch = state.rotation.pitch,
            roll = state.rotation.roll,
            yaw = state.rotation.yaw,
        },
        activeAxis = ROTATION_AXES[state.axisIndex],
        isShiftHeld = shiftHeld(),
    }
end


local function captureResult(state)
    local coords = GetEntityCoords(state.entity)
    local rotation = GetEntityRotation(state.entity, ROTATION_ORDER)

    return {
        model = state.model,
        coords = plainVec3(coords),
        heading = GetEntityHeading(state.entity),
        rotation = {
            pitch = rotation.x,
            roll = rotation.y,
            yaw = rotation.z,
        },
    }
end


local function openConfirmDialog(state)
    if activeState ~= state or state.dialogOpen then return end

    local result = captureResult(state)
    local snippet = QB.placement.generateSnippet(result)
    state.dialogOpen = true
    clearHeld()

    local ok, response = pcall(function()
        return QB.nui.withFocus(true, true, function()
            return Citizen.Await(QB.nui.request("placement:confirm", {
                model = tostring(state.model),
                snippet = snippet,
            }, Config.placement.confirmTimeout, state.resource))
        end, state.resource)
    end)

    if activeState ~= state then return end
    state.dialogOpen = false

    if not ok then
        rejectState(state, ("Placement summary failed: %s"):format(tostring(response)))
        return
    end

    if response and response.confirmed then resolveState(state, result) end
end


local function movementInput(positive, negative)
    return (held[positive] and 1 or 0) - (held[negative] and 1 or 0)
end


local function updateFreeCamera(state, multiplier)
    local lookX = GetDisabledControlNormal(0, 1)
    local lookY = GetDisabledControlNormal(0, 2)
    local strafe = GetDisabledControlNormal(0, 30)
    local forwardBack = GetDisabledControlNormal(0, 31)

    state.camYaw = (state.camYaw - lookX * Config.placement.cameraLookSensitivity) % 360.0
    state.camPitch = math.max(-89.0,
        math.min(89.0, state.camPitch - lookY * Config.placement.cameraLookSensitivity))

    local yawRad, pitchRad = math.rad(state.camYaw), math.rad(state.camPitch)
    local flat = math.cos(pitchRad)
    local forward = {
        x = -math.sin(yawRad) * flat,
        y = math.cos(yawRad) * flat,
        z = math.sin(pitchRad),
    }
    local right = { x = math.cos(yawRad), y = math.sin(yawRad), z = 0.0 }
    local distance = Config.placement.cameraMoveSpeed * multiplier * GetFrameTime()
    local moveForward, moveRight = -forwardBack * distance, strafe * distance

    state.camCoords.x = state.camCoords.x + forward.x * moveForward + right.x * moveRight
    state.camCoords.y = state.camCoords.y + forward.y * moveForward + right.y * moveRight
    state.camCoords.z = state.camCoords.z + forward.z * moveForward

    SetCamCoord(state.cam, state.camCoords.x, state.camCoords.y, state.camCoords.z)
    SetCamRot(state.cam, state.camPitch, 0.0, state.camYaw, ROTATION_ORDER)
end


local function updateEntityPlacement(state, multiplier)
    local forwardInput = movementInput("forward", "backward")
    local rightInput = movementInput("right", "left")
    local upInput = movementInput("up", "down")

    if forwardInput ~= 0 or rightInput ~= 0 or upInput ~= 0 then
        local yaw = math.rad(state.camYaw)
        local forwardX, forwardY = -math.sin(yaw), math.cos(yaw)
        local rightX, rightY = math.cos(yaw), math.sin(yaw)
        local dx = forwardX * forwardInput + rightX * rightInput
        local dy = forwardY * forwardInput + rightY * rightInput
        local dz = upInput
        local length = math.sqrt(dx * dx + dy * dy + dz * dz)
        if length > 1.0 then dx, dy, dz = dx / length, dy / length, dz / length end

        local distance = Config.placement.moveSpeed * multiplier * GetFrameTime()
        state.coords.x = state.coords.x + dx * distance
        state.coords.y = state.coords.y + dy * distance
        state.coords.z = state.coords.z + dz * distance
        SetEntityCoordsNoOffset(state.entity, state.coords.x, state.coords.y, state.coords.z, false, false, false)
    end

    local rotationInput = movementInput("rotateRight", "rotateLeft")
    if rotationInput ~= 0 then
        local axis = ROTATION_AXES[state.axisIndex]
        state.rotation[axis] = normalizeSignedAngle(state.rotation[axis]
            + rotationInput * Config.placement.rotationSpeed * multiplier * GetFrameTime())
        SetEntityRotation(state.entity, state.rotation.pitch, state.rotation.roll, state.rotation.yaw,
            ROTATION_ORDER, true)
    end
end


local function ensurePlacementThread(state)
    CreateThread(function()
        local ok, err = pcall(function()
            while activeState == state do
                if not DoesEntityExist(state.entity) then error("The placement preview entity disappeared.") end

                local multiplier = shiftHeld() and Config.placement.shiftMultiplier or 1.0
                if not state.dialogOpen then
                    updateFreeCamera(state, multiplier)
                    updateEntityPlacement(state, multiplier)
                end

                local now = GetGameTimer()
                if state.forceHud or now >= state.nextHudAt then
                    state.forceHud = false
                    state.nextHudAt = now + Config.placement.hudUpdateInterval
                    QB.nui.send("placement:hud", hudSnapshot(state))
                end

                if Config.placement.hideRadar then
                    state.radarManaged = true
                    DisplayRadar(false)
                end
                Wait(0)
            end
        end)

        if not ok and activeState == state then
            placementLog(("placement loop crashed: %s"):format(tostring(err)))
            rejectState(state, err)
        end
    end)
end


local function startCamera(state, camCoord, camRot)
    local cam = CreateCamWithParams("DEFAULT_SCRIPTED_CAMERA",
        camCoord.x, camCoord.y, camCoord.z,
        camRot.x, camRot.y, camRot.z,
        GetGameplayCamFov(), false, 0)

    state.cam = cam
    SetCamActive(cam, true)
    RenderScriptCams(true, true, Config.placement.cameraTransitionMs, true, true)
    state.visualsStarted = true
    if Config.placement.hideRadar then
        state.radarManaged = true
        DisplayRadar(false)
    end
    FreezeEntityPosition(state.playerPed, true)
    state.playerFrozen = true
    state.camCoords = plainVec3(camCoord)
    state.camPitch = camRot.x
    state.camYaw = camRot.z
end


local function validateModel(model)
    assert(type(model) == "string" or type(model) == "number", "Placement model must be a string or number.")
    assert(type(model) ~= "string" or model ~= "", "Placement model name cannot be empty.")
    local hash = type(model) == "string" and joaat(model) or model
    assert(IsModelValid(hash), ("Invalid placement model: %s"):format(tostring(model)))
end


---Starts a temporary local entity placement session. A same-resource caller
---receives an awaitable promise; a genuine cross-resource export call blocks
---and returns its settled result because Cfx cannot marshal a promise table.
---@param model string | number
---@return QBPlacementResult | promise | nil
function QB.placement.start(model)
    local invokingResource = GetInvokingResource()
    local externalCaller = invokingResource ~= nil

    if Config.placement.enabled == false then
        return rejectedForCaller("Entity placement is disabled on this server (Config.placement.enabled).",
            externalCaller)
    end

    if activeState or startingState or teardownState then
        return rejectedForCaller("An entity placement session is already active or finishing.", externalCaller)
    end

    local zones = rawget(QB, "zones")
    if zones and type(zones.isCreatorActive) == "function" and zones.isCreatorActive() then
        return rejectedForCaller("The zone creator is already active.", externalCaller)
    end

    local p = promise.new()
    local state = {
        promise = p,
        model = model,
        resource = invokingResource or GetCurrentResourceName(),
        playerPed = PlayerPedId(),
        entity = nil,
        cam = nil,
        controlLease = nil,
        dialogOpen = false,
        aborted = false,
        axisIndex = 1,
        nextHudAt = 0,
        forceHud = true,
        visualsStarted = false,
        radarManaged = false,
        radarWasHidden = type(IsRadarHidden) == "function" and IsRadarHidden() or false,
        playerFrozen = false,
    }
    startingState = state

    local ok, err = pcall(function()
        validateModel(model)

        local gameplayCamCoord = GetGameplayCamCoord()
        local gameplayCamRot = GetGameplayCamRot(ROTATION_ORDER)
        local hit, coords = QB.raycast.fromCamera(Config.placement.raycastDistance)
        if not hit or not coords then error("Aim at a solid surface before starting entity placement.") end
        if state.aborted then error("The placement owner stopped while placement was starting.") end

        local entity, createErr = QB.entities.create(model, coords, {
            preset = "static",
            heading = gameplayCamRot.z,
        })
        if not entity then error(createErr or "Failed to create the placement preview entity.") end
        state.entity = entity
        if state.aborted then error("The placement owner stopped while the preview was loading.") end

        state.coords = plainVec3(coords)
        state.rotation = { pitch = 0.0, roll = 0.0, yaw = normalizeSignedAngle(gameplayCamRot.z) }
        SetEntityCollision(entity, false, false)
        SetEntityAlpha(entity, Config.placement.previewAlpha, false)
        SetEntityRotation(entity, 0.0, 0.0, state.rotation.yaw, ROTATION_ORDER, true)

        state.controlLease = QB.controls.acquire(PLACEMENT_CONTROLS)
        startCamera(state, gameplayCamCoord, gameplayCamRot)
    end)

    startingState = nil
    if not ok then
        releaseStateResources(state, true)
        -- A caller-resource stop can settle this promise while model streaming
        -- is yielding. In that case the resumed start path still cleans up the
        -- just-created entity, but must not reject an already-resolved cancel.
        if not state.aborted then p:reject(err) end
        return settleForCaller(p, externalCaller)
    end

    activeState = state
    clearHeld()
    QB.nui.send("placement:start", {
        model = tostring(model),
        bindings = bindingsPayload(),
    })
    ensurePlacementThread(state)

    return settleForCaller(p, externalCaller)
end


---@return boolean
function QB.placement.isActive()
    return activeState ~= nil or startingState ~= nil or teardownState ~= nil
end


local function registerHeldBinding(id, description, defaultKey)
    bindingHandles[id] = QB.keybind.add({
        name = "qblib_placement_" .. id,
        description = description,
        defaultMapper = "keyboard",
        defaultKey = defaultKey,
        onPressed = function()
            if activeState and not activeState.dialogOpen then held[id] = true end
        end,
        onReleased = function() held[id] = false end,
    })
end


registerHeldBinding("forward", "Entity Placement: Move Forward", "UP")
registerHeldBinding("backward", "Entity Placement: Move Backward", "DOWN")
registerHeldBinding("left", "Entity Placement: Move Left", "LEFT")
registerHeldBinding("right", "Entity Placement: Move Right", "RIGHT")
registerHeldBinding("up", "Entity Placement: Move Up", "PAGEUP")
registerHeldBinding("down", "Entity Placement: Move Down", "PAGEDOWN")
registerHeldBinding("rotateLeft", "Entity Placement: Rotate Left", "LBRACKET")
registerHeldBinding("rotateRight", "Entity Placement: Rotate Right", "RBRACKET")

bindingHandles.cycle = QB.keybind.add({
    name = "qblib_placement_cycle",
    description = "Entity Placement: Cycle Rotation Axis",
    defaultMapper = "keyboard",
    defaultKey = "TAB",
    onPressed = function()
        if not activeState or activeState.dialogOpen then return end
        activeState.axisIndex = activeState.axisIndex % #ROTATION_AXES + 1
        activeState.forceHud = true
    end,
})

bindingHandles.confirm = QB.keybind.add({
    name = "qblib_placement_confirm",
    description = "Entity Placement: Open Summary",
    defaultMapper = "keyboard",
    defaultKey = "RETURN",
    onPressed = function()
        if activeState then openConfirmDialog(activeState) end
    end,
})

bindingHandles.cancel = QB.keybind.add({
    name = "qblib_placement_cancel",
    description = "Entity Placement: Cancel",
    defaultMapper = "keyboard",
    defaultKey = "X",
    onPressed = function()
        if activeState then resolveState(activeState, nil) end
    end,
})

AddEventHandler("onClientResourceStop", function(resourceName)
    local currentResource = GetCurrentResourceName()

    if resourceName == currentResource then
        local state = activeState or startingState
        activeState, startingState = nil, nil
        if state then
            state.aborted = true
            releaseStateResources(state, true)
            state.promise:reject("qblib stopped during entity placement.")
        end

        if teardownState then
            local teardown = teardownState
            teardownState = nil
            destroyCameraImmediately(teardown.cam, teardown.state)
        end

        pcall(QB.nui.send, "placement:hud", nil)
        pcall(QB.nui.send, "placement:closeConfirm", nil)
        return
    end

    local state = activeState or startingState
    if state and state.resource == resourceName then resolveState(state, nil) end
end)

RegisterNetEvent("qblib:editor:startPlacement", function(model)
    if type(model) ~= "string" and type(model) ~= "number" then return end
    if type(model) == "string" and model:match("^%-?%d+$") then model = tonumber(model) end

    local ok, result = pcall(function()
        return Citizen.Await(QB.placement.start(model))
    end)

    if not ok then
        placementLog(tostring(result))
        QB.notify.send({
            title = "Entity placement failed",
            message = tostring(result),
            type = "error",
        })
    elseif result then
        QB.notify.send({
            title = "Entity placement",
            message = "Placement data copied.",
            type = "success",
        })
    end
end)
