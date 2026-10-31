---@diagnostic disable: duplicate-doc-field
local isFiniteNumber = Kora.util.isFiniteNumber

local function assertRadius(distance)
    if distance == nil then distance = 5.0 end
    assert(Kora.util.isFiniteNumber(distance) and distance >= 0,
        'Distance must be a finite non-negative number.')
    return distance
end

local function assertCoords(coords, label)
    assert(coords and isFiniteNumber(coords.x) and isFiniteNumber(coords.y) and isFiniteNumber(coords.z),
        label .. ' must include finite x, y, and z values.')
end

local function assertEntity(entity)
    assert(Kora.util.isInteger(entity) and entity > 0, 'Entity must be a positive integer handle.')
end

local function withinRadius(dx, dy, dz, distance)
    distance = assertRadius(distance)
    return dx * dx + dy * dy + dz * dz <= distance * distance
end

---@param coords QBCoords
---@param distance? number
---@return boolean
function Kora.distance.player(coords, distance)
    assertCoords(coords, 'Coordinates')
    local playerCoords = Kora.cache.get('coords')
    return withinRadius(playerCoords.x - coords.x, playerCoords.y - coords.y, playerCoords.z - coords.z, distance)
end

---@param coords1 QBCoords
---@param coords2 QBCoords
---@param distance? number
---@return boolean
function Kora.distance.coords(coords1, coords2, distance)
    assertCoords(coords1, 'First set of coordinates')
    assertCoords(coords2, 'Second set of coordinates')
    return withinRadius(coords1.x - coords2.x, coords1.y - coords2.y, coords1.z - coords2.z, distance)
end

---@param entity integer
---@param distance? number
---@return boolean
function Kora.distance.entity(entity, distance)
    assertEntity(entity)
    local playerCoords = Kora.cache.get('coords')
    local entityCoords = GetEntityCoords(entity)
    return withinRadius(playerCoords.x - entityCoords.x, playerCoords.y - entityCoords.y,
        playerCoords.z - entityCoords.z, distance)
end

---@param point {x: number}
---@param distance? number
---@return boolean
function Kora.distance.x(point, distance)
    assert(point and isFiniteNumber(point.x), 'Point must include a finite x value.')
    local playerCoords = Kora.cache.get('coords')
    return withinRadius(playerCoords.x - point.x, 0, 0, distance)
end

---@param point {y: number}
---@param distance? number
---@return boolean
function Kora.distance.y(point, distance)
    assert(point and isFiniteNumber(point.y), 'Point must include a finite y value.')
    local playerCoords = Kora.cache.get('coords')
    return withinRadius(0, playerCoords.y - point.y, 0, distance)
end

---@param point QBCoords
---@param distance? number
---@return boolean
function Kora.distance.xy(point, distance)
    assertCoords(point, 'Point')

    local playerCoords = Kora.cache.get('coords')
    return withinRadius(playerCoords.x - point.x, playerCoords.y - point.y, 0, distance)
end
