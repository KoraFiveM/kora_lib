---@alias QBEntitiesType "ped" | "object" | "vehicle"
---@alias QBEntitiesPreset "static"

---@class QBEntitiesCreateOptions
---@field heading? number World heading in degrees. Overrides any heading on `coords` (`.w` or `.heading`) when set. Defaults to `coords.w`, then `coords.heading`, then 0.0 -- see `resolveHeading`.
---@field preset? QBEntitiesPreset Named bundle of setup behavior applied before `freeze`/`blockNonTempEvents`/`invincible` below. Currently only "static" is defined (freeze = true, blockNonTempEvents = true, invincible = true) -- an inert decorative prop/NPC that doesn't move, react, or take damage.
---@field freeze? boolean Explicit override for FreezeEntityPosition. Independent of any preset, and takes precedence over one when set (even to `false`).
---@field blockNonTempEvents? boolean Explicit override for SetBlockingOfNonTemporaryEvents. Independent of any preset, and takes precedence over one when set (even to `false`). Peds only -- silently ignored for objects/vehicles since the native itself is ped-specific.
---@field invincible? boolean Explicit override for SetEntityInvincible. Independent of any preset, and takes precedence over one when set (even to `false`).

local presets = {
    static = {
        freeze = true,
        blockNonTempEvents = true,
        invincible = true,
    },
}

-- Per-type creation dispatch. Each entry spawns a non-networked (isNetwork =
-- false), non-mission entity (netMissionEntity/bScriptHostPed = false) at the
-- given coords -- ownership/cleanup is handled entirely by this module's own
-- resource-stop tracking below, not by GTA's native script-host pinning.
local creators = {
    -- pedType is passed as 4 (conventionally PED_TYPE_CIVMALE) but is inert:
    -- CreatePed's own native docs state it is unused and the game assigns
    -- ped types automatically regardless of the value given.
    ped = function(model, x, y, z, heading)
        return CreatePed(4, model, x, y, z, heading, false, false)
    end,

    -- CreateObjectNoOffset (not CreateObject) is used deliberately: CreateObject's
    -- z coordinate is documented as "ground level" and applies an internal
    -- offset/snap adjustment, whereas CreateObjectNoOffset places the object
    -- exactly at the given coords -- required for predictable placement,
    -- especially when the entity is about to be frozen in place. It has no
    -- heading parameter, so heading is applied separately below.
    object = function(model, x, y, z, heading)
        local entity = CreateObjectNoOffset(model, x, y, z, false, false, false)
        if entity ~= 0 and DoesEntityExist(entity) then
            SetEntityHeading(entity, heading)
        end
        return entity
    end,

    vehicle = function(model, x, y, z, heading)
        return CreateVehicle(model, x, y, z, heading, false, false)
    end,
}

---Determines which of "ped" / "vehicle" / "object" `model` is, so callers
---never have to say what kind of entity they're spawning. `IsModelAPed` and
---`IsModelAVehicle` are static model-metadata queries -- they work off the
---model hash alone and don't require the asset to be streamed in first.
---Anything that's neither a ped nor a vehicle model is treated as an object
---(the generic "place something in the world" case).
---@param modelHash number
---@return QBEntitiesType
local function detectEntityType(modelHash)
    if IsModelAPed(modelHash) then return "ped" end
    if IsModelAVehicle(modelHash) then return "vehicle" end
    return "object"
end

-- Ownership tracking (which resource created a given entity, and bulk
-- cleanup when that resource stops) is delegated to the shared registry --
-- see local/resources/AGENTS.md.
local entityRegistry = QB.resources.registry(function(entity)
    if DoesEntityExist(entity) then DeleteEntity(entity) end
end)

-- Scoped entities have their own id space: their id identifies a persistent
-- scope registration, while an entity handle is deliberately transient (it
-- changes every time the player leaves and re-enters the scope).
local nextScopeId = 0
local scopeRegistry
local scopes = {}

---Resolves an explicit boolean option against a preset's value for the same
---key -- `nil` defers to the preset, any explicit boolean (including
---`false`) overrides it.
---@param explicit boolean?
---@param presetValue boolean?
---@return boolean
local function resolveOverride(explicit, presetValue)
    if explicit ~= nil then return explicit end
    return presetValue or false
end

---Resolves the heading to spawn at. An explicit `options.heading` always
---wins; otherwise it's read off `coords` itself -- `.w` for a real FiveM
---vector4 (the only heading-shaped field it actually exposes), falling back
---to `.heading` for plain coords tables that use that name by convention
---instead (vector4 has no `.heading` field of its own). Defaults to 0.0.
---@param options QBEntitiesCreateOptions
---@param coords vector3 | vector4 | {x: number, y: number, z: number, w?: number, heading?: number}
---@return number
local function resolveHeading(options, coords)
    if options.heading ~= nil then return options.heading end
    if type(coords.w) == "number" then return coords.w end
    if type(coords.heading) == "number" then return coords.heading end
    return 0.0
