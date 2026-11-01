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
local isFiniteNumber = Kora.util.isFiniteNumber

-- Per-type creation dispatch. Entities are non-networked and non-mission; cleanup is this
-- module's own resource-stop tracking, not GTA's script-host pinning.
local creators = {
    -- pedType 4 is inert: CreatePed ignores it and assigns ped types itself.
    ped = function(model, x, y, z, heading)
        return CreatePed(4, model, x, y, z, heading, false, false)
    end,

    -- CreateObjectNoOffset, not CreateObject: CreateObject treats z as "ground level" and
    -- snaps it, which breaks exact placement. It has no heading param, so heading is set below.
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

---Determines whether `model` is a "ped", "vehicle" or "object". IsModelAPed/IsModelAVehicle
---work from the hash alone (no streaming needed); anything else is an object.
---@param modelHash number
---@return QBEntitiesType
local function detectEntityType(modelHash)
    if IsModelAPed(modelHash) then return "ped" end
    if IsModelAVehicle(modelHash) then return "vehicle" end
    return "object"
end

-- Ownership/cleanup on resource stop is delegated to the shared registry (local/resources/AGENTS.md).
local entityRegistry = Kora.resources.registry(function(entity)
    if DoesEntityExist(entity) then DeleteEntity(entity) end
end)

-- Scoped entities have their own id space: the id names a persistent scope registration,
-- while the entity handle changes each time the player re-enters the scope.
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

---Resolves spawn heading: `options.heading`, else `coords.w` (vector4), else `coords.heading`, else 0.0.
---@param options QBEntitiesCreateOptions
---@param coords vector3 | vector4 | {x: number, y: number, z: number, w?: number, heading?: number}
---@return number
local function resolveHeading(options, coords)
    if options.heading ~= nil then return options.heading end
    if type(coords.w) == "number" then return coords.w end
    if type(coords.heading) == "number" then return coords.heading end
    return 0.0
end

local function assertCreateOptions(options)
    assert(type(options) == "table", "Entity options must be a table.")
    assert(options.preset == nil or presets[options.preset] ~= nil,
        ("Unknown entities preset: %s"):format(tostring(options.preset)))
    assert(options.freeze == nil or type(options.freeze) == "boolean", "Entity freeze must be a boolean.")
    assert(options.blockNonTempEvents == nil or type(options.blockNonTempEvents) == "boolean",
        "Entity blockNonTempEvents must be a boolean.")
    assert(options.invincible == nil or type(options.invincible) == "boolean", "Entity invincible must be a boolean.")
end

---Spawns a local, non-networked entity visible only to the calling client. Type (ped/vehicle/object)
---is auto-detected from `model`; it is tracked against the invoking resource and deleted if that stops.
---@param model string | number The model to spawn. Its type (ped/vehicle/object) is detected automatically.
---@param coords vector3 | vector4 | {x: number, y: number, z: number, w?: number, heading?: number} World coordinates to spawn at. A heading on `coords` (`.w` for vector4, or `.heading` for a plain table using that convention) is used unless `options.heading` is set -- see `resolveHeading`.
---@param options? QBEntitiesCreateOptions
---@return number | false entity The created entity handle, or false if the model never loaded or the entity failed to create.
---@return string? error
local function createForResource(model, coords, options, invokingResource)
    assert(options == nil or type(options) == "table", "Entity options must be a table.")
    options = options or {}
    assertCreateOptions(options)

    assert(coords and isFiniteNumber(coords.x) and isFiniteNumber(coords.y) and isFiniteNumber(coords.z),
        "Invalid coords: expected a vector3/vector4 or {x, y, z} table.")

    local preset = options.preset and presets[options.preset]

    local freeze = resolveOverride(options.freeze, preset and preset.freeze)
    local blockNonTempEvents = resolveOverride(options.blockNonTempEvents, preset and preset.blockNonTempEvents)
    local invincible = resolveOverride(options.invincible, preset and preset.invincible)
    local heading = resolveHeading(options, coords)
    assert(isFiniteNumber(heading), "Entity heading must be a finite number.")

    local entity

    local loadedModel, loadErr = Kora.stream.loadModel(model, function(loadedModelHash)
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

function Kora.entities.create(model, coords, options)
    -- Capture before loadModel yields: the invoking resource is only valid at the call boundary.
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

scopeRegistry = Kora.resources.registry(function(scopeId)
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
function Kora.entities.createScoped(model, coords, options)
    -- Capture ownership at the export boundary. The zone callbacks run later,
    -- when GetInvokingResource() no longer identifies the original caller.
    local invokingResource = GetInvokingResource() or GetCurrentResourceName()
    assert(options == nil or type(options) == "table", "Scoped entity options must be a table.")
    options = options or {}
    assertCreateOptions(options)

    assert(isFiniteNumber(options.radius) and options.radius > 0,
        "Scoped entity radius must be a finite number greater than zero.")
    assert(coords and isFiniteNumber(coords.x) and isFiniteNumber(coords.y) and isFiniteNumber(coords.z),
        "Invalid coords: expected a vector3/vector4 or {x, y, z} table.")
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
        local invoker = GetInvokingResource()
        if scope.removed or (invoker and invoker ~= scope.resource) then return false end
        scopeRegistry.untrack(scope.id)
        destroyScope(scope)
        return true
    end

    function handle.isSpawned()
        return scope.entity ~= nil and DoesEntityExist(scope.entity)
    end

    scope.zone = Kora.zones.sphere({
        coords = coords,
        radius = options.radius,
        onEnter = function()
            scope.inside = true
            if scope.removed or scope.entity or scope.spawning then return end
            scope.spawning = true

            -- Model streaming may yield. Zone callbacks run on zones' shared
            -- tick thread, so only start the work here; never stream inline.
            CreateThread(function()
                local ok, entity, createErr = pcall(createForResource, model, coords, options, invokingResource)
                scope.spawning = false

                if not ok then
                    print(("[kora_lib:entities] scoped entity %d failed to spawn: %s"):format(scope.id, tostring(entity)))
                    return
                end
                if not entity and createErr then
                    print(("[kora_lib:entities] scoped entity %d failed to spawn: %s"):format(scope.id, tostring(createErr)))
                end

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
---@field remove fun(): boolean Deletes the active entity and unregisters the scope. Returns false for a foreign or removed scope.
---@field isSpawned fun(): boolean Whether the scope currently owns a live entity.

---@class QBEntitiesScopedOptions : QBEntitiesCreateOptions
---@field radius number Spawn radius in metres; must be greater than zero.

---Deletes one tracked entity created by the calling resource, without waiting
---for that resource to stop.
---@param entity number The entity handle to remove.
---@return boolean success
---@return string? error
function Kora.entities.remove(entity)
    assert(type(entity) == "number", ("Invalid entity: %s"):format(entity))

    if not entityRegistry.owner(entity) then
        return false, "Entity is not tracked by Kora.entities."
    end
    if entityRegistry.owner(entity) ~= (GetInvokingResource() or GetCurrentResourceName()) then
        return false, "Entity is not owned by the calling resource."
    end

    entityRegistry.untrack(entity)

    if not DoesEntityExist(entity) then
        return false, "Entity does not exist."
    end

    DeleteEntity(entity)

    return true
end

---Requests network control of an existing entity. This is intentionally
---separate from `create`: kora_lib-created entities are local, while gameplay
---resources often need to clean up a server-authorized networked entity.
---@param entity number
---@param timeout? integer Defaults to 1000ms.
---@return boolean controlled
---@return string? error
function Kora.entities.requestControl(entity, timeout)
    assert(type(entity) == 'number' and entity ~= 0, ('Invalid entity: %s'):format(entity))
    if timeout == nil then timeout = 1000 end
    assert(Kora.util.isInteger(timeout) and timeout >= 0, 'Entity control timeout must be a non-negative integer.')
    if not DoesEntityExist(entity) then return false, 'Entity does not exist.' end
    if NetworkHasControlOfEntity(entity) then return true end

    local controlled, err = Kora.loops.controlled(function()
        NetworkRequestControlOfEntity(entity)
        return NetworkHasControlOfEntity(entity)
    end, false, timeout, true)
    return controlled ~= false, err
end

---Deletes an entity only after network control is acquired. Unlike `remove`,
---this is for an existing networked gameplay entity and does not require that
---kora_lib created it; callers must already have server authorization.
---@param entity number
---@param timeout? integer
---@return boolean deleted
---@return string? error
function Kora.entities.delete(entity, timeout)
    local controlled, err = Kora.entities.requestControl(entity, timeout)
    if not controlled then return false, err or 'Could not acquire entity control.' end
    SetEntityAsMissionEntity(entity, true, true)
    DeleteEntity(entity)
    return not DoesEntityExist(entity), DoesEntityExist(entity) and 'Entity deletion failed.' or nil
end
