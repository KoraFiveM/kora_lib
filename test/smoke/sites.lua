local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
local mocks = require('mocks')
mocks.install()

dofile(repoRoot .. 'build/initiate.lua')
dofile(repoRoot .. 'modules/util/shared.lua')
dofile(repoRoot .. 'modules/sites/shared.lua')
dofile(repoRoot .. 'modules/sites/server.lua')
dofile(repoRoot .. 'modules/sites/client.lua')

local function v3(x, y, z) return { x = x, y = y, z = z } end

local function fuelDefs()
    return {
        { id = 'grove', label = 'Grove St LTD', price = { pump = 1.55 }, refills = {
            { id = 'p1', type = 'pump', coords = v3(0, 0, 0) },
            { id = 'p2', type = 'pump', coords = v3(10, 0, 0), price = 1.70 },
            { id = 'c1', type = 'charger', coords = v3(20, 0, 0), powerKw = 50 },
        } },
        { id = 'legacy', refills = {
            { id = 'forecourt', type = 'pump', coords = v3(500, 0, 0), radius = 45.0 },
        } },
        { id = 'closed', disabled = true, refills = {
            { id = 'p1', type = 'pump', coords = v3(900, 0, 0) },
        } },
    }
end

local BUILD_OPTS = { childKey = 'refills', inherit = { 'price' }, globals = { price = { pump = 1.60, charger = 0.45 } } }

