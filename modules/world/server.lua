---@alias QBWorldEntityType "ped" | "vehicle" | "object" | "player"

---@class QBWorldQueryOptions
---@field models? (number|string)[] Restrict to these models. Strings are joaat-hashed. Ignored for "player".
---@field predicate? fun(entity: number, coords: table, distance: number): boolean Runs last, after the cheaper filters below.
---@field excludeEntities? number[] Entity handles to skip outright -- the only way to exclude a caller's own ped server-side, since there's no single-player concept to default that on (contrast client's includeOwnPed).
---@field radius? number getClosestEntity only -- search radius, meters. Defaults to Config.world.defaultRadius.

-- Plain { x, y, z } tables, not glm.vec3 -- see the identical note in
-- modules/world/client.lua.
local isFiniteNumber = QB.util.isFiniteNumber

local function toVec3(v)
    assert(v and isFiniteNumber(v.x) and isFiniteNumber(v.y) and isFiniteNumber(v.z),
        "Coordinates must be a vector3, glm.vec3, or {x=,y=,z=} table.")
    return { x = v.x, y = v.y, z = v.z }
end

local function assertRadius(radius)
    assert(isFiniteNumber(radius) and radius > 0, "radius must be a positive finite number.")
end

local function distSq(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return dx * dx + dy * dy + dz * dz
end

local ENTITY_TYPES = { ped = true, vehicle = true, object = true, player = true }
local ENTITY_TYPE_IDS = { ped = 1, vehicle = 2, object = 3 }
local isInteger = QB.util.isInteger

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

local function assertQueryOptions(options)
    assert(options == nil or type(options) == 'table', 'World query options must be a table.')
    if not options then return end

    assert(options.models == nil or type(options.models) == 'table', 'World query models must be an array.')
    if options.models then
        local count = 0
        for index, model in pairs(options.models) do
            assert(isInteger(index) and index >= 1 and (type(model) == 'string' or isInteger(model)),
                'World query models must be a dense array of model names or hashes.')
            count = count + 1
        end
        assert(count == #options.models, 'World query models must be a dense array.')
    end
    assert(options.excludeEntities == nil or type(options.excludeEntities) == 'table',
        'World query excludeEntities must be an array.')
    if options.excludeEntities then
        local count = 0
        for index, entity in pairs(options.excludeEntities) do
            assert(isInteger(index) and index >= 1 and isInteger(entity) and entity > 0,
                'World query excludeEntities must be a dense array of positive entity handles.')
            count = count + 1
        end
        assert(count == #options.excludeEntities, 'World query excludeEntities must be a dense array.')
    end
    assert(options.predicate == nil or QB.compat.isCallable(options.predicate),
        'World query predicate must be callable.')
end

local function visitCandidates(entityType, coords, radiusSq, options, visit)
    assertQueryOptions(options)
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
            local entityCoords = GetEntityCoords(entity)
            local dSq = distSq(origin, entityCoords)

            if dSq <= radiusSq then
                local distance = options.predicate and math.sqrt(dSq) or nil
                -- Predicates receive the documented plain coordinate table;
                -- internal visitors copy only a returned candidate.
                if not options.predicate or options.predicate(entity, toVec3(entityCoords), distance) then
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
            coords = toVec3(entityCoords),
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
    assertRadius(radius)

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
    assertQueryOptions(options)

    local radius = options and options.radius
    if radius == nil then radius = Config.world.defaultRadius end
    assertRadius(radius)
    local closestEntity, closestCoords, closestDistanceSq
    visitCandidates(entityType, coords, radius * radius, options, function(entity, entityCoords, dSq)
        if not closestDistanceSq or dSq < closestDistanceSq then
            closestEntity, closestCoords, closestDistanceSq = entity, toVec3(entityCoords), dSq
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
    assertRadius(radius)
    local occupied = visitCandidates('vehicle', coords, radius * radius, options, function() return true end)
    return occupied ~= true
end

---@class QBWorldNetworkEntityOptions
---@field entityType? "ped" | "vehicle" | "object" Required live entity type.
---@field maxDistance? number Maximum distance from the player's ped in metres.
---@field sameBucket? boolean Require the entity and player to share a routing bucket. Defaults to true.
---@field requireDriver? boolean Require the player's ped to occupy the vehicle's driver seat.

---Resolves and validates a client-supplied network entity before server code
---acts on it. Failure reasons are stable machine-readable codes so callers
---retain ownership of player-facing messages.
---@param src integer
---@param networkId integer
---@param options? QBWorldNetworkEntityOptions
---@return integer|nil entity
---@return string|nil reason
function QB.world.resolveNetworkEntity(src, networkId, options)
    assert(options == nil or type(options) == "table", "Network entity options must be a table.")
    options = options or {}

    assert(isInteger(src) and src > 0,
        "QB.world.resolveNetworkEntity requires a player source.")
    assert(options.entityType == nil or ENTITY_TYPE_IDS[options.entityType],
        "entityType must be 'ped', 'vehicle', or 'object'.")
    assert(options.maxDistance == nil or (type(options.maxDistance) == "number"
        and options.maxDistance >= 0 and options.maxDistance < math.huge),
        "maxDistance must be a non-negative number.")
    assert(options.sameBucket == nil or type(options.sameBucket) == "boolean",
        "sameBucket must be a boolean.")
    assert(options.requireDriver == nil or type(options.requireDriver) == "boolean",
        "requireDriver must be a boolean.")
    assert(not options.requireDriver or options.entityType == "vehicle",
        "requireDriver requires entityType = 'vehicle'.")

    if not isInteger(networkId) or networkId < 1 then
        return nil, "invalid_network_id"
    end

    local entity = NetworkGetEntityFromNetworkId(networkId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return nil, "entity_unavailable"
    end
    if options.entityType and GetEntityType(entity) ~= ENTITY_TYPE_IDS[options.entityType] then
        return nil, "wrong_entity_type"
    end

    local playerPed = GetPlayerPed(src)
    if not playerPed or playerPed == 0 or not DoesEntityExist(playerPed) then
        return nil, "player_unavailable"
    end
    if options.sameBucket ~= false and GetPlayerRoutingBucket(src) ~= GetEntityRoutingBucket(entity) then
        return nil, "routing_bucket_mismatch"
    end
    if options.maxDistance and distSq(toVec3(GetEntityCoords(playerPed)), toVec3(GetEntityCoords(entity)))
        > options.maxDistance * options.maxDistance then
        return nil, "too_far"
    end
    if options.requireDriver and GetPedInVehicleSeat(entity, -1) ~= playerPed then
        return nil, "driver_required"
    end

    return entity
end

---@class QBWorldNearbyPlayerOptions
---@field maxDistance number Maximum distance between the players in metres.
---@field sameBucket? boolean Require both players to share a routing bucket. Defaults to true.
---@field allowSelf? boolean Permit `src` and `targetSrc` to be equal. Defaults to false.

---Resolves a player-controlled target and verifies server-authoritative
---proximity before gameplay code acts on it.
---@param src integer
---@param targetSrc integer
---@param options QBWorldNearbyPlayerOptions
---@return integer|nil targetPed
---@return number|string reasonOrDistance Distance on success; stable reason code on failure.
function QB.world.resolveNearbyPlayer(src, targetSrc, options)
    assert(isInteger(src) and src > 0,
        "QB.world.resolveNearbyPlayer requires a player source.")
    assert(type(options) == "table", "QB.world.resolveNearbyPlayer requires an options table.")
    assert(type(options.maxDistance) == "number" and options.maxDistance >= 0
        and options.maxDistance < math.huge,
        "maxDistance must be a non-negative finite number.")
    assert(options.sameBucket == nil or type(options.sameBucket) == "boolean",
        "sameBucket must be a boolean.")
    assert(options.allowSelf == nil or type(options.allowSelf) == "boolean",
        "allowSelf must be a boolean.")

    if not isInteger(targetSrc) or targetSrc < 1 then
        return nil, "invalid_player"
    end
    if targetSrc == src and options.allowSelf ~= true then return nil, "self_not_allowed" end

    local sourcePed = GetPlayerPed(src)
    if not sourcePed or sourcePed == 0 or not DoesEntityExist(sourcePed) then
        return nil, "player_unavailable"
    end

    local targetPed = GetPlayerPed(targetSrc)
    if not targetPed or targetPed == 0 or not DoesEntityExist(targetPed) then
        return nil, "target_unavailable"
    end
    if options.sameBucket ~= false and GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(targetSrc) then
        return nil, "routing_bucket_mismatch"
    end

    local distanceSq = distSq(toVec3(GetEntityCoords(sourcePed)), toVec3(GetEntityCoords(targetPed)))
    if distanceSq > options.maxDistance * options.maxDistance then return nil, "too_far" end
    return targetPed, math.sqrt(distanceSq)
end
