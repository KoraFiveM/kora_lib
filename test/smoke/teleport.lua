local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
local mocks = require('mocks')
mocks.install()

dofile(repoRoot .. 'config.lua')
dofile(repoRoot .. 'build/initiate.lua')
dofile(repoRoot .. 'modules/util/shared.lua')

local currentPed, moved, heading, fadeOut, fadeIn = 42, nil, nil, 0, 0
local moves, freezes, focusCleared = {}, {}, 0
local waypoint, ground, waitingForCollision = nil, nil, false
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
_G.GetEntityHeading = function() return 33 end
_G.DoesEntityExist = function(entity) return entity == currentPed or entity == 99 end
_G.SetEntityCoords = function(entity, x, y, z)
    moved = { entity = entity, x = x, y = y, z = z }
    moves[#moves + 1] = moved
end
_G.SetEntityHeading = function(entity, value) heading = { entity = entity, value = value } end
_G.FreezeEntityPosition = function(entity, toggle) freezes[#freezes + 1] = { entity = entity, toggle = toggle } end
_G.RequestCollisionAtCoord = function() end
_G.IsEntityWaitingForWorldCollision = function() return waitingForCollision end
_G.SetFocusPosAndVel = function() end
_G.ClearFocus = function() focusCleared = focusCleared + 1 end
_G.DoScreenFadeOut = function() fadeOut = fadeOut + 1 end
_G.DoScreenFadeIn = function() fadeIn = fadeIn + 1 end
_G.IsScreenFadedOut = function() return true end

dofile(repoRoot .. 'local/resources/client.lua')
dofile(repoRoot .. 'modules/cache/client.lua')
dofile(repoRoot .. 'modules/visuals/client.lua')
QB.world.getWaypointCoords = function()
    if waypoint then return waypoint end
    return false, 'No waypoint is set.'
end
QB.world.getGroundCoords = function()
    if ground then return ground end
    return false, 'Ground was not found.'
end
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

harness.test('teleport rejects non-finite destinations and waypoint options before movement', function()
    moves, fadeOut, fadeIn = {}, 0, 0
    harness.assertThrows(function()
        QB.teleport.entity(99, { x = math.huge, y = 2, z = 3 }, { fade = false })
    end, 'infinite teleport coordinates should be rejected')
    harness.assertThrows(function()
        QB.teleport.entity(99, { x = 1, y = 2, z = 3, w = 0 / 0 }, { fade = false })
    end, 'NaN teleport headings should be rejected')
    harness.assertThrows(function()
        QB.teleport.entity(99, { x = 1, y = 2, z = 3, heading = 'east' }, { fade = false })
    end, 'non-numeric teleport headings should be rejected')
    harness.assertThrows(function()
        QB.teleport.entity(math.huge, { x = 1, y = 2, z = 3 }, { fade = false })
    end, 'non-finite entity handles should be rejected')
    harness.assertThrows(function()
        QB.teleport.entity(99, { x = 1, y = 2, z = 3 }, false)
    end, 'explicit non-table options should be rejected')
    harness.assertThrows(function()
        QB.teleport.entity(99, { x = 1, y = 2, z = 3 }, { fade = 'fast' })
    end, 'invalid fades should be rejected')

    waypoint = { x = 100, y = 200, z = 0 }
    harness.assertThrows(function()
        QB.teleport.toWaypoint({ collisionTimeout = math.huge })
    end, 'infinite waypoint timeouts should be rejected')
    harness.assertThrows(function()
        QB.teleport.toWaypoint({ groundAttempts = false })
    end, 'explicit invalid waypoint values must not default')
    harness.assertThrows(function()
        QB.teleport.toWaypoint({ launchHeight = '500' })
    end, 'numeric strings must not silently coerce into waypoint options')
    waypoint = nil
    harness.assertEqual(#moves, 0, 'invalid inputs must not move an entity')
    harness.assertEqual(fadeOut, 0, 'invalid inputs must not start a fade')
end)

harness.test('toWaypoint reports a missing waypoint without moving or fading', function()
    waypoint, moves, fadeOut, fadeIn = nil, {}, 0, 0
    local ok, err = QB.teleport.toWaypoint()
    harness.assertFalse(ok, 'missing waypoint should fail')
    harness.assertTrue(err:find('No waypoint', 1, true) ~= nil, 'failure should explain the missing waypoint')
    harness.assertEqual(#moves, 0, 'missing waypoint should not move the player')
    harness.assertEqual(fadeOut, 0, 'missing waypoint should not start a fade')
end)

harness.test('toWaypoint lands on resolved ground and always unfreezes and restores the screen', function()
    waypoint, ground = { x = 100, y = 200, z = 0 }, { x = 100, y = 200, z = 18 }
    moves, freezes, fadeOut, fadeIn, focusCleared = {}, {}, 0, 0, 0
    waitingForCollision = false

    local ok = QB.teleport.toWaypoint({ launchHeight = 500 })
    harness.assertTrue(ok, 'resolved waypoint should succeed')
    harness.assertEqual(moves[1].z, 500, 'entity should first move to the configured launch height')
    harness.assertEqual(moves[#moves].z, 18, 'entity should finish at resolved ground height')
    harness.assertFalse(freezes[#freezes].toggle, 'entity should be unfrozen after success')
    harness.assertEqual(fadeIn, 1, 'screen should fade back in after success')
    harness.assertEqual(focusCleared, 1, 'streaming focus should be cleared after success')
end)

harness.test('toWaypoint restores the origin after ground resolution fails', function()
    waypoint, ground = { x = 100, y = 200, z = 0 }, nil
    moves, freezes, fadeOut, fadeIn = {}, {}, 0, 0
    waitingForCollision = false

    local ok, err = QB.teleport.toWaypoint()
    harness.assertFalse(ok, 'missing ground should fail')
    harness.assertTrue(err:find('Ground was not found', 1, true) ~= nil, 'ground error should propagate')
    harness.assertEqual(moves[#moves].x, 0, 'failure should restore original x')
    harness.assertEqual(moves[#moves].z, 0, 'failure should restore original z')
    harness.assertEqual(heading.value, 33, 'failure should restore original heading')
    harness.assertFalse(freezes[#freezes].toggle, 'failure should still unfreeze the entity')
    harness.assertEqual(fadeIn, 1, 'failure should still restore the screen')
end)

harness.test('toWaypoint treats collision timeout as a failure and restores the origin', function()
    waypoint, ground = { x = 100, y = 200, z = 0 }, { x = 100, y = 200, z = 18 }
    moves, freezes, fadeOut, fadeIn = {}, {}, 0, 0
    waitingForCollision = true

    local ok, err = QB.teleport.toWaypoint({ collisionTimeout = 16 })
    waitingForCollision = false
    harness.assertFalse(ok, 'collision timeout should fail')
    harness.assertTrue(err:find('collision', 1, true) ~= nil, 'timeout should identify collision loading')
    harness.assertEqual(moves[#moves].x, 0, 'collision failure should restore original position')
    harness.assertFalse(freezes[#freezes].toggle, 'collision failure should still unfreeze')
    harness.assertEqual(fadeIn, 1, 'collision failure should still fade back in')
end)

harness.report('teleport')
