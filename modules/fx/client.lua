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
---@field name string

-- Looped particle-fx handles, id = the native particle handle returned by
-- StartParticleFxLooped*. Non-looped effects have nothing worth tracking --
-- they end on their own and QB.fx.stop is a no-op for them (see its doc
-- comment) -- so only looped ones ever enter this registry.
local ptfxRegistry = QB.resources.registry(function(particleId)
    StopParticleFxLooped(particleId, false)
end)

-- Screen effects are name-keyed (there is no per-call handle native side),
-- matching how modules/local/events and local/callback track their own
-- name-keyed registrations -- see local/resources/AGENTS.md.
local screenRegistry = QB.resources.registry(function(name)
    StopScreenEffect(name)
end)

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
    assert(def.entity or def.coords, "QB.fx.playPtfx requires either def.entity or def.coords.")

    local invokingResource = GetInvokingResource() or GetCurrentResourceName()

    local offset = def.offset or { x = 0.0, y = 0.0, z = 0.0 }
    local rot = def.rot or { x = 0.0, y = 0.0, z = 0.0 }
    local scale = def.scale or 1.0
    local looped = def.looped or false

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

        if def.duration and def.duration > 0 then
            local myParticleId = particleId
            CreateThread(function()
                Wait(def.duration)
                if ptfxRegistry.owner(myParticleId) then -- still tracked -- not already stopped
                    QB.fx.stop({ looped = true, particleId = myParticleId })
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

    local invokingResource = GetInvokingResource() or GetCurrentResourceName()

    StartScreenEffect(name, duration or 0, looped or false)
    screenRegistry.track(invokingResource, name)

    return { name = name }
end

---Stops a screen effect started with `QB.fx.screenEffect`.
---@param handle QBFxScreenHandle | false
---@return boolean stopped
function QB.fx.stopScreenEffect(handle)
    if not handle or not handle.name then return false end

    local owner = screenRegistry.untrack(handle.name)
    if not owner then return false end

    StopScreenEffect(handle.name)
    return true
end
