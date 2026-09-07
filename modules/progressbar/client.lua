---@class QBProgressBarDisable
---@field move? boolean Freezes the ped in place for the duration (`FreezeEntityPosition`). Defaults to false.
---@field combat? boolean Disables attack/aim/weapon-switch/melee controls for the duration. Defaults to false.
---@field car? boolean Disables vehicle driving controls while the ped is in a vehicle. Defaults to false.

---@class QBProgressBarAnim
---@field dict string Animation dictionary to play, requested and released automatically.
---@field clip string Clip name within `dict`.
---@field flag? number AnimFlags bitmask passed to `TaskPlayAnim`. Defaults to 1 (loop).
---@field blendIn? number Defaults to 8.0.
---@field blendOut? number Defaults to 8.0.

---@class QBProgressBarScenario
---@field name string Scenario name to play, e.g. `"WORLD_HUMAN_HAMMERING"`.
---@field playEnter? boolean Whether to play the scenario's enter animation. Defaults to true.

---@class QBProgressBarProp
---@field model string|integer Model name or hash.
---@field bone? string|integer Ped bone name or ID. Defaults to 60309.
---@field offset? vector3|table Local attachment offset. Defaults to vector3(0, 0, 0).
---@field rotation? vector3|table Local attachment rotation. Defaults to vector3(0, 0, 0).
---@field softPinning? boolean Defaults to true.
---@field collision? boolean Defaults to false.
---@field rotationOrder? integer Defaults to 0.
---@field syncRotation? boolean Defaults to true.

---@class QBProgressBarPayload
---@field label string Text shown above the bar.
---@field duration integer Milliseconds the bar takes to fill. Must be > 0 and <= Config.progressbar.maxDuration.
---@field canCancel? boolean Lets the player abort early with one of Config.progressbar.cancelControls. Defaults to false.
---@field disable? QBProgressBarDisable
---@field anim? QBProgressBarAnim Played for the duration, stopped and released automatically when the bar ends. Mutually exclusive with `scenario`.
---@field scenario? QBProgressBarScenario Played in place for the duration, stopped automatically when the bar ends. Mutually exclusive with `anim`.
---@field props? QBProgressBarProp[] Local cosmetic props attached to the player for the duration.

local busy = false
local activeSession = nil

local COMBAT_CONTROLS = { 24, 25, 47, 58, 140, 141, 142, 143 }
local CAR_CONTROLS = { 63, 64, 71, 72 }

local function deleteProgressProp(entity)
    if not entity or not DoesEntityExist(entity) then return end
    DetachEntity(entity, true, true)
    DeleteEntity(entity)
end

local propRegistry = QB.resources.registry(function(entity)
    local ok, err = pcall(deleteProgressProp, entity)
    if not ok then
        print(("[qblib:progressbar] failed to clean up prop %s: %s"):format(tostring(entity), tostring(err)))
    end
end)

local function isInteger(value)
    return type(value) == "number" and value % 1 == 0
end

local function assertVector(value, field, index)
    local valueType = type(value)
    assert((valueType == "table" or valueType == "vector3")
            and type(value.x) == "number" and type(value.y) == "number" and type(value.z) == "number",
        ("Progress bar prop %d %s must be vector-like with numeric x/y/z fields."):format(index, field))
end

local function modelHash(model)
    return type(model) == "string" and joaat(model) or model
end

