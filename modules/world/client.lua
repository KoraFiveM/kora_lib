---@alias QBWorldEntityType "ped" | "vehicle" | "object" | "player"

---@class QBWorldQueryOptions
---@field models? (number|string)[] Restrict to these models. Strings are joaat-hashed. Ignored for "player".
---@field predicate? fun(entity: number, coords: table, distance: number): boolean Runs last, after the cheaper filters below.
---@field includeInvisible? boolean Include entities IsEntityVisible reports as hidden. Defaults to false.
---@field includeOwnPed? boolean Include the local player's own ped/player entry. Defaults to false.
---@field excludeEntities? number[] Entity handles to skip outright.
---@field radius? number getClosestEntity only -- search radius, meters. Defaults to Config.world.defaultRadius.

-- Plain { x, y, z } tables, not glm.vec3 (see modules/raycast/client.lua).
local isFiniteNumber = Kora.util.isFiniteNumber
local isInteger = Kora.util.isInteger

local function toVec3(v)
    assert(v and isFiniteNumber(v.x) and isFiniteNumber(v.y) and isFiniteNumber(v.z),
        "Coordinates must be a vector3, glm.vec3, or {x=,y=,z=} table.")
    return { x = v.x, y = v.y, z = v.z }
end

local function assertRadius(radius)
    assert(isFiniteNumber(radius) and radius > 0, "radius must be a positive finite number.")
end

local function finiteOrDefault(value, default, label)
    if value == nil then return default end
    assert(isFiniteNumber(value), ("%s must be a finite number."):format(label))
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

-- "player" isn't a GetGamePool type: it's enumerated via the active player list (the local ped is excluded like "ped").
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
    assert(options.includeOwnPed == nil or type(options.includeOwnPed) == 'boolean',
        'World query includeOwnPed must be a boolean.')
    assert(options.includeInvisible == nil or type(options.includeInvisible) == 'boolean',
        'World query includeInvisible must be a boolean.')
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
                -- Only predicates have a public coordinate-table contract; internal visitors ignore or copy coords.
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

---@class QBWorldGroundOptions
---@field height? number Z height used for the collision/ground probes.
---@field attempts? integer Maximum number of probes.
---@field retryDelay? integer Milliseconds between probes.

---Resolves the ground Z below an XY coordinate after requesting collision.
---@param coords vector3|{x:number,y:number,z:number}
---@param options? QBWorldGroundOptions
---@return table|false coords
---@return string? error
function Kora.world.getGroundCoords(coords, options)
    local origin = toVec3(coords)
    assert(options == nil or type(options) == "table", "Ground query options must be a table.")
    options = options or {}

    local height = finiteOrDefault(options.height, math.max(origin.z, Config.world.groundHeight), 'Ground height')
    local attempts = finiteOrDefault(options.attempts, Config.world.groundAttempts, 'Ground attempts')
    local retryDelay = finiteOrDefault(options.retryDelay, Config.world.groundRetryDelay, 'Ground retry delay')
    assert(isInteger(attempts) and attempts > 0, 'Ground attempts must be a positive integer.')
    assert(isInteger(retryDelay) and retryDelay >= 0, 'Ground retry delay must be a non-negative integer.')

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
    assert(options == nil or type(options) == 'table', 'Cardinal direction options must be a table.')
    assert(options == nil or options.entity == nil or type(options.entity) == 'boolean',
        'Cardinal direction options.entity must be a boolean.')
    local heading
    if value == nil then
        heading = GetEntityHeading(Kora.cache.ped())
    elseif options and options.entity then
        assert(type(value) == 'number' and value ~= 0 and DoesEntityExist(value), 'Invalid entity.')
        heading = GetEntityHeading(value)
    else
        assert(type(value) == 'number', 'Heading must be a number.')
        heading = value
    end

    assert(isFiniteNumber(heading), 'Heading must be a finite number.')
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
---@param options? QBWorldQueryOptions
---@return boolean clear
function Kora.world.isSpawnClear(coords, radius, options)
    assertRadius(radius)
    assert(options == nil or type(options) == "table", "World query options must be a table.")
    options = options or {}

    -- Hidden streamed vehicles still block a spawn point. Copy the options so the caller's table isn't mutated.
    local query = {}
    for key, value in pairs(options) do query[key] = value end
    query.includeInvisible = true

    local occupied = visitCandidates('vehicle', coords, radius * radius, query, function() return true end)
    return occupied ~= true
end
