---@class QBFxPtfxDef
---@field dict string Particle effect asset (ptfx) dictionary name, streamed via `QB.stream.loadPtfx`.
---@field name string Effect name within `dict`.
---@field bone? string Bone name to attach to, resolved via `GetEntityBoneIndexByName`. Only honored when `entity` is also given and `looped` is true -- see the function doc comment.
---@field entity? number Attaches the effect to this entity. Mutually exclusive with `coords` -- `entity` wins if both are given.
---@field coords? vector3 | {x: number, y: number, z: number} World-space effect origin. Ignored when `entity` is given.
---@field offset? vector3 | {x: number, y: number, z: number} Defaults to zero.
---@field rot? vector3 | {x: number, y: number, z: number} Defaults to zero.
---@field scale? number Defaults to 1.0.
---@field duration? integer ms after which a `looped` effect auto-stops. Ignored for non-looped effects, which have their own baked-in lifetime.
---@field looped? boolean Defaults to false (fire-and-forget, plays out on its own).

---@class QBFxPtfxHandle
---@field looped boolean
---@field particleId? number Set only when `looped` is true -- the handle `StopParticleFxLooped` needs.

---@class QBFxScreenHandle
---@field id integer Opaque per-call identifier; use the whole handle with `QB.fx.stopScreenEffect`.
---@field name string

-- Looped particle-fx handles, id = the native particle handle returned by
-- StartParticleFxLooped*. Non-looped effects have nothing worth tracking --
-- they end on their own and QB.fx.stop is a no-op for them (see its doc
-- comment) -- so only looped ones ever enter this registry.
local ptfxRegistry = QB.resources.registry(function(particleId)
    StopParticleFxLooped(particleId, false)
end)

-- The native is name-keyed, but callers still need independent lifetimes. A
-- per-call handle plus a name refcount prevents one resource stopping its
-- copy of an effect from cancelling another resource's still-live copy.
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

local screenRegistry = QB.resources.registry(disposeScreenHandle)

local function assertDuration(duration, label)
    if duration == nil then duration = 0 end
    assert(QB.util.isInteger(duration) and duration >= 0,
        ("%s must be a finite non-negative integer."):format(label))
    return duration
end

local function assertVec3(value, label)
    assert(value and QB.util.isFiniteNumber(value.x) and QB.util.isFiniteNumber(value.y)
            and QB.util.isFiniteNumber(value.z),
        ("%s must have finite x, y, and z values."):format(label))
end

---Plays a particle effect, streaming `def.dict` via `QB.stream.loadPtfx`'s
---callback form -- the dict is released immediately after the effect starts,
---which is safe: once `StartParticleFx*` has been called, the running effect
---no longer needs its source dict flagged as needed (same release-after-use
---timing `QB.anim.play` and `modules/progressbar` use for anim dicts).
---
---Bone attachment (`def.bone`) is only honored for a looped effect on an
---`entity` (`StartParticleFxLoopedOnEntityBone`) -- the non-looped on-entity
---native has no generic bone-index variant, only a ped-bone-specific one this
---module doesn't special-case. A non-looped effect with both `entity` and
---`bone` set plays at the entity's origin, ignoring `bone`.
---@param def QBFxPtfxDef
---@return QBFxPtfxHandle | false handle False if `def.dict` never streamed in time.
---@return string? error
function QB.fx.playPtfx(def)
    assert(type(def) == "table", "QB.fx.playPtfx requires a def table.")
    assert(type(def.dict) == "string" and type(def.name) == "string", "QB.fx.playPtfx requires string dict/name.")
    assert(def.entity ~= nil or def.coords ~= nil, "QB.fx.playPtfx requires either def.entity or def.coords.")
    assert(def.entity == nil or (QB.util.isInteger(def.entity) and def.entity > 0), "Particle effect entity must be a positive finite integer.")
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
    assert(QB.util.isFiniteNumber(scale), "Particle effect scale must be finite.")

    local particleId
    local started = false

    local loadedDict, loadErr = QB.stream.loadPtfx(def.dict, function()
        UseParticleFxAssetNextCall(def.dict)

        if def.entity then
            if looped then
                if def.bone then
                    local boneIndex = GetEntityBoneIndexByName(def.entity, def.bone)
                    particleId = StartParticleFxLoopedOnEntityBone(def.name, def.entity,
                        offset.x, offset.y, offset.z, rot.x, rot.y, rot.z,
                        boneIndex, scale, false, false, false)
                else
                    particleId = StartParticleFxLoopedOnEntity(def.name, def.entity,
                        offset.x, offset.y, offset.z, rot.x, rot.y, rot.z,
                        scale, false, false, false)
                end
            else
                StartParticleFxNonLoopedOnEntity(def.name, def.entity,
                    offset.x, offset.y, offset.z, rot.x, rot.y, rot.z, scale, false, false, false)
            end
        else
            if looped then
                particleId = StartParticleFxLoopedAtCoord(def.name,
                    def.coords.x + offset.x, def.coords.y + offset.y, def.coords.z + offset.z,
                    rot.x, rot.y, rot.z, scale, false, false, false, false)
            else
                StartParticleFxNonLoopedAtCoord(def.name,
                    def.coords.x + offset.x, def.coords.y + offset.y, def.coords.z + offset.z,
                    rot.x, rot.y, rot.z, scale, false, false, false)
            end
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
                if ptfxRegistry.owner(myParticleId) then -- still tracked -- not already stopped
                    ptfxRegistry.untrack(myParticleId)
                    StopParticleFxLooped(myParticleId, false)
                end
            end)
        end
    end

    return { looped = looped, particleId = looped and particleId or nil }
end

---Stops a looped particle effect started with `QB.fx.playPtfx`. A no-op for
---a non-looped handle (or `false`/`nil`) -- there is nothing to stop, the
---effect ends on its own.
---@param handle QBFxPtfxHandle | false
---@return boolean stopped
function QB.fx.stop(handle)
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
function QB.fx.screenEffect(name, duration, looped)
    assert(type(name) == "string" and #name > 0, "QB.fx.screenEffect requires a string effect name.")
    assert(looped == nil or type(looped) == "boolean", "QB.fx.screenEffect looped must be a boolean.")
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

---Stops a screen effect started with `QB.fx.screenEffect`.
---@param handle QBFxScreenHandle | false
---@return boolean stopped
function QB.fx.stopScreenEffect(handle)
    if not handle then return false end

    local id = handle.id
    if type(id) ~= "number" and type(handle.name) == "string" then
        local caller = GetInvokingResource() or GetCurrentResourceName()
        for candidateId, entry in pairs(screenHandles) do
            if entry.name == handle.name and screenRegistry.owner(candidateId) == caller then
                id = candidateId
                break
            end
        end
    end
    if type(id) ~= "number" then return false end

    local caller = GetInvokingResource() or GetCurrentResourceName()
    if screenRegistry.owner(id) ~= caller then return false end

    local owner = screenRegistry.untrack(id)
    if not owner then return false end

    return disposeScreenHandle(id)
end
