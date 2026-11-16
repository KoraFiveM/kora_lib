local isFiniteNumber = Kora.util.isFiniteNumber

local function toVec3(v)
    assert(
        v and isFiniteNumber(v.x) and isFiniteNumber(v.y) and isFiniteNumber(v.z),
        KoraLang('Modules.World.coordinates_vector3_glm')
    )
    return { x = v.x, y = v.y, z = v.z }
end

local function assertRadius(radius)
    assert(isFiniteNumber(radius) and radius > 0, KoraLang('Modules.World.radius_positive_finite'))
end

local function distSq(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return dx * dx + dy * dy + dz * dz
end

local ENTITY_TYPES = { ped = true, vehicle = true, object = true, player = true }
local ENTITY_TYPE_IDS = { ped = 1, vehicle = 2, object = 3 }
local isInteger = Kora.util.isInteger

local poolFnByEntityType = {
    ped = GetAllPeds,
    vehicle = GetAllVehicles,
    object = GetAllObjects,
}

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
    assert(options == nil or type(options) == 'table', KoraLang('Modules.World.world_query_options'))
    if not options then return end

    assert(options.models == nil or type(options.models) == 'table', KoraLang('Modules.World.world_query_models'))
    if options.models then
        local count = 0
        for index, model in pairs(options.models) do
            assert(
                isInteger(index) and index >= 1 and (type(model) == 'string' or isInteger(model)),
                KoraLang('Modules.World.world_query_models_2')
            )
            count = count + 1
        end
        assert(count == #options.models, KoraLang('Modules.World.world_query_models_3'))
    end
    assert(
        options.excludeEntities == nil or type(options.excludeEntities) == 'table',
        KoraLang('Modules.World.world_query_excludeentit')
    )
    if options.excludeEntities then
        local count = 0
        for index, entity in pairs(options.excludeEntities) do
            assert(
                isInteger(index) and index >= 1 and isInteger(entity) and entity > 0,
                KoraLang('Modules.World.world_query_excludee_2')
            )
            count = count + 1
        end
        assert(count == #options.excludeEntities, KoraLang('Modules.World.world_query_excludee_3'))
    end
    assert(
        options.predicate == nil or Kora.compat.isCallable(options.predicate),
        KoraLang('Modules.World.world_query_predicate')
    )
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
---@param entityType KoraWorldEntityType
---@param coords any
---@param radius number
---@param options? KoraWorldQueryOptions
---@return {entity: number, coords: table, distance: number}[] matches Sorted ascending by distance.
function Kora.world.getNearbyEntities(entityType, coords, radius, options)
    assert(ENTITY_TYPES[entityType], KoraLang('Modules.World.entitytype_ped_vehicle'))
    assertRadius(radius)

    local matches = collectCandidates(entityType, coords, radius * radius, options)
    table.sort(matches, byDistance)
    return matches
end

---Finds the single nearest entity of `entityType` to `coords`.
---@param entityType KoraWorldEntityType
---@param coords any
---@param options? KoraWorldQueryOptions `radius` defaults to Config.world.defaultRadius.
---@return number|false entity `false` if nothing matched within range.
---@return table? coords Only present when an entity was found.
---@return number? distance Only present when an entity was found.
function Kora.world.getClosestEntity(entityType, coords, options)
    assert(ENTITY_TYPES[entityType], KoraLang('Modules.World.entitytype_ped_vehicle'))
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
---@param options? KoraWorldQueryOptions
---@return boolean clear
function Kora.world.isSpawnClear(coords, radius, options)
    assertRadius(radius)
    local occupied = visitCandidates('vehicle', coords, radius * radius, options, function() return true end)
    return occupied ~= true
end

---Resolves and validates a client-supplied network entity before server code
---acts on it. Failure reasons are stable machine-readable codes so callers
---retain ownership of player-facing messages. Failures lead with `false`, not
---`nil`: across the export boundary a leading nil drops the reason.
---@param src integer
---@param networkId integer
---@param options? KoraWorldNetworkEntityOptions
---@return integer|false entity
---@return string|nil reason
function Kora.world.resolveNetworkEntity(src, networkId, options)
    assert(options == nil or type(options) == "table", KoraLang('Modules.World.network_entity_options'))
    options = options or {}

    assert(isInteger(src) and src > 0, KoraLang('Modules.World.world_resolvenetworkenti'))
    assert(
        options.entityType == nil or ENTITY_TYPE_IDS[options.entityType],
        KoraLang('Modules.World.entitytype_ped_vehic_2')
    )
    assert(
        options.maxDistance == nil or (type(options.maxDistance) == "number"
        and options.maxDistance >= 0 and options.maxDistance < math.huge),
        KoraLang('Modules.World.maxdistance_non_negative')
    )
    assert(
        options.sameBucket == nil or type(options.sameBucket) == "boolean",
        KoraLang('Modules.World.samebucket_boolean')
    )
    assert(
        options.requireDriver == nil or type(options.requireDriver) == "boolean",
        KoraLang('Modules.World.requiredriver_boolean')
    )
    assert(
        not options.requireDriver or options.entityType == "vehicle",
        KoraLang('Modules.World.requiredriver_entitytype')
    )

    if not isInteger(networkId) or networkId < 1 then
        return false, "invalid_network_id"
    end

    local entity = NetworkGetEntityFromNetworkId(networkId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return false, "entity_unavailable"
    end
    if options.entityType and GetEntityType(entity) ~= ENTITY_TYPE_IDS[options.entityType] then
        return false, "wrong_entity_type"
    end

    local playerPed = GetPlayerPed(src)
    if not playerPed or playerPed == 0 or not DoesEntityExist(playerPed) then
        return false, "player_unavailable"
    end
    if options.sameBucket ~= false and GetPlayerRoutingBucket(src) ~= GetEntityRoutingBucket(entity) then
        return false, "routing_bucket_mismatch"
    end
    if options.maxDistance and distSq(toVec3(GetEntityCoords(playerPed)), toVec3(GetEntityCoords(entity)))
        > options.maxDistance * options.maxDistance then
        return false, "too_far"
    end
    if options.requireDriver and GetPedInVehicleSeat(entity, -1) ~= playerPed then
        return false, "driver_required"
    end

    return entity
end

---Resolves a player-controlled target and verifies server-authoritative
---proximity before gameplay code acts on it.
---@param src integer
---@param targetSrc integer
---@param options KoraWorldNearbyPlayerOptions
---@return integer|nil targetPed
---@return number|string reasonOrDistance Distance on success; stable reason code on failure.
function Kora.world.resolveNearbyPlayer(src, targetSrc, options)
    assert(isInteger(src) and src > 0, KoraLang('Modules.World.world_resolvenearbyplaye'))
    assert(type(options) == "table", KoraLang('Modules.World.world_resolvenearbyp_2'))
    assert(
        type(options.maxDistance) == "number" and options.maxDistance >= 0
        and options.maxDistance < math.huge,
        KoraLang('Modules.World.maxdistance_non_nega_2')
    )
    assert(
        options.sameBucket == nil or type(options.sameBucket) == "boolean",
        KoraLang('Modules.World.samebucket_boolean')
    )
    assert(
        options.allowSelf == nil or type(options.allowSelf) == "boolean",
        KoraLang('Modules.World.allowself_boolean')
    )

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
