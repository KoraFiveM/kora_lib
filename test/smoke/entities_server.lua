local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
require('mocks').install()

dofile(repoRoot .. 'build/initiate.lua')
dofile(repoRoot .. 'modules/util/shared.lua')

local calls = {}
function _G.IsModelInCdimage() return true end
function _G.IsModelAVehicle() return true end
function _G.CreateVehicleServerSetter(model, vehicleType, x, y, z, heading)
    calls = { model, vehicleType, x, y, z, heading }
    return 42
end
function _G.DoesEntityExist(entity) return entity == 42 end
function _G.NetworkGetNetworkIdFromEntity() return 4242 end

dofile(repoRoot .. 'modules/entities/server.lua')

harness.test('creates a strictmode server vehicle and returns its network id', function()
    local netId, err = QB.entities.createVehicle('sultan', { x = 1, y = 2, z = 3, w = 90.0 })
    harness.assertEqual(err, nil)
    harness.assertEqual(netId, 4242)
    harness.assertEqual(calls[2], 'automobile')
    harness.assertEqual(calls[6], 90.0)
end)

harness.test('rejects an invalid vehicle type', function()
    harness.assertThrows(function()
        QB.entities.createVehicle('sultan', { x = 1, y = 2, z = 3 }, 'spaceship')
    end)
end)

harness.report('entities server smoke')
