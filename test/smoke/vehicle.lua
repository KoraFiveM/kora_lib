local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
require('mocks').install()

dofile(repoRoot .. 'build/initiate.lua')
dofile(repoRoot .. 'modules/loops/shared.lua')

local exists = { [10] = true }
local control = false
local deleted = false
function _G.DoesEntityExist(entity) return exists[entity] == true end
function _G.NetworkHasControlOfEntity() return control end
function _G.NetworkRequestControlOfEntity() control = true end
function _G.IsEntityAVehicle(entity) return entity == 10 end
function _G.SetEntityAsMissionEntity() end
function _G.DeleteVehicle(entity) exists[entity] = nil; deleted = true end
function _G.GetPedInVehicleSeat(vehicle) return vehicle == 10 and 50 or 0 end
function _G.PlayerPedId() return 50 end
function _G.GetEntityModel() return 1234 end

dofile(repoRoot .. 'modules/vehicle/client.lua')

harness.test('vehicle delete acquires control before deleting', function()
    local ok, err = QB.vehicle.delete(10)
    harness.assertTrue(ok, tostring(err))
    harness.assertTrue(deleted, 'DeleteVehicle should be called')
    harness.assertTrue(control, 'network control should be requested')
end)

harness.test('vehicle helpers identify local driver and model', function()
    exists[10] = true
    harness.assertTrue(QB.vehicle.isDriver(10), 'player should be the driver')
    harness.assertEqual(QB.vehicle.model(10), 1234, 'should return model hash')
end)

harness.report('vehicle')
