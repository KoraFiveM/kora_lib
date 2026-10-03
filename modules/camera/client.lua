local state = {
    active = false,
    camera = nil,
    cameras = {},
    index = 0,
    options = nil,
    scriptCameraActive = false,
    previousViewMode = nil,
    instructions = nil,
    startedAt = 0,
    lastTick = 0,
}

local loopId = 0

local CAMERA_MODES = {
    cctv = true,
    recording = true,
    helicam = true,
    operator = true,
}

local isFiniteNumber = QB.util.isFiniteNumber

local function isCoords(value)
    return type(value) == 'table' or type(value) == 'vector3' or type(value) == 'vector4'
end

local function assertCoords(value, name)
    assert(isCoords(value) and isFiniteNumber(value.x) and isFiniteNumber(value.y) and isFiniteNumber(value.z),
        ('Camera %s must contain finite x, y, and z values.'):format(name))
end

local function assertText(value, name)
    assert(type(value) == 'string' and value ~= '' and #value <= 80,
        ('Camera %s must be a non-empty string of 80 characters or fewer.'):format(name))
end

local function validateCamera(camera, index)
    assert(type(camera) == 'table', ('Camera %d must be a table.'):format(index))
    assert(camera.coords ~= nil, ('Camera %d requires coords.'):format(index))
    assertCoords(camera.coords, ('%d coords'):format(index))

    if camera.target ~= nil then assertCoords(camera.target, ('%d target'):format(index)) end
    if camera.rotation ~= nil then assertCoords(camera.rotation, ('%d rotation'):format(index)) end
    if camera.fov ~= nil then
        assert(isFiniteNumber(camera.fov) and camera.fov >= 10.0 and camera.fov <= 120.0,
            ('Camera %d fov must be between 10 and 120.'):format(index))
    end
    if camera.label ~= nil then assertText(camera.label, ('%d label'):format(index)) end
end

local function normalizedOptions(options)
    assert(type(options) == 'table', 'Camera.open requires an options table.')

    local mode = options.mode or 'operator'
    assert(CAMERA_MODES[mode], 'Camera mode must be cctv, recording, helicam, or operator.')

    local cameras = options.cameras or {}
    assert(type(cameras) == 'table', 'Camera cameras must be a table.')
    if options.camera then cameras = { options.camera } end
    for index, camera in ipairs(cameras) do validateCamera(camera, index) end

    if options.title ~= nil then assertText(options.title, 'title') end
    if options.subtitle ~= nil then assertText(options.subtitle, 'subtitle') end
    if options.cameraLabel ~= nil then assertText(options.cameraLabel, 'cameraLabel') end
    assert(options.recording == nil or type(options.recording) == 'boolean', 'Camera recording must be a boolean.')
    assert(options.controls == nil or type(options.controls) == 'boolean', 'Camera controls must be a boolean.')
    assert(options.viewMode == nil or (type(options.viewMode) == 'number' and options.viewMode >= 0 and options.viewMode <= 4),
        'Camera viewMode must be between 0 and 4.')

    return {
        mode = mode,
        title = options.title or 'SECURE CAMERA NETWORK',
        subtitle = options.subtitle or (mode == 'cctv' and 'CITYWIDE MONITORING' or 'FIELD OPTICS'),
        cameraLabel = options.cameraLabel or (mode == 'cctv' and 'CAM 01' or 'LIVE UNIT'),
        recording = options.recording == true,
        controls = options.controls ~= false,
        timestamp = options.timestamp ~= false,
        viewMode = options.viewMode,
    }, cameras
end

local function destroyActiveCamera()
    if state.camera and DoesCamExist(state.camera) then DestroyCam(state.camera, false) end
    state.camera = nil
end

local function hudPayload()
    local options = state.options
    local camera = state.cameras[state.index]
    return {
        active = state.active,
        mode = options.mode,
        title = options.title,
        subtitle = options.subtitle,
        cameraLabel = camera and camera.label or options.cameraLabel,
        cameraIndex = state.index,
        totalCameras = #state.cameras,
        location = camera and camera.location or nil,
        recording = options.recording,
        timestamp = options.timestamp,
        elapsed = math.max(0, GetGameTimer() - state.startedAt),
    }
end

