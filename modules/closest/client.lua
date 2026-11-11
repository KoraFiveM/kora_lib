---@diagnostic disable: duplicate-doc-field

local function pedToPlayerId(ped)
    local players = GetActivePlayers()
    for playerIndex = 1, #players do
        local playerId = players[playerIndex]
        if GetPlayerPed(playerId) == ped then return playerId end
    end
    return nil
end

local function resolveCoords(coords)
    if coords == nil then coords = Kora.cache.get('coords') end
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

---@param coords vector3
---@param distance number
---@return {id: number?, distance: number?}
function Kora.closest.player(coords, distance)
    local ped, _, dist = Kora.world.getClosestEntity('player', resolveCoords(coords), {
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
function Kora.closest.vehicle(coords, distance)
    local entity, _, dist = Kora.world.getClosestEntity('vehicle', resolveCoords(coords), {
        radius = resolveDistance(distance),
    })
    return { id = entity or nil, distance = dist }
end

---@param coords vector3
---@param distance number
---@return {id: number?, distance: number?}
function Kora.closest.ped(coords, distance)
    local entity, _, dist = Kora.world.getClosestEntity('ped', resolveCoords(coords), {
        radius = resolveDistance(distance),
    })
    return { id = entity or nil, distance = dist }
end

---@param coords vector3
---@param distance number
---@return {id: number?, distance: number?}
function Kora.closest.object(coords, distance)
    local entity, _, dist = Kora.world.getClosestEntity('object', resolveCoords(coords), {
        radius = resolveDistance(distance),
    })
    return { id = entity or nil, distance = dist }
end
