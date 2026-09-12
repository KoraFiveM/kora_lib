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
    return coords or GetEntityCoords(GetPlayerPed(src))
end

function QB.closest.player(src, coords, distance)
    local ped, _, dist = QB.world.getClosestEntity('player', resolveCoords(src, coords), {
        radius = distance or 15.0,
        excludeEntities = { GetPlayerPed(src) },
    })
    if not ped then return { id = nil, distance = nil } end
    return { id = pedToPlayerId(ped), distance = dist }
end

function QB.closest.vehicle(src, coords, distance)
    local entity, _, dist = QB.world.getClosestEntity('vehicle', resolveCoords(src, coords), {
        radius = distance or 15.0,
    })
    return { id = entity or nil, distance = dist }
end

function QB.closest.ped(src, coords, distance)
    local entity, _, dist = QB.world.getClosestEntity('ped', resolveCoords(src, coords), {
        radius = distance or 15.0,
        excludeEntities = { GetPlayerPed(src) },
    })
    return { id = entity or nil, distance = dist }
end

function QB.closest.object(src, coords, distance)
    local entity, _, dist = QB.world.getClosestEntity('object', resolveCoords(src, coords), {
        radius = distance or 15.0,
    })
    return { id = entity or nil, distance = dist }
end
