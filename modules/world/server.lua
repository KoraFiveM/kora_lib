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
        for _, playerId in ipairs(GetPlayers()) do
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

---@return {entity: number, coords: table, distance: number}[]
local function collectCandidates(entityType, coords, radiusSq, options)
    options = options or {}

    local modelSet = buildModelSet(options.models)
    local excludeSet = buildExcludeSet(options.excludeEntities)
    local origin = toVec3(coords)

    local results = {}

    for _, entity in ipairs(poolEntities(entityType)) do
        if entity ~= 0 and DoesEntityExist(entity)
            and not (excludeSet and excludeSet[entity])
            and not (modelSet and not modelSet[GetEntityModel(entity)])
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
    local matches = collectCandidates(entityType, coords, radius * radius, options)

    if #matches == 0 then return false end

    local closest = matches[1]
    for i = 2, #matches do
        if matches[i].distance < closest.distance then closest = matches[i] end
    end

    return closest.entity, closest.coords, closest.distance
end
