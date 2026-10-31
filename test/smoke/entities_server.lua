local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
require('mocks').install()

dofile(repoRoot .. 'build/initiate.lua')
dofile(repoRoot .. 'modules/util/shared.lua')

local calls = {}
_G.IsModelInCdimage, _G.IsModelAVehicle = nil, nil
Kora.lookup.vehicle = function(hash) return hash == joaat('sultan') and {} or nil end
function _G.CreateVehicleServerSetter(model, vehicleType, x, y, z, heading)
    calls = { model, vehicleType, x, y, z, heading }
    return 42
end
function _G.DoesEntityExist(entity) return entity == 42 end
function _G.NetworkGetNetworkIdFromEntity() return 4242 end

dofile(repoRoot .. 'modules/entities/server.lua')

harness.test('creates a strictmode server vehicle and returns its network id', function()
    local netId, err = Kora.entities.createVehicle('sultan', { x = 1, y = 2, z = 3, w = 90.0 })
    harness.assertEqual(err, nil)
    harness.assertEqual(netId, 4242)
    harness.assertEqual(calls[2], 'automobile')
    harness.assertEqual(calls[6], 90.0)
end)

harness.test('rejects an invalid vehicle type', function()
    harness.assertThrows(function()
        Kora.entities.createVehicle('sultan', { x = 1, y = 2, z = 3 }, 'spaceship')
    end)
end)

harness.test('rejects models absent from the server lookup before creation', function()
    calls = {}
    local netId, err = Kora.entities.createVehicle(0, { x = 1, y = 2, z = 3 })
    harness.assertEqual(netId, false)
    harness.assertEqual(err, 'Vehicle model is invalid.')
    harness.assertEqual(next(calls), nil)
end)

harness.report('entities server smoke')
