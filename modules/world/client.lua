local isFiniteNumber = Kora.util.isFiniteNumber
local isInteger = Kora.util.isInteger

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

local function finiteOrDefault(value, default, label)
    if value == nil then return default end
    assert(isFiniteNumber(value), KoraLang('Modules.World.s_finite', label))
    return value
end

local function distSq(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return dx * dx + dy * dy + dz * dz
end

local ENTITY_TYPES = { ped = true, vehicle = true, object = true, player = true }

local poolTypeByEntityType = {
    ped = "CPed",
    vehicle = "CVehicle",
    object = "CObject",
}

local function poolEntities(entityType)
    if entityType == "player" then
        local peds = {}
        local players = GetActivePlayers()
        for playerIndex = 1, #players do
            peds[#peds + 1] = GetPlayerPed(players[playerIndex])
        end
        return peds
    end

    return GetGamePool(poolTypeByEntityType[entityType])
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
    assert(
        options.includeOwnPed == nil or type(options.includeOwnPed) == 'boolean',
        KoraLang('Modules.World.world_query_includeownpe')
    )
    assert(
        options.includeInvisible == nil or type(options.includeInvisible) == 'boolean',
        KoraLang('Modules.World.world_query_includeinvis')
    )
end

---Runs the cheap-reject filters (self, exclude list, model set, visibility) before the possibly expensive caller predicate.
local function visitCandidates(entityType, coords, radiusSq, options, visit)
    assertQueryOptions(options)
    options = options or {}

    local modelSet = buildModelSet(options.models)
    local excludeSet = buildExcludeSet(options.excludeEntities)
    local includeOwnPed = options.includeOwnPed or false
    local includeInvisible = options.includeInvisible or false
    local ownPed = PlayerPedId()
    local origin = toVec3(coords)

    local entities = poolEntities(entityType)
    for entityIndex = 1, #entities do
        local entity = entities[entityIndex]
        if entity ~= 0 and DoesEntityExist(entity)
            and (includeOwnPed or entity ~= ownPed)
            and not (excludeSet and excludeSet[entity])
            and not (modelSet and not modelSet[GetEntityModel(entity)])
            and (includeInvisible or IsEntityVisible(entity))
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

---Finds every entity of `entityType` within `radius` meters of `coords`, nearest first, from the live entity pool.
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

---Resolves the ground Z below an XY coordinate after requesting collision.
---@param coords vector3|{x:number,y:number,z:number}
---@param options? KoraWorldGroundOptions
---@return table|false coords
---@return string? error
function Kora.world.getGroundCoords(coords, options)
    local origin = toVec3(coords)
    assert(options == nil or type(options) == "table", KoraLang('Modules.World.ground_query_options'))
    options = options or {}

    local height = finiteOrDefault(options.height, math.max(origin.z, Config.world.groundHeight), 'Ground height')
    local attempts = finiteOrDefault(options.attempts, Config.world.groundAttempts, 'Ground attempts')
    local retryDelay = finiteOrDefault(options.retryDelay, Config.world.groundRetryDelay, 'Ground retry delay')
    assert(isInteger(attempts) and attempts > 0, KoraLang('Modules.World.ground_attempts_positive'))
    assert(isInteger(retryDelay) and retryDelay >= 0, KoraLang('Modules.World.ground_retry_delay'))

    for attempt = 1, attempts do
        RequestCollisionAtCoord(origin.x, origin.y, height)
        local found, groundZ = GetGroundZFor_3dCoord(origin.x, origin.y, height, false)
        if found then return { x = origin.x, y = origin.y, z = groundZ } end
        if attempt < attempts then Wait(retryDelay) end
    end

    return false, ('Unable to resolve ground coordinates after %d attempts.'):format(attempts)
end

---Returns the street and crossing-street labels at coordinates.
---@param coords? vector3|{x:number,y:number,z:number} Defaults to the cached player coordinates.
---@return string street
---@return string? crossing
function Kora.world.getStreetNames(coords)
    if coords == nil then coords = Kora.cache.coords() end
    coords = toVec3(coords)
    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = streetHash and streetHash ~= 0 and GetStreetNameFromHashKey(streetHash) or ''
    local crossing = crossingHash and crossingHash ~= 0 and GetStreetNameFromHashKey(crossingHash) or nil
    return street, crossing
end

---Returns the localized zone label and its engine zone code.
---@param coords? vector3|{x:number,y:number,z:number} Defaults to the cached player coordinates.
---@return string label
---@return string code
function Kora.world.getZoneName(coords)
    if coords == nil then coords = Kora.cache.coords() end
    coords = toVec3(coords)
    local code = GetNameOfZone(coords.x, coords.y, coords.z)
    local label = GetLabelText(code)
    if not label or label == 'NULL' then label = code end
    return label, code
end

local CARDINAL_DIRECTIONS = { 'N', 'NW', 'W', 'SW', 'S', 'SE', 'E', 'NE' }

---Returns the eight-point compass direction for a heading or entity.
---@param value? number Heading in degrees, or an entity handle when options.entity is true. Defaults to the cached player ped.
---@param options? {entity?: boolean}
---@return 'N'|'NW'|'W'|'SW'|'S'|'SE'|'E'|'NE'
function Kora.world.getCardinalDirection(value, options)
    assert(options == nil or type(options) == 'table', KoraLang('Modules.World.cardinal_direction_optio'))
    assert(
        options == nil or options.entity == nil or type(options.entity) == 'boolean',
        KoraLang('Modules.World.cardinal_direction_o_2')
    )
    local heading
    if value == nil then
        heading = GetEntityHeading(Kora.cache.ped())
    elseif options and options.entity then
        assert(type(value) == 'number' and value ~= 0 and DoesEntityExist(value), KoraLang('Modules.World.invalid_entity'))
        heading = GetEntityHeading(value)
    else
        assert(type(value) == 'number', KoraLang('Modules.World.heading'))
        heading = value
    end

    assert(isFiniteNumber(heading), KoraLang('Modules.World.heading_finite'))
    heading = heading % 360.0
    return CARDINAL_DIRECTIONS[(math.floor((heading + 22.5) / 45.0) % 8) + 1]
end

---Returns the active waypoint position, or false when no waypoint is set.
---@return table|false coords
---@return string? error
function Kora.world.getWaypointCoords()
    local blip = GetFirstBlipInfoId(8)
    if not blip or blip == 0 or not DoesBlipExist(blip) then
        return false, 'No waypoint is set.'
    end

    local coords = GetBlipInfoIdCoord(blip)
    return { x = coords.x, y = coords.y, z = coords.z }
end

---Reports whether no vehicle occupies the requested spawn radius.
---@param coords vector3|{x:number,y:number,z:number}
---@param radius number
---@param options? KoraWorldQueryOptions
---@return boolean clear
function Kora.world.isSpawnClear(coords, radius, options)
    assertRadius(radius)
    assert(options == nil or type(options) == "table", KoraLang('Modules.World.world_query_options'))
    options = options or {}

    local query = {}
    for key, value in pairs(options) do query[key] = value end
    query.includeInvisible = true

    local occupied = visitCandidates('vehicle', coords, radius * radius, query, function() return true end)
    return occupied ~= true
end
