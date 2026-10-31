---@diagnostic disable: duplicate-doc-field

-- See the identical note in modules/closest/client.lua: Kora.world's "player"
-- entityType returns a ped, but Kora.closest.player's contract is a player id.
local function pedToPlayerId(ped)
    local players = GetPlayers()
    for playerIndex = 1, #players do
        local playerId = players[playerIndex]
        if GetPlayerPed(playerId) == ped then return tonumber(playerId) or playerId end
    end
    return nil
end

local function resolveCoords(src, coords)
    assert(Kora.util.isInteger(src) and src > 0, 'Closest-search source must be a positive player ID.')
    if coords == nil then
        local ped = GetPlayerPed(src)
        assert(ped and ped ~= 0, 'Closest-search source must have an active ped.')
        coords = GetEntityCoords(ped)
    end
    assert(coords and Kora.util.isFiniteNumber(coords.x) and Kora.util.isFiniteNumber(coords.y)
        and Kora.util.isFiniteNumber(coords.z), 'Closest-search coordinates must be a finite vector3.')
    return coords
end

local function resolveDistance(distance)
    if distance == nil then return 15.0 end
    assert(Kora.util.isFiniteNumber(distance) and distance > 0,
        'Closest-search distance must be a positive finite number.')
    return distance
end

---@param src integer
---@param coords? QBCoords
---@param distance? number
---@return {id: integer?, distance: number?}
function Kora.closest.player(src, coords, distance)
    local ped, _, dist = Kora.world.getClosestEntity('player', resolveCoords(src, coords), {
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
function Kora.closest.vehicle(src, coords, distance)
    local entity, _, dist = Kora.world.getClosestEntity('vehicle', resolveCoords(src, coords), {
        radius = resolveDistance(distance),
    })
    return { id = entity or nil, distance = dist }
end

---@param src integer
---@param coords? QBCoords
---@param distance? number
---@return {id: integer?, distance: number?}
function Kora.closest.ped(src, coords, distance)
    local entity, _, dist = Kora.world.getClosestEntity('ped', resolveCoords(src, coords), {
        radius = resolveDistance(distance),
        excludeEntities = { GetPlayerPed(src) },
    })
    return { id = entity or nil, distance = dist }
end

---@param src integer
---@param coords? QBCoords
---@param distance? number
---@return {id: integer?, distance: number?}
function Kora.closest.object(src, coords, distance)
    local entity, _, dist = Kora.world.getClosestEntity('object', resolveCoords(src, coords), {
        radius = resolveDistance(distance),
    })
    return { id = entity or nil, distance = dist }
end
