local ptfxRegistry = Kora.resources.registry(function(particleId)
    StopParticleFxLooped(particleId, false)
end)

local nextScreenId = 0
local screenHandles = {}
local screenRefcounts = {}

local function disposeScreenHandle(id)
    local entry = screenHandles[id]
    if not entry then return false end

    screenHandles[id] = nil
    local remaining = (screenRefcounts[entry.name] or 1) - 1
    if remaining <= 0 then
        screenRefcounts[entry.name] = nil
        StopScreenEffect(entry.name)
    else
        screenRefcounts[entry.name] = remaining
    end

    return true
end

local screenRegistry = Kora.resources.registry(disposeScreenHandle)

local function assertDuration(duration, label)
    if duration == nil then duration = 0 end
    assert(Kora.util.isInteger(duration) and duration >= 0,
        ("%s must be a finite non-negative integer."):format(label))
    return duration
end

local function assertVec3(value, label)
    assert(value and Kora.util.isFiniteNumber(value.x) and Kora.util.isFiniteNumber(value.y)
            and Kora.util.isFiniteNumber(value.z),
        ("%s must have finite x, y, and z values."):format(label))
end

---Plays a particle effect, releasing `def.dict` right after the effect starts (the running effect no longer needs it).
---Bone attachment is only honored for a looped effect on an `entity`; a non-looped one plays at the entity origin, ignoring `bone`.
---@param def QBFxPtfxDef
---@return QBFxPtfxHandle | false handle False if `def.dict` never streamed in time.
---@return string? error
function Kora.fx.playPtfx(def)
    assert(type(def) == "table", "Kora.fx.playPtfx requires a def table.")
    assert(type(def.dict) == "string" and type(def.name) == "string", "Kora.fx.playPtfx requires string dict/name.")
    assert(def.entity ~= nil or def.coords ~= nil, "Kora.fx.playPtfx requires either def.entity or def.coords.")
    assert(def.entity == nil or (Kora.util.isInteger(def.entity) and def.entity > 0), "Particle effect entity must be a positive finite integer.")
    assert(def.bone == nil or type(def.bone) == "string", "Particle effect bone must be a string.")
    assert(def.looped == nil or type(def.looped) == "boolean", "Particle effect looped must be a boolean.")
    local duration = assertDuration(def.duration, "Particle effect duration")

    local invokingResource = GetInvokingResource() or GetCurrentResourceName()

    local offset = def.offset
    if offset == nil then offset = { x = 0.0, y = 0.0, z = 0.0 } end
    local rot = def.rot
    if rot == nil then rot = { x = 0.0, y = 0.0, z = 0.0 } end
    local scale = def.scale
    if scale == nil then scale = 1.0 end
    local looped = def.looped == true
    if not def.entity then assertVec3(def.coords, "Particle effect coordinates") end
    assertVec3(offset, "Particle effect offset")
    assertVec3(rot, "Particle effect rotation")
    assert(Kora.util.isFiniteNumber(scale), "Particle effect scale must be finite.")

    local particleId
    local started = false

    local loadedDict, loadErr = Kora.stream.loadPtfx(def.dict, function()
        UseParticleFxAssetNextCall(def.dict)

        if def.entity and looped and def.bone then
            local boneIndex = GetEntityBoneIndexByName(def.entity, def.bone)
            particleId = StartParticleFxLoopedOnEntityBone(def.name, def.entity,
                offset.x, offset.y, offset.z, rot.x, rot.y, rot.z,
                boneIndex, scale, false, false, false)
        elseif def.entity and looped then
            particleId = StartParticleFxLoopedOnEntity(def.name, def.entity,
                offset.x, offset.y, offset.z, rot.x, rot.y, rot.z,
                scale, false, false, false)
        elseif def.entity then
            StartParticleFxNonLoopedOnEntity(def.name, def.entity,
                offset.x, offset.y, offset.z, rot.x, rot.y, rot.z, scale, false, false, false)
        elseif looped then
            particleId = StartParticleFxLoopedAtCoord(def.name,
                def.coords.x + offset.x, def.coords.y + offset.y, def.coords.z + offset.z,
                rot.x, rot.y, rot.z, scale, false, false, false, false)
        else
            StartParticleFxNonLoopedAtCoord(def.name,
                def.coords.x + offset.x, def.coords.y + offset.y, def.coords.z + offset.z,
                rot.x, rot.y, rot.z, scale, false, false, false)
        end

        started = true
    end)

    if not loadedDict then
        return false, loadErr
    end

    if not started then
        return false, "Failed to start particle effect."
    end

    if looped and particleId and particleId ~= -1 then
        ptfxRegistry.track(invokingResource, particleId)

        if duration > 0 then
            local myParticleId = particleId
            CreateThread(function()
                Wait(duration)
                if ptfxRegistry.owner(myParticleId) then
                    ptfxRegistry.untrack(myParticleId)
                    StopParticleFxLooped(myParticleId, false)
                end
            end)
        end
    end

    return { looped = looped, particleId = looped and particleId or nil }
end

---Stops a looped particle effect started with `Kora.fx.playPtfx`; a no-op for non-looped handles.
---@param handle QBFxPtfxHandle | false
---@return boolean stopped
function Kora.fx.stop(handle)
    if not handle or not handle.looped or not handle.particleId then return false end

    local caller = GetInvokingResource() or GetCurrentResourceName()
    if ptfxRegistry.owner(handle.particleId) ~= caller then return false end

    local owner = ptfxRegistry.untrack(handle.particleId)
    if not owner then return false end

    StopParticleFxLooped(handle.particleId, false)
    return true
end

---Starts a native full-screen post-process effect (e.g. "DrugsMichaelAliensFightIn").
---@param name string
---@param duration? integer ms passed to `StartScreenEffect`. Defaults to 0 (the effect's own default).
---@param looped? boolean Defaults to false.
---@return QBFxScreenHandle handle
function Kora.fx.screenEffect(name, duration, looped)
    assert(type(name) == "string" and #name > 0, "Kora.fx.screenEffect requires a string effect name.")
    assert(looped == nil or type(looped) == "boolean", "Kora.fx.screenEffect looped must be a boolean.")
    duration = assertDuration(duration, "Screen effect duration")

    local invokingResource = GetInvokingResource() or GetCurrentResourceName()

    StartScreenEffect(name, duration, looped == true)
    nextScreenId = nextScreenId + 1
    local id = nextScreenId
    screenHandles[id] = { name = name }
    screenRefcounts[name] = (screenRefcounts[name] or 0) + 1
    screenRegistry.track(invokingResource, id)

    return { id = id, name = name }
end

---Stops a screen effect started with `Kora.fx.screenEffect`.
---@param handle QBFxScreenHandle | false
---@return boolean stopped
function Kora.fx.stopScreenEffect(handle)
    if not handle then return false end

    local caller = GetInvokingResource() or GetCurrentResourceName()
    local id = handle.id
    if type(id) ~= "number" and type(handle.name) == "string" then
        for candidateId, entry in pairs(screenHandles) do
            if entry.name == handle.name and screenRegistry.owner(candidateId) == caller then
                id = candidateId
                break
            end
        end
    end
    if type(id) ~= "number" then return false end

    if screenRegistry.owner(id) ~= caller then return false end

    local owner = screenRegistry.untrack(id)
    if not owner then return false end

    return disposeScreenHandle(id)
end
