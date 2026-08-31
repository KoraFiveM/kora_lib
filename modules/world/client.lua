---@alias QBWorldEntityType "ped" | "vehicle" | "object" | "player"

---@class QBWorldQueryOptions
---@field models? (number|string)[] Restrict to these models. Strings are joaat-hashed. Ignored for "player".
---@field predicate? fun(entity: number, coords: table, distance: number): boolean Runs last, after the cheaper filters below.
---@field includeInvisible? boolean Include entities IsEntityVisible reports as hidden. Defaults to false.
---@field includeOwnPed? boolean Include the local player's own ped/player entry. Defaults to false.
---@field excludeEntities? number[] Entity handles to skip outright.
---@field radius? number getClosestEntity only -- search radius, meters. Defaults to Config.world.defaultRadius.

-- Plain { x, y, z } tables, not glm.vec3 -- see the identical note in
-- modules/raycast/client.lua and modules/zones/client.lua for why.
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

local poolTypeByEntityType = {
    ped = "CPed",
    vehicle = "CVehicle",
    object = "CObject",
}

-- "player" isn't a GetGamePool type -- it's enumerated via the active player
-- list instead, one ped per connected player (including the local one, which
-- the ownPed exclusion below handles the same way it does for "ped").
local function poolEntities(entityType)
    if entityType == "player" then
        local peds = {}
        for _, playerId in ipairs(GetActivePlayers()) do
            peds[#peds + 1] = GetPlayerPed(playerId)
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
    for _, model in ipairs(models) do
        set[type(model) == "string" and joaat(model) or model] = true
    end
    return set
end

---@param entities? number[]
---@return table<number, boolean>?
local function buildExcludeSet(entities)
    if not entities then return nil end

    local set = {}
    for _, entity in ipairs(entities) do set[entity] = true end
    return set
end

---Runs every cheap-reject-first filter (self-exclusion, explicit exclude
---list, model set, visibility) before the caller-supplied predicate, which
---may be arbitrarily expensive -- matching the AABB-then-exact-shape
---discipline modules/zones already documents for its own containment tests.
---@return {entity: number, coords: table, distance: number}[]
local function collectCandidates(entityType, coords, radiusSq, options)
    options = options or {}

    local modelSet = buildModelSet(options.models)
    local excludeSet = buildExcludeSet(options.excludeEntities)
    local includeOwnPed = options.includeOwnPed or false
    local includeInvisible = options.includeInvisible or false
    local ownPed = PlayerPedId()
    local origin = toVec3(coords)

    local results = {}

    for _, entity in ipairs(poolEntities(entityType)) do
        if entity ~= 0 and DoesEntityExist(entity)
            and (includeOwnPed or entity ~= ownPed)
            and not (excludeSet and excludeSet[entity])
            and not (modelSet and not modelSet[GetEntityModel(entity)])
            and (includeInvisible or IsEntityVisible(entity))
        then
            local entityCoords = toVec3(GetEntityCoords(entity))
            local dSq = distSq(origin, entityCoords)

            if dSq <= radiusSq then
                local distance = math.sqrt(dSq)

                if not options.predicate or options.predicate(entity, entityCoords, distance) then
                    results[#results + 1] = { entity = entity, coords = entityCoords, distance = distance }
                end
            end
        end
    end

    return results
end

local function byDistance(a, b)
    return a.distance < b.distance
end

---Finds every entity of `entityType` within `radius` meters of `coords`,
---nearest first. Reads the live entity pool (GetGamePool/GetActivePlayers)
---rather than tracking anything itself -- unlike modules/entities, nothing
---returned here was created or is owned by this module.
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
    local matches = collectCandidates(entityType, coords, radius * radius, options)

    if #matches == 0 then return false end

    local closest = matches[1]
    for i = 2, #matches do
        if matches[i].distance < closest.distance then closest = matches[i] end
    end

    return closest.entity, closest.coords, closest.distance
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
function QB.world.getGroundCoords(coords, options)
    local origin = toVec3(coords)
    options = options or {}

    local height = tonumber(options.height) or math.max(origin.z, Config.world.groundHeight)
    local attempts = math.floor(tonumber(options.attempts) or Config.world.groundAttempts)
    local retryDelay = math.max(0, math.floor(tonumber(options.retryDelay) or Config.world.groundRetryDelay))
    assert(attempts > 0, 'Ground attempts must be a positive integer.')

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
function QB.world.getStreetNames(coords)
    coords = toVec3(coords or QB.cache.coords())
    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = streetHash and streetHash ~= 0 and GetStreetNameFromHashKey(streetHash) or ''
    local crossing = crossingHash and crossingHash ~= 0 and GetStreetNameFromHashKey(crossingHash) or nil
    return street, crossing
end

---Returns the localized zone label and its engine zone code.
---@param coords? vector3|{x:number,y:number,z:number} Defaults to the cached player coordinates.
---@return string label
---@return string code
function QB.world.getZoneName(coords)
    coords = toVec3(coords or QB.cache.coords())
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
function QB.world.getCardinalDirection(value, options)
    local heading
    if value == nil then
        heading = GetEntityHeading(QB.cache.ped())
    elseif options and options.entity then
        assert(type(value) == 'number' and value ~= 0 and DoesEntityExist(value), 'Invalid entity.')
        heading = GetEntityHeading(value)
    else
        assert(type(value) == 'number', 'Heading must be a number.')
        heading = value
    end

    heading = heading % 360.0
    return CARDINAL_DIRECTIONS[(math.floor((heading + 22.5) / 45.0) % 8) + 1]
end

---Returns the active waypoint position, or false when no waypoint is set.
---@return table|false coords
---@return string? error
function QB.world.getWaypointCoords()
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
function QB.world.isSpawnClear(coords, radius, options)
    assert(type(radius) == 'number' and radius > 0, 'radius must be a positive number.')
    options = options or {}

    -- Hidden streamed vehicles still block a spawn point. Copy the caller's
    -- table so this helper does not mutate an options object they may reuse.
    local query = {}
    for key, value in pairs(options) do query[key] = value end
    query.includeInvisible = true

    return #collectCandidates('vehicle', coords, radius * radius, query) == 0
end
