---@class QBProgressBarDisable
---@field move? boolean Freezes the ped in place for the duration (`FreezeEntityPosition`). Defaults to false.
---@field moveMode? 'freeze'|'controls' How move=true is enforced. Defaults to freeze; ox compatibility uses controls.
---@field controlProfile? 'kora_lib'|'ox' Selects the exact control set. Defaults to kora_lib.
---@field sprint? boolean Disables sprinting. Defaults to false.
---@field combat? boolean Disables attack/aim/weapon-switch/melee controls for the duration. Defaults to false.
---@field car? boolean Disables vehicle driving controls while the ped is in a vehicle. Defaults to false.
---@field vehicle? boolean Alias of `car`.
---@field mouse? boolean Disables look input. Defaults to false.

---@class QBProgressBarAnim
---@field dict string Animation dictionary to play, requested and released automatically.
---@field clip string Clip name within `dict`.
---@field flag? number AnimFlags bitmask passed to `TaskPlayAnim`. Defaults to 1 (loop).
---@field blendIn? number Defaults to 8.0.
---@field blendOut? number Defaults to 8.0.
---@field stopBlendOut? number Cleanup blend-out override; ox_lib compatibility uses 1.0.
---@field duration? integer Animation duration; defaults to -1.
---@field playbackRate? number Animation playback rate; defaults to 0.
---@field lockX? boolean
---@field lockY? boolean
---@field lockZ? boolean

---@class QBProgressBarScenario
---@field name string Scenario name to play, e.g. `"WORLD_HUMAN_HAMMERING"`.
---@field playEnter? boolean Whether to play the scenario's enter animation. Defaults to true.

---@class QBProgressBarProp
---@field model string|integer Model name or hash.
---@field bone? string|integer Ped bone name or ID. Defaults to 60309.
---@field offset? vector3|table Local attachment offset. Defaults to vector3(0, 0, 0).
---@field coords? vector3 Legacy `prop`/`proptwo` attachment offset.
---@field rotation? vector3|table Local attachment rotation. Defaults to vector3(0, 0, 0).
---@field softPinning? boolean Defaults to true.
---@field collision? boolean Defaults to false.
---@field rotationOrder? integer Defaults to 0.
---@field syncRotation? boolean Defaults to true.

---@class QBProgressBarPayload
---@field label string Text shown above the bar.
---@field duration integer Milliseconds the bar takes to fill. Must be > 0 and <= Config.progressbar.maxDuration.
---@field maxDuration? integer|false Override the duration cap; false matches ox_lib's unbounded positive durations.
---@field canCancel? boolean Lets the player abort early with one of Config.progressbar.cancelControls. Defaults to false.
---@field cancelControls? integer[]|false Override the local cancel controls; false delegates cancellation to a compatibility command.
---@field useWhileDead? boolean Defaults to false.
---@field allowRagdoll? boolean Defaults to false.
---@field allowCuffed? boolean Defaults to false.
---@field allowFalling? boolean Defaults to false.
---@field allowSwimming? boolean Defaults to false.
---@field presentation? 'bar'|'circle' Defaults to bar.
---@field position? 'middle'|'bottom' Circle placement; defaults to middle.
---@field disable? QBProgressBarDisable
---@field anim? QBProgressBarAnim Played for the duration, stopped and released automatically when the bar ends. Mutually exclusive with `scenario`.
---@field strictAnim? boolean Raise when an animation dictionary cannot load; ox_lib compatibility enables this.
---@field scenario? QBProgressBarScenario Played in place for the duration, stopped automatically when the bar ends. Mutually exclusive with `anim`.
---@field props? QBProgressBarProp[] Local cosmetic props attached to the player for the duration.
---@field prop? QBProgressBarProp Local cosmetic prop using `coords`.
---@field proptwo? QBProgressBarProp Second local cosmetic prop using `coords`.
---@field emote? string Played when neither `anim` nor `scenario` is supplied.
---@field maxProps? integer|false Override the local prop cap; false matches ox_lib's uncapped local props.

local busy = false
local activeSession = nil
local isInteger = Kora.util.isInteger
local isFiniteNumber = Kora.util.isFiniteNumber

