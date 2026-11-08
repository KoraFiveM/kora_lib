---@class QBPlacementRotation
---@field pitch number Rotation around X, in degrees.
---@field roll number Rotation around Y, in degrees.
---@field yaw number Rotation around Z, in degrees.

---@class QBPlacementResult
---@field model string | number Original model name/hash passed to `Kora.placement.start`.
---@field coords {x: number, y: number, z: number}
---@field heading number Native entity heading, read independently from Euler yaw.
---@field rotation QBPlacementRotation

local ROTATION_ORDER = 2
local ROTATION_AXES = { "yaw", "pitch", "roll" }
local PLACEMENT_CONTROLS = {
    172, 173, 174, 175, -- cellphone arrows
    187, 188, 189, 190, -- frontend arrows
    207, 208,           -- frontend Page Down / Page Up
    312, 313,           -- replay [ / ]
    191, 192,           -- Enter / Tab
    73,                 -- X
}

local activeState = nil
local startingState = nil
local held = {}
local bindingHandles = {}

local function placementLog(message)
    print(("[kora_lib:placement] %s"):format(message))
end

local function plainVec3(value)
    return { x = value.x, y = value.y, z = value.z }
end

local function assertVec3(value, label)
    assert(type(value) == "table" or type(value) == "vector3", ("%s must be vector-like."):format(label))
    assert(Kora.util.isFiniteNumber(value.x) and Kora.util.isFiniteNumber(value.y) and Kora.util.isFiniteNumber(value.z),
        ("%s must contain finite x, y, and z values."):format(label))
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
function Kora.placement.generateSnippet(result)
    assert(type(result) == "table", "Placement result must be a table.")
    assert(type(result.model) == "string" or type(result.model) == "number",
        "Placement result model must be a string or number.")
    assertVec3(result.coords, "Placement result coords")
    assert(Kora.util.isFiniteNumber(result.heading), "Placement result heading must be a finite number.")
    assert(type(result.rotation) == "table", "Placement result rotation must be a table.")
    assert(Kora.util.isFiniteNumber(result.rotation.pitch) and Kora.util.isFiniteNumber(result.rotation.roll)
        and Kora.util.isFiniteNumber(result.rotation.yaw),
        "Placement result rotation must contain finite pitch, roll, and yaw values.")

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

local function releaseStateResources(state)
    clearHeld()
    if state.dialogRequest then
        pcall(Kora.nui.cancelRequest, state.dialogRequest, { cancelled = true })
        state.dialogRequest = nil
    end

    if state.controlLease then
        pcall(Kora.compat.releaseControlLease, state.controlLease, state.resource)
        state.controlLease = nil
    end

    if state.entity then
        -- Called even if another path already deleted the entity; remove() also drops ownership tracking.
        pcall(Kora.entities.remove, state.entity)
        -- remove() refuses when the tracked owner differs from the current caller context; never leave the preview behind.
        if DoesEntityExist(state.entity) then
            -- Non-mission entities can be refused by DeleteEntity; claim it first so the preview is really gone.
            pcall(SetEntityAsMissionEntity, state.entity, true, true)
            pcall(DeleteEntity, state.entity)
            if DoesEntityExist(state.entity) and IsEntityAVehicle(state.entity) then pcall(DeleteVehicle, state.entity) end
        end
        state.entity = nil
    end

    if state.instructions then
        pcall(state.instructions.hide)
        state.instructions = nil
    end

    if state.hudHidden then
        state.hudHidden = nil
        pcall(function() exports.kora_hud:show() end)
    end

    pcall(Kora.nui.send, "placement:hud", nil)
    -- If the owner stops while the summary holds NUI focus, answer the pending request with "keep editing" so Kora.nui releases focus; no-op when no dialog is open.
    pcall(Kora.nui.send, "placement:closeConfirm", nil)
    if state.radarManaged and not state.radarWasHidden then pcall(DisplayRadar, true) end

    if state.freecam then
        pcall(state.freecam.stop)
        state.freecam = nil
    end
    if state.bounds then
        pcall(state.bounds.remove)
        state.bounds = nil
    end
end


local function settleState(state, value, rejection)
    if activeState == state then activeState = nil end
    if startingState == state then startingState = nil end
    state.aborted = true
    releaseStateResources(state)

    if rejection then
        state.promise:reject(value)
    else
        state.promise:resolve(value)
    end