harness.test('build resolves inherited fields child -> site (per type) -> globals once', function()
    local index = Kora.sites.build(fuelDefs(), BUILD_OPTS)
    harness.assertEqual(index.children['grove:p1'].price, 1.55, 'site per-type price')
    harness.assertEqual(index.children['grove:p2'].price, 1.70, 'child override wins')
    harness.assertEqual(index.children['grove:c1'].price, 0.45, 'global per-type fallback')
    harness.assertEqual(index.children['legacy:forecourt'].price, 1.60, 'global fallback without a site value')
    harness.assertEqual(index.children['grove:c1'].powerKw, 50, 'other child fields are kept')
    harness.assertEqual(index.children['grove:p1'].siteId, 'grove')
    harness.assertEqual(index.children['grove:p1'].key, 'grove:p1')
    harness.assertEqual(index.sites.grove.label, 'Grove St LTD')
    harness.assertEqual(#index.list, 5)
    harness.assertEqual(index.list[1].key, 'grove:p1', 'list keeps definition order')
    harness.assertTrue(index.children['closed:p1'].disabled, 'a disabled site disables its children')
end)

harness.test('build accepts scalar site values and does not modify its input', function()
    local defs = { { id = 's', price = 2.0, children = { { id = 1, type = 'x', coords = v3(0, 0, 0) } } } }
    local index = Kora.sites.build(defs, { inherit = { 'price' } })
    harness.assertEqual(index.children['s:1'].price, 2.0, 'a scalar applies to every child')
    harness.assertEqual(defs[1].children[1].price, nil, 'the definition table is not modified')
    harness.assertEqual(defs[1].children[1].id, 1)
    harness.assertTrue(Kora.sites.get(index, 's', 1.0) ~= nil, '1 and 1.0 name the same child')
end)

harness.test('build rejects malformed definitions', function()
    harness.assertThrows(function() Kora.sites.build('nope') end)
    harness.assertThrows(function() Kora.sites.build({ { id = 'a:b', children = {} } }) end, 'ids cannot contain ":"')
    harness.assertThrows(function() Kora.sites.build({ { id = 'a', children = {} }, { id = 'a', children = {} } }) end)
    harness.assertThrows(function() Kora.sites.build({ { id = 'a' } }) end, 'children array is required')
    harness.assertThrows(function()
        Kora.sites.build({ { id = 'a', children = { { id = 'c' } } } })
    end, 'children need coords')
    harness.assertThrows(function()
        Kora.sites.build({ { id = 'a', children = { { id = 'c', coords = v3(0, 0, 0) }, { id = 'c', coords = v3(0, 0, 0) } } } })
    end, 'duplicate children are rejected')
end)

harness.test('get returns sites and children and treats malformed ids as unknown', function()
    local index = Kora.sites.build(fuelDefs(), BUILD_OPTS)
    harness.assertEqual(Kora.sites.get(index, 'grove').label, 'Grove St LTD')
    harness.assertEqual(Kora.sites.get(index, 'grove', 'p2').price, 1.70)
    harness.assertEqual(Kora.sites.get(index, 'nope'), nil)
    harness.assertEqual(Kora.sites.get(index, 'grove', 'p9'), nil)
    harness.assertEqual(Kora.sites.get(index, {}, 'p1'), nil)
    harness.assertEqual(Kora.sites.get(index, 'grove', 0 / 0), nil)
end)

-- Server validation with a mocked player ped and resolveNetworkEntity.
local pedCoords = v3(0, 1, 0)
local pedExists = true
_G.GetPlayerPed = function() return 77 end
_G.DoesEntityExist = function() return pedExists end
_G.GetEntityCoords = function() return pedCoords end
local resolveCalls = {}
local resolveResult = { 900 }
Kora.world.resolveNetworkEntity = function(src, netId, options)
    resolveCalls[#resolveCalls + 1] = { src = src, netId = netId, options = options }
    return table.unpack(resolveResult)
end

harness.test('validate checks existence, state, type and distance to that one child', function()
    local index = Kora.sites.build(fuelDefs(), BUILD_OPTS)
    local opts = { maxDistance = 4.0, types = { 'pump' } }
    pedCoords = v3(0, 1, 0)

    harness.assertEqual(Kora.sites.validate(1, index, 'grove', 'p1', opts).key, 'grove:p1')
    harness.assertEqual(select(2, Kora.sites.validate(1, index, 'nowhere', 'p1', opts)), 'unknown_site')
    harness.assertEqual(select(2, Kora.sites.validate(1, index, 'grove', 'p9', opts)), 'unknown_child')
    harness.assertEqual(select(2, Kora.sites.validate(1, index, { 'grove' }, 'p1', opts)), 'unknown_site')
    harness.assertEqual(select(2, Kora.sites.validate(1, index, 'closed', 'p1', opts)), 'disabled')
    harness.assertEqual(select(2, Kora.sites.validate(1, index, 'grove', 'c1', opts)), 'wrong_type')
    harness.assertEqual(select(2, Kora.sites.validate(1, index, 'grove', 'p2', opts)), 'too_far',
        'being near another pump of the same station is not enough')

    pedExists = false
    harness.assertEqual(select(2, Kora.sites.validate(1, index, 'grove', 'p1', opts)), 'player_unavailable')
    pedExists = true
end)

harness.test('validate lets a child radius widen the limit (legacy forecourt)', function()
    local index = Kora.sites.build(fuelDefs(), BUILD_OPTS)
    pedCoords = v3(530, 0, 0)
    harness.assertTrue(Kora.sites.validate(1, index, 'legacy', 'forecourt', { maxDistance = 4.0 }) ~= nil)
    pedCoords = v3(560, 0, 0)
    harness.assertEqual(select(2, Kora.sites.validate(1, index, 'legacy', 'forecourt', { maxDistance = 4.0 })), 'too_far')
    harness.assertThrows(function() Kora.sites.validate(1, index, 'grove', 'p1', {}) end,
        'a child without radius needs maxDistance')
end)

harness.test('validate resolves the vehicle near the child and passes its failure reason through', function()
    local index = Kora.sites.build(fuelDefs(), BUILD_OPTS)
    pedCoords = v3(0, 1, 0)
    resolveResult = { 900 }
    local child, vehicle = Kora.sites.validate(1, index, 'grove', 'p1', { maxDistance = 4.0, vehicleNetId = 55, vehicleDistance = 8.0 })
    harness.assertEqual(child.key, 'grove:p1')
    harness.assertEqual(vehicle, 900)
    local call = resolveCalls[#resolveCalls]
    harness.assertEqual(call.netId, 55)
    harness.assertEqual(call.options.entityType, 'vehicle')
    harness.assertEqual(call.options.near.radius, 8.0)
    harness.assertEqual(call.options.near.coords.x, 0)

    resolveResult = { nil, 'too_far_from_point' }
    local none, reason = Kora.sites.validate(1, index, 'grove', 'p1', { maxDistance = 4.0, vehicleNetId = 55 })
    harness.assertEqual(none, nil)
    harness.assertEqual(reason, 'too_far_from_point')
end)

-- Client zones with a mocked Kora.interact.
local zones, removedZoneNames = {}, {}
Kora.interact.addCircleZone = function(name, coords, radius, targetOptions, debug)
    zones[#zones + 1] = { name = name, coords = coords, radius = radius, options = targetOptions, debug = debug }
    return { name = name }
end
Kora.interact.removeZone = function(name)
    removedZoneNames[#removedZoneNames + 1] = name
    return true
end

harness.test('registerZones adds one zone per matching enabled child and removes them together', function()
    zones, removedZoneNames = {}, {}
    local index = Kora.sites.build(fuelDefs(), BUILD_OPTS)
    local pumpOptions = { options = { { label = 'Refuel', event = 'fuel:refuel' } } }
    local handle = Kora.sites.registerZones(index, {
        pump = pumpOptions,
        charger = function(child)
            return { { label = ('Charge (%d kW)'):format(child.powerKw), event = 'fuel:charge', args = { child.key } } }
        end,
    }, { radius = 2.5 })

    harness.assertEqual(#zones, 4, 'three grove refills and the legacy forecourt; the closed site is skipped')
    harness.assertEqual(zones[1].name, 'kora_lib_test:sites:grove:p1', 'names are prefixed with the resource')
    harness.assertEqual(zones[1].radius, 2.5)
    harness.assertEqual(zones[1].options, pumpOptions)
    harness.assertEqual(zones[3].options[1].label, 'Charge (50 kW)', 'per-child option builders receive the child')
    harness.assertEqual(zones[4].radius, 45.0, 'a child radius wins over the default')

    harness.assertEqual(handle.remove(), 4)
    harness.assertEqual(#removedZoneNames, 4)
    harness.assertEqual(handle.remove(), 0, 'removing twice is a no-op')
end)

harness.test('registerZones skips types without options and children an option builder declines', function()
    zones = {}
    local index = Kora.sites.build(fuelDefs(), BUILD_OPTS)
    Kora.sites.registerZones(index, { charger = function() return nil end })
    harness.assertEqual(#zones, 0)
    harness.assertThrows(function() Kora.sites.registerZones(index, { pump = {} }, { radius = 0 }) end)
end)

harness.test('init.lua loads Kora.sites into the consumer instead of proxying it', function()
    mocks.install()
    _G.exports = { kora_lib = {} }
    _G.IsDuplicityVersion = function() return true end
    _G.GetCurrentResourceName = function() return 'kora_fuel' end
    _G.LoadResourceFile = function(resource, path)
        if resource ~= 'kora_lib' then return nil end
        local file = assert(io.open(repoRoot .. path, 'r'))
        local source = file:read('*a')
        file:close()
        return source
    end
    dofile(repoRoot .. 'init.lua')

    local index = Kora.sites.build(fuelDefs(), BUILD_OPTS)
    harness.assertEqual(index.children['grove:p2'].price, 1.70, 'build runs locally')
    harness.assertEqual(type(rawget(Kora.sites, 'validate')), 'function', 'the server realm gets validate locally')
    harness.assertEqual(rawget(Kora.sites, 'registerZones'), nil, 'the client-only function is not loaded on the server')
end)

harness.report('sites')
