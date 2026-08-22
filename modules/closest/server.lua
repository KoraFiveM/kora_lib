---@diagnostic disable: duplicate-doc-field

local function getCoordsAndDistance(src, coords, distance)
    if not coords then
        coords = GetEntityCoords(GetPlayerPed(src))
    end
    if not distance then distance = 15.0 end
    return coords, distance
end

function QB.closest.player(src, coords, distance)
    coords, distance = getCoordsAndDistance(src, coords, distance)
    local closestPlayer, closestDistance = nil, nil
    for _, player in ipairs(GetActivePlayers()) do
        if tostring(player) ~= tostring(src) then
            local targetCoords = GetEntityCoords(GetPlayerPed(player))
            local dist = #(coords - targetCoords)
            if dist <= distance and (not closestDistance or dist <= closestDistance) then
                closestDistance = dist
                closestPlayer = player
            end
        end
    end
    return { id = closestPlayer, distance = closestDistance }
end

function QB.closest.vehicle(src, coords, distance)
    coords, distance = getCoordsAndDistance(src, coords, distance)
    local closestVehicle, closestDistance = nil, nil
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        local targetCoords = GetEntityCoords(vehicle)
        local dist = #(coords - targetCoords)
        if dist <= distance and (not closestDistance or dist <= closestDistance) then
            closestDistance = dist
            closestVehicle = vehicle
        end
    end
    return { id = closestVehicle, distance = closestDistance }
end

function QB.closest.ped(src, coords, distance)
    coords, distance = getCoordsAndDistance(src, coords, distance)
    local closestPed, closestDistance = nil, nil
    for _, ped in ipairs(GetGamePool('CPed')) do
        local targetCoords = GetEntityCoords(ped)
        local dist = #(coords - targetCoords)
        if dist <= distance and (not closestDistance or dist <= closestDistance) then
            closestDistance = dist
            closestPed = ped
        end
    end
    return { id = closestPed, distance = closestDistance }
end

function QB.closest.object(src, coords, distance)
    coords, distance = getCoordsAndDistance(src, coords, distance)
    local closestObject, closestDistance = nil, nil
    for _, object in ipairs(GetGamePool('CObject')) do
        local targetCoords = GetEntityCoords(object)
        local dist = #(coords - targetCoords)
        if dist <= distance and (not closestDistance or dist <= closestDistance) then
            closestDistance = dist
            closestObject = object
        end
    end
    return { id = closestObject, distance = closestDistance }
end
