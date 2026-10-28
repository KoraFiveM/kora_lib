local nearProximitySq = Config.zones.nearProximity ^ 2

local zoneRegistry = {}
local grid = {}
local insideZones = {}

-- Forward-declared: destroyZone and zoneOwnership each need to reference the
-- other (destroyZone untracks on removal; zoneOwnership's onDispose destroys
-- a zone when its resource stops), so neither can be a plain `local function`.
local destroyZone
local zoneOwnership
local debugZones = {}

local function interactionsLocked()
    local state = LocalPlayer and LocalPlayer.state
    return state and state['qbmultichar:mode'] and state['qbmultichar:mode'] ~= false
end

-- setZoneDebug (below ensureDebugThread, since it needs to call it) is
-- likewise forward-declared: both the handle's setDebug method (buildHandle,
-- right below) and QB.zones.setDebug need to call it, and buildHandle runs
-- long before ensureDebugThread is defined.
local setZoneDebug

local nextZoneId = 0
local tickThreadStarted = false
local trackedZoneCount = 0
local debugThreadStarted = false

-- Plain { x, y, z } tables, not glm.vec3 -- the `glm` global isn't guaranteed
-- to exist on every FiveM client build. distSq/containsBox below do their own
-- component-wise subtraction instead of relying on glm's operator overloads.
local function toVec3(v)
    -- Coordinate coercion happens only at public API boundaries (creation,
    -- editing, and explicit handle.contains calls), never in the tick loop.
    -- Read through pcall so malformed non-table values produce the documented
    -- contract error instead of Lua's unhelpful "attempt to index" failure.
    local ok, x, y, z = pcall(function() return v.x, v.y, v.z end)
    assert(ok and QB.util.isFiniteNumber(x) and QB.util.isFiniteNumber(y) and QB.util.isFiniteNumber(z),
        "Coordinates must be a vector3, glm.vec3, or {x=,y=,z=} table.")
    return { x = x, y = y, z = z }
end

-- The private bootstrap helper normalizes native functions and every Cfx
-- cross-resource funcref proxy shape consistently across kora_lib modules.
local isCallable = QB.compat.isCallable

-- A promise object doesn't survive crossing a real cross-resource exports()
-- call back to the caller: only METHOD CALLS on it reach the real promise
-- inside kora_lib, while plain field reads (.state, .value -- what Citizen.Await
-- itself checks) on the crossed reference never reflect the real remote
-- promise's settlement, so the caller's own Citizen.Await silently resolves
-- nil regardless of the real outcome. GetInvokingResource() is nil for a
-- same-VM call (kora_lib's own qb_zonecreator command below, every dofile()'d
-- smoke test) and the real calling resource's name for a genuine
-- cross-resource exports() call (same signal this file already relies on for
-- ownership tracking -- see this module's own AGENTS.md "Resource ownership"
-- note) -- exactly the distinction that matters here. Same-VM callers get the
-- real promise back unchanged, so qb_zonecreator's own Citizen.Await keeps
-- working exactly as before. A genuine cross-resource caller gets the
-- already-awaited plain value (or a raised error on rejection, which -- like
-- every other kora_lib error -- surfaces to that caller as a printed
-- export-call error and a nil return, not a catchable Lua error) instead of
-- a promise it can't usefully await. Deliberately duplicated per-file -- see
-- local/callback/{client,server}.lua, local/events/{client,server}.lua, and
-- modules/{cache,nui}/client.lua for the other copies.
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

-- Squared distance from a point to the nearest point on an AABB, with the
-- clamp inlined rather than materialising that nearest point. This runs once
-- per candidate zone per tick -- and the tick runs per FRAME while anyone is
-- standing in a zone with an `inside` callback -- so the intermediate
-- {x,y,z} table it used to build was pure per-frame garbage, on a path whose
-- entire job is to be cheap enough to run every frame.
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

-- abs() makes the sign convention of cosR/sinR irrelevant here, so the same cached
-- values used by the inverse rotation in containsBox can be reused as-is.
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

-- A flat circle is deliberately a 2D radial test: its center Z is retained
-- for debugging/editing, but never participates in containment.
local function containsCircle(zone, p)
    local dx, dy = p.x - zone.coords.x, p.y - zone.coords.y
    local distanceSq = dx * dx + dy * dy
    return zone.includeBoundary and distanceSq <= zone.radiusSq or distanceSq < zone.radiusSq
end

-- Even-odd ray-casting test (PNPOLY) over the XY footprint, normally gated by
-- a height band. ignoreZ is for legacy 2D areas that intentionally have none.
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

-- Bumped by every grid mutation (create, destroy, and the re-insert behind
-- QB.zones.edit). The tick's candidate cache below keys off it, so a stale
-- candidate list can never outlive the grid it was built from.
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

