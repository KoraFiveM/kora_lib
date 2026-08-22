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