local COMBAT_CONTROLS = { 24, 25, 47, 58, 140, 141, 142, 143 }
local CAR_CONTROLS = { 63, 64, 71, 72 }
local SPRINT_CONTROLS = { 21 }
local MOUSE_CONTROLS = { 1, 2, 106 }
local MOVEMENT_CONTROLS = { 21, 30, 31, 36 }
local OX_COMBAT_CONTROLS = { 25 }
local OX_CAR_CONTROLS = { 63, 64, 71, 72, 75 }
local BEHAVIOUR_FIELDS = { 'useWhileDead', 'allowRagdoll', 'allowCuffed', 'allowFalling', 'allowSwimming' }
-- `vehicle` is an alias of `car`: several resources were written against that name.
local DISABLE_FIELDS = { 'move', 'sprint', 'combat', 'car', 'vehicle', 'mouse' }
local KNOWN_PAYLOAD_KEYS = {
    label = true, duration = true, maxDuration = true, canCancel = true, cancelControls = true,
    useWhileDead = true, allowRagdoll = true, allowCuffed = true, allowFalling = true, allowSwimming = true,
    presentation = true, position = true, disable = true, anim = true, strictAnim = true, scenario = true,
    props = true, prop = true, proptwo = true, emote = true, maxProps = true,
}
local KNOWN_DISABLE_KEYS = { moveMode = true, controlProfile = true }
for i = 1, #DISABLE_FIELDS do KNOWN_DISABLE_KEYS[DISABLE_FIELDS[i]] = true end
local ANIM_LOCK_FIELDS = { 'lockX', 'lockY', 'lockZ' }
local PROP_BOOLEAN_FIELDS = { 'softPinning', 'collision', 'syncRotation' }
local LEASE_FIELDS = { 'carLease', 'combatLease', 'sprintLease', 'mouseLease', 'movementLease' }

local function deleteProgressProp(entity)
    if not entity or not DoesEntityExist(entity) then return end
    DetachEntity(entity, true, true)
    DeleteEntity(entity)
end

local propRegistry = Kora.resources.registry(function(entity)
    local ok, err = pcall(deleteProgressProp, entity)
    if not ok then
        print(("[kora_lib:progressbar] failed to clean up prop %s: %s"):format(tostring(entity), tostring(err)))
    end
end)

local function assertVector(value, field, index)
    local valueType = type(value)
    assert((valueType == "table" or valueType == "vector3")
            and isFiniteNumber(value.x) and isFiniteNumber(value.y) and isFiniteNumber(value.z),
        ("Progress bar prop %d %s must be vector-like with finite x/y/z fields."):format(index, field))
end

local function modelHash(model)
    return type(model) == "string" and joaat(model) or model
end