end


local function resolveState(state, value)
    settleState(state, value, false)
end


local function rejectState(state, message)
    settleState(state, tostring(message), true)
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
    local snippet = Kora.placement.generateSnippet(result)
    state.dialogOpen = true
    clearHeld()

    local ok, response = pcall(function()
        if state.options.copy == false then
            state.dialogRequest = Kora.nui.requestAsync('openAlert', { title = 'Confirm placement', message = 'Save this object at its current position and rotation?' }, false, state.resource, true)
            return Citizen.Await(state.dialogRequest)
        end
        return Kora.nui.withFocus(true, true, function()
            return Citizen.Await(Kora.nui.request("placement:confirm", {
                model = tostring(state.model),
                snippet = snippet,
            }, Config.placement.confirmTimeout, state.resource))
        end, state.resource)
    end)

    if activeState ~= state then return end
    state.dialogOpen = false
    state.dialogRequest = nil

    if not ok then
        rejectState(state, ("Placement summary failed: %s"):format(tostring(response)))
        return
    end

    if response and response.confirmed then resolveState(state, result) end
end

local function inBounds(state, coords)
    return not state.bounds or state.bounds.contains(coords)
end

local function setPosition(state, coords)
    if not inBounds(state, coords) then return false end
    state.coords = plainVec3(coords)
    SetEntityCoordsNoOffset(state.entity, coords.x, coords.y, coords.z, false, false, false)
    state.forceHud = true
    return true
end

local function numericInput(state)
    if activeState ~= state or state.dialogOpen then return end
    state.dialogOpen = true
    clearHeld()
    local ok, response = pcall(function()
        state.dialogRequest = Kora.nui.requestAsync('openInputDialog', { title = 'Adjust object placement', fields = {
            { id = 'coords', label = 'Position', type = 'vector', dimensions = 3, required = true, default = plainVec3(state.coords) },
            { id = 'rotation', label = 'Rotation (pitch, roll, yaw)', type = 'vector', dimensions = 3, required = true,
                default = { x = state.rotation.pitch, y = state.rotation.roll, z = state.rotation.yaw } },
        } }, false, state.resource, true)
        return Citizen.Await(state.dialogRequest)
    end)
    if activeState ~= state then return end
    state.dialogOpen = false
    state.dialogRequest = nil
    if not ok then rejectState(state, response); return end
    if not response or response.cancelled then return end
    local values = response.values
    if type(values) ~= 'table' then return end
    local valid = pcall(function() assertVec3(values.coords, 'Position'); assertVec3(values.rotation, 'Rotation') end)
    if not valid or not setPosition(state, values.coords) then
        Kora.notify.send({ message = 'Placement must stay inside the allowed property boundary.', type = 'error' })
        return
    end
    state.raycast = false
    state.rotation = { pitch = values.rotation.x, roll = values.rotation.y, yaw = values.rotation.z }
    SetEntityRotation(state.entity, state.rotation.pitch, state.rotation.roll, state.rotation.yaw, ROTATION_ORDER, true)
end


local function movementInput(positive, negative)
    return (held[positive] and 1 or 0) - (held[negative] and 1 or 0)
end


