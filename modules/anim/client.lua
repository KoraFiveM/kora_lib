---@class QBAnimPlayOptions
---@field duration? integer ms passed to `TaskPlayAnim` as its own duration argument. Defaults to -1 (plays for the clip's natural length, or loops indefinitely if `flag` sets the loop bit).
---@field flag? number AnimFlags bitmask passed to `TaskPlayAnim`. Defaults to 1 (loop).
---@field blendInSpeed? number Defaults to 8.0.
---@field blendOutSpeed? number Defaults to 8.0.
---@field playbackRate? number 0..1, passed to `TaskPlayAnim`. Defaults to 0.0 (the clip's own baked-in rate).
---@field lockX? boolean Defaults to false.
---@field lockY? boolean Defaults to false.
---@field lockZ? boolean Defaults to false.
---@field onFinish? fun(entity: number) Called once, after `duration` ms have elapsed and the anim was stopped by this module (not called on an explicit `Kora.anim.stop`, and not called at all when `duration` is omitted -- see the function doc comment).

---@class QBAnimHandle
---@field entity number
---@field dict string
---@field clip string

---@class QBAnimAttachOptions
---@field softPin? boolean Passed to `AttachEntityToEntity`'s useSoftPinning. Defaults to false.
---@field collision? boolean Passed to `AttachEntityToEntity`'s collision. Defaults to false.
---@field vertexIndex? number Legacy option name for the native's rotationOrder. Defaults to 0.
---@field fixedRot? boolean Defaults to true.

-- Keyed by entity. A per-entity `generation` counter stops a delayed auto-stop
-- thread from stopping a LATER anim that replaced the one it was scheduled for.
local activeByEntity = {}
local generationByEntity = {}
local isInteger = Kora.util.isInteger
local isCallable = Kora.compat.isCallable

local function bumpGeneration(entity)
    local nextGeneration = (generationByEntity[entity] or 0) + 1
    generationByEntity[entity] = nextGeneration
    return nextGeneration
end

local function resolveBlendOutSpeed(value)
    assert(value == nil or Kora.util.isFiniteNumber(value), 'Animation blendOutSpeed must be finite.')
    return value or 8.0
end

-- Ownership/cleanup on resource stop is delegated to the shared registry
-- (local/resources/AGENTS.md); id = entity.
local animRegistry = Kora.resources.registry(function(entity)
    Kora.anim.stop(entity)
end)

-- Separate from animRegistry: mixing entity and prop id spaces in one registry
-- would corrupt reverse lookup (local/resources/AGENTS.md).
local propRegistry = Kora.resources.registry(function(prop)
    if DoesEntityExist(prop) then
        DetachEntity(prop, true, false)
        DeleteEntity(prop)
    end
end)

---Plays an animation on `entity`. The dict is loaded via `Kora.stream.loadAnimDict` without
---a callback and released on stop, `duration` timeout, or owner stop. One anim per entity:
---a new one replaces the old (its `onFinish` is never called).
---@param entity number
---@param dict string
---@param clip string
---@param opts? QBAnimPlayOptions
---@return QBAnimHandle | false handle False if `dict` never streamed in time.
---@return string? error
function Kora.anim.play(entity, dict, clip, opts)
    assert(type(entity) == "number" and entity ~= 0, ("Invalid entity: %s"):format(entity))
    assert(type(dict) == "string" and type(clip) == "string", "Kora.anim.play requires string dict/clip.")

    -- Capture before loadAnimDict yields: the invoking resource is only valid at the call boundary.
    local invokingResource = GetInvokingResource() or GetCurrentResourceName()

    assert(opts == nil or type(opts) == "table", "Animation options must be a table.")
    opts = opts or {}
    local duration = opts.duration
    assert(duration == nil or (isInteger(duration) and duration >= -1),
        "Animation duration must be -1 or a non-negative finite integer.")
    assert(opts.flag == nil or isInteger(opts.flag), 'Animation flag must be a finite integer.')
    assert(opts.blendInSpeed == nil or Kora.util.isFiniteNumber(opts.blendInSpeed),
        'Animation blendInSpeed must be finite.')
    assert(opts.blendOutSpeed == nil or Kora.util.isFiniteNumber(opts.blendOutSpeed),
        'Animation blendOutSpeed must be finite.')
    assert(opts.playbackRate == nil or Kora.util.isFiniteNumber(opts.playbackRate),
        'Animation playbackRate must be finite.')
    for _, field in ipairs({ 'lockX', 'lockY', 'lockZ' }) do
        assert(opts[field] == nil or type(opts[field]) == 'boolean',
            ('Animation %s must be a boolean.'):format(field))
    end
    assert(opts.onFinish == nil or isCallable(opts.onFinish), "Animation onFinish must be callable.")

    local currentOwner = animRegistry.owner(entity)
    if currentOwner and currentOwner ~= invokingResource then
        return false, "Animation is owned by another resource."
    end

    local loadedDict, loadErr = Kora.stream.loadAnimDict(dict)
    if not loadedDict then
        return false, loadErr
    end

    -- Release the OLD dict unless the new anim reuses it. Bumping `generation`
    -- turns the old anim's in-flight duration timer into a no-op.
    local previous = activeByEntity[entity]
    if previous and previous.dict ~= dict then
        RemoveAnimDict(previous.dict)
    end

    local myGeneration = bumpGeneration(entity)

    TaskPlayAnim(entity, dict, clip,
        opts.blendInSpeed or 8.0, opts.blendOutSpeed or 8.0, duration or -1,
        opts.flag or 1, opts.playbackRate or 0.0,
        opts.lockX or false, opts.lockY or false, opts.lockZ or false)

    local handle = { entity = entity, dict = dict, clip = clip, generation = myGeneration }
    activeByEntity[entity] = handle
    animRegistry.track(invokingResource, entity)

    if duration and duration > 0 then
        CreateThread(function()
            Wait(duration)
            if generationByEntity[entity] ~= myGeneration then return end

            Kora.anim.stop(entity)
            if opts.onFinish then
                local ok, err = pcall(opts.onFinish, entity)
                if not ok then
                    print(("[kora_lib] Kora.anim onFinish (%s) errored: %s"):format(invokingResource, tostring(err)))
                end
            end
        end)
    end

    return handle
end

---Stops whatever anim `Kora.anim.play` started on `entity` (a no-op if none is
---tracked) and releases its dict.
---@param entity number
---@param blendOutSpeed? number Defaults to 8.0.
---@return boolean stopped False if this module had nothing active on `entity`.
function Kora.anim.stop(entity, blendOutSpeed)
    blendOutSpeed = resolveBlendOutSpeed(blendOutSpeed)

    local handle = activeByEntity[entity]
    if not handle then return false end

    local invoker = GetInvokingResource()
    if invoker and animRegistry.owner(entity) ~= invoker then return false end

    activeByEntity[entity] = nil
    animRegistry.untrack(entity)
    bumpGeneration(entity)

    if DoesEntityExist(entity) then
        StopAnimTask(entity, handle.dict, handle.clip, blendOutSpeed)
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
function Kora.anim.stopHandle(handle, blendOutSpeed)
    if type(handle) ~= "table" then return false end
    local current = activeByEntity[handle.entity]
    if not current or current.generation ~= handle.generation then return false end
    return Kora.anim.stop(handle.entity, blendOutSpeed)
end

---@param entity number
---@return boolean
function Kora.anim.isPlaying(entity)
    local handle = activeByEntity[entity]
    if not handle then return false end
    return IsEntityPlayingAnim(entity, handle.dict, handle.clip, 3)
end

---Creates a local, non-networked prop (`CreateObjectNoOffset`, same
---placement native `modules/entities` uses for objects) and attaches it to
---`entity` at `bone`, streaming `model` first via `Kora.stream.loadModel`.
---@param entity number
---@param model string | number
---@param bone string Bone name resolved via `GetEntityBoneIndexByName` -- works for both ped and non-ped target entities.
---@param offset? vector3 | {x: number, y: number, z: number} Defaults to zero offset.
---@param rotation? vector3 | {x: number, y: number, z: number} Defaults to zero rotation.
---@param opts? QBAnimAttachOptions
---@return number | false prop The created, attached prop entity, or false if the model never streamed or `entity`/`bone` was invalid.
---@return string? error
function Kora.anim.attachProp(entity, model, bone, offset, rotation, opts)
    assert(type(entity) == "number" and DoesEntityExist(entity), ("Invalid entity: %s"):format(entity))
    assert(type(bone) == "string" and #bone > 0, "Kora.anim.attachProp requires a string bone name.")

    local invokingResource = GetInvokingResource() or GetCurrentResourceName()

    if offset == nil then offset = { x = 0.0, y = 0.0, z = 0.0 } end
    if rotation == nil then rotation = { x = 0.0, y = 0.0, z = 0.0 } end
    assert((type(offset) == 'table' or type(offset) == 'vector3')
        and Kora.util.isFiniteNumber(offset.x) and Kora.util.isFiniteNumber(offset.y) and Kora.util.isFiniteNumber(offset.z),
        'Animation prop offset must contain finite x, y, and z values.')
    assert((type(rotation) == 'table' or type(rotation) == 'vector3')
        and Kora.util.isFiniteNumber(rotation.x) and Kora.util.isFiniteNumber(rotation.y) and Kora.util.isFiniteNumber(rotation.z),
        'Animation prop rotation must contain finite x, y, and z values.')
    assert(opts == nil or type(opts) == 'table', 'Animation prop options must be a table.')
    opts = opts or {}
    assert(opts.softPin == nil or type(opts.softPin) == 'boolean', 'Animation prop softPin must be a boolean.')
    assert(opts.collision == nil or type(opts.collision) == 'boolean', 'Animation prop collision must be a boolean.')
    assert(opts.fixedRot == nil or type(opts.fixedRot) == 'boolean', 'Animation prop fixedRot must be a boolean.')
    assert(opts.vertexIndex == nil or (isInteger(opts.vertexIndex) and opts.vertexIndex >= 0 and opts.vertexIndex <= 5),
        'Animation prop vertexIndex must be an integer from 0 to 5.')

    local boneIndex = GetEntityBoneIndexByName(entity, bone)
    if boneIndex == -1 then
        return false, ("Bone '%s' does not exist on the target entity."):format(bone)
    end

    local prop

    local loadedModel, loadErr = Kora.stream.loadModel(model, function(loadedModelHash)
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

---Detaches and deletes a prop created with `Kora.anim.attachProp`. Refuses
---props this module didn't create, matching `Kora.entities.remove`/`Kora.blips.remove`.
---@param prop number
---@return boolean success
---@return string? error
function Kora.anim.detachProp(prop)
    assert(type(prop) == "number", ("Invalid prop: %s"):format(prop))

    local owner = propRegistry.owner(prop)
    if not owner then
        return false, "Prop is not tracked by Kora.anim."
    end

    local invoker = GetInvokingResource()
    if invoker and owner ~= invoker then return false, "Prop is owned by another resource." end

    propRegistry.untrack(prop)

    if not DoesEntityExist(prop) then
        return false, "Prop does not exist."
    end

    DetachEntity(prop, true, false)
    DeleteEntity(prop)

    return true
end

---Starts a scenario on an entity. Scenarios have no streamed dictionary and
---are therefore deliberately separate from Kora.anim.play's tracked lifecycle.
---@param entity number
---@param scenario string
---@param enterVehicle? boolean Defaults to false.
function Kora.anim.playScenario(entity, scenario, enterVehicle)
    assert(type(entity) == 'number' and DoesEntityExist(entity), ('Invalid entity: %s'):format(entity))
    assert(type(scenario) == 'string' and #scenario > 0, 'Kora.anim.playScenario requires a scenario.')
    TaskStartScenarioInPlace(entity, scenario, 0, enterVehicle == true)
end

---@param entity number
---@param immediate? boolean Defaults to false.
function Kora.anim.clear(entity, immediate)
    assert(type(entity) == 'number' and DoesEntityExist(entity), ('Invalid entity: %s'):format(entity))
    Kora.anim.stop(entity)
    if immediate then ClearPedTasksImmediately(entity) else ClearPedTasks(entity) end
end