local function assertProp(prop, index, requireCoords)
    assert(type(prop) == "table", ("Progress bar prop %d must be a table."):format(index))
    assert(type(prop.model) == "string" or isInteger(prop.model),
        ("Progress bar prop %d requires a string model name or integer hash."):format(index))
    assert(IsModelValid(modelHash(prop.model)), ("Progress bar prop %d has an invalid model."):format(index))
    assert(not requireCoords or prop.coords ~= nil, ("Progress bar prop %d requires coords."):format(index))
    assert(not requireCoords or isInteger(prop.bone), ("Progress bar prop %d requires an integer bone ID."):format(index))
    assert(not requireCoords or prop.rotation ~= nil, ("Progress bar prop %d requires rotation."):format(index))

    if prop.bone ~= nil then
        assert((type(prop.bone) == "string" and #prop.bone > 0) or (isInteger(prop.bone) and prop.bone >= 0),
            ("Progress bar prop %d bone must be a non-negative integer ID or non-empty name."):format(index))
    end
    if prop.offset ~= nil then assertVector(prop.offset, "offset", index) end
    if prop.coords ~= nil then assertVector(prop.coords, "coords", index) end
    if prop.rotation ~= nil then assertVector(prop.rotation, "rotation", index) end

    for i = 1, #PROP_BOOLEAN_FIELDS do
        local field = PROP_BOOLEAN_FIELDS[i]
        assert(prop[field] == nil or type(prop[field]) == "boolean",
            ("Progress bar prop %d %s must be a boolean."):format(index, field))
    end

    if prop.rotationOrder ~= nil then
        assert(isInteger(prop.rotationOrder) and prop.rotationOrder >= 0 and prop.rotationOrder <= 5,
            ("Progress bar prop %d rotationOrder must be an integer from 0 to 5."):format(index))
    end
end

---@param payload QBProgressBarPayload
local function assertPayload(payload)
    assert(type(payload) == "table", "Progress bar payload must be a table.")
    assert(type(payload.label) == "string" and #payload.label > 0, "Progress bar requires a label string.")
    assert(isInteger(payload.duration) and payload.duration > 0, "Progress bar duration must be a positive integer.")
    assert(payload.maxDuration == nil or payload.maxDuration == false
        or (isInteger(payload.maxDuration) and payload.maxDuration > 0),
        "Progress bar maxDuration must be a positive integer or false.")
    local maxDuration = payload.maxDuration == nil and Config.progressbar.maxDuration or payload.maxDuration
    assert(maxDuration == false or payload.duration <= maxDuration,
        ("Progress bar duration must be at most %d ms."):format(maxDuration or Config.progressbar.maxDuration))
    assert(payload.canCancel == nil or type(payload.canCancel) == "boolean",
        "Progress bar canCancel must be a boolean.")
    assert(payload.cancelControls == nil or payload.cancelControls == false or type(payload.cancelControls) == 'table',
        'Progress bar cancelControls must be an array or false.')
    if type(payload.cancelControls) == 'table' then
        local count = 0
        for key, control in pairs(payload.cancelControls) do
            assert(type(key) == 'number' and key >= 1 and key % 1 == 0,
                'Progress bar cancelControls must be a dense array.')
            assert(isInteger(control) and control >= 0, 'Progress bar cancelControls entries must be non-negative integers.')
            count = count + 1
        end
        assert(count == #payload.cancelControls, 'Progress bar cancelControls must be a dense array.')
    end
    for i = 1, #BEHAVIOUR_FIELDS do
        local field = BEHAVIOUR_FIELDS[i]
        assert(payload[field] == nil or type(payload[field]) == 'boolean',
            ("Progress bar %s must be a boolean."):format(field))
    end
    assert(payload.presentation == nil or payload.presentation == 'bar' or payload.presentation == 'circle',
        "Progress bar presentation must be 'bar' or 'circle'.")
    assert(payload.position == nil or payload.position == 'middle' or payload.position == 'bottom',
        "Progress bar position must be 'middle' or 'bottom'.")
    if payload.disable then
        assert(type(payload.disable) == 'table', 'Progress bar disable must be a table.')
        for i = 1, #DISABLE_FIELDS do
            local field = DISABLE_FIELDS[i]
            assert(payload.disable[field] == nil or type(payload.disable[field]) == 'boolean',
                ("Progress bar disable.%s must be a boolean."):format(field))
        end
        assert(payload.disable.moveMode == nil or payload.disable.moveMode == 'freeze' or payload.disable.moveMode == 'controls',
            "Progress bar disable.moveMode must be 'freeze' or 'controls'.")
        assert(payload.disable.controlProfile == nil or payload.disable.controlProfile == 'kora_lib'
            -- 'qblib' is the deprecated name of the default profile.
            or payload.disable.controlProfile == 'qblib' or payload.disable.controlProfile == 'ox',
            "Progress bar disable.controlProfile must be 'kora_lib' or 'ox'.")
    end

    if payload.anim then
        assert(type(payload.anim) == "table" and type(payload.anim.dict) == "string" and type(payload.anim.clip) == "string",
            "Progress bar anim requires string dict/clip fields.")
        assert(payload.anim.duration == nil or isInteger(payload.anim.duration), 'Progress bar anim duration must be an integer.')
        assert(payload.anim.playbackRate == nil or isFiniteNumber(payload.anim.playbackRate),
            'Progress bar anim playbackRate must be a finite number.')
        assert(payload.anim.stopBlendOut == nil or isFiniteNumber(payload.anim.stopBlendOut),
            'Progress bar anim stopBlendOut must be a finite number.')
        for i = 1, #ANIM_LOCK_FIELDS do
            local field = ANIM_LOCK_FIELDS[i]
            assert(payload.anim[field] == nil or type(payload.anim[field]) == 'boolean',
                ("Progress bar anim %s must be a boolean."):format(field))
        end
    end
    assert(payload.strictAnim == nil or type(payload.strictAnim) == 'boolean',
        'Progress bar strictAnim must be a boolean.')
    assert(payload.emote == nil or type(payload.emote) == 'string', 'Progress bar emote must be a string.')

    if payload.scenario then
        assert(type(payload.scenario) == "table" and type(payload.scenario.name) == "string" and #payload.scenario.name > 0,
            "Progress bar scenario requires a string name field.")
    end

    assert(not (payload.anim and payload.scenario), "Progress bar cannot play both anim and scenario -- pick one.")

    if payload.props ~= nil then
        assert(type(payload.props) == "table", "Progress bar props must be an array.")
        assert(payload.maxProps == nil or payload.maxProps == false or (isInteger(payload.maxProps) and payload.maxProps > 0),
            "Progress bar maxProps must be a positive integer or false.")
        local maxProps = payload.maxProps == nil and Config.progressbar.maxProps or payload.maxProps
        assert(maxProps == false or #payload.props <= maxProps,
            ("Progress bar supports at most %d props."):format(maxProps or Config.progressbar.maxProps))

        local propCount = 0
        for key in pairs(payload.props) do
            assert(type(key) == "number" and key % 1 == 0 and key >= 1,
                "Progress bar props must be a dense array.")
            propCount = propCount + 1
        end
        assert(propCount == #payload.props, "Progress bar props must be a dense array.")

        for index = 1, #payload.props do assertProp(payload.props[index], index, false) end
    end
    if payload.prop then assertProp(payload.prop, 1, true) end
    if payload.proptwo then assertProp(payload.proptwo, 2, true) end
end

-- resource -> key path -> true. An unknown key is usually a typo or another library's
-- vocabulary (X7: disable.vehicle was ignored for months), so say so once instead of never.
local warnedUnknownKeys = {}

local function warnUnknownKey(resource, path)
    local warned = warnedUnknownKeys[resource]
    if not warned then
        warned = {}
        warnedUnknownKeys[resource] = warned
    end
    if warned[path] then return end
    warned[path] = true
    print(("[kora_lib:progressbar] %s passed unknown progress bar option '%s'; it is ignored."):format(resource, path))
end

local function warnUnknownKeys(payload)
    local resource = GetInvokingResource() or GetCurrentResourceName()
    for key in pairs(payload) do
        if not KNOWN_PAYLOAD_KEYS[key] then warnUnknownKey(resource, tostring(key)) end
    end
    if type(payload.disable) == 'table' then
        for key in pairs(payload.disable) do
            if not KNOWN_DISABLE_KEYS[key] then warnUnknownKey(resource, 'disable.' .. tostring(key)) end
        end
    end
end

local function disablesVehicle(disable)
    return disable ~= nil and (disable.car == true or disable.vehicle == true)
end

---Validates a progress-bar payload without starting a bar. Unknown top-level and `disable`
---keys are reported once per calling resource and key.
---@param payload QBProgressBarPayload
---@return true
function Kora.progressbar.validate(payload)
    assertPayload(payload)
    warnUnknownKeys(payload)
    return true
end

---@param dict string
---@return boolean loaded
local function ensureAnimDict(dict)
    local ok, loaded = pcall(Kora.stream.loadAnimDict, dict)
    return ok and loaded ~= false
end

local function safeCleanup(label, fn)
    local ok, err = pcall(fn)
    if not ok then
        print(("[kora_lib:progressbar] %s cleanup failed: %s"):format(label, tostring(err)))
    end
end

local function cleanupSession(session, cancelled)
    if not session or session.cleaned then return end
    session.cleaned = true

    if activeSession == session then activeSession = nil end
    busy = false

    for i = 1, #LEASE_FIELDS do
        local field = LEASE_FIELDS[i]
        if session[field] then
            Kora.compat.releaseControlLease(session[field], session.owner)
            session[field] = nil
        end
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
                StopAnimTask(session.ped, session.anim.dict, session.anim.clip,
                    session.anim.stopBlendOut or session.anim.blendOut or 8.0)
            end)
        end
        safeCleanup("animation dictionary", function() RemoveAnimDict(session.anim.dict) end)
        session.animLoaded = false
        session.animStarted = false
    end

    if session.emoteStarted then
        safeCleanup("emote", function() exports.kora_emotemenu:cancelEmote(true) end)
        session.emoteStarted = false
    end

    for i = 1, #session.props do
        local entity = session.props[i]
        propRegistry.untrack(entity)
        safeCleanup("prop", function() deleteProgressProp(entity) end)
    end
    session.props = {}

    if cancelled and session.nuiStarted then
        safeCleanup("NUI", function() Kora.nui.send("progressCancel") end)
    end
end

local function discardProp(session, entity)
    if not entity then return end
    propRegistry.untrack(entity)
    safeCleanup("prop", function() deleteProgressProp(entity) end)

    for index = 1, #session.props do
        local tracked = session.props[index]
        if tracked == entity then
            table.remove(session.props, index)
            return
        end
    end
end

local function prepareProp(session, definition, index)
    local entity
    local ok, err = pcall(function()
        local loaded, loadErr = Kora.stream.loadModel(definition.model, function(hash)
            if session.cleaned then return end

            local coords = GetEntityCoords(session.ped)
            if session.networkedProps then
                entity = CreateObject(hash, coords.x, coords.y, coords.z, true, true, true)
            else
                entity = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, false, false, false)
            end
            if not entity or entity == 0 or not DoesEntityExist(entity) then
                error("CreateObjectNoOffset did not return a valid entity.")
            end

            session.props[#session.props + 1] = entity
            propRegistry.track(session.owner, entity)
            if session.networkedProps then
                local netId = NetworkGetNetworkIdFromEntity(entity)
                SetNetworkIdExistsOnAllMachines(netId, true)
                NetworkUseHighPrecisionBlending(netId, true)
                SetNetworkIdCanMigrate(netId, false)
            end

            local bone = definition.bone or 60309
            local boneIndex = type(bone) == "string"
                and GetEntityBoneIndexByName(session.ped, bone)
                or GetPedBoneIndex(session.ped, bone)
            assert(boneIndex ~= -1, ("ped bone '%s' was not found."):format(tostring(bone)))

            local offset = definition.offset or { x = 0.0, y = 0.0, z = 0.0 }
            local rotation = definition.rotation or { x = 0.0, y = 0.0, z = 0.0 }
            AttachEntityToEntity(entity, session.ped, boneIndex,
                offset.x, offset.y, offset.z,
                rotation.x, rotation.y, rotation.z,
                session.networkedProps == true,
                definition.softPinning ~= false,
                definition.collision == true,
                true,
                definition.rotationOrder or 0,
                definition.syncRotation ~= false)
        end)

        assert(loaded, loadErr or "model streaming timed out.")
    end)

    if not ok then
        discardProp(session, entity)
        print(("[kora_lib:progressbar] prop %d could not be created -- continuing without it: %s")
            :format(index, tostring(err)))
    end
end

local function updateVehicleControls(session, enabled, profile)
    local shouldHold = enabled and IsPedInAnyVehicle(session.ped, false)

    if shouldHold and not session.carLease then
        session.carLease = Kora.compat.acquireControls(profile == 'ox' and OX_CAR_CONTROLS or CAR_CONTROLS, nil, session.owner)
    elseif not shouldHold and session.carLease then
        Kora.compat.releaseControlLease(session.carLease, session.owner)
        session.carLease = nil
    end
end

---Shows a filling progress bar and reports whether it ran to completion.
---@param payload QBProgressBarPayload
---@param owner? string Internal owner override for compatibility providers.
---@return boolean completed
---@return string? error
function Kora.progressbar.start(payload, owner, hooks)
    Kora.progressbar.validate(payload)
    assert(owner == nil or (type(owner) == 'string' and owner ~= ''), 'Progress bar owner must be a non-empty string.')
    if hooks then
        assert(hooks.networkedProps == nil or type(hooks.networkedProps) == 'boolean', 'Networked props flag must be boolean.')
        for _, name in ipairs({ 'onStart', 'onTick', 'isFinished' }) do
            assert(hooks[name] == nil or Kora.compat.isCallable(hooks[name]), 'Progress hook must be callable.')
        end
    end
    local cancelControls = payload.cancelControls == nil and Config.progressbar.cancelControls or payload.cancelControls

    if busy then return false, "A progress bar is already active." end

    local session = {
        owner = owner or GetInvokingResource() or GetCurrentResourceName(),
        ped = PlayerPedId(),
        props = {},
        networkedProps = hooks and hooks.networkedProps == true,
        anim = payload.anim,
        cleaned = false,
        cancelRequested = false,
    }

    busy = true
    activeSession = session

    local ok, result = pcall(function()
        local props = payload.props or {}
        for index = 1, #props do
            prepareProp(session, props[index], index)
            if session.cleaned then return false end
        end
        if payload.prop then
            prepareProp(session, { model = payload.prop.model, bone = payload.prop.bone, offset = payload.prop.coords,
                rotation = payload.prop.rotation }, #props + 1)
            if session.cleaned then return false end
        end
        if payload.proptwo then
            prepareProp(session, { model = payload.proptwo.model, bone = payload.proptwo.bone,
                offset = payload.proptwo.coords, rotation = payload.proptwo.rotation }, #props + 2)
            if session.cleaned then return false end
        end

        if payload.anim then
            session.animLoaded = ensureAnimDict(payload.anim.dict)
            if session.cleaned then return false end
            if session.animLoaded then
                TaskPlayAnim(session.ped, payload.anim.dict, payload.anim.clip,
                    payload.anim.blendIn or 8.0, payload.anim.blendOut or 8.0,
                    payload.anim.duration or -1, payload.anim.flag or 1, payload.anim.playbackRate or 0,
                    payload.anim.lockX == true, payload.anim.lockY == true, payload.anim.lockZ == true)
                session.animStarted = true
            elseif payload.strictAnim then
                error(("Progress bar animation dictionary '%s' could not be loaded."):format(payload.anim.dict))
            else
                print(("[kora_lib:progressbar] anim dict '%s' could not be loaded -- continuing without it.")
                    :format(payload.anim.dict))
            end
        elseif payload.scenario then
            TaskStartScenarioInPlace(session.ped, payload.scenario.name, 0, payload.scenario.playEnter ~= false)
            session.scenarioStarted = true
        elseif payload.emote then
            exports.kora_emotemenu:playEmote(payload.emote)
            session.emoteStarted = true
        end

        if payload.disable and payload.disable.move then
            if payload.disable.moveMode == 'controls' then
                session.movementLease = Kora.compat.acquireControls(MOVEMENT_CONTROLS, nil, session.owner)
            else
                FreezeEntityPosition(session.ped, true)
                session.frozen = true
            end
        end

        if payload.disable and payload.disable.combat then
            session.combatLease = Kora.compat.acquireControls(payload.disable.controlProfile == 'ox' and OX_COMBAT_CONTROLS or COMBAT_CONTROLS,
                { disablePlayerFiring = true }, session.owner)
        end
        if payload.disable and payload.disable.sprint then
            session.sprintLease = Kora.compat.acquireControls(SPRINT_CONTROLS, nil, session.owner)
        end
        if payload.disable and payload.disable.mouse then
            session.mouseLease = Kora.compat.acquireControls(MOUSE_CONTROLS, nil, session.owner)
        end
        updateVehicleControls(session, disablesVehicle(payload.disable),
            payload.disable and payload.disable.controlProfile)

        if session.cleaned then return false end

        session.nuiStarted = true
        Kora.nui.send("progressStart", {
            label = payload.label,
            duration = payload.duration,
            presentation = payload.presentation or 'bar',
            position = payload.position,
        })

        if hooks and hooks.onStart then hooks.onStart() end
        local finishedEarly = false
        local cancelled = Kora.loops.controlled(function()
            if session.cleaned or activeSession ~= session then return true end
            if hooks and hooks.onTick then hooks.onTick() end
            if hooks and hooks.isFinished and hooks.isFinished() then
                finishedEarly = true
                return true
            end
            if (not payload.useWhileDead and IsEntityDead(session.ped))
                or (not payload.allowRagdoll and IsPedRagdoll(session.ped))
                or (not payload.allowCuffed and IsPedCuffed(session.ped))
                or (not payload.allowFalling and IsPedFalling(session.ped))
                or (not payload.allowSwimming and IsPedSwimming(session.ped))
                or session.cancelRequested then return true end

            updateVehicleControls(session, disablesVehicle(payload.disable),
                payload.disable and payload.disable.controlProfile)

            if payload.canCancel and cancelControls then
                for i = 1, #cancelControls do
                    if IsControlJustPressed(0, cancelControls[i]) then return true end
                end
            end
            return false
        end, false, payload.duration)

        local completed = (cancelled == false or finishedEarly) and not session.cleaned
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

---Requests cancellation of the caller's active progress bar.
---@param owner? string Internal owner override for compatibility providers.
---@return boolean cancelled
function Kora.progressbar.cancel(owner)
    assert(owner == nil or (type(owner) == 'string' and owner ~= ''), 'Progress bar owner must be a non-empty string.')
    local session = activeSession
    if not session or session.cleaned then return false end
    local resource = owner or GetInvokingResource() or GetCurrentResourceName()
    if session.owner ~= resource then return false end
    session.cancelRequested = true
    return true
end

---@return boolean
function Kora.progressbar.isActive()
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
