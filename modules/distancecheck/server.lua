
local isFiniteNumber = Kora.util.isFiniteNumber
local isInteger = Kora.util.isInteger

local function assertPlayerSource(src)
    assert(isInteger(src) and src >= 1, 'Source must be a positive integer server ID.')
end

local function assertRadius(distance)
    if distance == nil then distance = 5.0 end
    assert(isFiniteNumber(distance) and distance >= 0,
        'Distance must be a finite non-negative number.')
    return distance
end

local function assertCoords(coords, label)
    assert(coords and isFiniteNumber(coords.x) and isFiniteNumber(coords.y) and isFiniteNumber(coords.z),
        label .. ' must include finite x, y, and z values.')
end

local function assertEntity(entity)
    assert(isInteger(entity) and entity > 0, 'Entity must be a positive integer handle.')
    assert(not DoesEntityExist or DoesEntityExist(entity), 'Entity does not exist.')
end

local function getPlayerCoords(src)
    local playerPed = GetPlayerPed(src)
    assertEntity(playerPed)
    return GetEntityCoords(playerPed)
end

local function withinRadius(dx, dy, dz, distance)
    distance = assertRadius(distance)
    return dx * dx + dy * dy + dz * dz <= distance * distance
end

---@param src integer
---@param coords KoraCoords
---@param distance? number
---@return boolean
function Kora.distance.player(src, coords, distance)
    assertPlayerSource(src)
    assertCoords(coords, 'Coordinates')
    local playerCoords = getPlayerCoords(src)
    return withinRadius(playerCoords.x - coords.x, playerCoords.y - coords.y, playerCoords.z - coords.z, distance)
end

---@param coords1 KoraCoords
---@param coords2 KoraCoords
---@param distance? number
---@return boolean
function Kora.distance.coords(coords1, coords2, distance)
    assertCoords(coords1, 'First set of coordinates')
    assertCoords(coords2, 'Second set of coordinates')
    return withinRadius(coords1.x - coords2.x, coords1.y - coords2.y, coords1.z - coords2.z, distance)
end

---@param src integer
---@param entity integer
---@param distance? number
---@return boolean
function Kora.distance.entity(src, entity, distance)
    assertPlayerSource(src)
    assertEntity(entity)
    local playerCoords = getPlayerCoords(src)
    local entityCoords = GetEntityCoords(entity)
    return withinRadius(playerCoords.x - entityCoords.x, playerCoords.y - entityCoords.y,
        playerCoords.z - entityCoords.z, distance)
end

---@param src integer
---@param point {x: number}
---@param distance? number
---@return boolean
function Kora.distance.x(src, point, distance)
    assertPlayerSource(src)
    assert(point and isFiniteNumber(point.x), 'Point must include a finite x value.')
    local playerCoords = getPlayerCoords(src)
    return withinRadius(playerCoords.x - point.x, 0, 0, distance)
end

---Whether any entry in `list` is within `opts.radius` (defaults to 5.0, like
---every other Kora.distance check) of the player, using `opts.coordsOf` to
---read each entry's coordinates. Built on `Kora.util.nearest` -- the common
---"is the player near any of these known locations" shape used by several
---resources (door, vendor, pickup spot lists).
---@param src integer
---@param list any[]
---@param opts {radius?: number, coordsOf: fun(entry: any): KoraCoords}
---@return boolean found
---@return any entry
function Kora.distance.playerNearAny(src, list, opts)
    assertPlayerSource(src)
    assert(type(list) == 'table', 'Kora.distance.playerNearAny requires a list.')
    assert(type(opts) == 'table' and Kora.util.isCallable(opts.coordsOf),
        'Kora.distance.playerNearAny requires opts.coordsOf.')

    local playerCoords = getPlayerCoords(src)
    local entry = Kora.util.nearest(list, playerCoords, {
        radius = assertRadius(opts.radius),
        coordsOf = opts.coordsOf,
    })
    return entry ~= nil, entry
end

---@param src integer
---@param point {y: number}
---@param distance? number
---@return boolean
function Kora.distance.y(src, point, distance)
    assertPlayerSource(src)
    assert(point and isFiniteNumber(point.y), 'Point must include a finite y value.')
    local playerCoords = getPlayerCoords(src)
    return withinRadius(0, playerCoords.y - point.y, 0, distance)
end

---@param src integer
---@param point KoraCoords
---@param distance? number
---@return boolean
function Kora.distance.xy(src, point, distance)
    assertPlayerSource(src)
    assertCoords(point, 'Point')

    local playerCoords = getPlayerCoords(src)
    return withinRadius(playerCoords.x - point.x, playerCoords.y - point.y, 0, distance)
end
