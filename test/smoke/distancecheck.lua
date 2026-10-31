-- Smoke test for the distancecheck module (Kora.distance.*), both realms. Client
-- functions measure from the local player (Kora.cache.get('coords')); server
-- functions take `src` first and measure from that player's ped. Plain
-- coordinate tables prove the hot path does not need temporary vectors.
--
-- Client and server both define Kora.distance.*, so -- per kora_lib's
-- same-name-across-realms rule -- the client functions are captured before the
-- server file overwrites them.

local h = dofile('test/harness.lua')

-- Auto-vivifying Kora, as build/initiate.lua creates it.
_G.Kora = setmetatable({}, { __index = function(t, k) local m = {}; rawset(t, k, m); return m end })
dofile('modules/util/shared.lua')

-- Local player sits at the origin for the client tests.
Kora.cache.get = function(key) if key == 'coords' then return { x = 0, y = 0, z = 0 } end end

dofile('modules/distancecheck/client.lua')
local cPlayer, cCoords, cEntity, cXY = Kora.distance.player, Kora.distance.coords, Kora.distance.entity, Kora.distance.xy

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
    _G.GetEntityCoords = function() return { x = 0, y = 0, z = 2 } end
    h.assertTrue(cEntity(123, 5), 'dist 2 <= 5')
    h.assertFalse(cEntity(123, 1), 'dist 2 > 1')
end)

h.test('client entity(): rejects an invalid handle before calling natives', function()
    h.assertThrows(function() cEntity(0, 5) end)
    h.assertThrows(function() cEntity(-1, 5) end)
    h.assertThrows(function() cEntity('not-an-entity', 5) end)
end)

h.test('xy(): ignores the z axis', function()
    h.assertTrue(cXY({ x = 1, y = 1, z = 1000 }, 5), 'xy dist ~1.41 <= 5 despite huge z')
end)

h.test('missing arguments assert', function()
    h.assertThrows(function() cPlayer(nil) end)
    h.assertThrows(function() cCoords({ x = 1, y = 1, z = 1 }, nil) end)
end)

h.test('non-finite and negative radii are rejected', function()
    h.assertThrows(function() cPlayer({ x = 0, y = 0, z = 0 }, math.huge) end)
    h.assertThrows(function() cPlayer({ x = 0, y = 0, z = 0 }, -1) end)
    h.assertThrows(function() cPlayer({ x = 0, y = 0, z = 0 }, false) end)
end)

h.test('client coordinates reject non-finite values before distance arithmetic', function()
    h.assertThrows(function() cPlayer({ x = math.huge, y = 0, z = 0 }, 5) end)
    h.assertThrows(function() cCoords({ x = 0, y = 0, z = 0 }, { x = 0, y = 0 / 0, z = 0 }, 5) end)
end)

-- Server realm: src-first, position from GetPlayerPed(src) + GetEntityCoords.
_G.GetPlayerPed = function(src) return src end
_G.GetEntityCoords = function() return { x = 0, y = 0, z = 0 } end
dofile('modules/distancecheck/server.lua')

h.test('server player(): uses the source ped position', function()
    h.assertTrue(Kora.distance.player(1, { x = 3, y = 0, z = 0 }, 5))
    h.assertFalse(Kora.distance.player(1, { x = 9, y = 0, z = 0 }, 5))
end)

h.test('server entity(): requires src and entity', function()
    _G.GetEntityCoords = function(e) return e == 99 and { x = 0, y = 0, z = 2 } or { x = 0, y = 0, z = 0 } end
    h.assertTrue(Kora.distance.entity(1, 99, 5))
    h.assertThrows(function() Kora.distance.entity(nil, 99) end)
end)

h.test('server source/entity checks reject missing live handles', function()
    h.assertThrows(function() Kora.distance.entity(1, 0, 5) end)
    h.assertThrows(function() Kora.distance.entity(1, -1, 5) end)

    local originalGetPlayerPed = GetPlayerPed
    _G.GetPlayerPed = function() return 0 end
    h.assertThrows(function() Kora.distance.player(1, { x = 0, y = 0, z = 0 }, 5) end)
    _G.GetPlayerPed = originalGetPlayerPed
end)

h.test('server source-based checks reject malformed player IDs', function()
    local point = { x = 0, y = 0, z = 0 }
    for _, operation in ipairs({ Kora.distance.player, Kora.distance.entity, Kora.distance.x, Kora.distance.y, Kora.distance.xy }) do
        h.assertThrows(function()
            operation(1.5, point, 5)
        end)
    end
end)

h.test('server rejects a non-finite radius before it can authorize proximity', function()
    h.assertThrows(function() Kora.distance.player(1, { x = 0, y = 0, z = 0 }, math.huge) end)
    h.assertThrows(function() Kora.distance.player(1, { x = 0, y = 0, z = 0 }, false) end)
end)

h.test('server coordinates reject non-finite values before distance arithmetic', function()
    h.assertThrows(function() Kora.distance.player(1, { x = 0, y = math.huge, z = 0 }, 5) end)
end)

h.report('distancecheck')