local function updateEntityPlacement(state, multiplier)
    local forwardInput = movementInput("forward", "backward")
    local rightInput = movementInput("right", "left")
    local upInput = movementInput("up", "down")

    if forwardInput ~= 0 or rightInput ~= 0 or upInput ~= 0 then
        state.raycast = false
        local yaw = math.rad(state.camYaw)
        local forwardX, forwardY = -math.sin(yaw), math.cos(yaw)
        local rightX, rightY = math.cos(yaw), math.sin(yaw)
        local dx = forwardX * forwardInput + rightX * rightInput
        local dy = forwardY * forwardInput + rightY * rightInput
        local dz = upInput
        local length = math.sqrt(dx * dx + dy * dy + dz * dz)
        if length > 1.0 then dx, dy, dz = dx / length, dy / length, dz / length end

        local distance = Config.placement.moveSpeed * multiplier * GetFrameTime()
        setPosition(state, { x = state.coords.x + dx * distance, y = state.coords.y + dy * distance, z = state.coords.z + dz * distance })
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
                assert(DoesEntityExist(state.entity), "The placement preview entity disappeared.")

                local multiplier = shiftHeld() and Config.placement.shiftMultiplier or 1.0
                if not state.dialogOpen then
                    local rotation = state.freecam.getRotation()
                    if rotation then state.camYaw = rotation.yaw end
                    updateEntityPlacement(state, multiplier)
                    if state.raycast then
                        local hit, coords = Kora.raycast.fromCam(state.freecam.getCamera(), Config.placement.raycastDistance, nil, state.entity)
                        if activeState == state and hit then setPosition(state, coords) end
                    end
                end

                local now = GetGameTimer()
                if state.forceHud or now >= state.nextHudAt then
                    state.forceHud = false
                    state.nextHudAt = now + Config.placement.hudUpdateInterval
                    Kora.nui.send("placement:hud", hudSnapshot(state))
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
    local freecam, err = Kora.freecam.start({
        coords = camCoord,
        rotation = camRot,
        moveSpeed = Config.placement.cameraMoveSpeed,
        lookSensitivity = Config.placement.cameraLookSensitivity,
        fastMultiplier = Config.placement.shiftMultiplier,
        transitionMs = Config.placement.cameraTransitionMs,
    })
    assert(freecam, err)
    state.freecam = freecam
    if Config.placement.hideRadar then
        state.radarManaged = true
        DisplayRadar(false)
    end
    state.camYaw = camRot.z
end


local function validateModel(model)
    assert(type(model) == "string" or type(model) == "number", "Placement model must be a string or number.")
    assert(type(model) ~= "string" or model ~= "", "Placement model name cannot be empty.")
    assert(type(model) ~= "number" or Kora.util.isInteger(model), "Placement model hash must be a finite integer.")
    local hash = type(model) == "string" and joaat(model) or model
    assert(IsModelValid(hash), ("Invalid placement model: %s"):format(tostring(model)))
end

