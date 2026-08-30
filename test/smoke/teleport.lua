local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
local mocks = require('mocks')
mocks.install()

dofile(repoRoot .. 'config.lua')
dofile(repoRoot .. 'build/initiate.lua')

local currentPed, moved, heading, fadeOut, fadeIn = 42, nil, nil, 0, 0
_G.PlayerId = function() return 1 end
_G.GetPlayerServerId = function() return 1 end
_G.PlayerPedId = function() return currentPed end
_G.IsPedInAnyVehicle = function() return false end
_G.GetVehiclePedIsIn = function() return 0 end
_G.GetVehicleMaxNumberOfPassengers = function() return 0 end
_G.GetPedInVehicleSeat = function() return 0 end
_G.GetSelectedPedWeapon = function() return 0 end
_G.GetEntityHealth = function() return 200 end
_G.GetPedArmour = function() return 0 end
_G.GetPlayerStamina = function() return 100 end
_G.GetEntityCoords = function() return { x = 0, y = 0, z = 0 } end
_G.DoesEntityExist = function(entity) return entity == currentPed or entity == 99 end
_G.SetEntityCoords = function(entity, x, y, z) moved = { entity = entity, x = x, y = y, z = z } end
_G.SetEntityHeading = function(entity, value) heading = { entity = entity, value = value } end
_G.DoScreenFadeOut = function() fadeOut = fadeOut + 1 end
_G.DoScreenFadeIn = function() fadeIn = fadeIn + 1 end
_G.IsScreenFadedOut = function() return true end

dofile(repoRoot .. 'local/resources/client.lua')
dofile(repoRoot .. 'modules/cache/client.lua')
dofile(repoRoot .. 'modules/visuals/client.lua')
dofile(repoRoot .. 'modules/teleport/client.lua')

harness.test('player moves the cached ped behind the default fade and applies vector4 heading', function()
    QB.teleport.player({ x = 10, y = 20, z = 30, w = 90 })
    harness.assertEqual(moved.entity, currentPed, 'player teleport should use the cached ped')
    harness.assertEqual(moved.x, 10, 'player teleport should set x')
    harness.assertEqual(heading.value, 90, 'player teleport should apply heading')
    harness.assertEqual(fadeOut, 1, 'player teleport should fade out by default')
    harness.assertEqual(fadeIn, 1, 'player teleport should fade back in by default')
end)

harness.test('entity can move without a fade', function()
    fadeOut, fadeIn = 0, 0
    QB.teleport.entity(99, { x = 1, y = 2, z = 3 }, { fade = false })
    harness.assertEqual(moved.entity, 99, 'entity teleport should move the requested entity')
    harness.assertEqual(fadeOut, 0, 'fade=false should not fade out')
    harness.assertEqual(fadeIn, 0, 'fade=false should not fade in')
end)

harness.report('teleport')
