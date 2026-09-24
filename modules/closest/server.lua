---@diagnostic disable: duplicate-doc-field

-- See the identical note in modules/closest/client.lua: QB.world's "player"
-- entityType returns a ped, but QB.closest.player's contract is a player id.
local function pedToPlayerId(ped)
    local players = GetPlayers()
    for playerIndex = 1, #players do
        local playerId = players[playerIndex]
        if GetPlayerPed(playerId) == ped then return tonumber(playerId) or playerId end
    end
    return nil
end

local function resolveCoords(src, coords)
    assert(QB.util.isInteger(src) and src > 0, 'Closest-search source must be a positive player ID.')
    if coords == nil then
        local ped = GetPlayerPed(src)
        assert(ped and ped ~= 0, 'Closest-search source must have an active ped.')
        coords = GetEntityCoords(ped)
    end
    assert(coords and QB.util.isFiniteNumber(coords.x) and QB.util.isFiniteNumber(coords.y)
        and QB.util.isFiniteNumber(coords.z), 'Closest-search coordinates must be a finite vector3.')
    return coords
end

local function resolveDistance(distance)
    if distance == nil then return 15.0 end
    assert(QB.util.isFiniteNumber(distance) and distance > 0,
        'Closest-search distance must be a positive finite number.')
    return distance
end

---@param src integer
---@param coords? QBCoords
---@param distance? number
---@return {id: integer?, distance: number?}
function QB.closest.player(src, coords, distance)
    local ped, _, dist = QB.world.getClosestEntity('player', resolveCoords(src, coords), {
        radius = resolveDistance(distance),
        excludeEntities = { GetPlayerPed(src) },
    })
    if not ped then return { id = nil, distance = nil } end
    local playerId = pedToPlayerId(ped)
    if not playerId then return { id = nil, distance = nil } end
    return { id = playerId, distance = dist }
end

---@param src integer
---@param coords? QBCoords
---@param distance? number
---@return {id: integer?, distance: number?}
function QB.closest.vehicle(src, coords, distance)
    local entity, _, dist = QB.world.getClosestEntity('vehicle', resolveCoords(src, coords), {
        radius = resolveDistance(distance),
    })
    return { id = entity or nil, distance = dist }
end

---@param src integer
---@param coords? QBCoords
---@param distance? number
---@return {id: integer?, distance: number?}
function QB.closest.ped(src, coords, distance)
    local entity, _, dist = QB.world.getClosestEntity('ped', resolveCoords(src, coords), {
        radius = resolveDistance(distance),
        excludeEntities = { GetPlayerPed(src) },
    })
    return { id = entity or nil, distance = dist }
end

---@param src integer
---@param coords? QBCoords
---@param distance? number
---@return {id: integer?, distance: number?}
function QB.closest.object(src, coords, distance)
    local entity, _, dist = QB.world.getClosestEntity('object', resolveCoords(src, coords), {
        radius = resolveDistance(distance),
    })
    return { id = entity or nil, distance = dist }
end
