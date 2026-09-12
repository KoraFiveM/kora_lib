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
    return coords or QB.cache.get('coords')
end

---@param coords vector3
---@param distance number
---@return {id: number?, distance: number?}
function QB.closest.player(coords, distance)
    local ped, _, dist = QB.world.getClosestEntity('player', resolveCoords(coords), {
        radius = distance or 15.0,
        excludeEntities = { PlayerPedId() },
    })
    if not ped then return { id = nil, distance = nil } end
    return { id = pedToPlayerId(ped), distance = dist }
end

---@param coords vector3
---@param distance number
---@return {id: number?, distance: number?}
function QB.closest.vehicle(coords, distance)
    local entity, _, dist = QB.world.getClosestEntity('vehicle', resolveCoords(coords), {
        radius = distance or 15.0,
    })
    return { id = entity or nil, distance = dist }
end

---@param coords vector3
---@param distance number
---@return {id: number?, distance: number?}
function QB.closest.ped(coords, distance)
    local entity, _, dist = QB.world.getClosestEntity('ped', resolveCoords(coords), {
        radius = distance or 15.0,
        excludeEntities = { PlayerPedId() },
    })
    return { id = entity or nil, distance = dist }
end

---@param coords vector3
---@param distance number
---@return {id: number?, distance: number?}
function QB.closest.object(coords, distance)
    local entity, _, dist = QB.world.getClosestEntity('object', resolveCoords(coords), {
        radius = distance or 15.0,
    })
    return { id = entity or nil, distance = dist }
end
