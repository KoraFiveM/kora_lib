---@diagnostic disable: duplicate-doc-field
local function getCoordsAndDistance(coords, distance)
    if not coords then
        coords = QB.cache.get('coords')
    end
    if not distance then distance = 15.0 end
    return coords, distance
end

---@param coords vector3
---@param distance number
---@return {id: number, distance: number}
function QB.closest.player(coords, distance)
    coords, distance = getCoordsAndDistance(coords, distance)
    local closestPlayer, closestDistance = nil, nil
    for _, player in ipairs(GetActivePlayers()) do
        local targetCoords = GetEntityCoords(GetPlayerPed(player))
        local dist = #(coords - targetCoords)
        if not closestDistance or dist <= closestDistance then
            closestDistance = dist
            closestPlayer = player
        end
    end
    return { id = closestPlayer, distance = closestDistance }
end

---@param coords vector3
---@param distance number
---@return {id: number, distance: number}
function QB.closest.vehicle(coords, distance)
    coords, distance = getCoordsAndDistance(coords, distance)
    local closestVehicle, closestDistance = nil, nil
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        local targetCoords = GetEntityCoords(vehicle)
        local dist = #(coords - targetCoords)
        if not closestDistance or dist <= closestDistance then
            closestDistance = dist
            closestVehicle = vehicle
        end
    end
    return { id = closestVehicle, distance = closestDistance }
end

---@param coords vector3
---@param distance number
---@return {id: number, distance: number}
function QB.closest.ped(coords, distance)
    coords, distance = getCoordsAndDistance(coords, distance)
    local closestPed, closestDistance = nil, nil
    for _, ped in ipairs(GetGamePool('CPed')) do
        local targetCoords = GetEntityCoords(ped)
        local dist = #(coords - targetCoords)
        if not closestDistance or dist <= closestDistance then
            closestDistance = dist
            closestPed = ped
        end
    end
    return { id = closestPed, distance = closestDistance }
end

---@param coords vector3
---@param distance number
---@return {id: number, distance: number}
function QB.closest.object(coords, distance)
    coords, distance = getCoordsAndDistance(coords, distance)
    print(coords, distance)
    local closestObject, closestDistance = nil, nil
    for _, object in ipairs(GetGamePool('CObject')) do
        local targetCoords = GetEntityCoords(object)
        local dist = #(coords - targetCoords)
        if not closestDistance or dist <= closestDistance then
            closestDistance = dist
            closestObject = object
        end
    end
    return { id = closestObject, distance = closestDistance }
end