end

---Spawns a local, non-networked entity visible only to the calling client,
---streaming its model with `QB.stream.loadModel` first. Whether the result
---is a ped, vehicle, or object is auto-detected from `model` itself (see
---`detectEntityType`) -- callers never specify a type. The entity is created
---inside `loadModel`'s callback so it's built before the model is released,
---and is tracked against whichever resource invoked `create` (via
---`GetInvokingResource`, falling back to the current resource when called
---directly rather than through an export) so it is automatically deleted if
---that resource stops.
---@param model string | number The model to spawn. Its type (ped/vehicle/object) is detected automatically.
---@param coords vector3 | vector4 | {x: number, y: number, z: number, w?: number, heading?: number} World coordinates to spawn at. A heading on `coords` (`.w` for vector4, or `.heading` for a plain table using that convention) is used unless `options.heading` is set -- see `resolveHeading`.
---@param options? QBEntitiesCreateOptions
---@return number | false entity The created entity handle, or false if the model never loaded or the entity failed to create.
---@return string? error
local function createForResource(model, coords, options, invokingResource)
    options = options or {}

    assert(coords and type(coords.x) == "number" and type(coords.y) == "number" and type(coords.z) == "number",
        "Invalid coords: expected a vector3/vector4 or {x, y, z} table.")

    local preset = options.preset and presets[options.preset]
    assert(options.preset == nil or preset ~= nil, ("Unknown entities preset: %s"):format(options.preset))

    local freeze = resolveOverride(options.freeze, preset and preset.freeze)
    local blockNonTempEvents = resolveOverride(options.blockNonTempEvents, preset and preset.blockNonTempEvents)
    local invincible = resolveOverride(options.invincible, preset and preset.invincible)
    local heading = resolveHeading(options, coords)

    local entity

    local loadedModel, loadErr = QB.stream.loadModel(model, function(loadedModelHash)
        local entityType = detectEntityType(loadedModelHash)
        local created = creators[entityType](loadedModelHash, coords.x, coords.y, coords.z, heading)
        if created == 0 or not DoesEntityExist(created) then return end

        if freeze then FreezeEntityPosition(created, true) end
        if blockNonTempEvents and entityType == "ped" then
            SetBlockingOfNonTemporaryEvents(created, true)
        end
        if invincible then SetEntityInvincible(created, true) end

        entityRegistry.track(invokingResource, created)
        entity = created
    end)

    if not loadedModel then
        return false, loadErr
    end

    if not entity then
        return false, "Failed to create entity."
    end

    return entity
end

function QB.entities.create(model, coords, options)
    -- Must be captured before any Wait()/polling happens inside loadModel --
    -- the invoking-resource context is only valid at this call boundary.
    return createForResource(model, coords, options, GetInvokingResource() or GetCurrentResourceName())
end

local function removeScopedEntity(scope)
    local entity = scope.entity
    if not entity then return end

    scope.entity = nil
    scope.handle.entity = nil
    entityRegistry.untrack(entity)

    if DoesEntityExist(entity) then DeleteEntity(entity) end
end

local function destroyScope(scope)
    if scope.removed then return end
    scope.removed = true
    scopes[scope.id] = nil

    removeScopedEntity(scope)

    if scope.zone then scope.zone.remove() end
end

scopeRegistry = QB.resources.registry(function(scopeId)
    local scope = scopes[scopeId]
    if scope then destroyScope(scope) end
end)