local function updatePlacementInstructions(state)
    if not state.instructions then return end
    local movementLabel = state.movementMode == "camera" and "Camera" or "Grid"
    local buttons = {
        { control = 32, label = "Move camera forward", group = "Move camera" },
        { control = 33, label = "Move camera backward", group = "Move camera" },
        { control = 34, label = "Move camera left", group = "Move camera" },
        { control = 35, label = "Move camera right", group = "Move camera" },
        { keybind = bindingHandles.movement, label = "Camera movement: " .. movementLabel },
        { keybind = bindingHandles.forward, label = "Move entity forward" },
        { keybind = bindingHandles.backward, label = "Move entity backward" },
        { keybind = bindingHandles.up, label = "Move entity up" },
        { keybind = bindingHandles.down, label = "Move entity down" },
        { keybind = bindingHandles.rotateLeft, label = "Rotate " .. ROTATION_AXES[state.axisIndex] .. " left" },
        { keybind = bindingHandles.rotateRight, label = "Rotate " .. ROTATION_AXES[state.axisIndex] .. " right" },
        { keybind = bindingHandles.cycle, label = "Rotation axis: " .. ROTATION_AXES[state.axisIndex] },
        { keybind = bindingHandles.confirm, label = "Confirm" },
        { keybind = bindingHandles.cancel, label = "Cancel" },
    }
    if state.options.numericInput then buttons[#buttons + 1] = { keybind = bindingHandles.numeric, label = 'Numeric position / rotation' } end
    if state.options.raycast ~= nil then buttons[#buttons + 1] = { keybind = bindingHandles.raycast, label = 'Toggle surface placement' } end
    state.instructions.setButtons(buttons)
end


---Starts a temporary local entity placement session. Same-resource callers get a promise; cross-resource export calls block and return the settled result (Cfx can't marshal a promise).
---@param model string | number
---@return QBPlacementResult | promise | nil
function Kora.placement.start(model, options)
    local invokingResource = GetInvokingResource()
    local externalCaller = invokingResource ~= nil
    options = options or {}
    assert(type(options) == 'table', 'Placement options must be a table.')
    for _, name in ipairs({ 'raycast', 'numericInput', 'copy' }) do
        assert(options[name] == nil or type(options[name]) == 'boolean', 'Placement ' .. name .. ' must be a boolean.')
    end
    if options.coords then assertVec3(options.coords, 'Placement initial coordinates') end
    if options.rotation then
        assert(type(options.rotation) == 'table' and Kora.util.isFiniteNumber(options.rotation.pitch)
            and Kora.util.isFiniteNumber(options.rotation.roll) and Kora.util.isFiniteNumber(options.rotation.yaw), 'Placement rotation requires finite pitch, roll and yaw.')
    end

    if Config.placement.enabled == false then
        return rejectedForCaller("Entity placement is disabled on this server (Config.placement.enabled).",
            externalCaller)
    end

    if activeState or startingState then
        return rejectedForCaller("An entity placement session is already active.", externalCaller)
    end

    local zones = rawget(Kora, "zones")
    if zones and type(zones.isCreatorActive) == "function" and zones.isCreatorActive() then
        return rejectedForCaller("The zone creator is already active.", externalCaller)
    end

    local p = promise.new()
    local state = {
        promise = p,
        model = model,
        resource = invokingResource or GetCurrentResourceName(),
        entity = nil,
        freecam = nil,
        controlLease = nil,
        dialogOpen = false,
        aborted = false,
        axisIndex = 1,
        nextHudAt = 0,
        forceHud = true,
        radarManaged = false,
        radarWasHidden = type(IsRadarHidden) == "function" and IsRadarHidden() or false,
        movementMode = "camera",
        instructions = nil,
        options = options,
        raycast = options.raycast == true,
    }
    startingState = state

    local ok, err = pcall(function()
        validateModel(model)

        local gameplayCamCoord = GetGameplayCamCoord()
        local gameplayCamRot = GetGameplayCamRot(ROTATION_ORDER)
        local hit, coords
        if options.coords then hit, coords = true, options.coords else hit, coords = Kora.raycast.fromCamera(Config.placement.raycastDistance) end
        assert(hit and coords, "Aim at a solid surface before starting entity placement.")
        if options.bounds then
            assert(type(options.bounds) == 'table', 'Placement bounds must be a polygon definition.')
            state.bounds = Kora.zones.poly({ points = options.bounds.points, minZ = options.bounds.minZ, maxZ = options.bounds.maxZ, trackPlayer = false })
            assert(state.bounds.contains(coords), 'Initial placement is outside the property boundary.')
        end
        assert(not state.aborted, "The placement owner stopped while placement was starting.")

        local entity, createErr = Kora.entities.create(model, coords, {
            preset = "static",
            heading = gameplayCamRot.z,
        })
        assert(entity, createErr or "Failed to create the placement preview entity.")
        state.entity = entity
        assert(not state.aborted, "The placement owner stopped while the preview was loading.")

        state.coords = plainVec3(coords)
        local rotation = options.rotation or { pitch = 0.0, roll = 0.0, yaw = normalizeSignedAngle(gameplayCamRot.z) }
        state.rotation = { pitch = rotation.pitch, roll = rotation.roll, yaw = rotation.yaw }
        SetEntityCollision(entity, false, false)
        SetEntityAlpha(entity, Config.placement.previewAlpha, false)
        SetEntityRotation(entity, state.rotation.pitch, state.rotation.roll, state.rotation.yaw, ROTATION_ORDER, true)

        state.controlLease = Kora.compat.acquireControls(PLACEMENT_CONTROLS, nil, state.resource)
        startCamera(state, gameplayCamCoord, gameplayCamRot)
    end)

    startingState = nil
    if not ok then
        releaseStateResources(state)
        -- A caller stop can settle the promise mid model-streaming; the resumed path still cleans up the entity but must not reject the already-resolved cancel.
        if not state.aborted then p:reject(err) end
        return settleForCaller(p, externalCaller)
    end

    activeState = state
    clearHeld()
    if Config.placement.hideHud and GetResourceState("kora_hud") == "started" then
        state.hudHidden = pcall(function() exports.kora_hud:hide() end)
    end
    state.instructions = Kora.instructional.show({ { control = 32, label = "Move camera forward" } })
    updatePlacementInstructions(state)
    Kora.nui.send("placement:start", {
        model = tostring(model),
    })
    ensurePlacementThread(state)

    return settleForCaller(p, externalCaller)
end


---@return boolean
function Kora.placement.isActive()
    return activeState ~= nil or startingState ~= nil
end

---Cancels only the invoking resource's placement and settles its result as nil.
---@return boolean, string?
function Kora.placement.cancel()
    local state = activeState or startingState
    if not state then return true end
    local owner = GetInvokingResource() or GetCurrentResourceName()
    if state.resource ~= owner then return false, 'Another resource owns the active placement.' end
    resolveState(state, nil)
    return true
end


local function registerHeldBinding(id, description, defaultKey)
    bindingHandles[id] = Kora.keybind.add({
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

bindingHandles.cycle = Kora.keybind.add({
    name = "qblib_placement_cycle",
    description = "Entity Placement: Cycle Rotation Axis",
    defaultMapper = "keyboard",
    defaultKey = "TAB",
    onPressed = function()
        if not activeState or activeState.dialogOpen then return end
        activeState.axisIndex = activeState.axisIndex % #ROTATION_AXES + 1
        activeState.forceHud = true
        updatePlacementInstructions(activeState)
    end,
})

bindingHandles.confirm = Kora.keybind.add({
    name = "qblib_placement_confirm",
    description = "Entity Placement: Open Summary",
    defaultMapper = "keyboard",
    defaultKey = "RETURN",
    onPressed = function()
        if activeState then openConfirmDialog(activeState) end
    end,
})

bindingHandles.cancel = Kora.keybind.add({
    name = "qblib_placement_cancel",
    description = "Entity Placement: Cancel",
    defaultMapper = "keyboard",
    defaultKey = "X",
    onPressed = function()
        if activeState then resolveState(activeState, nil) end
    end,
})

bindingHandles.movement = Kora.keybind.add({
    name = "qblib_placement_movement",
    description = "Entity Placement: Toggle Camera / Grid Movement",
    defaultMapper = "keyboard",
    defaultKey = "G",
    onPressed = function()
        if not activeState or activeState.dialogOpen then return end
        activeState.movementMode = activeState.movementMode == "camera" and "grid" or "camera"
        activeState.freecam.setMovementMode(activeState.movementMode)
        updatePlacementInstructions(activeState)
    end,
})

bindingHandles.numeric = Kora.keybind.add({
    name = 'qblib_placement_numeric', description = 'Entity Placement: Numeric Position and Rotation', defaultMapper = 'keyboard', defaultKey = 'N',
    onPressed = function()
        if activeState and activeState.options.numericInput then numericInput(activeState) end
    end,
})

bindingHandles.raycast = Kora.keybind.add({
    name = 'qblib_placement_raycast', description = 'Entity Placement: Toggle Surface Placement', defaultMapper = 'keyboard', defaultKey = 'R',
    onPressed = function()
        if activeState and activeState.options.raycast ~= nil and not activeState.dialogOpen then
            activeState.raycast = not activeState.raycast
            activeState.forceHud = true
        end
    end,
})

AddEventHandler("onClientResourceStop", function(resourceName)
    local currentResource = GetCurrentResourceName()

    if resourceName == currentResource then
        local state = activeState or startingState
        activeState, startingState = nil, nil
        if state then
            state.aborted = true
            releaseStateResources(state)
            state.promise:reject("kora_lib stopped during entity placement.")
        end

        pcall(Kora.nui.send, "placement:hud", nil)
        pcall(Kora.nui.send, "placement:closeConfirm", nil)
        return
    end

    local state = activeState or startingState
    if state and state.resource == resourceName then resolveState(state, nil) end
end)

local function onStartPlacement(model)
    if type(model) ~= "string" and type(model) ~= "number" then return end
    if type(model) == "string" and model:match("^%-?%d+$") then model = tonumber(model) end

    local ok, result = pcall(function()
        return Citizen.Await(Kora.placement.start(model))
    end)

    if not ok then
        placementLog(tostring(result))
        Kora.notify.send({
            title = "Entity placement failed",
            message = tostring(result),
            type = "error",
        })
    elseif result then
        Kora.notify.send({
            title = "Entity placement",
            message = "Placement data copied.",
            type = "success",
        })
    end
end

RegisterNetEvent("kora_lib:editor:startPlacement", onStartPlacement)
-- Deprecated alias for callers that predate the rename.
RegisterNetEvent("qblib:editor:startPlacement", onStartPlacement)