---@param payload QBProgressBarPayload
local function assertPayload(payload)
    assert(type(payload) == "table", "Progress bar payload must be a table.")
    assert(type(payload.label) == "string" and #payload.label > 0, "Progress bar requires a label string.")
    assert(isInteger(payload.duration) and payload.duration > 0, "Progress bar duration must be a positive integer.")
    assert(payload.duration <= Config.progressbar.maxDuration,
        ("Progress bar duration must be at most %d ms (Config.progressbar.maxDuration)."):format(Config.progressbar.maxDuration))
    assert(payload.canCancel == nil or type(payload.canCancel) == "boolean",
        "Progress bar canCancel must be a boolean.")

    if payload.anim then
        assert(type(payload.anim) == "table" and type(payload.anim.dict) == "string" and type(payload.anim.clip) == "string",
            "Progress bar anim requires string dict/clip fields.")
    end

    if payload.scenario then
        assert(type(payload.scenario) == "table" and type(payload.scenario.name) == "string" and #payload.scenario.name > 0,
            "Progress bar scenario requires a string name field.")
    end

    assert(not (payload.anim and payload.scenario), "Progress bar cannot play both anim and scenario -- pick one.")

    if payload.props == nil then return end
    assert(type(payload.props) == "table", "Progress bar props must be an array.")
    assert(#payload.props <= Config.progressbar.maxProps,
        ("Progress bar supports at most %d props (Config.progressbar.maxProps)."):format(Config.progressbar.maxProps))

    local propCount = 0
    for key in pairs(payload.props) do
        assert(type(key) == "number" and key % 1 == 0 and key >= 1,
            "Progress bar props must be a dense array.")
        propCount = propCount + 1
    end
    assert(propCount == #payload.props, "Progress bar props must be a dense array.")

    for index, prop in ipairs(payload.props) do
        assert(type(prop) == "table", ("Progress bar prop %d must be a table."):format(index))
        assert(type(prop.model) == "string" or isInteger(prop.model),
            ("Progress bar prop %d requires a string model name or integer hash."):format(index))
        assert(IsModelValid(modelHash(prop.model)), ("Progress bar prop %d has an invalid model."):format(index))

        if prop.bone ~= nil then
            assert((type(prop.bone) == "string" and #prop.bone > 0) or (isInteger(prop.bone) and prop.bone >= 0),
                ("Progress bar prop %d bone must be a non-negative integer ID or non-empty name."):format(index))
        end
        if prop.offset ~= nil then assertVector(prop.offset, "offset", index) end
        if prop.rotation ~= nil then assertVector(prop.rotation, "rotation", index) end

        for _, field in ipairs({ "softPinning", "collision", "syncRotation" }) do
            assert(prop[field] == nil or type(prop[field]) == "boolean",
                ("Progress bar prop %d %s must be a boolean."):format(index, field))
        end

        if prop.rotationOrder ~= nil then
            assert(isInteger(prop.rotationOrder) and prop.rotationOrder >= 0 and prop.rotationOrder <= 5,
                ("Progress bar prop %d rotationOrder must be an integer from 0 to 5."):format(index))
        end
    end
end

---@param dict string
---@return boolean loaded
local function ensureAnimDict(dict)
    local ok, loaded = pcall(QB.stream.loadAnimDict, dict)
    return ok and loaded ~= false
end

local function safeCleanup(label, fn)
    local ok, err = pcall(fn)
    if not ok then
        print(("[qblib:progressbar] %s cleanup failed: %s"):format(label, tostring(err)))
    end
end

local function cleanupSession(session, cancelled)
    if not session or session.cleaned then return end
    session.cleaned = true

    if activeSession == session then activeSession = nil end
    busy = false

    if session.carLease then
        QB.controls.release(session.carLease)
        session.carLease = nil
    end
    if session.combatLease then
        QB.controls.release(session.combatLease)
        session.combatLease = nil
    end

    if session.frozen then
        safeCleanup("ped freeze", function() FreezeEntityPosition(session.ped, false) end)
        session.frozen = false
    end

    if session.scenarioStarted then
        safeCleanup("scenario", function() ClearPedTasks(session.ped) end)
        session.scenarioStarted = false
    elseif session.animLoaded then
        if session.animStarted then
            safeCleanup("animation", function()
                StopAnimTask(session.ped, session.anim.dict, session.anim.clip, session.anim.blendOut or 8.0)
            end)
        end
        safeCleanup("animation dictionary", function() RemoveAnimDict(session.anim.dict) end)
        session.animLoaded = false
        session.animStarted = false
    end

    for _, entity in ipairs(session.props) do
        propRegistry.untrack(entity)
        safeCleanup("prop", function() deleteProgressProp(entity) end)
    end
    session.props = {}

    if cancelled and session.nuiStarted then
        safeCleanup("NUI", function() QB.nui.send("progressCancel") end)
    end
end

local function discardProp(session, entity)
    if not entity then return end
    propRegistry.untrack(entity)
    safeCleanup("prop", function() deleteProgressProp(entity) end)

    for index, tracked in ipairs(session.props) do
        if tracked == entity then
            table.remove(session.props, index)
            return
        end
    end
end

local function prepareProp(session, definition, index)
    local entity
    local ok, err = pcall(function()
        local loaded, loadErr = QB.stream.loadModel(definition.model, function(hash)
            if session.cleaned then return end

            local coords = GetEntityCoords(session.ped)
            entity = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, false, false, false)
            if not entity or entity == 0 or not DoesEntityExist(entity) then
                error("CreateObjectNoOffset did not return a valid entity.")
            end

            session.props[#session.props + 1] = entity
            propRegistry.track(session.owner, entity)

            local bone = definition.bone or 60309
            local boneIndex = type(bone) == "string"
                and GetEntityBoneIndexByName(session.ped, bone)
                or GetPedBoneIndex(session.ped, bone)
            if boneIndex == -1 then error(("ped bone '%s' was not found."):format(tostring(bone))) end

            local offset = definition.offset or { x = 0.0, y = 0.0, z = 0.0 }
            local rotation = definition.rotation or { x = 0.0, y = 0.0, z = 0.0 }
            AttachEntityToEntity(entity, session.ped, boneIndex,
                offset.x, offset.y, offset.z,
                rotation.x, rotation.y, rotation.z,
                false,
                definition.softPinning ~= false,
                definition.collision == true,
                true,
                definition.rotationOrder or 0,
                definition.syncRotation ~= false)
        end)

        if not loaded then error(loadErr or "model streaming timed out.") end
    end)

    if not ok then
        discardProp(session, entity)
        print(("[qblib:progressbar] prop %d could not be created -- continuing without it: %s")
            :format(index, tostring(err)))
    end
end

local function updateVehicleControls(session, enabled)
    local shouldHold = enabled and IsPedInAnyVehicle(session.ped, false)

    if shouldHold and not session.carLease then
        session.carLease = QB.controls.acquire(CAR_CONTROLS)
    elseif not shouldHold and session.carLease then
        QB.controls.release(session.carLease)
        session.carLease = nil
    end
end

---Shows a filling progress bar and reports whether it ran to completion.
---@param payload QBProgressBarPayload
---@return boolean completed
---@return string? error
function QB.progressbar.start(payload)
    assertPayload(payload)

    if busy then return false, "A progress bar is already active." end

    local session = {
        owner = GetInvokingResource() or GetCurrentResourceName(),
        ped = PlayerPedId(),
        props = {},
        anim = payload.anim,
        cleaned = false,
        cancelRequested = false,
    }

    busy = true
    activeSession = session

    local ok, result = pcall(function()
        for index, prop in ipairs(payload.props or {}) do
            prepareProp(session, prop, index)
            if session.cleaned then return false end
        end

        if payload.anim then
            session.animLoaded = ensureAnimDict(payload.anim.dict)
            if session.cleaned then return false end
            if session.animLoaded then
                TaskPlayAnim(session.ped, payload.anim.dict, payload.anim.clip,
                    payload.anim.blendIn or 8.0, payload.anim.blendOut or 8.0,
                    -1, payload.anim.flag or 1, 0, false, false, false)
                session.animStarted = true
            else
                print(("[qblib:progressbar] anim dict '%s' could not be loaded -- continuing without it.")
                    :format(payload.anim.dict))
            end
        elseif payload.scenario then
            TaskStartScenarioInPlace(session.ped, payload.scenario.name, 0, payload.scenario.playEnter ~= false)
            session.scenarioStarted = true
        end

        if payload.disable and payload.disable.move then
            FreezeEntityPosition(session.ped, true)
            session.frozen = true
        end

        if payload.disable and payload.disable.combat then
            session.combatLease = QB.controls.acquire(COMBAT_CONTROLS, { disablePlayerFiring = true })
        end
        updateVehicleControls(session, payload.disable and payload.disable.car == true)

        if session.cleaned then return false end

        session.nuiStarted = true
        QB.nui.send("progressStart", { label = payload.label, duration = payload.duration })

        local cancelled = QB.loops.controlled(function()
            if session.cleaned or activeSession ~= session then return true end
            if IsEntityDead(session.ped) or session.cancelRequested then return true end

            updateVehicleControls(session, payload.disable and payload.disable.car == true)

            if payload.canCancel then
                for _, control in ipairs(Config.progressbar.cancelControls) do
                    if IsControlJustPressed(0, control) then return true end
                end
            end
            return false
        end, false, payload.duration)

        local completed = cancelled == false and not session.cleaned
        cleanupSession(session, not completed)
        return completed
    end)

    if not ok then
        cleanupSession(session, true)
        error(result, 0)
    end

    if not session.cleaned then cleanupSession(session, not result) end
    return result
end

---Requests cancellation of the active progress bar.
---@return boolean cancelled
function QB.progressbar.cancel()
    local session = activeSession
    if not session or session.cleaned then return false end
    session.cancelRequested = true
    return true
end

---@return boolean
function QB.progressbar.isActive()
    return busy
end

AddEventHandler("onClientResourceStop", function(resourceName)
    local session = activeSession
    if not session then return end

    if resourceName == session.owner or resourceName == GetCurrentResourceName() then
        session.cancelRequested = true
        cleanupSession(session, true)
    end
end)
