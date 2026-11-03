---@alias QBWorldEntityType "ped" | "vehicle" | "object" | "player"

---@class QBWorldQueryOptions
---@field models? (number|string)[] Restrict to these models. Strings are joaat-hashed. Ignored for "player".
---@field predicate? fun(entity: number, coords: table, distance: number): boolean Runs last, after the cheaper filters below.
---@field excludeEntities? number[] Entity handles to skip outright -- the only way to exclude a caller's own ped server-side, since there's no single-player concept to default that on (contrast client's includeOwnPed).
---@field radius? number getClosestEntity only -- search radius, meters. Defaults to Config.world.defaultRadius.

-- Plain { x, y, z } tables, not glm.vec3 (see modules/world/client.lua).
local isFiniteNumber = Kora.util.isFiniteNumber

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
local isInteger = Kora.util.isInteger

-- GetGamePool is client-only; the server has one native per entity kind.
local poolFnByEntityType = {
    ped = GetAllPeds,
    vehicle = GetAllVehicles,
    object = GetAllObjects,
}

-- "player" is enumerated via GetPlayers (GetActivePlayers is client-only), one ped per player.
local function poolEntities(entityType)
    if entityType == "player" then
        local peds = {}
        local players = GetPlayers()
        for playerIndex = 1, #players do
            peds[#peds + 1] = GetPlayerPed(players[playerIndex])
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
    assert(options.predicate == nil or Kora.compat.isCallable(options.predicate),
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
                -- Predicates receive the documented plain coordinate table; internal visitors copy only a returned candidate.
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

---Finds every entity of `entityType` within `radius` meters of `coords`, nearest first, from the live server pools.
---@param entityType QBWorldEntityType
---@param coords any
---@param radius number
---@param options? QBWorldQueryOptions
---@return {entity: number, coords: table, distance: number}[] matches Sorted ascending by distance.
function Kora.world.getNearbyEntities(entityType, coords, radius, options)
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
function Kora.world.getClosestEntity(entityType, coords, options)
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
function Kora.world.isSpawnClear(coords, radius, options)
    assertRadius(radius)
    local occupied = visitCandidates('vehicle', coords, radius * radius, options, function() return true end)
    return occupied ~= true
end

---@class QBWorldNetworkEntityOptions
---@field entityType? "ped" | "vehicle" | "object" Required live entity type.
---@field maxDistance? number Maximum distance from the player's ped in metres.
---@field sameBucket? boolean Require the entity and player to share a routing bucket. Defaults to true.
---@field requireDriver? boolean Require the player's ped to occupy the vehicle's driver seat.
---@field plate? string Expected plate (vehicles); both sides are trimmed and upper-cased.
---@field model? string|integer|(string|integer)[] Accepted model name(s) or hash(es).
---@field unoccupied? boolean Require every seat of the vehicle to be empty.
---@field notPlayer? boolean Require the ped not to be a player.
---@field near? {coords: vector3|table, radius: number} Require the entity within `radius` metres of a fixed point.

-- GTA vehicles have at most 16 seats: the driver (-1) and passengers 0..14.
local LAST_SEAT_INDEX = 14

-- Model hashes reach the server signed or unsigned depending on the native, so
-- both sides are compared as unsigned 32-bit values.
local function unsignedModel(model)
    return (type(model) == "string" and joaat(model) or model) & 0xFFFFFFFF
end

local function buildAcceptedModels(model)
    local models = type(model) == "table" and model or { model }
    assert(#models > 0, "model must be a model name, a hash, or a non-empty list of either.")
    local accepted = {}
    for index = 1, #models do
        local entry = models[index]
        assert(type(entry) == "string" or isInteger(entry),
            "model must be a model name, a hash, or a non-empty list of either.")
        accepted[unsignedModel(entry)] = true
    end
    return accepted
end

local function normalizePlate(plate)
    if type(plate) == "number" then plate = tostring(plate) end
    if type(plate) ~= "string" then return nil end
    return Kora.util.trim(plate):upper()
end

local function hasOccupant(vehicle)
    for seat = -1, LAST_SEAT_INDEX do
        local ped = GetPedInVehicleSeat(vehicle, seat)
        if ped and ped ~= 0 then return true end
    end
    return false
end

---Resolves and validates a client-supplied network entity before server code
---acts on it. Failure reasons are stable machine-readable codes so callers
---retain ownership of player-facing messages.
---@param src integer
---@param networkId integer
---@param options? QBWorldNetworkEntityOptions
---@return integer|nil entity
---@return string|nil reason
function Kora.world.resolveNetworkEntity(src, networkId, options)
    assert(options == nil or type(options) == "table", "Network entity options must be a table.")
    options = options or {}

    assert(isInteger(src) and src > 0,
        "Kora.world.resolveNetworkEntity requires a player source.")
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
    -- plate is usually client data, so a wrong type fails as plate_mismatch below instead of raising here.
    assert(options.plate == nil or options.entityType == "vehicle", "plate requires entityType = 'vehicle'.")
    assert(options.unoccupied == nil or type(options.unoccupied) == "boolean", "unoccupied must be a boolean.")
    assert(not options.unoccupied or options.entityType == "vehicle", "unoccupied requires entityType = 'vehicle'.")
    assert(not (options.unoccupied and options.requireDriver), "unoccupied and requireDriver cannot both be set.")
    assert(options.notPlayer == nil or type(options.notPlayer) == "boolean", "notPlayer must be a boolean.")
    assert(not options.notPlayer or options.entityType == "ped", "notPlayer requires entityType = 'ped'.")
    local acceptedModels = options.model ~= nil and buildAcceptedModels(options.model) or nil
    local near = options.near
    if near ~= nil then
        assert(type(near) == "table" and isFiniteNumber(near.radius) and near.radius >= 0,
            "near must be { coords = vector3, radius = non-negative number }.")
        near = { coords = toVec3(near.coords), radiusSq = near.radius * near.radius }
    end

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
    if acceptedModels and not acceptedModels[unsignedModel(GetEntityModel(entity))] then
        return nil, "wrong_model"
    end
    if options.plate ~= nil then
        local expected = normalizePlate(options.plate)
        if not expected or expected ~= normalizePlate(GetVehicleNumberPlateText(entity)) then
            return nil, "plate_mismatch"
        end
    end
    if options.unoccupied and hasOccupant(entity) then
        return nil, "occupied"
    end
    if options.notPlayer and IsPedAPlayer(entity) then
        return nil, "is_player"
    end
    if near and distSq(near.coords, toVec3(GetEntityCoords(entity))) > near.radiusSq then
        return nil, "too_far_from_point"
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
function Kora.world.resolveNearbyPlayer(src, targetSrc, options)
    assert(isInteger(src) and src > 0,
        "Kora.world.resolveNearbyPlayer requires a player source.")
    assert(type(options) == "table", "Kora.world.resolveNearbyPlayer requires an options table.")
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
