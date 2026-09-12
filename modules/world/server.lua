---@alias QBWorldEntityType "ped" | "vehicle" | "object" | "player"

---@class QBWorldQueryOptions
---@field models? (number|string)[] Restrict to these models. Strings are joaat-hashed. Ignored for "player".
---@field predicate? fun(entity: number, coords: table, distance: number): boolean Runs last, after the cheaper filters below.
---@field excludeEntities? number[] Entity handles to skip outright -- the only way to exclude a caller's own ped server-side, since there's no single-player concept to default that on (contrast client's includeOwnPed).
---@field radius? number getClosestEntity only -- search radius, meters. Defaults to Config.world.defaultRadius.

-- Plain { x, y, z } tables, not glm.vec3 -- see the identical note in
-- modules/world/client.lua.
local function toVec3(v)
    assert(type(v.x) == "number" and type(v.y) == "number" and type(v.z) == "number",
        "Coordinates must be a vector3, glm.vec3, or {x=,y=,z=} table.")
    return { x = v.x, y = v.y, z = v.z }
end

local function distSq(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return dx * dx + dy * dy + dz * dz
end

local ENTITY_TYPES = { ped = true, vehicle = true, object = true, player = true }

-- GetGamePool is client-only -- the server-side equivalents are one native
-- per entity kind rather than a single pool-name-keyed native.
local poolFnByEntityType = {
    ped = GetAllPeds,
    vehicle = GetAllVehicles,
    object = GetAllObjects,
}

-- "player" is enumerated via the connected player list, one ped per
-- connected player (GetActivePlayers is client-only; GetPlayers is its
-- server-side counterpart).
local function poolEntities(entityType)
    if entityType == "player" then
        local peds = {}
        local players = GetPlayers()
        for playerIndex = 1, #players do
            local playerId = players[playerIndex]
            peds[#peds + 1] = GetPlayerPed(playerId)
        end
        return peds
    end

    return poolFnByEntityType[entityType]()
end

---@param models? (number|string)[]
---@return table<number, boolean>?
local function buildModelSet(models)
    if not models then return nil end

    local set = {}
    for modelIndex = 1, #models do
        local model = models[modelIndex]
        set[type(model) == "string" and joaat(model) or model] = true
    end
    return set
end

---@param entities? number[]
---@return table<number, boolean>?
local function buildExcludeSet(entities)
    if not entities then return nil end

    local set = {}
    for i = 1, #entities do set[entities[i]] = true end
    return set
end

local function visitCandidates(entityType, coords, radiusSq, options, visit)
    options = options or {}

    local modelSet = buildModelSet(options.models)
    local excludeSet = buildExcludeSet(options.excludeEntities)
    local origin = toVec3(coords)

    local entities = poolEntities(entityType)
    for entityIndex = 1, #entities do
        local entity = entities[entityIndex]
        if entity ~= 0 and DoesEntityExist(entity)
            and not (excludeSet and excludeSet[entity])
            and not (modelSet and not modelSet[GetEntityModel(entity)])
        then
            local entityCoords = toVec3(GetEntityCoords(entity))
            local dSq = distSq(origin, entityCoords)

            if dSq <= radiusSq then
                local distance = options.predicate and math.sqrt(dSq) or nil
                if not options.predicate or options.predicate(entity, entityCoords, distance) then
                    local result = visit(entity, entityCoords, dSq, distance)
                    if result ~= nil then return result end
                end
            end
        end
    end
end

---@return {entity: number, coords: table, distance: number}[]
local function collectCandidates(entityType, coords, radiusSq, options)
    local results = {}
    visitCandidates(entityType, coords, radiusSq, options, function(entity, entityCoords, dSq, distance)
        results[#results + 1] = {
            entity = entity,
            coords = entityCoords,
            distance = distance or math.sqrt(dSq),
        }
    end)

    return results
end

local function byDistance(a, b)
    return a.distance < b.distance
end

---Finds every entity of `entityType` within `radius` meters of `coords`,
---nearest first. Reads the live server entity pools rather than tracking
---anything itself.
---@param entityType QBWorldEntityType
---@param coords any
---@param radius number
---@param options? QBWorldQueryOptions
---@return {entity: number, coords: table, distance: number}[] matches Sorted ascending by distance.
function QB.world.getNearbyEntities(entityType, coords, radius, options)
    assert(ENTITY_TYPES[entityType], "entityType must be 'ped', 'vehicle', 'object', or 'player'.")
    assert(type(radius) == "number" and radius > 0, "radius must be a positive number.")

    local matches = collectCandidates(entityType, coords, radius * radius, options)
    table.sort(matches, byDistance)
    return matches
end

---Finds the single nearest entity of `entityType` to `coords`.
---@param entityType QBWorldEntityType
---@param coords any
---@param options? QBWorldQueryOptions `radius` defaults to Config.world.defaultRadius.
---@return number|false entity `false` if nothing matched within range.
---@return table? coords Only present when an entity was found.
---@return number? distance Only present when an entity was found.
function QB.world.getClosestEntity(entityType, coords, options)
    assert(ENTITY_TYPES[entityType], "entityType must be 'ped', 'vehicle', 'object', or 'player'.")

    local radius = (options and options.radius) or Config.world.defaultRadius
    local closestEntity, closestCoords, closestDistanceSq
    visitCandidates(entityType, coords, radius * radius, options, function(entity, entityCoords, dSq)
        if not closestDistanceSq or dSq < closestDistanceSq then
            closestEntity, closestCoords, closestDistanceSq = entity, entityCoords, dSq
        end
    end)

    if not closestEntity then return false end
    return closestEntity, closestCoords, math.sqrt(closestDistanceSq)
end

---Reports whether no vehicle occupies the requested spawn radius.
---@param coords vector3|{x:number,y:number,z:number}
---@param radius number
---@param options? QBWorldQueryOptions
---@return boolean clear
function QB.world.isSpawnClear(coords, radius, options)
    assert(type(radius) == 'number' and radius > 0, 'radius must be a positive number.')
    local occupied = visitCandidates('vehicle', coords, radius * radius, options, function() return true end)
    return occupied ~= true
end
