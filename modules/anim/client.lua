---@class QBAnimPlayOptions
---@field duration? integer ms passed to `TaskPlayAnim` as its own duration argument. Defaults to -1 (plays for the clip's natural length, or loops indefinitely if `flag` sets the loop bit).
---@field flag? number AnimFlags bitmask passed to `TaskPlayAnim`. Defaults to 1 (loop).
---@field blendInSpeed? number Defaults to 8.0.
---@field blendOutSpeed? number Defaults to 8.0.
---@field playbackRate? number 0..1, passed to `TaskPlayAnim`. Defaults to 0.0 (the clip's own baked-in rate).
---@field lockX? boolean Defaults to false.
---@field lockY? boolean Defaults to false.
---@field lockZ? boolean Defaults to false.
---@field onFinish? fun(entity: number) Called once, after `duration` ms have elapsed and the anim was stopped by this module (not called on an explicit `QB.anim.stop`, and not called at all when `duration` is omitted -- see the function doc comment).

---@class QBAnimHandle
---@field entity number
---@field dict string
---@field clip string

---@class QBAnimAttachOptions
---@field softPin? boolean Passed to `AttachEntityToEntity`'s useSoftPinning. Defaults to false.
---@field collision? boolean Passed to `AttachEntityToEntity`'s collision. Defaults to false.
---@field vertexIndex? number Legacy option name for the native's rotationOrder. Defaults to 0.
---@field fixedRot? boolean Defaults to true.

-- Keyed by entity, not a synthetic handle id -- QB.anim.stop/isPlaying take
-- the entity directly (matching how every other per-entity qblib primitive,
-- e.g. QB.cache, is addressed), so the entity itself IS the id space this
-- module tracks. A `generation` counter guards a delayed auto-stop thread
-- (started by a `duration` option) against stopping a LATER anim that
-- replaced the one it was scheduled for.
local activeByEntity = {}
local generationByEntity = {}

local function bumpGeneration(entity)
    local nextGeneration = (generationByEntity[entity] or 0) + 1
    generationByEntity[entity] = nextGeneration
    return nextGeneration
end

-- Ownership tracking (which resource started a given entity's anim, and bulk
-- cleanup when that resource stops) is delegated to the shared registry --
-- see local/resources/AGENTS.md. The id tracked here is the entity, same
-- space `activeByEntity` uses.
local animRegistry = QB.resources.registry(function(entity)
    QB.anim.stop(entity)
end)

-- Ownership tracking for attached props, id = the created prop entity.
-- Separate registry from animRegistry: unrelated id spaces (an anim's owning
-- entity vs. a prop's own entity handle) sharing one registry would corrupt
-- each other's reverse lookup -- see local/resources/AGENTS.md.
local propRegistry = QB.resources.registry(function(prop)
    if DoesEntityExist(prop) then
        DetachEntity(prop, true, false)
        DeleteEntity(prop)
    end
end)

---Plays an animation on `entity`, streaming `dict` first via
---`QB.stream.loadModel`'s sibling `QB.stream.loadAnimDict` -- called WITHOUT
---a callback, so the dict is deliberately left loaded for the anim's
---lifetime and released by this module (on `QB.anim.stop`, a `duration`
---timeout, or the owning resource stopping), not immediately after this
---function returns. Only one anim per entity is tracked at a time: starting
---a new one on an entity that already has one replaces it (the previous
---anim's dict is released, its `onFinish` is never called).
---@param entity number
---@param dict string
---@param clip string
---@param opts? QBAnimPlayOptions
---@return QBAnimHandle | false handle False if `dict` never streamed in time.
---@return string? error
function QB.anim.play(entity, dict, clip, opts)
    assert(type(entity) == "number" and entity ~= 0, ("Invalid entity: %s"):format(entity))
    assert(type(dict) == "string" and type(clip) == "string", "QB.anim.play requires string dict/clip.")

    -- Must be captured before QB.stream.loadAnimDict's own poll/Wait loop --
    -- the invoking-resource context is only valid at this call boundary,
    -- same reasoning modules/blips and modules/entities document for
    -- themselves.
    local invokingResource = GetInvokingResource() or GetCurrentResourceName()

    opts = opts or {}

    local loadedDict, loadErr = QB.stream.loadAnimDict(dict)
    if not loadedDict then
        return false, loadErr
    end

    -- Replacing whatever this entity was already doing: release the OLD
    -- dict, unless it's the same dict the new anim is about to use (a
    -- replay/re-parameterize on the same dict) -- in that case the dict we
    -- just resolved above IS the one still about to play, and freeing it
    -- here would release an asset this very call still needs. Also bumps
    -- `generation` so any in-flight duration timer for the old anim becomes
    -- a no-op instead of stopping the one we're about to start.
    local previous = activeByEntity[entity]
    if previous and previous.dict ~= dict then
        RemoveAnimDict(previous.dict)
    end

    local myGeneration = bumpGeneration(entity)

    TaskPlayAnim(entity, dict, clip,
        opts.blendInSpeed or 8.0, opts.blendOutSpeed or 8.0, opts.duration or -1,
        opts.flag or 1, opts.playbackRate or 0.0,
        opts.lockX or false, opts.lockY or false, opts.lockZ or false)

    local handle = { entity = entity, dict = dict, clip = clip, generation = myGeneration }
    activeByEntity[entity] = handle
    animRegistry.track(invokingResource, entity)

    if opts.duration and opts.duration > 0 then
        CreateThread(function()
            Wait(opts.duration)
            if generationByEntity[entity] ~= myGeneration then return end

            QB.anim.stop(entity)
            if opts.onFinish then opts.onFinish(entity) end
        end)
    end

    return handle
end

---Stops whatever anim `QB.anim.play` started on `entity` (a no-op if none is
---tracked) and releases its dict.
---@param entity number
---@param blendOutSpeed? number Defaults to 8.0.
---@return boolean stopped False if this module had nothing active on `entity`.
function QB.anim.stop(entity, blendOutSpeed)
    local handle = activeByEntity[entity]
    if not handle then return false end

    activeByEntity[entity] = nil
    animRegistry.untrack(entity)
    bumpGeneration(entity)

    if DoesEntityExist(entity) then
        StopAnimTask(entity, handle.dict, handle.clip, blendOutSpeed or 8.0)
    end
    RemoveAnimDict(handle.dict)

    return true
end

---Stops an animation only if `handle` is still the current animation on its
---entity. This is useful for compositional systems such as status effects,
---where tearing down an older effect must not stop a newer animation.
---@param handle QBAnimHandle
---@param blendOutSpeed? number
---@return boolean stopped
function QB.anim.stopHandle(handle, blendOutSpeed)
    if type(handle) ~= "table" then return false end
    local current = activeByEntity[handle.entity]
    if not current or current.generation ~= handle.generation then return false end
    return QB.anim.stop(handle.entity, blendOutSpeed)
end

---@param entity number
---@return boolean
function QB.anim.isPlaying(entity)
    local handle = activeByEntity[entity]
    if not handle then return false end
    return IsEntityPlayingAnim(entity, handle.dict, handle.clip, 3)
end

---Creates a local, non-networked prop (`CreateObjectNoOffset`, same
---placement native `modules/entities` uses for objects) and attaches it to
---`entity` at `bone`, streaming `model` first via `QB.stream.loadModel`.
---@param entity number
---@param model string | number
---@param bone string Bone name resolved via `GetEntityBoneIndexByName` -- works for both ped and non-ped target entities.
---@param offset? vector3 | {x: number, y: number, z: number} Defaults to zero offset.
---@param rotation? vector3 | {x: number, y: number, z: number} Defaults to zero rotation.
---@param opts? QBAnimAttachOptions
---@return number | false prop The created, attached prop entity, or false if the model never streamed or `entity`/`bone` was invalid.
---@return string? error
function QB.anim.attachProp(entity, model, bone, offset, rotation, opts)
    assert(type(entity) == "number" and DoesEntityExist(entity), ("Invalid entity: %s"):format(entity))
    assert(type(bone) == "string" and #bone > 0, "QB.anim.attachProp requires a string bone name.")

    local invokingResource = GetInvokingResource() or GetCurrentResourceName()

    offset = offset or { x = 0.0, y = 0.0, z = 0.0 }
    rotation = rotation or { x = 0.0, y = 0.0, z = 0.0 }
    opts = opts or {}

    local boneIndex = GetEntityBoneIndexByName(entity, bone)
    if boneIndex == -1 then
        return false, ("Bone '%s' does not exist on the target entity."):format(bone)
    end

    local prop

    local loadedModel, loadErr = QB.stream.loadModel(model, function(loadedModelHash)
        local created = CreateObjectNoOffset(loadedModelHash, offset.x, offset.y, offset.z, false, false, false)
        if created == 0 or not DoesEntityExist(created) then return end

        AttachEntityToEntity(created, entity, boneIndex,
            offset.x, offset.y, offset.z, rotation.x, rotation.y, rotation.z,
            false, opts.softPin or false, opts.collision or false, IsEntityAPed(entity),
            opts.vertexIndex or 0, opts.fixedRot ~= false)

        propRegistry.track(invokingResource, created)
        prop = created
    end)

    if not loadedModel then
        return false, loadErr
    end

    if not prop then
        return false, "Failed to create prop."
    end

    return prop
end

---Detaches and deletes a prop created with `QB.anim.attachProp`. Refuses
---props this module didn't create, matching `QB.entities.remove`/`QB.blips.remove`.
---@param prop number
---@return boolean success
---@return string? error
function QB.anim.detachProp(prop)
    assert(type(prop) == "number", ("Invalid prop: %s"):format(prop))

    local owner = propRegistry.untrack(prop)
    if not owner then
        return false, "Prop is not tracked by QB.anim."
    end

    if not DoesEntityExist(prop) then
        return false, "Prop does not exist."
    end

    DetachEntity(prop, true, false)
    DeleteEntity(prop)

    return true
end

---Starts a scenario on an entity. Scenarios have no streamed dictionary and
---are therefore deliberately separate from QB.anim.play's tracked lifecycle.
---@param entity number
---@param scenario string
---@param enterVehicle? boolean Defaults to false.
function QB.anim.playScenario(entity, scenario, enterVehicle)
    assert(type(entity) == 'number' and DoesEntityExist(entity), ('Invalid entity: %s'):format(entity))
    assert(type(scenario) == 'string' and #scenario > 0, 'QB.anim.playScenario requires a scenario.')
    TaskStartScenarioInPlace(entity, scenario, 0, enterVehicle == true)
end

---@param entity number
---@param immediate? boolean Defaults to false.
function QB.anim.clear(entity, immediate)
    assert(type(entity) == 'number' and DoesEntityExist(entity), ('Invalid entity: %s'):format(entity))
    QB.anim.stop(entity)
    if immediate then ClearPedTasksImmediately(entity) else ClearPedTasks(entity) end
end