-- Ownership tracking (which resource created a given zone, and bulk cleanup
-- when that resource stops) is delegated to the shared registry -- see
-- local/resources/AGENTS.md. destroyZone above already handles the full
-- teardown a manual QB.zones.remove()/handle.remove() needs, so onDispose
-- just routes a still-owned zone id back through it.
zoneOwnership = QB.resources.registry(function(zoneId)
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

    -- Only these fields are allowed to be edited.
    for key in pairs(opts) do
        assert(
            key == "coords" or key == "onEnter" or key == "onExit",
            ("Zone edit does not allow changing '%s'. Only coords, onEnter, and onExit can be edited."):format(key)
        )
    end

    -- Validate every field before mutating anything, so a rejected edit (e.g.
    -- a bad onEnter alongside a valid coords) never leaves the zone
    -- half-changed -- either every requested field applies, or none do.
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

    -- Every validation above passed: apply. Skip the grid churn (and the aabb
    -- recompute, which would come out identical) when the new coords equal
    -- the zone's current ones -- e.g. a caller re-editing onEnter/onExit
    -- while re-passing the coords it already has.
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
        print(("[qblib:zones] %s callback for zone %d (%s, owned by %s) errored: %s")
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
    assert(opts.rotation == nil or QB.util.isFiniteNumber(opts.rotation), "rotation must be a finite number.")
    assert(opts.ignoreZ == nil or type(opts.ignoreZ) == "boolean", "ignoreZ must be a boolean.")

    local coords = toVec3(opts.coords)
    local size = toVec3(opts.size)

    assert(size.x > 0 and size.y > 0 and size.z > 0, "Box zone size must be positive on every axis.")

    -- cosR/sinR are cached from -rotation so containsBox's inverse-transform reads as a
    -- plain rotation-by-rotation lookup; rotatedHalfExtents only cares about the magnitudes.
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
    assert(QB.util.isFiniteNumber(opts.radius) and opts.radius > 0, "Sphere zone requires a positive finite radius.")
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
    assert(QB.util.isFiniteNumber(opts.radius) and opts.radius > 0, "Circle zone requires a positive finite radius.")
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
        assert(QB.util.isInteger(index) and index >= 1, "Poly zone points must be a dense array.")
        pointCount = pointCount + 1
    end
    assert(pointCount >= 3 and pointCount == #opts.points, "Poly zone requires at least 3 dense points.")
    assert(opts.thickness == nil or QB.util.isFiniteNumber(opts.thickness), "thickness must be a finite number.")
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

    assert(minZ == nil or QB.util.isFiniteNumber(minZ), "minZ must be a finite number.")
    assert(maxZ == nil or QB.util.isFiniteNumber(maxZ), "maxZ must be a finite number.")

    if minZ == nil then
        -- `thickness` is measured UPWARD FROM THE LOWEST POINT, not centred on
        -- the points' average height. Poly points are almost always placed by
        -- aiming at the ground (that's what the in-world creator does), so a
        -- centred band buried half the zone underground and left only
        -- thickness/2 of usable headroom -- and on sloping ground an average
        -- could sit above the lowest point's own floor, leaving a gap there.
        -- Anchoring at the lowest point means the zone always sits ON the
        -- surface it was drawn on and `thickness` reads as "how tall is it".
        -- Pass explicit minZ/maxZ when you need a band that floats instead.
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

-- Each face as 4 corner indices (into BOX_SIGNS/corners), wound around the
-- face's perimeter so the two triangles drawFace splits it into aren't
-- crossed/degenerate.
local BOX_FACES = {
    { 1, 2, 4, 3 }, -- -X
    { 5, 6, 8, 7 }, -- +X
    { 1, 2, 6, 5 }, -- -Y
    { 3, 4, 8, 7 }, -- +Y
    { 1, 3, 7, 5 }, -- -Z (bottom)
    { 2, 4, 8, 6 }, -- +Z (top)
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

-- DrawPoly draws one filled, single-sided (backface-culled) triangle in
-- world space. Drawn twice per triangle, winding order reversed the second
-- time, so a wall reads as solid whether the camera is outside the zone or
-- (common for a box you're actively standing in) inside it.
local function drawWallTriangle(x1, y1, z1, x2, y2, z2, x3, y3, z3, color)
    DrawPoly(x1, y1, z1, x2, y2, z2, x3, y3, z3, color.r, color.g, color.b, color.a)
    DrawPoly(x1, y1, z1, x3, y3, z3, x2, y2, z2, color.r, color.g, color.b, color.a)
end

-- Splits a quad (4 corners, wound around its perimeter) into 2 triangles.
local function drawWallQuad(x1, y1, z1, x2, y2, z2, x3, y3, z3, x4, y4, z4, color)
    drawWallTriangle(x1, y1, z1, x2, y2, z2, x3, y3, z3, color)
    drawWallTriangle(x1, y1, z1, x3, y3, z3, x4, y4, z4, color)
end

-- Walls render at a lower alpha than edges/corners (Config.zones.debugWallAlpha,
-- not color.a) -- a fully-opaque fill at the same alpha as the wireframe
-- would bury the edges/corners it's meant to complement, not just add to them.
local function wallColor(color)
    return { r = color.r, g = color.g, b = color.b, a = Config.zones.debugWallAlpha }
end

local function hexToRgb(hex)
    return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
end

-- Debug zones and the creator's live preview should look like the rest of
-- kora_lib's UI, not carry their own hardcoded colour -- so the colour tracks
-- QB.theme.accentColor() live (a config change takes effect on the very next
-- draw) instead of being baked into Config.zones at load time.
local function zoneDebugColor()
    local r, g, b = hexToRgb(QB.theme.accentColor())
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

        -- The vertical side wall between this edge and the next -- no top/
        -- bottom cap faces, since the footprint isn't guaranteed convex and
        -- properly triangulating an arbitrary polygon is a lot of added
        -- complexity for a debug-only visual; the wireframe alone already
        -- shows the footprint shape clearly enough on its own.
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

-- Shared by the handle's own setDebug method and QB.zones.setDebug (both a
-- single-id call and the nil-id "every zone" fan-out) -- one place that keeps
-- zone.debug, debugZones, and the debug thread's running-or-not state
-- consistent, rather than three copies of the same add/remove-from-set logic.
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

    -- The tracker can run its first tick as soon as it is started below. Build
    -- the public handle before then, so an onEnter callback can safely call
    -- QB.zones.getInside() during that first tick.
    zone.handle = buildHandle(zone)

    zoneRegistry[zone.id] = zone
    if zone.trackPlayer then
        insertIntoGrid(zone)
        trackedZoneCount = trackedZoneCount + 1
    end

    zoneOwnership.track(zone.resource, zone.id)

    -- Config.zones.debug is a server-wide default OR'd in here, same pattern
    -- kora_target's own Config.target.debug already uses on top of this --
    -- opts.debug still wins on its own (a zone can opt in even with the
    -- global default off), it just isn't the only way in anymore.
    if Config.zones.debug == true or opts.debug == true then
        setZoneDebug(zone, true)
    end

    if zone.trackPlayer then ensureTickThread() end

    return zone.handle
end

---@class QBZoneHandle
---@field id integer
---@field type "box" | "sphere" | "circle" | "poly"
---@field resource string The resource that created this zone.
---@field data any Whatever was passed as opts.data at creation, unchanged.
---@field remove fun(): boolean Tears the zone down. Returns false for a foreign or removed zone.
---@field contains fun(coords: any): boolean Exact containment test against an arbitrary point.
---@field isInside fun(): boolean Whether the local player is currently inside, read live.
---@field setDebug fun(enabled: boolean): boolean Toggles this zone's debug wireframe at runtime. Returns false for a foreign zone.

---@class QBZoneCommonOptions
---@field onEnter? fun(zone: table)
---@field onExit? fun(zone: table)
---@field inside? fun(zone: table, coords: any) Runs every frame while inside; keep it cheap.
---@field trackPlayer? boolean Set false for a predicate-only zone; it remains available through `contains()` but is not polled.
---@field debug? boolean Draw the zone's bounds while it exists.
---@field data? any Arbitrary passthrough, readable back via the handle's `data` field.

---@class QBZoneBoxOptions : QBZoneCommonOptions
---@field coords any Box center (vector3/glm.vec3/{x=,y=,z=}).
---@field size any Full extents (x, y, z), all greater than 0.
---@field rotation? number Degrees around the Z axis. Defaults to 0.
---@field ignoreZ? boolean Ignore the Z extent during containment. Defaults to false.

---@class QBZoneSphereOptions : QBZoneCommonOptions
---@field coords any Sphere center.
---@field radius number Must be greater than 0.
---@field includeBoundary? boolean Whether a point exactly on radius is inside. Defaults to true.

---@class QBZoneCircleOptions : QBZoneCommonOptions
---@field coords any Circle center; its Z is retained for debug rendering but ignored by containment.
---@field radius number Must be greater than 0.
---@field includeBoundary? boolean Whether a point exactly on radius is inside. Defaults to true.

---@class QBZonePolyOptions : QBZoneCommonOptions
---@field points any[] At least 3 points; only their XY defines the footprint.
---@field thickness? number Height band measured upward from the lowest point's Z.
---@field minZ? number Explicit height band floor. Must be given with maxZ, or neither.
---@field maxZ? number Explicit height band ceiling.
---@field ignoreZ? boolean Ignore the height band during containment. Defaults to false.

---Creates a rotatable box zone.
---@param opts QBZoneBoxOptions
---@return QBZoneHandle zone
function QB.zones.box(opts)
    return createZone("box", opts, initBox)
end

---Creates a sphere zone.
---@param opts QBZoneSphereOptions
---@return QBZoneHandle zone
function QB.zones.sphere(opts)
    return createZone("sphere", opts, initSphere)
end

---Creates a flat 2D circle zone. Its containment test ignores the point's Z coordinate.
---@param opts QBZoneCircleOptions
---@return QBZoneHandle zone
function QB.zones.circle(opts)
    return createZone("circle", opts, initCircle)
end

---Creates a polygon zone: a 2D footprint (opts.points) extruded across a vertical height
---band (opts.minZ/opts.maxZ, or opts.thickness upward from the lowest point's Z).
---@param opts QBZonePolyOptions
---@return QBZoneHandle zone
function QB.zones.poly(opts)
    return createZone("poly", opts, initPoly)
end

---Creates a point zone. Not a separate shape: this is a sphere zone with a small default
---radius, and returns the exact same zone handle QB.zones.sphere does.
---@param opts QBZoneSphereOptions `radius` defaults to Config.zones.defaultPointRadius.
---@return QBZoneHandle zone
function QB.zones.point(opts)
    assert(type(opts) == "table", "Point zone options must be a table.")
    if opts.radius == nil then
        local pointOpts = {}
        for key, value in pairs(opts) do pointOpts[key] = value end
        pointOpts.radius = Config.zones.defaultPointRadius
        opts = pointOpts
    end

    return createZone("sphere", opts, initSphere)
end

---Every zone the local player is currently inside, across every resource --
---read straight off the enter/exit state the tick loop already maintains, so
---this costs a registry walk and nothing more (no containment maths).
---
---Useful when you care about "what am I standing in right now" without having
---retained a handle from every constructor call yourself, and it's the only
---way to see zones another resource created.
---@param resource? string Only return zones owned by this resource. Omit for all of them.
---@return QBZoneHandle[] zones Unordered -- the registry is a hash, not a list.
function QB.zones.getInside(resource)
    assert(resource == nil or type(resource) == "string", "resource filter must be a string.")

    local inside = {}

    for _, zone in pairs(zoneRegistry) do
        if zone.isInside and (resource == nil or zone.resource == resource) then
            inside[#inside + 1] = zone.handle
        end
    end

    return inside
end

---Toggles debug wireframe drawing on an already-created zone (or every
---currently-registered zone at once) at runtime -- unlike `opts.debug`,
---which only ever gets read once, at creation. Also reachable per-zone as
---`zone.setDebug(enabled)` on the handle itself, and globally via the
---`qb_zonedebug` command below.
---@param id? integer A zone id (`zone.id`). Omit (nil) to affect every registered zone.
---@param enabled boolean
---@return boolean changed
function QB.zones.setDebug(id, enabled)
    assert(id == nil or QB.util.isInteger(id), "id must be a zone id or nil.")
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

-- The 3x3 cell scan is memoised: its result only changes when the player
-- crosses a 50m cell boundary or the grid itself changes. On foot that is
-- roughly once every ten seconds, so rebuilding the candidate set on every
-- tick meant nine hash lookups, a set union and a fresh table to throw away,
-- per frame, to arrive at the same answer as last frame.
--
-- Cached as a dense ARRAY of zone references rather than a set of ids, so the
-- tick walks it by index and reads each zone directly instead of paying a
-- second registry lookup per candidate.
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
        -- The vector3 from the native is used directly. Copying it into a
        -- {x,y,z} table allocated one more object per tick and bought nothing:
        -- every reader here (the AABB clamp, all three containment tests) only
        -- ever reads .x/.y/.z, which a vector3 already answers.
        local p = GetEntityCoords(ped)

        local list = candidatesFor(worldToCell(p.x, p.y))
        local locked = interactionsLocked()

        -- The spatial grid deliberately only examines nearby zones. Zones that
        -- were inside on the prior tick need one cheap independent check so a
        -- teleport or fast vehicle move cannot strand their isInside/onExit
        -- state after they fall outside that neighbourhood.
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

            -- A cached list is a snapshot, and an onEnter/onExit handler is
            -- free to destroy a zone while this loop is still walking it --
            -- so liveness is re-checked per zone, off the flag destroyZone
            -- already sets, rather than by looking the id up again.
            if not zone.removed then
                -- Scene/character selection moves a hidden ped through the
                -- real world. Treat all gameplay zones as exited until that
                -- mode ends so beds, banks, doors, and similar callbacks
                -- cannot open over the selection UI.
                if locked then
                    if zone.isInside then
                        zone.isInside = false
                        if zone.onExit then safeCall(zone, "onExit", zone.onExit, zone) end
                    end
                    goto continue
                end
                local dSq = aabbDistSq(p, zone.aabb, zone.ignoreZ)
                if dSq < minDistSq then minDistSq = dSq end

                -- Exact containment only runs once the player is inside the zone's cheap
                -- AABB reject test; everything outside every candidate's AABB skips it.
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
            -- No candidate in any neighbouring cell, so there is nothing to be
            -- near and no reason to pay for a speed native to prove it.
            interval = Config.zones.tickFar
        else
            -- Widen the "near" threshold for fast-moving entities so a small zone can't be
            -- skipped entirely between two far-tier ticks.
            local farTravel = GetEntitySpeed(ped) * (Config.zones.tickFar / 1000) * Config.zones.speedSafetyFactor
            local effectiveNearSq = math.max(nearProximitySq, farTravel * farTravel)
            interval = minDistSq <= effectiveNearSq and Config.zones.tickNear or Config.zones.tickFar
        end

        Wait(interval)
    end

    tickThreadStarted = false
end

------------------------------------------------------------------------------
-- Zone creator: aim, place points, and copy the finished QB.zones.* call.
-- See modules/zones/AGENTS.md for the design notes behind this section.
------------------------------------------------------------------------------

local initFnByType = { box = initBox, sphere = initSphere, poly = initPoly }

-- Every place that validates a zone-creator type string shares this set,
-- rather than each repeating its own "box or sphere or poly" chain.
local ZONE_TYPES = { box = true, sphere = true, poly = true }

-- Which of a shape's numeric parameters the scroll wheel currently adjusts;
-- TAB cycles through this list. Single-entry lists still work (cycling is a no-op).
-- zOffset is on every shape's cycle: the placement raycast can only ever land
-- on solid geometry, so without it a zone is permanently stuck at ground level
-- and there'd be no way to build one over a floor, a rooftop, or water.
-- "editPoint" is a mode rather than a number: while it's the active entry the
-- placement key picks up the point nearest your aim and, on a second press,
-- drops it at the new aim -- instead of appending a new point. It lives on
-- this cycle (rather than being its own keybind) so the one thing Tab already
-- means -- "what does the next keypress/scroll act on" -- keeps covering
-- everything, and the HUD keeps being the single place that says what mode
-- you're in.
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

-- Compared against the RAW stored points (not the zOffset-raised ones drawn
-- on screen): both the stored point and the placement raycast sit on the
-- ground, so this stays accurate no matter how far the zone has been lifted.
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
    print(("[qblib:zones] %s"):format(msg))
end

local function formatNumber(n)
    assert(QB.util.isFiniteNumber(n), "Zone snippets require finite numeric values.")
    return ("%.2f"):format(n)
end

local function formatCoords(v)
    return ("vector3(%s, %s, %s)"):format(formatNumber(v.x), formatNumber(v.y), formatNumber(v.z))
end

---Formats `opts` (as returned by QB.zones.startCreator's promise, or hand-built
---in the same shape) into the QB.zones.<type>({...}) Lua snippet the creator's
---confirm dialog shows and copies to the clipboard. Pure and deterministic --
---no side effects, so it doesn't need the creator running to be useful/testable.
---@param zoneType "box" | "sphere" | "poly"
---@param opts table
---@return string
function QB.zones.generateSnippet(zoneType, opts)
    assert(ZONE_TYPES[zoneType], "generateSnippet type must be 'box', 'sphere', or 'poly'.")
    assert(type(opts) == "table", "generateSnippet options must be a table.")

    if zoneType == "box" then
        return ("QB.zones.box({\n    coords = %s,\n    size = %s,\n    rotation = %s,\n})")
            :format(formatCoords(opts.coords), formatCoords(opts.size), formatNumber(opts.rotation or 0))
    end

    if zoneType == "sphere" then
        return ("QB.zones.sphere({\n    coords = %s,\n    radius = %s,\n})")
            :format(formatCoords(opts.coords), formatNumber(opts.radius))
    end

    local pointLines = {}
    for i = 1, #opts.points do
        local point = opts.points[i]
        pointLines[i] = "        " .. formatCoords(point) .. ","
    end

    if opts.minZ ~= nil or opts.maxZ ~= nil then
        assert(opts.minZ ~= nil and opts.maxZ ~= nil, "Poly snippets require both minZ and maxZ.")
        return ("QB.zones.poly({\n    points = {\n%s\n    },\n    minZ = %s,\n    maxZ = %s,\n})")
            :format(table.concat(pointLines, "\n"), formatNumber(opts.minZ), formatNumber(opts.maxZ))
    end

    return ("QB.zones.poly({\n    points = {\n%s\n    },\n    thickness = %s,\n})")
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
        -- Signed, and NOT clamped like the size params below -- lowering a zone
        -- below the surface it was placed on is as valid as raising it.
        zOffset = 0.0,
        activeParam = 1,
        -- Which point "editPoint" mode currently has under its crosshair (while
        -- hovering) or has picked up (while grabbing) -- see `grabbing` below.
        -- Recomputed from the aim every frame while hovering, so it never goes
        -- stale against a points list that undo/place just changed.
        editIndex = nil,
        -- false: editIndex just tracks whatever point is nearest the aim (a
        -- hover highlight). true: the place key has picked that point up --
        -- editIndex is now frozen on it regardless of where the camera flies
        -- until place (drop it at the new aim) or undo (cancel the grab)
        -- releases it. Without this, flying away to look at a placement spot
        -- immediately re-targets editIndex at whatever's nearest THAT spot
        -- instead, so there was never a way to actually move a distant point.
        grabbing = false,
        promise = promise.new(),
        -- dirty starts true so the first frame builds an (empty, since nothing's
        -- placed yet) preview; cachedPreview/lastHud let the per-frame thread
        -- below skip rebuilding either when nothing shape-relevant has changed.
        dirty = true,
        cachedPreview = nil,
        lastHud = nil,
    }
end

---Pre-populates a freshly created creator state from an existing zone's opts
---(the same shape QB.zones.<type>() takes, and QB.zones.startCreator's own
---resolved promise returns) -- lets QB.zones.startCreator(type, existingOpts)
---reposition/resize an already-built zone instead of only ever starting fresh.
---Any field `opts` doesn't provide is left at newCreatorState's default.
---@param state table
---@param opts table
local function seedCreatorState(state, opts)
    assert(type(opts) == "table", "startCreator existingOpts must be a table.")

    -- Validated with the same rules the real constructors enforce
    -- (positive sizes/radius, capped point count) -- and validated HERE,
    -- synchronously, so hostile/malformed seed values raise back into the
    -- caller instead of surfacing later as an uncaught assert inside the
    -- per-frame preview thread when buildPreviewZone re-runs initBox/etc.
    if state.type == "box" then
        if opts.coords then state.center = toVec3(opts.coords) end
        if opts.size then
            local size = toVec3(opts.size)
            assert(size.x > 0 and size.z > 0, "Seeded box size must be positive on every axis.")
            -- The creator only tracks one uniform X/Y "size" scalar (see
            -- creatorParamCycles); a non-square seed box's Y size is dropped,
            -- which only matters as a starting point the player can re-adjust.
            state.size = size.x
            state.height = size.z
        end
        if opts.rotation ~= nil then
            assert(QB.util.isFiniteNumber(opts.rotation), "Seeded rotation must be a finite number.")
            state.rotation = opts.rotation % 360
        end
    elseif state.type == "sphere" then
        if opts.coords then state.center = toVec3(opts.coords) end
        if opts.radius ~= nil then
            assert(QB.util.isFiniteNumber(opts.radius) and opts.radius > 0, "Seeded radius must be a positive finite number.")
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
            assert(QB.util.isFiniteNumber(opts.minZ) and QB.util.isFiniteNumber(opts.maxZ),
                "Seeded minZ and maxZ must be finite numbers.")
            assert(opts.maxZ > opts.minZ, "Seeded maxZ must be greater than minZ.")
            state.thickness = opts.maxZ - opts.minZ
        elseif opts.thickness ~= nil then
            assert(QB.util.isFiniteNumber(opts.thickness) and opts.thickness > 0,
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

-- state.zOffset is applied HERE rather than being folded into state.center at
-- placement time, so it stays independently adjustable: re-placing the zone
-- (aim + E) keeps whatever elevation was dialled in, and scrolling zOffset
-- doesn't have to un-apply a previous value.
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

    -- Poly has no single centre to shift, so every point moves together --
    -- which keeps the footprint identical and just slides the height band.
    local points = {}
    for i = 1, #state.points do
        local point = state.points[i]
        points[i] = raise(point, state.zOffset)
    end

    return { points = points, thickness = state.thickness }
end

-- Builds a scratch zone-shaped table (reusing initBox/initSphere/initPoly, the
-- same functions real zones are built with) purely so drawDebugFn can render
-- the in-progress shape exactly like a normal `debug = true` zone. Delegates
-- "is there enough placed yet to preview" to creatorCanConfirm rather than
-- re-deriving the same rule with separate logic that could drift out of sync.
local function buildPreviewZone(state)
    if not creatorCanConfirm(state) then return nil end

    local scratch = { type = state.type }
    initFnByType[state.type](scratch, creatorOpts(state))
    return scratch
end

---Tears the creator down and settles its promise with `value` -- shared by
---both a successful confirm (`{ type, opts }`) and a cancel (`nil`), which
---otherwise differed only in which value they resolved with.
---@param value any
local function releaseCreatorUi(state)
    if state and state.instructions then
        state.instructions.hide()
        state.instructions = nil
    end
end

local function releaseCreatorCamera(state)
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

-- Shift reverses the cycle direction (Shift+Tab steps backwards) and speeds up
-- scroll-adjustment (Shift+scroll moves shiftMultiplier times faster) -- rotate
-- in particular is painfully slow to dial in a full turn one rotationStep at a
-- time, and the same goes for nudging size/zOffset/etc. in bigger increments.
-- Checked at keypress/scroll time rather than being its own keybind because
-- RegisterKeyMapping has no modifier syntax to bind "Shift+Tab"/"Shift+Scroll"
-- with in the first place.
--
-- IsRawKeyDown reads the physical Shift key (VK_SHIFT = 0x10) and so can't be
-- thrown off by a rebound sprint control, but it isn't present on every
-- client build -- hence the guarded call and the INPUT_SPRINT (21) fallback.
--
-- IMPORTANT: this must be IsRawKeyDown, not IsRawKeyPressed. Despite the
-- name, IS_RAW_KEY_PRESSED is edge-triggered -- true only on the single frame
-- the key transitions from up to down, mirroring IS_RAW_KEY_RELEASED's "was
-- just released" -- while IS_RAW_KEY_DOWN is the level/held check ("is
-- currently down"). Using PRESSED here meant shiftHeld() was true for at
-- most one frame per keypress, so it essentially never lined up with a
-- scroll tick and the multiplier was never perceptible.
-- Both signals are checked and OR'd together, not "raw first, control as
-- fallback-on-error": IsRawKeyDown(16) can exist and execute without erroring
-- yet still never report true for a real Shift press (its raw key codes don't
-- reliably line up with the generic VK_SHIFT constant on every client build),
-- and a pcall can't tell "the native is missing" apart from "the native ran
-- and says false". Trusting a clean `false` from it unconditionally silently
-- disabled Shift detection entirely on those builds. IsControlPressed(0, 21)
-- (Sprint, bound to Shift by default) is checked unconditionally instead, so
-- a working raw-key build gains nothing and a broken one still gets Shift.
local function shiftHeld()
    local ok, pressed = pcall(function() return IsRawKeyDown(16) end)
    if ok and pressed == true then return true end

    return IsControlPressed(0, 21)
end

-- Unmultiplied per-tick step for whichever param is currently active -- 0 for
-- "editPoint" since it's a mode, not a value. Shared by adjustActiveParam
-- (which still applies its own direction/shiftMultiplier/clamping) and
-- creatorHudSnapshot, so the HUD's displayed step can never drift out of
-- sync with what a scroll tick actually does.
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
        -- A mode, not a value: point selection is driven by the place/undo
        -- keys (pick up/drop/cancel), so there's nothing for the scroll wheel
        -- to nudge here.
        return
    elseif param == "rotation" then
        state.rotation = (state.rotation + direction * step.rotationStep * multiplier) % 360
    elseif param == "zOffset" then
        -- Signed on purpose -- unlike the size params below, negative is
        -- meaningful (sinking a zone beneath the surface it was placed on).
        state.zOffset = state.zOffset + direction * step.sizeStep * multiplier
    else
        -- size/height/radius/thickness all move the same way: nudge by
        -- sizeStep, clamped so it can never reach zero/negative.
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
        -- 0 rather than nil: a nil-valued key is simply absent once serialized,
        -- so the HUD could never tell "no point grabbed" from "field missing".
        editIndex = state.editIndex or 0,
        grabbing = state.grabbing,
        canConfirm = creatorCanConfirm(state),
        aiming = aiming,
        -- Surfaced so the HUD can actually show shift doing something instead
        -- of it being an invisible, easy-to-doubt modifier: isShiftHeld drives
        -- a visible indicator, stepSize is what one scroll tick currently
        -- moves the active param by (already shiftMultiplier-scaled).
        isShiftHeld = shift,
        stepSize = activeParamBaseStep(state) * (shift and Config.zones.creator.shiftMultiplier or 1),
    }
end

-- Manual field comparison instead of json.encode-ing both sides -- this runs
-- every frame purely to answer "did anything change", so it should be cheaper
-- than a full serialize-and-compare of a table this small and flat-shaped.
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

-- Runs inside a RegisterCommand handler's own coroutine, so Citizen.Await
-- inside QB.nui.withFocus's fn suspends this call until the dialog responds
-- without blocking the creator's separate per-frame preview thread.
local function openConfirmDialog(state)
    local opts = creatorOpts(state)
    local snippet = QB.zones.generateSnippet(state.type, opts)

    local ok, response = pcall(function()
        return QB.nui.withFocus(true, true, function()
            return Citizen.Await(QB.nui.request("zoneCreator:confirm",
                { type = state.type, snippet = snippet }, Config.zones.creator.confirmTimeout, state.resource))
        end, state.resource)
    end)

    if creatorState ~= state then return end -- cancelled/finished elsewhere while the dialog was open

    if not ok then
        creatorLog(("confirm dialog failed: %s"):format(tostring(response)))
        resolveCreator(nil)
        return
    end

    if response and response.confirmed then
        resolveCreator({ type = state.type, opts = opts })
    end
    -- otherwise ("keep editing"): creatorState is untouched, the preview thread carries on
end

-- In editPoint mode the place key is a two-step pick-up/drop instead of a
-- single click: the first press grabs whichever point is currently hovered
-- (freezing it in `grabbing`, below, so flying elsewhere doesn't re-target
-- it), the second press drops it at the NEW aim and releases the grab. A
-- single-press "move nearest point to wherever you're aiming right now"
-- can't express "carry this one specific point over there" at all, since
-- the moment the camera turns away from the point, it's no longer nearest
-- its own aim.
local function creatorPlaceEditPoint(state)
    if state.grabbing then
        local hit, coords = QB.raycast.fromCam(state.cam, Config.zones.creator.raycastDistance)
        if not hit then
            creatorLog("nothing to drop the point on -- aim at solid ground/geometry.")
            return
        end

        local index = state.editIndex
        if index == nil or state.points[index] == nil then
            -- The points list changed out from under a grab (e.g. undo while
            -- grabbing already released it) -- nothing left to drop.
            state.grabbing = false
            return
        end

        -- Stored raw, exactly like a freshly placed point: zOffset is
        -- re-applied on top in creatorOpts, so moving a point on a lifted
        -- zone doesn't bake the lift in twice.
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

    local hit, coords = QB.raycast.fromCam(state.cam, Config.zones.creator.raycastDistance)
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
        -- While a point is grabbed, undo cancels the grab (drop it back where
        -- it started) rather than deleting the last point in the list -- that
        -- last point is very likely a completely different one from whatever
        -- is currently being carried around.
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

-- Shift also reverses the cycle direction (Shift+Tab steps backwards), which
-- matters once a shape has 4 parameters -- tabbing forward three times to get
-- back one is miserable. shiftHeld() itself is defined above, next to
-- adjustActiveParam, which is its other caller.
local function creatorCycleParam(state)
    local cycle = creatorParamCycles[state.type]
    local step = shiftHeld() and -1 or 1

    -- +#cycle before the modulo keeps the -1 case positive: Lua's % is already
    -- floor-based (so -1 % 3 == 2), but writing it out means the intent
    -- survives someone porting this to a language where % follows the sign of
    -- the dividend instead.
    state.activeParam = ((state.activeParam - 1 + step + #cycle) % #cycle) + 1
    -- No state.dirty here: the active parameter doesn't change the shape
    -- itself, only which one scroll adjusts -- the HUD field comparison below
    -- already catches an activeParam change without needing a preview rebuild.
end

---Registers an owner-tracked zone-creator keybind that only calls
---`handler(creatorState)` while a creator session is active.
---Every qblib_zonecreator_* command follows this exact shape, so it's defined
---once instead of five times.
---@param command string
---@param label string
---@param key string
---@param handler fun(state: table)
local creatorBindings = {}

local function registerCreatorKeybind(command, label, key, handler)
    local handle = QB.keybind.add({
        name = command,
        description = label,
        defaultMapper = 'keyboard',
        defaultKey = key,
        onPressed = function()
            if creatorState then handler(creatorState) end
        end,
    })
    creatorBindings[command] = handle
    return handle
end

registerCreatorKeybind("qblib_zonecreator_place", "Zone Creator: Place Point", "E", creatorPlace)
registerCreatorKeybind("qblib_zonecreator_undo", "Zone Creator: Undo Last Point", "BACK", creatorUndo)
registerCreatorKeybind("qblib_zonecreator_cycle", "Zone Creator: Cycle Adjustable Parameter (Shift reverses)", "TAB", creatorCycleParam)

registerCreatorKeybind("qblib_zonecreator_confirm", "Zone Creator: Confirm / Open Summary", "RETURN", function(state)
    if creatorCanConfirm(state) then openConfirmDialog(state) end
end)

registerCreatorKeybind("qblib_zonecreator_cancel", "Zone Creator: Cancel", "X", function() resolveCreator(nil) end)

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
        { control = 32, label = "Move forward" },
        { control = 33, label = "Move backward" },
        { control = 34, label = "Move left" },
        { control = 35, label = "Move right" },
        { keybind = creatorBindings.qblib_zonecreator_movement, label = "Movement: " .. movementLabel },
        { keybind = creatorBindings.qblib_zonecreator_place, label = placeLabel },
        { keybind = creatorBindings.qblib_zonecreator_undo, label = "Undo" },
        { keybind = creatorBindings.qblib_zonecreator_cycle, label = "Adjust: " .. paramLabel },
        { keybind = creatorBindings.qblib_zonecreator_confirm, label = "Confirm" },
        { keybind = creatorBindings.qblib_zonecreator_cancel, label = "Cancel" },
    })
end

registerCreatorKeybind("qblib_zonecreator_movement", "Zone Creator: Toggle Camera / Grid Movement", "G", function(state)
    state.movementMode = state.movementMode == "camera" and "grid" or "camera"
    state.freecam.setMovementMode(state.movementMode)
    state.lastInstructionKey = nil
    updateCreatorInstructions(state)
end)

-- Lazily started per creator session (mirrors ensureTickThread/ensureDebugThread
-- above) and self-stops the moment creatorState no longer points at it, whether
-- that's a confirm, a cancel, or the resource stopping entirely.
local function ensureCreatorThread(state)
    CreateThread(function()
        -- pcall-wrapped: this loop calls a lot of natives every frame, and
        -- any one of them erroring would otherwise silently kill this
        -- coroutine right there, skipping the shared-camera cleanup and radar
        -- restoration below.
        local ok, err = pcall(function()
        while creatorState == state do
            assert(state.freecam and state.freecam.isActive(), "The zone creator freecam stopped unexpectedly.")
            local hit, aimCoords = QB.raycast.fromCam(state.cam, Config.zones.creator.raycastDistance)

            if IsControlJustPressed(0, 14) then adjustActiveParam(state, 1) end
            if IsControlJustPressed(0, 15) then adjustActiveParam(state, -1) end

            if hit and aimCoords then
                DrawMarker(28, aimCoords.x, aimCoords.y, aimCoords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    0.15, 0.15, 0.15, 255, 255, 0, 200, false, false, 2, false, nil, nil, false)
            end

            -- The preview shape only depends on placement/size/rotation state
            -- (never on the live raycast), so it's only rebuilt when a place/
            -- undo/adjust actually changed something, not every single frame.
            if state.dirty then
                state.cachedPreview = buildPreviewZone(state)
                state.dirty = false
            end

            if state.cachedPreview then drawDebugFn[state.cachedPreview.type](state.cachedPreview, zoneDebugColor()) end

            local editing = isEditingPoints(state)

            if not editing then
                -- Leaving edit-point mode always drops any in-progress grab --
                -- there's nowhere left to see/confirm it once the HUD/markers
                -- for it stop being drawn below.
                state.grabbing = false
            elseif not state.grabbing then
                -- Only re-tracked while hovering, not while grabbing: a
                -- grabbed point stays exactly the one that was picked no
                -- matter where the camera flies afterward -- only place
                -- (drop it) or undo (cancel the grab) changes it again.
                state.editIndex = (hit and aimCoords) and nearestPointIndex(state.points, aimCoords) or nil
            end

            -- Points are drawn individually in two cases: below 3, because
            -- there's no polygon to preview yet and the first two placements
            -- would otherwise leave the screen unchanged; and while editing,
            -- because you need to see which vertex is hovered/grabbed. In
            -- between, the real preview's own debug draw already marks them.
            if state.type == "poly" and (editing or #state.points < 3) then
                for i = 1, #state.points do
                    local point = state.points[i]
                    local grabbedHere = editing and state.grabbing and i == state.editIndex
                    local hoveredHere = editing and not state.grabbing and i == state.editIndex

                    -- A grabbed point's marker follows the CURRENT aim rather
                    -- than its last confirmed position -- a live preview of
                    -- where place (E) will drop it, which is the whole point
                    -- of being able to fly away and still be "holding" it.
                    local drawAt = (grabbedHere and hit and aimCoords) and aimCoords or point

                    -- zOffset only applies to the point's own stored position,
                    -- not to the aim-following ghost above (the aim is already
                    -- a real world coordinate, not one that needs raising).
                    local drawZ = drawAt.z + (drawAt == point and state.zOffset or 0.0)

                    -- Grabbed draws in blue (actively being carried) so it
                    -- reads as a distinct state from hovered (white, "this is
                    -- what place would grab next") and idle (red).
                    local size = (grabbedHere or hoveredHere) and 0.45 or 0.25
                    local r, g, b = 255, 60, 60
                    if hoveredHere then r, g, b = 255, 255, 255 end
                    if grabbedHere then r, g, b = 60, 180, 255 end

                    DrawMarker(28, drawAt.x, drawAt.y, drawZ, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        size, size, size, r, g, b, 200, false, false, 2, false, nil, nil, false)
                end
            end

            -- Only pushed to the NUI when something actually changed, so the
            -- HUD doesn't get a message every single frame while nothing moved.
            local snapshot = creatorHudSnapshot(state, hit)
            if not hudSnapshotsEqual(snapshot, state.lastHud) then
                state.lastHud = snapshot
                QB.nui.send("zoneCreator:hud", snapshot)
                updateCreatorInstructions(state)
            end

            -- Re-asserted every frame rather than once at startup: the game
            -- turns the radar back on by itself on plenty of transitions
            -- (entering a vehicle, respawning, leaving an interior), so a
            -- single call at the top would silently stop holding partway
            -- through a placement session.
            if Config.zones.creator.hideRadar then
                state.radarManaged = true
                DisplayRadar(false)
            end

            Wait(0)
        end
        end)

        if not ok then
            creatorLog(("zone creator crashed and was cleaned up: %s"):format(tostring(err)))

            -- A crash left creatorState pointing at this now-dead session --
            -- clear it so a fresh QB.zones.startCreator isn't rejected as
            -- "already running" forever, and reject the dangling promise
            -- rather than leaving a caller's Await suspended indefinitely.
            if creatorState == state then
                creatorState = nil
                state.promise:reject(("zone creator crashed: %s"):format(tostring(err)))
            end
        end

        releaseCreatorUi(state)
        releaseCreatorCamera(state)

        -- Restore only the state this creator changed. Forcing the radar on
        -- here overrides a HUD resource (or the player's existing hidden
        -- state) when it was already hidden before the creator opened.
        restoreCreatorRadar(state)

        QB.nui.send("zoneCreator:hud", nil)

    end)
end

-- A restart of THIS resource (kora_lib itself, not whichever resource called
-- QB.zones.startCreator) kills the creator's thread outright -- no pcall, no
-- loop-exit path, and no cleanup below either runs for that, since the
-- coroutine is simply gone. Without this, a player mid-session when kora_lib
-- restarts is left frozen in place with a scripted camera stuck on screen
-- until they reconnect. Immediate, not eased: there's no gameplay camera
-- transition worth easing into when the resource providing it is already gone.
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

-- The shared freecam starts from the gameplay view and owns camera/control/
-- player restoration. The creator only retains its native handle for raycasts.
local function startCreatorCamera()
    local freecam, err = QB.freecam.start({
        moveSpeed = Config.zones.creator.cameraMoveSpeed,
        lookSensitivity = Config.zones.creator.cameraLookSensitivity,
        fastMultiplier = Config.zones.creator.shiftMultiplier,
        transitionMs = Config.zones.creator.cameraTransitionMs,
    })
    assert(freecam, err)
    return freecam, freecam.getCamera()
end

local function beginCreator(zoneType, resource, existingOpts)
    local state = newCreatorState(zoneType, resource)
    if existingOpts then seedCreatorState(state, existingOpts) end
    creatorState = state

    local started, freecam, cam = pcall(startCreatorCamera)
    if not started then
        creatorState = nil
        error(freecam, 0)
    end
    state.freecam, state.cam = freecam, cam
    state.instructions = QB.instructional.show({
        { control = 32, label = "Move forward" },
    })
    updateCreatorInstructions(state)

    if Config.zones.creator.hideRadar then
        state.radarManaged = true
        DisplayRadar(false)
    end

    ensureCreatorThread(state)
    QB.nui.send("zoneCreator:start", { type = zoneType })

    return state.promise
end

---Starts the in-world zone creator: aim and press the placement key to mark
---points, adjust size/rotation/radius/thickness with the scroll wheel (the
---cycle key switches which parameter scroll adjusts), then confirm to open a
---summary dialog with the generated QB.zones.<type>({...}) snippet and a
---copy-to-clipboard button.
---@param zoneType "box" | "sphere" | "poly"
---@param existingOpts? table Seeds the creator from an existing zone's opts (same shape QB.zones.<type>() takes) -- e.g. `QB.zones.startCreator("box", myZoneOpts)` to reposition/resize `myZoneOpts` instead of starting empty. Validated like the real constructors; malformed values raise synchronously.
---@return promise|any result Resolves/returns { type, opts } once confirmed, or nil if cancelled, for a same-VM
---caller (unchanged, awaitable as before) or a genuine cross-resource caller respectively. Rejects/errors if a
---creator is already running or the creator is disabled (Config.zones.creator.enabled) -- see settleForExport
---above for the same-VM-vs-cross-resource distinction. An invalid zoneType or malformed existingOpts raises a
---synchronous error instead (like the zone constructors themselves), same for both kinds of caller.
function QB.zones.startCreator(zoneType, existingOpts)
    assert(ZONE_TYPES[zoneType], "startCreator type must be 'box', 'sphere', or 'poly'.")

    if Config.zones.creator.enabled == false then
        local p = promise.new()
        p:reject("The zone creator is disabled on this server (Config.zones.creator.enabled).")
        return settleForExport(p)
    end

    local placement = rawget(QB, "placement")
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

    -- Captured now, synchronously, while GetInvokingResource() still reflects
    -- the caller that reached across the exports boundary -- by the time the
    -- player actually confirms (seconds/minutes later, via a keypress with no
    -- export call in progress), GetInvokingResource() would just return nil.
    return settleForExport(beginCreator(zoneType, GetInvokingResource() or GetCurrentResourceName(), existingOpts))
end

---Whether a zone creator session currently owns player input (camera fly,
---place/undo/cycle keybinds). Consulted by other resources whose own
---keybind collides with a creator keybind by default -- e.g. kora_inventory's
---TAB-bound inventory toggle vs. qblib_zonecreator_cycle -- so the second
---handler can bail instead of firing alongside the creator's.
---@return boolean
function QB.zones.isCreatorActive()
    return creatorState ~= nil
end

-- No-args toggle direction: "any zone currently drawing debug" flips
-- everything off, otherwise flips everything on. Reads debugZones directly
-- (rather than tracking a separate on/off flag of its own) so it stays
-- correct even after a resource has been calling QB.zones.setDebug per-zone
-- behind this command's back -- there's no separate piece of state that
-- could drift out of sync with what's actually drawing.
RegisterCommand("qb_zonedebug", function(_, args)
    local arg = args[1] and tostring(args[1]):lower() or nil
    local enabled

    if arg == "on" then
        enabled = true
    elseif arg == "off" then
        enabled = false
    elseif arg == nil then
        enabled = next(debugZones) == nil
    else
        creatorLog(("qb_zonedebug: unrecognised argument '%s' -- use 'on', 'off', or no argument to toggle."):format(arg))
        return
    end

    QB.zones.setDebug(nil, enabled)
    creatorLog(("zone debug drawing %s for every registered zone."):format(enabled and "enabled" or "disabled"))
end, false)

---@class QBZoneEditOptions
---@field coords? any New center coordinates. Only supported by box and sphere zones.
---@field onEnter? fun(zone: table)|false New enter callback, or false to remove it.
---@field onExit? fun(zone: table)|false New exit callback, or false to remove it.

---Edits an existing zone without replacing its handle.
---
---Only `coords`, `onEnter`, and `onExit` can be changed.
---Shape properties such as size, radius, rotation, points, and thickness
---cannot be modified through this function.
---
---Pass `false` for `onEnter` or `onExit` to remove the existing callback.
---@param handle QBZoneHandle
---@param opts QBZoneEditOptions
---@return QBZoneHandle? handle The same handle passed to the function, or nil for a foreign zone.
---@return string? error
function QB.zones.edit(handle, opts)
    return editZone(handle, opts)
end

RegisterNetEvent("qblib:editor:startZoneCreator", function(zoneType)
    if type(zoneType) ~= "string" then return end
    local ok, result = pcall(function() return Citizen.Await(QB.zones.startCreator(zoneType)) end)

    if not ok then
        creatorLog(("zone creator failed: %s"):format(tostring(result)))
    elseif result then
        creatorLog(("captured a %s zone definition; no live zone was registered."):format(result.type))
    else
        creatorLog("zone creator cancelled.")
    end
end)
