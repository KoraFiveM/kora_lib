
function QB.distance.player(src, coords, distance)
    assert(src, "Source is required")
    assert(coords, "Coordinates are required")
    assert(coords.x and coords.y and coords.z, "Coordinates must include x, y, and z")
    local playerCoords = GetEntityCoords(GetPlayerPed(src))
    local dist = #(playerCoords - vector3(coords.x, coords.y, coords.z))
    return dist <= (distance or 5.0)
end

function QB.distance.coords(coords1, coords2, distance)
    assert(coords1, "First set of coordinates is required")
    assert(coords2, "Second set of coordinates is required")
    assert(coords1.x and coords1.y and coords1.z, "First set of coordinates must include x, y, and z")
    assert(coords2.x and coords2.y and coords2.z, "Second set of coordinates must include x, y, and z")
    local dist = #(vector3(coords1.x, coords1.y, coords1.z) - vector3(coords2.x, coords2.y, coords2.z))
    return dist <= (distance or 5.0)
end

function QB.distance.entity(src, entity, distance)
    assert(src, "Source is required")
    assert(entity, "Entity is required")
    local playerCoords = GetEntityCoords(GetPlayerPed(src))
    local entityCoords = GetEntityCoords(entity)
    local dist = #(playerCoords - entityCoords)
    return dist <= (distance or 5.0)
end

function QB.distance.x(src, point, distance)
    assert(src, "Source is required")
    assert(point, "Point is required")
    assert(point.x, "Point must include x")
    local playerCoords = GetEntityCoords(GetPlayerPed(src))
    local dist = #(vector3(playerCoords.x, 0, 0) - vector3(point.x, 0, 0))
    return dist <= (distance or 5.0)
end

function QB.distance.y(src, point, distance)
    assert(src, "Source is required")
    assert(point, "Point is required")
    assert(point.y, "Point must include y")
    local playerCoords = GetEntityCoords(GetPlayerPed(src))
    local dist = #(vector3(0, playerCoords.y, 0) - vector3(0, point.y, 0))
    return dist <= (distance or 5.0)
end

function QB.distance.xy(src, point, distance)
    assert(src, "Source is required")
    assert(point, "Point is required")
    assert(point.x and point.y and point.z, "Point must include x, y, and z")

    local playerCoords = GetEntityCoords(GetPlayerPed(src))
    local dist = #(vector3(playerCoords.x, playerCoords.y, 0) - vector3(point.x, point.y, 0))

    return dist <= (distance or 5.0)
end
