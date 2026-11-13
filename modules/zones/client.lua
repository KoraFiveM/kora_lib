local nearProximitySq = Config.zones.nearProximity ^ 2

local zoneRegistry = {}
local grid = {}
local insideZones = {}

local destroyZone
local zoneOwnership
local debugZones = {}

local function interactionsLocked()
    local state = LocalPlayer and LocalPlayer.state
    return state and state['kora_multichar:mode'] and state['kora_multichar:mode'] ~= false
end

local setZoneDebug

local nextZoneId = 0
local tickThreadStarted = false
local trackedZoneCount = 0
local debugThreadStarted = false

local function toVec3(v)
    local ok, x, y, z = pcall(function() return v.x, v.y, v.z end)
    assert(ok and Kora.util.isFiniteNumber(x) and Kora.util.isFiniteNumber(y) and Kora.util.isFiniteNumber(z),
        "Coordinates must be a vector3, glm.vec3, or {x=,y=,z=} table.")
    return { x = x, y = y, z = z }
end

local isCallable = Kora.compat.isCallable

local function settleForExport(p)
    if GetInvokingResource() then
        return Citizen.Await(p)
    end
    return p
end

local function distSq(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return dx * dx + dy * dy + dz * dz
end

local function aabbDistSq(p, aabb, ignoreZ)
    local px, py = p.x, p.y
    local cx = px < aabb.minX and aabb.minX or (px > aabb.maxX and aabb.maxX or px)
    local cy = py < aabb.minY and aabb.minY or (py > aabb.maxY and aabb.maxY or py)
    local dx, dy = px - cx, py - cy
    if ignoreZ then return dx * dx + dy * dy end

    local pz = p.z
    local cz = pz < aabb.minZ and aabb.minZ or (pz > aabb.maxZ and aabb.maxZ or pz)
    local dz = pz - cz
    return dx * dx + dy * dy + dz * dz
end

local function makeAabb(minX, maxX, minY, maxY, minZ, maxZ)
    return { minX = minX, maxX = maxX, minY = minY, maxY = maxY, minZ = minZ, maxZ = maxZ }
end

local function rotatedHalfExtents(halfX, halfY, cosR, sinR)
    return math.abs(halfX * cosR) + math.abs(halfY * sinR),
        math.abs(halfX * sinR) + math.abs(halfY * cosR)
end

local function containsBox(zone, p)
    local dx, dy = p.x - zone.coords.x, p.y - zone.coords.y
    local localX = dx * zone.cosR - dy * zone.sinR
    local localY = dx * zone.sinR + dy * zone.cosR

    if math.abs(localX) > zone.halfX or math.abs(localY) > zone.halfY then return false end
    if zone.ignoreZ then return true end

    return math.abs(p.z - zone.coords.z) <= zone.halfZ
end

local function containsSphere(zone, p)
    local distanceSq = distSq(p, zone.coords)
    return zone.includeBoundary and distanceSq <= zone.radiusSq or distanceSq < zone.radiusSq
end

local function containsCircle(zone, p)
    local dx, dy = p.x - zone.coords.x, p.y - zone.coords.y
    local distanceSq = dx * dx + dy * dy
    return zone.includeBoundary and distanceSq <= zone.radiusSq or distanceSq < zone.radiusSq
end

local function containsPoly(zone, p)
    if not zone.ignoreZ and (p.z < zone.minZ or p.z > zone.maxZ) then return false end

    local points = zone.points
    local inside = false
    local j = #points

    for i = 1, #points do
        local pi, pj = points[i], points[j]

        if (pi.y > p.y) ~= (pj.y > p.y) and
            p.x < (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y) + pi.x then
            inside = not inside
        end

        j = i
    end

    return inside
end

local containsFn = {
    box = containsBox,
    sphere = containsSphere,
    circle = containsCircle,
    poly = containsPoly,
}

local function nextId()
    nextZoneId = nextZoneId + 1
    return nextZoneId
end

local function cellKey(cx, cy)
    return cx * 100000 + cy
end

local function worldToCell(x, y)
    return math.floor(x / Config.zones.gridSize), math.floor(y / Config.zones.gridSize)
end

local gridEpoch = 0

local function insertIntoGrid(zone)
    gridEpoch = gridEpoch + 1

    local minCx, minCy = worldToCell(zone.aabb.minX, zone.aabb.minY)
    local maxCx, maxCy = worldToCell(zone.aabb.maxX, zone.aabb.maxY)

    for cx = minCx, maxCx do
        for cy = minCy, maxCy do
            local key = cellKey(cx, cy)
            local bucket = grid[key]

            if not bucket then
                bucket = {}
                grid[key] = bucket
            end

            bucket[zone.id] = true
            zone.cells[key] = true
        end
    end
end

local function removeFromGrid(zone)
    gridEpoch = gridEpoch + 1

    for key in pairs(zone.cells) do
        local bucket = grid[key]

        if bucket then
            bucket[zone.id] = nil
            if next(bucket) == nil then grid[key] = nil end
        end
    end

    zone.cells = {}
end

destroyZone = function(zone)
    if zone.removed then return end
    zone.removed = true
    insideZones[zone.id] = nil

    if zone.trackPlayer then
        removeFromGrid(zone)
        trackedZoneCount = trackedZoneCount - 1
    end
    debugZones[zone.id] = nil
    zoneOwnership.untrack(zone.id)

    zoneRegistry[zone.id] = nil
end

zoneOwnership = Kora.resources.registry(function(zoneId)
    local zone = zoneRegistry[zoneId]
    if zone then destroyZone(zone) end
end)

local function canManageZone(zone)
    local invoker = GetInvokingResource()
    return not invoker or zoneOwnership.owner(zone.id) == invoker
end

local function buildHandle(zone)
    return {
        id = zone.id,
        type = zone.type,
        resource = zone.resource,
        data = zone.data,
        remove = function()
            if zone.removed or not canManageZone(zone) then return false end
            destroyZone(zone)
            return true
        end,
        contains = function(coords) return containsFn[zone.type](zone, toVec3(coords)) end,
        isInside = function() return zone.isInside end,
        setDebug = function(enabled)
            assert(type(enabled) == "boolean", "enabled must be a boolean.")
            if not canManageZone(zone) then return false end
            setZoneDebug(zone, enabled)
            return true
        end,
    }
end

local function editZone(handle, opts)
    assert(type(handle) == "table", "Zone handle must be a table.")
    assert(type(opts) == "table", "Zone edit options must be a table.")

    local zone = zoneRegistry[handle.id]

    assert(zone and not zone.removed, "Zone handle is invalid or the zone has been removed.")
    if not canManageZone(zone) then return nil, "Zone is owned by another resource." end

    for key in pairs(opts) do
        assert(
            key == "coords" or key == "onEnter" or key == "onExit",
            ("Zone edit does not allow changing '%s'. Only coords, onEnter, and onExit can be edited."):format(key)
        )
    end

    local coords
    if opts.coords ~= nil then
        assert(zone.type ~= "poly", "Poly zones do not have editable coords; edit their points instead.")
        coords = toVec3(opts.coords)
    end

    if opts.onEnter ~= nil then
        assert(
            opts.onEnter == false or isCallable(opts.onEnter),
            "onEnter must be a function or false."
        )
    end

    if opts.onExit ~= nil then
        assert(
            opts.onExit == false or isCallable(opts.onExit),
            "onExit must be a function or false."
        )
    end

    if coords ~= nil and (coords.x ~= zone.coords.x or coords.y ~= zone.coords.y or coords.z ~= zone.coords.z) then
        if zone.trackPlayer then removeFromGrid(zone) end

        zone.coords = coords

        if zone.type == "box" then
            local worldHalfX, worldHalfY = rotatedHalfExtents(
                zone.halfX,
                zone.halfY,
                zone.cosR,
                zone.sinR
            )

            zone.aabb = makeAabb(
                coords.x - worldHalfX, coords.x + worldHalfX,
                coords.y - worldHalfY, coords.y + worldHalfY,
                coords.z - zone.halfZ, coords.z + zone.halfZ
            )
        elseif zone.type == "sphere" then
            zone.aabb = makeAabb(
                coords.x - zone.radius, coords.x + zone.radius,
                coords.y - zone.radius, coords.y + zone.radius,
                coords.z - zone.radius, coords.z + zone.radius
            )
        elseif zone.type == "circle" then
            zone.aabb = makeAabb(
                coords.x - zone.radius, coords.x + zone.radius,
                coords.y - zone.radius, coords.y + zone.radius,
                coords.z, coords.z
            )
        end

        if zone.trackPlayer then insertIntoGrid(zone) end
    end

    if opts.onEnter ~= nil then
        zone.onEnter = opts.onEnter == false and nil or opts.onEnter
    end

    if opts.onExit ~= nil then
        zone.onExit = opts.onExit == false and nil or opts.onExit
    end

    return zone.handle
end

local function safeCall(zone, label, fn, ...)
    local ok, err = pcall(fn, ...)

    if not ok then
        Kora.logging.error('lib.client.callback_for_zone_owned_by_errored', ("[kora_lib:zones] %s callback for zone %d (%s, owned by %s) errored: %s")
            :format(label, zone.id, zone.type, zone.resource, tostring(err)))
    end
end

local function assertCommonOptions(opts)
    assert(type(opts) == "table", "Zone options must be a table.")
    assert(opts.onEnter == nil or isCallable(opts.onEnter), "onEnter must be a function.")
    assert(opts.onExit == nil or isCallable(opts.onExit), "onExit must be a function.")
    assert(opts.inside == nil or isCallable(opts.inside), "inside must be a function.")
    assert(opts.debug == nil or type(opts.debug) == "boolean", "debug must be a boolean.")
    assert(opts.trackPlayer == nil or type(opts.trackPlayer) == "boolean", "trackPlayer must be a boolean.")
end

local function initBox(zone, opts)
    assert(opts.coords, "Box zone requires coords.")
    assert(opts.size, "Box zone requires size.")
    assert(opts.rotation == nil or Kora.util.isFiniteNumber(opts.rotation), "rotation must be a finite number.")
    assert(opts.ignoreZ == nil or type(opts.ignoreZ) == "boolean", "ignoreZ must be a boolean.")

    local coords = toVec3(opts.coords)
    local size = toVec3(opts.size)

    assert(size.x > 0 and size.y > 0 and size.z > 0, "Box zone size must be positive on every axis.")

    local radians = -math.rad(opts.rotation or 0)

    zone.coords = coords
    zone.halfX = size.x / 2
    zone.halfY = size.y / 2
    zone.halfZ = size.z / 2
    zone.cosR = math.cos(radians)
    zone.sinR = math.sin(radians)
    zone.ignoreZ = opts.ignoreZ == true

    local worldHalfX, worldHalfY = rotatedHalfExtents(zone.halfX, zone.halfY, zone.cosR, zone.sinR)

    zone.aabb = makeAabb(
        coords.x - worldHalfX, coords.x + worldHalfX,
        coords.y - worldHalfY, coords.y + worldHalfY,
        coords.z - zone.halfZ, coords.z + zone.halfZ
    )
end

local function initSphere(zone, opts)
    assert(opts.coords, "Sphere zone requires coords.")
    assert(Kora.util.isFiniteNumber(opts.radius) and opts.radius > 0, "Sphere zone requires a positive finite radius.")
    assert(opts.includeBoundary == nil or type(opts.includeBoundary) == "boolean", "includeBoundary must be a boolean.")

    local coords = toVec3(opts.coords)

    zone.coords = coords
    zone.radius = opts.radius
    zone.radiusSq = opts.radius * opts.radius
    zone.includeBoundary = opts.includeBoundary ~= false

    zone.aabb = makeAabb(
        coords.x - opts.radius, coords.x + opts.radius,
        coords.y - opts.radius, coords.y + opts.radius,
        coords.z - opts.radius, coords.z + opts.radius
    )
end

local function initCircle(zone, opts)
    assert(opts.coords, "Circle zone requires coords.")
    assert(Kora.util.isFiniteNumber(opts.radius) and opts.radius > 0, "Circle zone requires a positive finite radius.")
    assert(opts.includeBoundary == nil or type(opts.includeBoundary) == "boolean", "includeBoundary must be a boolean.")

    local coords = toVec3(opts.coords)

    zone.coords = coords
    zone.radius = opts.radius
    zone.radiusSq = opts.radius * opts.radius
    zone.includeBoundary = opts.includeBoundary ~= false
    zone.ignoreZ = true
    zone.aabb = makeAabb(
        coords.x - opts.radius, coords.x + opts.radius,
        coords.y - opts.radius, coords.y + opts.radius,
        coords.z, coords.z
    )
end

local function initPoly(zone, opts)
    assert(type(opts.points) == "table", "Poly zone points must be a dense array.")
    local pointCount = 0
    for index in pairs(opts.points) do
        assert(Kora.util.isInteger(index) and index >= 1, "Poly zone points must be a dense array.")
        pointCount = pointCount + 1
    end
    assert(pointCount >= 3 and pointCount == #opts.points, "Poly zone requires at least 3 dense points.")
    assert(opts.thickness == nil or Kora.util.isFiniteNumber(opts.thickness), "thickness must be a finite number.")
    assert((opts.minZ == nil) == (opts.maxZ == nil), "minZ and maxZ must both be given, or neither.")
    assert(opts.ignoreZ == nil or type(opts.ignoreZ) == "boolean", "ignoreZ must be a boolean.")

    local points = {}
    local minX, maxX = math.huge, -math.huge
    local minY, maxY = math.huge, -math.huge
    local lowestZ = math.huge

    for i = 1, #opts.points do
        local point = opts.points[i]
        local v = toVec3(point)
        points[i] = v
        minX, maxX = math.min(minX, v.x), math.max(maxX, v.x)
        minY, maxY = math.min(minY, v.y), math.max(maxY, v.y)
        lowestZ = math.min(lowestZ, v.z)
    end

    local minZ, maxZ = opts.minZ, opts.maxZ

    assert(minZ == nil or Kora.util.isFiniteNumber(minZ), "minZ must be a finite number.")
    assert(maxZ == nil or Kora.util.isFiniteNumber(maxZ), "maxZ must be a finite number.")

    if minZ == nil then
        local thickness = opts.thickness or Config.zones.defaultPolyThickness
        minZ, maxZ = lowestZ, lowestZ + thickness
    end

    assert(maxZ > minZ, "maxZ must be greater than minZ.")

    zone.points = points
    zone.minZ = minZ
    zone.maxZ = maxZ
    zone.ignoreZ = opts.ignoreZ == true

    zone.aabb = makeAabb(minX, maxX, minY, maxY, minZ, maxZ)
end

local BOX_SIGNS = {
    { -1, -1, -1 }, { -1, -1, 1 }, { -1, 1, -1 }, { -1, 1, 1 },
    { 1,  -1, -1 }, { 1,  -1, 1 }, { 1,  1,  -1 }, { 1,  1,  1 },
}

local BOX_FACES = {
    { 1, 2, 4, 3 },
    { 5, 6, 8, 7 },
    { 1, 2, 6, 5 },
    { 3, 4, 8, 7 },
    { 1, 3, 7, 5 },
    { 2, 4, 8, 6 },
}

local BOX_EDGES = {
    { 1, 2 }, { 1, 3 }, { 1, 5 },
    { 2, 4 }, { 2, 6 },
    { 3, 4 }, { 3, 7 },
    { 4, 8 },
    { 5, 6 }, { 5, 7 },
    { 6, 8 },
    { 7, 8 },
}

local function boxCorner(zone, sx, sy, sz)
    local lx, ly = sx * zone.halfX, sy * zone.halfY

    return zone.coords.x + lx * zone.cosR + ly * zone.sinR,
        zone.coords.y - lx * zone.sinR + ly * zone.cosR,
        zone.coords.z + sz * zone.halfZ
end

local function drawWallTriangle(x1, y1, z1, x2, y2, z2, x3, y3, z3, color)
    DrawPoly(x1, y1, z1, x2, y2, z2, x3, y3, z3, color.r, color.g, color.b, color.a)
    DrawPoly(x1, y1, z1, x3, y3, z3, x2, y2, z2, color.r, color.g, color.b, color.a)
end

local function drawWallQuad(x1, y1, z1, x2, y2, z2, x3, y3, z3, x4, y4, z4, color)
    drawWallTriangle(x1, y1, z1, x2, y2, z2, x3, y3, z3, color)
    drawWallTriangle(x1, y1, z1, x3, y3, z3, x4, y4, z4, color)
end

local function wallColor(color)
    return { r = color.r, g = color.g, b = color.b, a = Config.zones.debugWallAlpha }
end

local function hexToRgb(hex)
    return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
end

local function zoneDebugColor()
    local r, g, b = hexToRgb(Kora.theme.accentColor())
    return { r = r, g = g, b = b, a = Config.zones.debugAlpha }
end

local function drawDebugBox(zone, color)
    local corners = {}

    for i = 1, #BOX_SIGNS do
        local signs = BOX_SIGNS[i]
        corners[i] = { boxCorner(zone, signs[1], signs[2], signs[3]) }
    end

    for edgeIndex = 1, #BOX_EDGES do
        local edge = BOX_EDGES[edgeIndex]
        local a, b = corners[edge[1]], corners[edge[2]]
        DrawLine(a[1], a[2], a[3], b[1], b[2], b[3], color.r, color.g, color.b, color.a)
    end

    local walls = wallColor(color)

    for faceIndex = 1, #BOX_FACES do
        local face = BOX_FACES[faceIndex]
        local a, b, c, d = corners[face[1]], corners[face[2]], corners[face[3]], corners[face[4]]
        drawWallQuad(a[1], a[2], a[3], b[1], b[2], b[3], c[1], c[2], c[3], d[1], d[2], d[3], walls)
    end
end

local function drawDebugSphere(zone, color)
    DrawMarker(28, zone.coords.x, zone.coords.y, zone.coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        zone.radius * 2, zone.radius * 2, zone.radius * 2, color.r, color.g, color.b, color.a,
        false, false, 2, false, nil, nil, false)
end

local function drawDebugCircle(zone, color)
    DrawMarker(1, zone.coords.x, zone.coords.y, zone.coords.z - 500.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        zone.radius * 2, zone.radius * 2, 1000.0, color.r, color.g, color.b, color.a,
        false, false, 2, false, nil, nil, false)
end

local function drawDebugPoly(zone, color)
    local points = zone.points
    local n = #points
    local walls = wallColor(color)

    for i = 1, n do
        local a, b = points[i], points[i % n + 1]

        DrawLine(a.x, a.y, zone.minZ, b.x, b.y, zone.minZ, color.r, color.g, color.b, color.a)
        DrawLine(a.x, a.y, zone.maxZ, b.x, b.y, zone.maxZ, color.r, color.g, color.b, color.a)
        DrawLine(a.x, a.y, zone.minZ, a.x, a.y, zone.maxZ, color.r, color.g, color.b, color.a)

        drawWallQuad(
            a.x, a.y, zone.minZ,
            a.x, a.y, zone.maxZ,
            b.x, b.y, zone.maxZ,
            b.x, b.y, zone.minZ,
            walls)
    end
end

local drawDebugFn = {
    box = drawDebugBox,
    sphere = drawDebugSphere,
    circle = drawDebugCircle,
    poly = drawDebugPoly,
}

local function ensureDebugThread()
    if debugThreadStarted then return end
    debugThreadStarted = true

    CreateThread(function()
        while next(debugZones) ~= nil do
            for _, zone in pairs(debugZones) do
                drawDebugFn[zone.type](zone, zoneDebugColor())
            end

            Wait(0)
        end

        debugThreadStarted = false
    end)
end

setZoneDebug = function(zone, enabled)
    zone.debug = enabled

    if enabled then
        debugZones[zone.id] = zone
        ensureDebugThread()
    else
        debugZones[zone.id] = nil
    end
end

local tickLoop

local function ensureTickThread()
    if tickThreadStarted then return end
    tickThreadStarted = true
    CreateThread(tickLoop)
end

local function createZone(zoneType, opts, initShape)
    assertCommonOptions(opts)

    local zone = {
        id = nextId(),
        type = zoneType,
        onEnter = opts.onEnter,
        onExit = opts.onExit,
        inside = opts.inside,
        trackPlayer = opts.trackPlayer ~= false,
        debug = false,
        data = opts.data,
        resource = GetInvokingResource() or GetCurrentResourceName(),
        isInside = false,
        cells = {},
        removed = false,
    }

    initShape(zone, opts)

    zone.handle = buildHandle(zone)

    zoneRegistry[zone.id] = zone
    if zone.trackPlayer then
        insertIntoGrid(zone)
        trackedZoneCount = trackedZoneCount + 1
    end

    zoneOwnership.track(zone.resource, zone.id)

    if Config.zones.debug == true or opts.debug == true then
        setZoneDebug(zone, true)
    end

    if zone.trackPlayer then ensureTickThread() end

    return zone.handle
end

---Creates a rotatable box zone.
---@param opts KoraZoneBoxOptions
---@return KoraZoneHandle zone
function Kora.zones.box(opts)
    return createZone("box", opts, initBox)
end

---Creates a sphere zone.
---@param opts KoraZoneSphereOptions
---@return KoraZoneHandle zone
function Kora.zones.sphere(opts)
    return createZone("sphere", opts, initSphere)
end

---Creates a flat 2D circle zone. Its containment test ignores the point's Z coordinate.
---@param opts KoraZoneCircleOptions
---@return KoraZoneHandle zone
function Kora.zones.circle(opts)
    return createZone("circle", opts, initCircle)
end

---Creates a polygon zone: a 2D footprint (opts.points) extruded across a vertical height
---band (opts.minZ/opts.maxZ, or opts.thickness upward from the lowest point's Z).
---@param opts KoraZonePolyOptions
---@return KoraZoneHandle zone
function Kora.zones.poly(opts)
    return createZone("poly", opts, initPoly)
end

---Creates a point zone. Not a separate shape: this is a sphere zone with a small default
---radius, and returns the exact same zone handle Kora.zones.sphere does.
---@param opts KoraZoneSphereOptions `radius` defaults to Config.zones.defaultPointRadius.
---@return KoraZoneHandle zone
function Kora.zones.point(opts)
    assert(type(opts) == "table", "Point zone options must be a table.")
    if opts.radius == nil then
        local pointOpts = {}
        for key, value in pairs(opts) do pointOpts[key] = value end
        pointOpts.radius = Config.zones.defaultPointRadius
        opts = pointOpts
    end

    return createZone("sphere", opts, initSphere)
end

---Every zone the local player is currently inside, across every resource (a registry walk, no containment maths).
---@param resource? string Only return zones owned by this resource. Omit for all of them.
---@return KoraZoneHandle[] zones Unordered -- the registry is a hash, not a list.
function Kora.zones.getInside(resource)
    assert(resource == nil or type(resource) == "string", "resource filter must be a string.")

    local inside = {}

    for _, zone in pairs(zoneRegistry) do
        if zone.isInside and (resource == nil or zone.resource == resource) then
            inside[#inside + 1] = zone.handle
        end
    end

    return inside
end

---Toggles debug wireframe drawing on one zone (or every zone) at runtime. Also available as `zone.setDebug(enabled)`
---and via the `kora_zonedebug` command.
---@param id? integer A zone id (`zone.id`). Omit (nil) to affect every registered zone.
---@param enabled boolean
---@return boolean changed
function Kora.zones.setDebug(id, enabled)
    assert(id == nil or Kora.util.isInteger(id), "id must be a zone id or nil.")
    assert(type(enabled) == "boolean", "enabled must be a boolean.")

    if id ~= nil then
        local zone = zoneRegistry[id]
        if not zone or not canManageZone(zone) then return false end
        setZoneDebug(zone, enabled)
        return true
    end

    if GetInvokingResource() then return false end
    for _, zone in pairs(zoneRegistry) do
        setZoneDebug(zone, enabled)
    end
    return true
end

local candidateCell, candidateList, candidateEpoch = nil, nil, -1

local function candidatesFor(cx, cy)
    local key = cellKey(cx, cy)
    if candidateCell == key and candidateEpoch == gridEpoch then return candidateList end

    local seen, list = {}, {}

    for dx = -1, 1 do
        for dy = -1, 1 do
            local bucket = grid[cellKey(cx + dx, cy + dy)]

            if bucket then
                for zoneId in pairs(bucket) do
                    if not seen[zoneId] then
                        seen[zoneId] = true
                        local zone = zoneRegistry[zoneId]
                        if zone then list[#list + 1] = zone end
                    end
                end
            end
        end
    end

    candidateCell, candidateList, candidateEpoch = key, list, gridEpoch
    return list
end

tickLoop = function()
    while trackedZoneCount > 0 do
        local ped = PlayerPedId()
        local p = GetEntityCoords(ped)

        local list = candidatesFor(worldToCell(p.x, p.y))
        local locked = interactionsLocked()

        for zoneId, zone in pairs(insideZones) do
            if zone.removed then
                insideZones[zoneId] = nil
            elseif locked or aabbDistSq(p, zone.aabb, zone.ignoreZ) ~= 0 or not containsFn[zone.type](zone, p) then
                zone.isInside = false
                insideZones[zoneId] = nil
                if zone.onExit then safeCall(zone, "onExit", zone.onExit, zone) end
            end
        end

        local minDistSq = math.huge
        local needsPerFrame = false

        for i = 1, #list do
            local zone = list[i]

            if not zone.removed then
                if locked then
                    if zone.isInside then
                        zone.isInside = false
                        if zone.onExit then safeCall(zone, "onExit", zone.onExit, zone) end
                    end
                    goto continue
                end
                local dSq = aabbDistSq(p, zone.aabb, zone.ignoreZ)
                if dSq < minDistSq then minDistSq = dSq end

                local isInside = dSq == 0 and containsFn[zone.type](zone, p) or false

                if isInside and not zone.isInside then
                    zone.isInside = true
                    insideZones[zone.id] = zone
                    if zone.onEnter then safeCall(zone, "onEnter", zone.onEnter, zone) end
                elseif not isInside and zone.isInside then
                    zone.isInside = false
                    insideZones[zone.id] = nil
                    if zone.onExit then safeCall(zone, "onExit", zone.onExit, zone) end
                end

                if isInside and zone.inside then
                    needsPerFrame = true
                    safeCall(zone, "inside", zone.inside, zone, p)
                end
                ::continue::
            end
        end

        local interval

        if needsPerFrame then
            interval = Config.zones.tickInside
        elseif minDistSq == math.huge then
            interval = Config.zones.tickFar
        else
            local farTravel = GetEntitySpeed(ped) * (Config.zones.tickFar / 1000) * Config.zones.speedSafetyFactor
            local effectiveNearSq = math.max(nearProximitySq, farTravel * farTravel)
            interval = minDistSq <= effectiveNearSq and Config.zones.tickNear or Config.zones.tickFar
        end

        Wait(interval)
    end

    tickThreadStarted = false
end

local initFnByType = { box = initBox, sphere = initSphere, poly = initPoly }

local ZONE_TYPES = { box = true, sphere = true, poly = true }

local creatorParamCycles = {
    box = { "size", "height", "rotation", "zOffset" },
    sphere = { "radius", "zOffset" },
    poly = { "thickness", "zOffset", "editPoint" },
}

local function activeParamName(state)
    return creatorParamCycles[state.type][state.activeParam]
end

local function isEditingPoints(state)
    return state.type == "poly" and activeParamName(state) == "editPoint"
end

local function nearestPointIndex(points, coords)
    local bestIndex, bestDist = nil, math.huge

    for i = 1, #points do
        local point = points[i]
        local d = distSq(point, coords)
        if d < bestDist then bestIndex, bestDist = i, d end
    end

    return bestIndex
end

local creatorState = nil

local function radarIsHidden()
    if type(IsRadarHidden) ~= "function" then return false end
    local ok, hidden = pcall(IsRadarHidden)
    return ok and hidden == true
end

local function restoreCreatorRadar(state)
    if state and state.radarManaged and not state.radarWasHidden then DisplayRadar(true) end
end

local function creatorLog(msg)
    Kora.logging.info('lib.client.diagnostic', ("[kora_lib:zones] %s"):format(msg))
end

local function formatNumber(n)
    assert(Kora.util.isFiniteNumber(n), "Zone snippets require finite numeric values.")
    return ("%.2f"):format(n)
end

local function formatCoords(v)
    return ("vector3(%s, %s, %s)"):format(formatNumber(v.x), formatNumber(v.y), formatNumber(v.z))
end

---Formats `opts` (as resolved by Kora.zones.startCreator) into the Kora.zones.<type>({...}) snippet the confirm dialog copies. Pure.
---@param zoneType "box" | "sphere" | "poly"
---@param opts table
---@return string
function Kora.zones.generateSnippet(zoneType, opts)
    assert(ZONE_TYPES[zoneType], "generateSnippet type must be 'box', 'sphere', or 'poly'.")
    assert(type(opts) == "table", "generateSnippet options must be a table.")

    if zoneType == "box" then
        return ("Kora.zones.box({\n    coords = %s,\n    size = %s,\n    rotation = %s,\n})")
            :format(formatCoords(opts.coords), formatCoords(opts.size), formatNumber(opts.rotation or 0))
    end

    if zoneType == "sphere" then
        return ("Kora.zones.sphere({\n    coords = %s,\n    radius = %s,\n})")
            :format(formatCoords(opts.coords), formatNumber(opts.radius))
    end

    local pointLines = {}
    for i = 1, #opts.points do
        local point = opts.points[i]
        pointLines[i] = "        " .. formatCoords(point) .. ","
    end

    if opts.minZ ~= nil or opts.maxZ ~= nil then
        assert(opts.minZ ~= nil and opts.maxZ ~= nil, "Poly snippets require both minZ and maxZ.")
        return ("Kora.zones.poly({\n    points = {\n%s\n    },\n    minZ = %s,\n    maxZ = %s,\n})")
            :format(table.concat(pointLines, "\n"), formatNumber(opts.minZ), formatNumber(opts.maxZ))
    end

    return ("Kora.zones.poly({\n    points = {\n%s\n    },\n    thickness = %s,\n})")
        :format(table.concat(pointLines, "\n"), formatNumber(opts.thickness))
end

local function newCreatorState(zoneType, resource)
    local creator = Config.zones.creator

    return {
        type = zoneType,
        resource = resource,
        center = nil,
        points = {},
        freecam = nil,
        cam = nil,
        movementMode = "camera",
        instructions = nil,
        lastInstructionKey = nil,
        radarManaged = false,
        radarWasHidden = radarIsHidden(),
        size = creator.defaultBoxSize,
        height = creator.defaultBoxHeight,
        rotation = 0.0,
        radius = creator.defaultRadius,
        thickness = creator.defaultThickness,
        zOffset = 0.0,
        activeParam = 1,
        editIndex = nil,
        grabbing = false,
        promise = promise.new(),
        dirty = true,
        cachedPreview = nil,
        lastHud = nil,
    }
end

---Pre-populates a creator state from an existing zone's opts so startCreator can reposition/resize a built zone; omitted fields keep defaults.
---@param state table
---@param opts table
local function seedCreatorState(state, opts)
    assert(type(opts) == "table", "startCreator existingOpts must be a table.")

    if state.type == "box" then
        if opts.coords then state.center = toVec3(opts.coords) end
        if opts.size then
            local size = toVec3(opts.size)
            assert(size.x > 0 and size.z > 0, "Seeded box size must be positive on every axis.")
            state.size = size.x
            state.height = size.z
        end
        if opts.rotation ~= nil then
            assert(Kora.util.isFiniteNumber(opts.rotation), "Seeded rotation must be a finite number.")
            state.rotation = opts.rotation % 360
        end
    elseif state.type == "sphere" then
        if opts.coords then state.center = toVec3(opts.coords) end
        if opts.radius ~= nil then
            assert(Kora.util.isFiniteNumber(opts.radius) and opts.radius > 0, "Seeded radius must be a positive finite number.")
            state.radius = opts.radius
        end
    elseif state.type == "poly" then
        if opts.points then
            assert(type(opts.points) == "table" and #opts.points <= Config.zones.creator.maxPolyPoints,
                ("Seeded poly points must be a table of at most %d points."):format(Config.zones.creator.maxPolyPoints))

            local points = {}
            for i = 1, #opts.points do
                local point = opts.points[i]
                points[i] = toVec3(point)
            end
            state.points = points
        end

        assert((opts.minZ == nil) == (opts.maxZ == nil), "Seeded minZ and maxZ must both be given, or neither.")
        if opts.minZ ~= nil then
            assert(Kora.util.isFiniteNumber(opts.minZ) and Kora.util.isFiniteNumber(opts.maxZ),
                "Seeded minZ and maxZ must be finite numbers.")
            assert(opts.maxZ > opts.minZ, "Seeded maxZ must be greater than minZ.")
            state.thickness = opts.maxZ - opts.minZ
        elseif opts.thickness ~= nil then
            assert(Kora.util.isFiniteNumber(opts.thickness) and opts.thickness > 0,
                "Seeded thickness must be a positive finite number.")
            state.thickness = opts.thickness
        end
    end

    state.dirty = true
end

local function creatorCanConfirm(state)
    if state.type == "poly" then return #state.points >= 3 end
    return state.center ~= nil
end

local function raise(v, dz)
    return { x = v.x, y = v.y, z = v.z + dz }
end

local function creatorOpts(state)
    if state.type == "box" then
        return {
            coords = raise(state.center, state.zOffset),
            size = { x = state.size, y = state.size, z = state.height },
            rotation = state.rotation,
        }
    end

    if state.type == "sphere" then
        return { coords = raise(state.center, state.zOffset), radius = state.radius }
    end

    local points = {}
    for i = 1, #state.points do
        local point = state.points[i]
        points[i] = raise(point, state.zOffset)
    end

    return { points = points, thickness = state.thickness }
end

local function buildPreviewZone(state)
    if not creatorCanConfirm(state) then return nil end

    local scratch = { type = state.type }
    initFnByType[state.type](scratch, creatorOpts(state))
    return scratch
end

---Tears the creator down and settles its promise with `value` (`{ type, opts }` on confirm, `nil` on cancel).
---@param value any
local function releaseCreatorUi(state)
    if state and state.instructions then
        state.instructions.hide()
        state.instructions = nil
    end
    if state and state.hudHidden then
        state.hudHidden = nil
        if GetResourceState("kora_hud") == "started" then
            pcall(function() exports.kora_hud:show() end)
        end
    end
end

local function releaseCreatorCamera(state)
    if state and state.controlLease then
        Kora.compat.releaseControlLease(state.controlLease, state.resource)
        state.controlLease = nil
    end
    if state and state.freecam then
        state.freecam.stop()
        state.freecam = nil
    end
end

local function resolveCreator(value)
    local state = creatorState
    creatorState = nil
    if state then
        releaseCreatorUi(state)
        releaseCreatorCamera(state)
        state.promise:resolve(value)
    end
end

local function shiftHeld()
    local ok, pressed = pcall(function() return IsRawKeyDown(16) end)
    if ok and pressed == true then return true end

    return IsControlPressed(0, 21)
end

local function activeParamBaseStep(state)
    local param = creatorParamCycles[state.type][state.activeParam]
    if param == "editPoint" then return 0 end
    if param == "rotation" then return Config.zones.creator.rotationStep end
    return Config.zones.creator.sizeStep
end

local function adjustActiveParam(state, direction)
    local param = creatorParamCycles[state.type][state.activeParam]
    local step = Config.zones.creator
    local multiplier = shiftHeld() and step.shiftMultiplier or 1

    if param == "editPoint" then
        return
    elseif param == "rotation" then
        state.rotation = (state.rotation + direction * step.rotationStep * multiplier) % 360
    elseif param == "zOffset" then
        state.zOffset = state.zOffset + direction * step.sizeStep * multiplier
    else
        state[param] = math.max(step.sizeStep, state[param] + direction * step.sizeStep * multiplier)
    end

    state.dirty = true
end

local function creatorHudSnapshot(state, aiming)
    local shift = shiftHeld()

    return {
        type = state.type,
        pointCount = #state.points,
        hasCenter = state.center ~= nil,
        activeParam = creatorParamCycles[state.type][state.activeParam],
        size = state.size,
        height = state.height,
        rotation = state.rotation,
        radius = state.radius,
        thickness = state.thickness,
        zOffset = state.zOffset,
        editIndex = state.editIndex or 0,
        grabbing = state.grabbing,
        canConfirm = creatorCanConfirm(state),
        aiming = aiming,
        isShiftHeld = shift,
        stepSize = activeParamBaseStep(state) * (shift and Config.zones.creator.shiftMultiplier or 1),
    }
end

local function hudSnapshotsEqual(a, b)
    if not b then return false end

    return a.type == b.type
        and a.pointCount == b.pointCount
        and a.hasCenter == b.hasCenter
        and a.activeParam == b.activeParam
        and a.size == b.size
        and a.height == b.height
        and a.rotation == b.rotation
        and a.radius == b.radius
        and a.thickness == b.thickness
        and a.zOffset == b.zOffset
        and a.editIndex == b.editIndex
        and a.grabbing == b.grabbing
        and a.canConfirm == b.canConfirm
        and a.aiming == b.aiming
        and a.isShiftHeld == b.isShiftHeld
        and a.stepSize == b.stepSize
end

local function openConfirmDialog(state)
    local opts = creatorOpts(state)
    local snippet = Kora.zones.generateSnippet(state.type, opts)

    local ok, response = pcall(function()
        return Kora.nui.withFocus(true, true, function()
            return Citizen.Await(Kora.nui.request("zoneCreator:confirm",
                { type = state.type, snippet = snippet }, Config.zones.creator.confirmTimeout, state.resource))
        end, state.resource)
    end)

    if creatorState ~= state then return end

    if not ok then
        creatorLog(("confirm dialog failed: %s"):format(tostring(response)))
        resolveCreator(nil)
        return
    end

    if response and response.confirmed then
        resolveCreator({ type = state.type, opts = opts })
    end
end

local function creatorPlaceEditPoint(state)
    if state.grabbing then
        local hit, coords = Kora.raycast.fromCam(state.cam, Config.zones.creator.raycastDistance)
        if not hit then
            creatorLog("nothing to drop the point on -- aim at solid ground/geometry.")
            return
        end

        local index = state.editIndex
        if index == nil or state.points[index] == nil then
            state.grabbing = false
            return
        end

        state.points[index] = coords
        state.grabbing = false
        state.dirty = true
        return
    end

    if state.editIndex == nil then
        creatorLog("no point nearby to select -- aim closer to a placed point.")
        return
    end

    state.grabbing = true
end

local function creatorPlace(state)
    if state.type == "poly" and isEditingPoints(state) then
        creatorPlaceEditPoint(state)
        return
    end

    local hit, coords = Kora.raycast.fromCam(state.cam, Config.zones.creator.raycastDistance)
    if not hit then
        creatorLog("nothing to place a point on -- aim at solid ground/geometry.")
        return
    end

    if state.type == "poly" then
        if #state.points >= Config.zones.creator.maxPolyPoints then
            creatorLog(("poly zones are capped at %d points."):format(Config.zones.creator.maxPolyPoints))
            return
        end
        state.points[#state.points + 1] = coords
    else
        state.center = coords
    end

    state.dirty = true
end

local function creatorUndo(state)
    if state.type == "poly" then
        if state.grabbing then
            state.grabbing = false
        else
            table.remove(state.points)
        end
    else
        state.center = nil
    end

    state.dirty = true
end

local function creatorCycleParam(state)
    local cycle = creatorParamCycles[state.type]
    local step = shiftHeld() and -1 or 1

    state.activeParam = ((state.activeParam - 1 + step + #cycle) % #cycle) + 1
end

---Registers an owner-tracked zone-creator keybind that only calls `handler(creatorState)` while a creator session is active.
---@param command string
---@param label string
---@param key string
---@param handler fun(state: table)
---@param mapper? string RegisterKeyMapping input mapper, 'keyboard' by default ('MOUSE_BUTTON' for mouse clicks).
local creatorBindings = {}

local function registerCreatorKeybind(command, label, key, handler, mapper)
    local handle = Kora.keybind.add({
        name = command,
        description = label,
        defaultMapper = mapper or 'keyboard',
        defaultKey = key,
        onPressed = function()
            if creatorState then handler(creatorState) end
        end,
    })
    creatorBindings[command] = handle
    return handle
end

registerCreatorKeybind("kora_lib_zonecreator_place", "Zone Creator: Place Point", "E", creatorPlace)
registerCreatorKeybind("kora_lib_zonecreator_undo", "Zone Creator: Undo Last Point", "BACK", creatorUndo)
registerCreatorKeybind("kora_lib_zonecreator_place_click", "Zone Creator: Place Point (Mouse)", "MOUSE_LEFT", creatorPlace, "MOUSE_BUTTON")
registerCreatorKeybind("kora_lib_zonecreator_undo_click", "Zone Creator: Undo Last Point (Mouse)", "MOUSE_RIGHT", creatorUndo, "MOUSE_BUTTON")
registerCreatorKeybind("kora_lib_zonecreator_cycle", "Zone Creator: Cycle Adjustable Parameter (Shift reverses)", "TAB", creatorCycleParam)

registerCreatorKeybind("kora_lib_zonecreator_confirm", "Zone Creator: Confirm / Open Summary", "RETURN", function(state)
    if creatorCanConfirm(state) then openConfirmDialog(state) end
end)

registerCreatorKeybind("kora_lib_zonecreator_cancel", "Zone Creator: Cancel", "X", function() resolveCreator(nil) end)

local function updateCreatorInstructions(state)
    if not state.instructions then return end
    local param = activeParamName(state)
    local paramLabel = ({ zOffset = "height offset", editPoint = "point editing" })[param] or param
    local movementLabel = state.movementMode == "camera" and "Camera" or "Grid"
    local placeLabel = "Place point"
    if param == "editPoint" then placeLabel = state.grabbing and "Drop point" or "Grab point" end
    local key = table.concat({ state.movementMode, param, placeLabel, tostring(creatorCanConfirm(state)) }, ":")
    if state.lastInstructionKey == key then return end
    state.lastInstructionKey = key
    state.instructions.setButtons({
        { control = 32, label = "Move forward", group = "Move" },
        { control = 33, label = "Move backward", group = "Move" },
        { control = 34, label = "Move left", group = "Move" },
        { control = 35, label = "Move right", group = "Move" },
        { keybind = creatorBindings.kora_lib_zonecreator_movement, label = "Movement: " .. movementLabel },
        { keybind = creatorBindings.kora_lib_zonecreator_place, label = placeLabel },
        { keybind = creatorBindings.kora_lib_zonecreator_place_click, label = placeLabel },
        { keybind = creatorBindings.kora_lib_zonecreator_undo, label = "Undo" },
        { keybind = creatorBindings.kora_lib_zonecreator_undo_click, label = "Undo" },
        { keybind = creatorBindings.kora_lib_zonecreator_cycle, label = "Adjust: " .. paramLabel },
        { keybind = creatorBindings.kora_lib_zonecreator_confirm, label = "Confirm" },
        { keybind = creatorBindings.kora_lib_zonecreator_cancel, label = "Cancel" },
    })
end

registerCreatorKeybind("kora_lib_zonecreator_movement", "Zone Creator: Toggle Camera / Grid Movement", "G", function(state)
    state.movementMode = state.movementMode == "camera" and "grid" or "camera"
    state.freecam.setMovementMode(state.movementMode)
    state.lastInstructionKey = nil
    updateCreatorInstructions(state)
end)

local function ensureCreatorThread(state)
    CreateThread(function()
        local ok, err = pcall(function()
        while creatorState == state do
            assert(state.freecam and state.freecam.isActive(), "The zone creator freecam stopped unexpectedly.")
            local hit, aimCoords = Kora.raycast.fromCam(state.cam, Config.zones.creator.raycastDistance)

            if IsControlJustPressed(0, 14) then adjustActiveParam(state, 1) end
            if IsControlJustPressed(0, 15) then adjustActiveParam(state, -1) end

            if hit and aimCoords then
                DrawMarker(28, aimCoords.x, aimCoords.y, aimCoords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    0.15, 0.15, 0.15, 255, 255, 0, 200, false, false, 2, false, nil, nil, false)
            end

            if state.dirty then
                state.cachedPreview = buildPreviewZone(state)
                state.dirty = false
            end

            if state.cachedPreview then drawDebugFn[state.cachedPreview.type](state.cachedPreview, zoneDebugColor()) end

            local editing = isEditingPoints(state)

            if not editing then
                state.grabbing = false
            elseif not state.grabbing then
                state.editIndex = (hit and aimCoords) and nearestPointIndex(state.points, aimCoords) or nil
            end

            if state.type == "poly" and (editing or #state.points < 3) then
                for i = 1, #state.points do
                    local point = state.points[i]
                    local grabbedHere = editing and state.grabbing and i == state.editIndex
                    local hoveredHere = editing and not state.grabbing and i == state.editIndex

                    local drawAt = (grabbedHere and hit and aimCoords) and aimCoords or point

                    local drawZ = drawAt.z + (drawAt == point and state.zOffset or 0.0)

                    local size = (grabbedHere or hoveredHere) and 0.45 or 0.25
                    local r, g, b = 255, 60, 60
                    if hoveredHere then r, g, b = 255, 255, 255 end
                    if grabbedHere then r, g, b = 60, 180, 255 end

                    DrawMarker(28, drawAt.x, drawAt.y, drawZ, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        size, size, size, r, g, b, 200, false, false, 2, false, nil, nil, false)
                end
            end

            local snapshot = creatorHudSnapshot(state, hit)
            if not hudSnapshotsEqual(snapshot, state.lastHud) then
                state.lastHud = snapshot
                Kora.nui.send("zoneCreator:hud", snapshot)
                updateCreatorInstructions(state)
            end

            if Config.zones.creator.hideRadar then
                state.radarManaged = true
                DisplayRadar(false)
            end

            Wait(0)
        end
        end)

        if not ok then
            creatorLog(("zone creator crashed and was cleaned up: %s"):format(tostring(err)))

            if creatorState == state then
                creatorState = nil
                state.promise:reject(("zone creator crashed: %s"):format(tostring(err)))
            end
        end

        releaseCreatorUi(state)
        releaseCreatorCamera(state)

        restoreCreatorRadar(state)

        Kora.nui.send("zoneCreator:hud", nil)

    end)
end

AddEventHandler('onClientResourceStop', function(resourceName)
    if not creatorState then return end

    if resourceName == creatorState.resource and resourceName ~= GetCurrentResourceName() then
        resolveCreator(nil)
        return
    end

    if resourceName ~= GetCurrentResourceName() then return end

    releaseCreatorUi(creatorState)
    restoreCreatorRadar(creatorState)
end)

local CREATOR_CLICK_CONTROLS = { 24, 25, 68, 69, 70, 91, 92, 140, 141, 142, 257, 263, 264 }

local function startCreatorCamera(resource)
    local freecam, err = Kora.freecam.start({
        moveSpeed = Config.zones.creator.cameraMoveSpeed,
        lookSensitivity = Config.zones.creator.cameraLookSensitivity,
        fastMultiplier = Config.zones.creator.shiftMultiplier,
        transitionMs = Config.zones.creator.cameraTransitionMs,
    })
    assert(freecam, err)

    local leased, lease = pcall(Kora.compat.acquireControls, CREATOR_CLICK_CONTROLS, { disablePlayerFiring = true }, resource)
    if not leased then
        freecam.stop()
        error(lease, 0)
    end
    return freecam, freecam.getCamera(), lease
end

local function beginCreator(zoneType, resource, existingOpts)
    local state = newCreatorState(zoneType, resource)
    if existingOpts then seedCreatorState(state, existingOpts) end
    creatorState = state

    local started, freecam, cam, lease = pcall(startCreatorCamera, resource)
    if not started then
        creatorState = nil
        error(freecam, 0)
    end
    state.freecam, state.cam, state.controlLease = freecam, cam, lease
    state.instructions = Kora.instructional.show({
        { control = 32, label = "Move forward" },
    })
    updateCreatorInstructions(state)

    if Config.zones.creator.hideHud and GetResourceState("kora_hud") == "started" then
        state.hudHidden = pcall(function() exports.kora_hud:hide() end) or nil
    end

    if Config.zones.creator.hideRadar then
        state.radarManaged = true
        DisplayRadar(false)
    end

    ensureCreatorThread(state)
    Kora.nui.send("zoneCreator:start", { type = zoneType })

    return state.promise
end

---Starts the in-world zone creator: aim and place points, adjust with the scroll wheel (the cycle key picks the
---parameter), then confirm for a dialog with the generated Kora.zones.<type>({...}) snippet and a copy button.
---@param zoneType "box" | "sphere" | "poly"
---@param existingOpts? table Seeds the creator from an existing zone's opts (same shape Kora.zones.<type>() takes) -- e.g. `Kora.zones.startCreator("box", myZoneOpts)` to reposition/resize `myZoneOpts` instead of starting empty. Validated like the real constructors; malformed values raise synchronously.
---@return promise|any result Resolves/returns { type, opts } once confirmed, or nil if cancelled, for a same-VM
---caller (unchanged, awaitable as before) or a genuine cross-resource caller respectively. Rejects/errors if a
---creator is already running or the creator is disabled (Config.zones.creator.enabled) -- see settleForExport
---above for the same-VM-vs-cross-resource distinction. An invalid zoneType or malformed existingOpts raises a
---synchronous error instead (like the zone constructors themselves), same for both kinds of caller.
function Kora.zones.startCreator(zoneType, existingOpts)
    assert(ZONE_TYPES[zoneType], "startCreator type must be 'box', 'sphere', or 'poly'.")

    if Config.zones.creator.enabled == false then
        local p = promise.new()
        p:reject("The zone creator is disabled on this server (Config.zones.creator.enabled).")
        return settleForExport(p)
    end

    local placement = rawget(Kora, "placement")
    if placement and type(placement.isActive) == "function" and placement.isActive() then
        local p = promise.new()
        p:reject("Entity placement is already active.")
        return settleForExport(p)
    end

    if creatorState then
        local p = promise.new()
        p:reject("A zone creator is already running.")
        return settleForExport(p)
    end

    return settleForExport(beginCreator(zoneType, GetInvokingResource() or GetCurrentResourceName(), existingOpts))
end

---Whether a zone creator session currently owns player input. Lets resources with a colliding default keybind (e.g.
---kora_inventory's TAB vs kora_lib_zonecreator_cycle) bail instead of firing alongside the creator.
---@return boolean
function Kora.zones.isCreatorActive()
    return creatorState ~= nil
end

RegisterCommand("kora_zonedebug", function(_, args)
    local arg = args[1] and tostring(args[1]):lower() or nil
    local enabled

    if arg == "on" then
        enabled = true
    elseif arg == "off" then
        enabled = false
    elseif arg == nil then
        enabled = next(debugZones) == nil
    else
        creatorLog(("kora_zonedebug: unrecognised argument '%s' -- use 'on', 'off', or no argument to toggle."):format(arg))
        return
    end

    Kora.zones.setDebug(nil, enabled)
    creatorLog(("zone debug drawing %s for every registered zone."):format(enabled and "enabled" or "disabled"))
end, false)

local function suggestZoneDebug()
    TriggerEvent("chat:addSuggestion", "/kora_zonedebug", "Toggle zone debug drawing", {
        { name = "on|off", help = "Optional; omit to toggle" },
    })
end
suggestZoneDebug()
AddEventHandler("chat:init", suggestZoneDebug)

---Edits an existing zone without replacing its handle. Only `coords`, `onEnter` and `onExit` can change; pass
---`false` for a callback to remove it.
---@param handle KoraZoneHandle
---@param opts KoraZoneEditOptions
---@return KoraZoneHandle? handle The same handle passed to the function, or nil for a foreign zone.
---@return string? error
function Kora.zones.edit(handle, opts)
    return editZone(handle, opts)
end

local function onStartZoneCreator(zoneType)
    if type(zoneType) ~= "string" then return end
    local ok, result = pcall(function() return Citizen.Await(Kora.zones.startCreator(zoneType)) end)

    if not ok then
        creatorLog(("zone creator failed: %s"):format(tostring(result)))
    elseif result then
        creatorLog(("captured a %s zone definition; no live zone was registered."):format(result.type))
    else
        creatorLog("zone creator cancelled.")
    end
end

RegisterNetEvent("kora_lib:editor:startZoneCreator", onStartZoneCreator)
