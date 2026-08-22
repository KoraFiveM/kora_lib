-- Smoke test for the distancecheck module (QB.distance.*), both realms. Client
-- functions measure from the local player (QB.cache.get('coords')); server
-- functions take `src` first and measure from that player's ped. vector3 is
-- mocked locally (FiveM's isn't available under plain lua5.4) with __sub/__len
-- so `#(a - b)` yields Euclidean distance, exactly as the module relies on.
--
-- Client and server both define QB.distance.*, so -- per qblib's
-- same-name-across-realms rule -- the client functions are captured before the
-- server file overwrites them.

local h = dofile('test/harness.lua')

-- Auto-vivifying QB, as build/initiate.lua creates it.
_G.QB = setmetatable({}, { __index = function(t, k) local m = {}; rawset(t, k, m); return m end })

local vmt = {}
vmt.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vmt) end
vmt.__len = function(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
_G.vector3 = function(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vmt) end

-- Local player sits at the origin for the client tests.
QB.cache.get = function(key) if key == 'coords' then return vector3(0, 0, 0) end end

dofile('modules/distancecheck/client.lua')
local cPlayer, cCoords, cEntity, cXY = QB.distance.player, QB.distance.coords, QB.distance.entity, QB.distance.xy

h.test('client player(): true within radius, false beyond', function()
    h.assertTrue(cPlayer({ x = 3, y = 0, z = 0 }, 5), 'dist 3 <= 5')
    h.assertFalse(cPlayer({ x = 10, y = 0, z = 0 }, 5), 'dist 10 > 5')
end)

h.test('client player(): default radius is 5', function()
    h.assertTrue(cPlayer({ x = 4, y = 0, z = 0 }))
    h.assertFalse(cPlayer({ x = 6, y = 0, z = 0 }))
end)

h.test('coords(): measures between two arbitrary points (3-4-5 triangle)', function()
    h.assertTrue(cCoords({ x = 0, y = 0, z = 0 }, { x = 0, y = 3, z = 4 }, 5), 'dist 5 <= 5')
    h.assertFalse(cCoords({ x = 0, y = 0, z = 0 }, { x = 0, y = 3, z = 4 }, 4), 'dist 5 > 4')
end)

h.test('client entity(): measures from the player to the entity', function()
    _G.GetEntityCoords = function() return vector3(0, 0, 2) end
    h.assertTrue(cEntity(123, 5), 'dist 2 <= 5')
    h.assertFalse(cEntity(123, 1), 'dist 2 > 1')
end)

h.test('xy(): ignores the z axis', function()
    h.assertTrue(cXY({ x = 1, y = 1, z = 1000 }, 5), 'xy dist ~1.41 <= 5 despite huge z')
end)

h.test('missing arguments assert', function()
    h.assertThrows(function() cPlayer(nil) end)
    h.assertThrows(function() cCoords({ x = 1, y = 1, z = 1 }, nil) end)
end)

-- Server realm: src-first, position from GetPlayerPed(src) + GetEntityCoords.
_G.GetPlayerPed = function(src) return src end
_G.GetEntityCoords = function() return vector3(0, 0, 0) end
dofile('modules/distancecheck/server.lua')

h.test('server player(): uses the source ped position', function()
    h.assertTrue(QB.distance.player(1, { x = 3, y = 0, z = 0 }, 5))
    h.assertFalse(QB.distance.player(1, { x = 9, y = 0, z = 0 }, 5))
end)

h.test('server entity(): requires src and entity', function()
    _G.GetEntityCoords = function(e) return e == 99 and vector3(0, 0, 2) or vector3(0, 0, 0) end
    h.assertTrue(QB.distance.entity(1, 99, 5))
    h.assertThrows(function() QB.distance.entity(nil, 99) end)
end)

h.report('distancecheck')