---Registers a local entity that exists only while the player is inside its
---radius. It uses the zones module's spatial grid, so distant scoped entities
---do not stream models or occupy a GTA entity slot. Leaving the radius deletes
---the local entity; re-entering creates a fresh one. The registration itself
---is automatically removed if the calling resource stops.
---@param model string | number The model to spawn. Its type is detected automatically.
---@param coords vector3 | vector4 | {x: number, y: number, z: number, w?: number, heading?: number} World coordinates to spawn at.
---@param options QBEntitiesScopedOptions Options accepted by `create`, plus a required `radius` in metres.
---@return QBScopedEntityHandle scope A persistent scope handle. Read `scope.entity` for the current entity handle, or nil while outside the radius.
function QB.entities.createScoped(model, coords, options)
    -- Capture ownership at the export boundary. The zone callbacks run later,
    -- when GetInvokingResource() no longer identifies the original caller.
    local invokingResource = GetInvokingResource() or GetCurrentResourceName()
    options = options or {}

    assert(type(options.radius) == "number" and options.radius > 0,
        "Scoped entity radius must be a number greater than zero.")

    nextScopeId = nextScopeId + 1

    local scope = {
        id = nextScopeId,
        resource = invokingResource,
        entity = nil,
        zone = nil,
        inside = false,
        spawning = false,
        removed = false,
    }

    local handle = {
        id = scope.id,
        resource = invokingResource,
        entity = nil,
    }
    scope.handle = handle

    function handle.remove()
        if scopeRegistry.untrack(scope.id) then destroyScope(scope) end
    end

    function handle.isSpawned()
        return scope.entity ~= nil and DoesEntityExist(scope.entity)
    end

    scope.zone = QB.zones.sphere({
        coords = coords,
        radius = options.radius,
        onEnter = function()
            if scope.removed or scope.entity or scope.spawning then return end
            scope.inside = true
            scope.spawning = true

            -- Model streaming may yield. Zone callbacks run on zones' shared
            -- tick thread, so only start the work here; never stream inline.
            CreateThread(function()
                local entity = createForResource(model, coords, options, invokingResource)
                scope.spawning = false

                -- The scope can be removed, or exited, while model streaming
                -- yields. Never leave behind an entity that completed after
                -- its registration stopped being in scope.
                if scope.removed or not scope.inside then
                    if entity then
                        entityRegistry.untrack(entity)
                        if DoesEntityExist(entity) then DeleteEntity(entity) end
                    end
                    return
                end

                if entity then
                    scope.entity = entity
                    handle.entity = entity
                end
            end)
        end,
        onExit = function()
            scope.inside = false
            if not scope.removed then removeScopedEntity(scope) end
        end,
    })

    scopes[scope.id] = scope
    scopeRegistry.track(invokingResource, scope.id)

    return handle
end

---@class QBScopedEntityHandle
---@field id integer Stable scoped-registration id.
---@field resource string Resource that created the scoped entity.
---@field entity? number Current local entity handle, or nil while outside the scope.
---@field remove fun() Deletes the active entity and unregisters the scope.
---@field isSpawned fun(): boolean Whether the scope currently owns a live entity.

---@class QBEntitiesScopedOptions : QBEntitiesCreateOptions
---@field radius number Spawn radius in metres; must be greater than zero.

---Deletes one tracked entity created with QB.entities.create and drops it
---from whichever resource's tracked set it belongs to, without waiting for
---that resource to stop. Refuses entities this module didn't create --
---exports.qblib:entities_remove is callable from any resource, and an
---untracked-handle gate is what stops it doubling as a delete-anything
---primitive against entities owned by other resources or the world.
---@param entity number The entity handle to remove.
---@return boolean success
---@return string? error
function QB.entities.remove(entity)
    assert(type(entity) == "number", ("Invalid entity: %s"):format(entity))

    local owner = entityRegistry.untrack(entity)

    if not owner then
        return false, "Entity is not tracked by QB.entities."
    end

    if not DoesEntityExist(entity) then
        return false, "Entity does not exist."
    end

    DeleteEntity(entity)

    return true
end

---Requests network control of an existing entity. This is intentionally
---separate from `create`: qblib-created entities are local, while gameplay
---resources often need to clean up a server-authorized networked entity.
---@param entity number
---@param timeout? integer Defaults to 1000ms.
---@return boolean controlled
---@return string? error
function QB.entities.requestControl(entity, timeout)
    assert(type(entity) == 'number' and entity ~= 0, ('Invalid entity: %s'):format(entity))
    if not DoesEntityExist(entity) then return false, 'Entity does not exist.' end
    if NetworkHasControlOfEntity(entity) then return true end

    local controlled, err = QB.loops.controlled(function()
        NetworkRequestControlOfEntity(entity)
        return NetworkHasControlOfEntity(entity)
    end, false, timeout or 1000, true)
    return controlled ~= false, err
end

---Deletes an entity only after network control is acquired. Unlike `remove`,
---this is for an existing networked gameplay entity and does not require that
---qblib created it; callers must already have server authorization.
---@param entity number
---@param timeout? integer
---@return boolean deleted
---@return string? error
function QB.entities.delete(entity, timeout)
    local controlled, err = QB.entities.requestControl(entity, timeout)
    if not controlled then return false, err or 'Could not acquire entity control.' end
    SetEntityAsMissionEntity(entity, true, true)
    DeleteEntity(entity)
    return not DoesEntityExist(entity), DoesEntityExist(entity) and 'Entity deletion failed.' or nil
end