local function showInstructions()
    if not state.options.controls then return end
    local buttons = {}
    if #state.cameras > 1 then
        buttons[#buttons + 1] = { control = 10, label = 'Next camera' }
        buttons[#buttons + 1] = { control = 11, label = 'Previous camera' }
    end
    buttons[#buttons + 1] = { control = 177, label = 'Exit camera' }
    state.instructions = QB.instructional.show(buttons)
end

local function sendUpdate()
    QB.nui.send('camera:update', hudPayload())
end

local function createCamera(camera)
    if not camera then return end

    local coords = camera.coords
    local rotation = camera.rotation or vector3(0.0, 0.0, 0.0)
    local handle = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', coords.x, coords.y, coords.z,
        rotation.x, rotation.y, rotation.z, camera.fov or 52.0, false, 2)
    assert(handle and handle ~= 0 and DoesCamExist(handle), 'Camera could not be created.')

    if camera.target then PointCamAtCoord(handle, camera.target.x, camera.target.y, camera.target.z) end
    SetCamActive(handle, true)
    return handle
end

local function activateCamera(index)
    if #state.cameras == 0 then return end
    state.index = ((index - 1) % #state.cameras) + 1
    destroyActiveCamera()
    state.camera = createCamera(state.cameras[state.index])
    state.scriptCameraActive = true
    RenderScriptCams(true, true, 350, true, true)
    sendUpdate()
end

local function restorePlayerCamera()
    destroyActiveCamera()
    if state.scriptCameraActive then
        RenderScriptCams(false, true, 250, true, true)
        state.scriptCameraActive = false
    end
    if state.previousViewMode ~= nil then
        SetFollowPedCamViewMode(state.previousViewMode)
        state.previousViewMode = nil
    end
end

---Starts the control/timer loop. It only lives while the camera is open and
---exits on its own when the camera closes or a newer session replaces it.
local function startLoop()
    loopId = loopId + 1
    local id = loopId

    CreateThread(function()
        while state.active and loopId == id do
            if IsControlJustPressed(0, 177) or IsControlJustPressed(0, 322) then
                QB.camera.close('escape')
            elseif IsControlJustPressed(0, 10) then
                QB.camera.next()
            elseif IsControlJustPressed(0, 11) then
                QB.camera.previous()
            end

            local now = GetGameTimer()
            if now - state.lastTick >= 1000 then
                state.lastTick = now
                QB.nui.send('camera:tick', { elapsed = math.max(0, now - state.startedAt) })
            end
            Wait(0)
        end
    end)
end

---Opens the reusable camera overlay. Fixed cameras use `cameras`; recording,
---helicam, and operator modes can omit it to keep the player's native view.
---@param options QBCameraOptions
---@return boolean opened
function QB.camera.open(options)
    local normalized, cameras = normalizedOptions(options)
    if state.active then QB.camera.close('replaced') end

    state.active, state.options, state.cameras = true, normalized, cameras
    state.index, state.startedAt, state.lastTick = 0, GetGameTimer(), 0
    if normalized.viewMode ~= nil then
        state.previousViewMode = GetFollowPedCamViewMode()
        SetFollowPedCamViewMode(normalized.viewMode)
    end

    if #cameras > 0 then activateCamera(1) end
    showInstructions()
    QB.nui.send('camera:open', hudPayload())
    startLoop()
    return true
end

---Closes the active camera and restores the player's previous view.
---@param reason? string
---@return boolean closed
function QB.camera.close(reason)
    if not state.active then return false end

    restorePlayerCamera()
    if state.instructions then
        state.instructions.hide()
        state.instructions = nil
    end
    state.active, state.options, state.cameras, state.index = false, nil, {}, 0
    QB.nui.send('camera:close', { reason = reason or 'closed' })
    return true
end

---@return boolean open
function QB.camera.isOpen()
    return state.active
end

---Switches to the next camera in the current camera network.
---@return boolean changed
function QB.camera.next()
    if not state.active or #state.cameras < 2 then return false end
    activateCamera(state.index + 1)
    return true
end

---Switches to the previous camera in the current camera network.
---@return boolean changed
function QB.camera.previous()
    if not state.active or #state.cameras < 2 then return false end
    activateCamera(state.index - 1)
    return true
end

---Changes the recording indicator without changing the live camera.
---@param recording boolean
---@return boolean updated
function QB.camera.setRecording(recording)
    assert(type(recording) == 'boolean', 'Camera setRecording requires a boolean.')
    if not state.active then return false end
    state.options.recording = recording
    sendUpdate()
    return true
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() and state.active then restorePlayerCamera() end
end)