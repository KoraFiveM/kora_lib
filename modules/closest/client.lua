---@diagnostic disable: duplicate-doc-field

-- QB.world.getClosestEntity('player', ...) returns the closest player's PED
-- (see modules/world/client.lua's poolEntities), but QB.closest.player's own
-- established contract is a player id (usable with e.g. GetPlayerServerId),
-- not a ped handle -- so the ped has to be mapped back to its owning player.
local function pedToPlayerId(ped)
    local players = GetActivePlayers()
    for playerIndex = 1, #players do
        local playerId = players[playerIndex]
        if GetPlayerPed(playerId) == ped then return playerId end
    end
    return nil
end

local function resolveCoords(coords)
    if coords == nil then coords = QB.cache.get('coords') end
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

---@param coords vector3
---@param distance number
---@return {id: number?, distance: number?}
function QB.closest.player(coords, distance)
    local ped, _, dist = QB.world.getClosestEntity('player', resolveCoords(coords), {
        radius = resolveDistance(distance),
    })
    if not ped then return { id = nil, distance = nil } end
    local playerId = pedToPlayerId(ped)
    if not playerId then return { id = nil, distance = nil } end
    return { id = playerId, distance = dist }
end

---@param coords vector3
---@param distance number
---@return {id: number?, distance: number?}
function QB.closest.vehicle(coords, distance)
    local entity, _, dist = QB.world.getClosestEntity('vehicle', resolveCoords(coords), {
        radius = resolveDistance(distance),
    })
    return { id = entity or nil, distance = dist }
end

---@param coords vector3
---@param distance number
---@return {id: number?, distance: number?}
function QB.closest.ped(coords, distance)
    local entity, _, dist = QB.world.getClosestEntity('ped', resolveCoords(coords), {
        radius = resolveDistance(distance),
    })
    return { id = entity or nil, distance = dist }
end

---@param coords vector3
---@param distance number
---@return {id: number?, distance: number?}
function QB.closest.object(coords, distance)
    local entity, _, dist = QB.world.getClosestEntity('object', resolveCoords(coords), {
        radius = resolveDistance(distance),
    })
    return { id = entity or nil, distance = dist }
end
