local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
require('mocks').install()

dofile(repoRoot .. 'build/initiate.lua')
dofile(repoRoot .. 'modules/logging/shared.lua')
dofile(repoRoot .. 'modules/loops/shared.lua')

local VEHICLE = 10
local state, calls, requestSucceeds

local function reset()
    state = {
        exists = true, control = false, plate = '  TEST42  ', plateIndex = 2,
        colors = { 1, 2 }, extras = { [0] = true, [20] = false },
        mods = {}, toggles = { [18] = true, [20] = true, [22] = true }, customColors = false, customXenon = false,
    }
    for id = 0, 49 do state.mods[id] = id - 1 end
    calls, requestSucceeds = {}, true
end

local function record(name, ...)
    calls[name] = calls[name] or {}
    calls[name][#calls[name] + 1] = { ... }
end

reset()
function _G.DoesEntityExist(entity) return entity == VEHICLE and state.exists end
function _G.IsEntityAVehicle(entity) return entity == VEHICLE end
function _G.NetworkHasControlOfEntity() return state.control end
function _G.NetworkRequestControlOfEntity() if requestSucceeds then state.control = true end end
Kora.entities.requestControl = function(entity)
    if not DoesEntityExist(entity) then return false, 'Entity does not exist.' end
    if NetworkHasControlOfEntity(entity) then return true end
    NetworkRequestControlOfEntity(entity)
    return NetworkHasControlOfEntity(entity), 'Could not acquire control.'
end
function _G.SetEntityAsMissionEntity() end
function _G.DeleteVehicle() state.exists = false; record('DeleteVehicle') end
function _G.GetPedInVehicleSeat() return 50 end
function _G.PlayerPedId() return 50 end
function _G.GetEntityModel() return 1234 end
function _G.GetVehicleNumberPlateText() return state.plate end
function _G.GetDisplayNameFromVehicleModel() return 'ADDER' end
function _G.GetLabelText() return 'Adder' end
function _G.GetVehicleExtraColours() return 3, 4 end
function _G.GetVehicleColours() return state.colors[1], state.colors[2] end
function _G.GetIsVehiclePrimaryColourCustom() return state.customColors end
function _G.GetIsVehicleSecondaryColourCustom() return state.customColors end
function _G.GetVehicleCustomPrimaryColour() return 10, 20, 30 end
function _G.GetVehicleCustomSecondaryColour() return 40, 50, 60 end
function _G.DoesExtraExist(_, id) return id == 0 or id == 20 end
function _G.IsVehicleExtraTurnedOn(_, id) return state.extras[id] and 1 or 0 end
function _G.GetVehicleWheelHealth(_, id) return 900 + id end
function _G.IsVehicleTyreBurst(_, id, complete) return id == 1 and not complete end
function _G.IsVehicleWindowIntact(_, id) return id ~= 2 end
function _G.IsVehicleDoorDamaged(_, id) return id == 3 end
function _G.GetVehicleXenonLightsCustomColor() return state.customXenon, 7, 8, 9 end
function _G.GetVehicleXenonLightsColor() return 6 end
function _G.GetVehicleMod(_, id) return state.mods[id] end
function _G.GetVehicleLivery() return 5 end
function _G.GetVehicleNumberPlateTextIndex() return state.plateIndex end
function _G.GetVehicleBodyHealth() return 999.94 end
function _G.GetVehicleEngineHealth() return 888.86 end
function _G.GetVehiclePetrolTankHealth() return 777.74 end
function _G.GetVehicleFuelLevel() return 55.55 end
function _G.GetVehicleDirtLevel() return 4.44 end
function _G.GetVehicleOilLevel() return 3.33 end
function _G.GetVehicleDashboardColour() return 8 end
function _G.GetVehicleWheelType() return 7 end
function _G.GetVehicleWheelSize() return 1.1 end
function _G.GetVehicleWheelWidth() return 1.2 end
function _G.GetVehicleWindowTint() return 3 end
function _G.IsVehicleNeonLightEnabled(_, id) return id % 2 == 0 end
function _G.GetVehicleNeonLightsColour() return 1, 2, 3 end
function _G.GetVehicleInteriorColour() return 9 end
function _G.GetVehicleTyreSmokeColor() return 4, 5, 6 end
function _G.IsToggleModOn(_, id) return state.toggles[id] end
function _G.GetVehicleModVariation(_, id) return id == 23 end
function _G.GetVehicleRoofLivery() return 2 end

local setters = {
    'SetVehicleModKit', 'SetVehicleNumberPlateText', 'SetVehicleNumberPlateTextIndex',
    'SetVehicleBodyHealth', 'SetVehicleEngineHealth', 'SetVehiclePetrolTankHealth',
    'SetVehicleFuelLevel', 'SetVehicleDirtLevel', 'SetVehicleOilLevel',
    'ClearVehicleCustomPrimaryColour', 'ClearVehicleCustomSecondaryColour', 'SetVehicleColours',
    'SetVehicleCustomPrimaryColour', 'SetVehicleCustomSecondaryColour', 'SetVehicleExtraColours',
    'SetVehicleDashboardColour', 'SetVehicleInteriorColour', 'SetVehicleWheelType',
    'SetVehicleWheelSize', 'SetVehicleWheelWidth', 'SetVehicleExtra', 'SetVehicleWheelHealth',
    'SetVehicleTyreBurst', 'SetVehicleTyreFixed', 'SetVehicleWindowTint', 'FixVehicleWindow',
    'SmashVehicleWindow', 'SetVehicleDoorBroken', 'SetVehicleDoorShut',
    'SetVehicleNeonLightEnabled', 'SetVehicleNeonLightsColour', 'SetVehicleTyreSmokeColor',
    'SetVehicleMod', 'ToggleVehicleMod', 'SetVehicleLivery', 'SetVehicleRoofLivery',
    'SetVehicleXenonLightsCustomColor', 'SetVehicleXenonLightsColor',
}
for _, name in ipairs(setters) do
    _G[name] = function(...) record(name, ...) end
end

dofile(repoRoot .. 'modules/util/shared.lua')
dofile(repoRoot .. 'modules/vehicle/shared.lua')
dofile(repoRoot .. 'modules/vehicle/client.lua')

harness.test('normalizePlate applies explicit whitespace and character policies', function()
    harness.assertEqual(Kora.vehicle.normalizePlate(' ab  12 '), 'AB 12')
    harness.assertEqual(Kora.vehicle.normalizePlate(' ab  12 ', { whitespace = 'remove' }), 'AB12')
    harness.assertEqual(Kora.vehicle.normalizePlate(' ab  12 ', { whitespace = 'preserve' }), 'AB  12')
    local invalid, reason = Kora.vehicle.normalizePlate('AB-12')
    harness.assertEqual(invalid, nil)
    harness.assertEqual(reason, 'invalid_characters')
    harness.assertEqual(Kora.vehicle.normalizePlate('CUSTOM-PLATE', {
        maxLength = 32,
        characters = 'any',
    }), 'CUSTOM-PLATE')
    harness.assertThrows(function() Kora.vehicle.normalizePlate('TEST42', false) end)
end)

harness.test('vehicle delete acquires control before deleting', function()
    reset()
    local ok, err = Kora.vehicle.delete(VEHICLE)
    harness.assertTrue(ok, tostring(err))
    harness.assertEqual(#calls.DeleteVehicle, 1)
    harness.assertTrue(state.control, 'network control should be requested')
    harness.assertThrows(function() Kora.vehicle.delete(VEHICLE, false) end)
end)

harness.test('identity helpers validate, trim, and localize vehicles', function()
    reset()
    harness.assertTrue(Kora.vehicle.isDriver(VEHICLE))
    harness.assertEqual(Kora.vehicle.model(VEHICLE), 1234)
    harness.assertEqual(Kora.vehicle.plate(VEHICLE), 'TEST42')
    harness.assertEqual(Kora.vehicle.label(VEHICLE), 'Adder')
    harness.assertFalse(Kora.vehicle.plate(99))
end)

harness.test('getProperties returns the complete compatible shape including extras 0 through 20', function()
    reset()
    local props, err = Kora.vehicle.getProperties(VEHICLE)
    harness.assertTrue(props ~= false, tostring(err))
    harness.assertEqual(props.model, 1234)
    harness.assertEqual(props.plate, 'TEST42')
    harness.assertEqual(props.extras['0'], true)
    harness.assertEqual(props.extras['20'], false)
    harness.assertEqual(props.tireHealth[5], 905)
    harness.assertEqual(props.windowStatus[2], false)
    harness.assertEqual(props.doorStatus[3], true)
    harness.assertEqual(props.modSpoilers, -1)
    harness.assertEqual(props.modKit49, 48)
    harness.assertEqual(props.modTurbo, true)
    harness.assertEqual(props.modCustomTiresF, true)
    harness.assertEqual(props.xenonColor, 6)
end)

harness.test('getProperties emits JSON-stable RGB color objects without table.pack metadata', function()
    reset()
    state.customColors = true
    state.customXenon = true
    local props = Kora.vehicle.getProperties(VEHICLE)
    harness.assertEqual(props.color1.r, 10)
    harness.assertEqual(props.color2.b, 60)
    harness.assertEqual(props.neonColor.g, 2)
    harness.assertEqual(props.tyreSmokeColor.b, 6)
    harness.assertEqual(props.xenonColor.g, 8)
    harness.assertEqual(props.color1.n, nil)
    harness.assertEqual(props.neonColor.n, nil)
    harness.assertEqual(props.xenonColor.n, nil)
end)

harness.test('setProperties obtains control and preserves explicit false and zero values', function()
    reset()
    local ok, err = Kora.vehicle.setProperties(VEHICLE, {
        plate = '', plateIndex = 0, fuelLevel = 0, dirtLevel = 0,
        color1 = 0, pearlescentColor = 0, wheelColor = 0,
        wheelSize = 0, wheelWidth = 0, windowTint = 0,
        extras = { ['0'] = false, ['20'] = true },
        tireBurstState = { ['1'] = false },
        windowStatus = { [2] = false, [3] = true },
        doorStatus = { [3] = false, [4] = true },
        neonEnabled = { ['1'] = false, ['2'] = true, ['3'] = false, ['4'] = true },
        modSpoilers = 0, modTurbo = false, modSmokeEnabled = false, modXenon = false,
        modFrontWheels = 0, modCustomTiresF = false, modLivery = 0, liveryRoof = 0,
        color2 = { ['1'] = 11, ['2'] = 22, ['3'] = 33 },
        neonColor = { ['1'] = 44, ['2'] = 55, ['3'] = 66 },
        tyreSmokeColor = { r = 77, g = 88, b = 99 },
    })
    harness.assertTrue(ok, tostring(err))
    harness.assertTrue(state.control)
    harness.assertEqual(calls.SetVehicleNumberPlateText[1][2], '')
    harness.assertEqual(calls.SetVehicleFuelLevel[1][2], 0)
    harness.assertEqual(calls.SetVehicleWindowTint[1][2], 0)
    harness.assertEqual(calls.SetVehicleExtra[1][3], 1, 'false extra state uses disable=1')
    harness.assertEqual(calls.SetVehicleExtra[2][3], 0, 'true extra state uses disable=0')
    harness.assertEqual(calls.ToggleVehicleMod[1][3], false)
    harness.assertEqual(calls.SetVehicleMod[#calls.SetVehicleMod - 1][3], 0)
    harness.assertTrue(calls.SetVehicleTyreFixed ~= nil, 'false burst state should repair the tyre')
    harness.assertEqual(calls.SetVehicleNeonLightEnabled[2][3], true,
        'JSON-decoded neon state keys should be applied')
    harness.assertEqual(calls.SetVehicleCustomSecondaryColour[1][2], 11)
    harness.assertEqual(calls.SetVehicleNeonLightsColour[1][3], 55)
    harness.assertEqual(calls.SetVehicleTyreSmokeColor[1][4], 99)
end)

harness.test('setProperties returns a bounded control failure without mutating', function()
    reset()
    requestSucceeds = false
    local ok, err = Kora.vehicle.setProperties(VEHICLE, { fuelLevel = 0 }, { timeout = 1 })
    harness.assertFalse(ok)
    harness.assertTrue(type(err) == 'string')
    harness.assertEqual(calls.SetVehicleFuelLevel, nil)
end)

harness.test('setProperties rejects non-finite native values before mutation', function()
    reset()
    harness.assertThrows(function()
        Kora.vehicle.setProperties(VEHICLE, { fuelLevel = math.huge })
    end)
    harness.assertThrows(function()
        Kora.vehicle.setProperties(VEHICLE, { neonColor = { r = 1, g = 0 / 0, b = 3 } })
    end)
    harness.assertThrows(function()
        Kora.vehicle.setProperties(VEHICLE, {}, false)
    end)
    harness.assertEqual(calls.SetVehicleModKit, nil, 'invalid properties must not reach vehicle natives')
end)

harness.test('setProperties rejects malformed plate and interior colour before mutation', function()
    reset()
    harness.assertThrows(function()
        Kora.vehicle.setProperties(VEHICLE, { plate = {} })
    end)
    harness.assertThrows(function()
        Kora.vehicle.setProperties(VEHICLE, { interiorColor = math.huge })
    end)
    harness.assertEqual(calls.SetVehicleModKit, nil, 'invalid properties must not reach vehicle natives')
end)

harness.test('setProperties rejects invalid wheel, window, and door indices before mutation', function()
    reset()
    harness.assertThrows(function()
        Kora.vehicle.setProperties(VEHICLE, { tireHealth = { [math.huge] = 1000 } })
    end)
    harness.assertThrows(function()
        Kora.vehicle.setProperties(VEHICLE, { windowStatus = { [8] = true } })
    end)
    harness.assertThrows(function()
        Kora.vehicle.setProperties(VEHICLE, { doorStatus = { ['not-an-index'] = false } })
    end)
    harness.assertEqual(calls.SetVehicleModKit, nil, 'invalid indexed properties must not reach vehicle natives')
end)

harness.test('setProperties rejects non-boolean state fields before mutation', function()
    reset()
    for _, props in ipairs({
        { extras = { [0] = 'enabled' } },
        { tireBurstState = { [1] = 1 } },
        { windowStatus = { [2] = 'intact' } },
        { doorStatus = { [3] = 0 } },
        { neonEnabled = { [1] = true, [2] = false, [3] = true, [4] = 'on' } },
        { modTurbo = 1 },
        { modCustomTiresF = 'yes' },
    }) do
        harness.assertThrows(function() Kora.vehicle.setProperties(VEHICLE, props) end)
    end
    harness.assertEqual(calls.SetVehicleModKit, nil, 'invalid boolean states must not reach vehicle natives')
end)

harness.test('property helpers reject invalid entities', function()
    reset()
    local props = Kora.vehicle.getProperties(99)
    harness.assertFalse(props)
    local ok = Kora.vehicle.setProperties(99, {})
    harness.assertFalse(ok)
end)

harness.test('vehicle helpers reject malformed handles before native work', function()
    reset()
    for _, vehicle in ipairs({ 0, -1, 1.5, math.huge, -math.huge, 0 / 0 }) do
        harness.assertFalse(Kora.vehicle.model(vehicle))
        harness.assertFalse(Kora.vehicle.plate(vehicle))
        harness.assertFalse(Kora.vehicle.getProperties(vehicle))
        harness.assertFalse(Kora.vehicle.setProperties(vehicle, {}))
        harness.assertThrows(function() Kora.vehicle.delete(vehicle) end)
    end
end)

harness.report('vehicle')
