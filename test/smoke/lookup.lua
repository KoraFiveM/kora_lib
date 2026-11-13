local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
local mocks = require('mocks')

local function actualJoaat(value)
    local hash = 0
    value = value:lower()
    for index = 1, #value do
        hash = (hash + value:byte(index)) & 0xffffffff
        hash = (hash + (hash << 10)) & 0xffffffff
        hash = (hash ~ (hash >> 6)) & 0xffffffff
    end
    hash = (hash + (hash << 3)) & 0xffffffff
    hash = (hash ~ (hash >> 11)) & 0xffffffff
    return (hash + (hash << 15)) & 0xffffffff
end

local function jsonEncode(value)
    local kind = type(value)
    if kind == 'nil' then return 'null' end
    if kind == 'number' or kind == 'boolean' then return tostring(value) end
    if kind == 'string' then return string.format('%q', value) end
    if kind ~= 'table' then error('unsupported JSON fixture value') end

    local count, highest, array = 0, 0, true
    for key in pairs(value) do
        count = count + 1
        if type(key) ~= 'number' or key % 1 ~= 0 or key < 1 then array = false
        else highest = math.max(highest, key) end
    end
    array = array and highest == count
    local parts = {}
    if array then
        for index = 1, highest do parts[#parts + 1] = jsonEncode(value[index]) end
        return '[' .. table.concat(parts, ',') .. ']'
    end
    for key, entry in pairs(value) do
        parts[#parts + 1] = jsonEncode(tostring(key)) .. ':' .. jsonEncode(entry)
    end
    table.sort(parts)
    return '{' .. table.concat(parts, ',') .. '}'
end

local net = mocks.install()
dofile(repoRoot .. 'build/initiate.lua')
dofile(repoRoot .. 'modules/logging/shared.lua')
dofile(repoRoot .. 'modules/util/shared.lua')
dofile(repoRoot .. 'modules/loops/shared.lua')

local function hash(name) return joaat(name:lower()) % 4294967296 end
local hashes = {
    vehicle = hash('test_vehicle'),
    ped = hash('test_ped'),
    object = hash('test_object'),
    weapon = hash('WEAPON_TEST'),
    component = hash('COMPONENT_TEST'),
    pickup = hash('PICKUP_TEST'),
    shared = hash('shared_model'),
    collision = hash('collision_probe'),
}

local bundles = {
    ['modules/lookup/data/vehicle.lua'] = ('return {[%d]={"test_vehicle","Test Vehicle","TEST_VEHICLE","sports","fixture","TEST","car",2},[%d]={"shared_model"},[4294967295]={"signed_test"}}')
        :format(hashes.vehicle, hashes.shared),
    ['modules/lookup/data/ped.lua'] = ('return {[%d]={"test_ped","Test Ped","TEST_PED","civilian","fixture","CIVMALE"},[%d]={"shared_model_ped"}}')
        :format(hashes.ped, hashes.shared),
    ['modules/lookup/data/object.lua'] = ('return {[%d]={"test_object"},[%d]={{"collision_one"},{"collision_two"}}}')
        :format(hashes.object, hashes.collision),
    ['modules/lookup/data/weapon.lua'] = ('return {[%d]={"WEAPON_TEST","Test Weapon","WT_TEST","GROUP_TEST","fixture","W_TEST","BULLET"}}')
        :format(hashes.weapon),
    ['modules/lookup/data/weapon_component.lua'] = ('return {[%d]={"COMPONENT_TEST","Test Component","WCT_TEST",nil,"fixture",{"WEAPON_TEST"},"clip","gun_root"}}')
        :format(hashes.component),
    ['modules/lookup/data/pickup.lua'] = ('return {[%d]={"PICKUP_TEST",nil,nil,nil,nil,"P_TEST"}}')
        :format(hashes.pickup),
}
local loadCounts = {}
_G.LoadResourceFile = function(_, path)
    loadCounts[path] = (loadCounts[path] or 0) + 1
    return bundles[path]
end

dofile(repoRoot .. 'modules/lookup/shared.lua')
local coreState = Kora.lookup._state

harness.test('base hits work while the custom catalog is pending and load lazily', function()
    harness.assertFalse(Kora.lookup.ready(), 'the client overlay starts pending')
    local record = Kora.lookup.get('vehicle', 'TEST_VEHICLE')
    harness.assertEqual(record.name, 'test_vehicle')
    harness.assertEqual(record.hash, hashes.vehicle)
    harness.assertEqual(record.metadata.class, 'sports')
    harness.assertEqual(record.metadata.manufacturer, 'TEST')
    harness.assertEqual(loadCounts['modules/lookup/data/vehicle.lua'], 1)
    harness.assertEqual(loadCounts['modules/lookup/data/ped.lua'], nil, 'unused namespaces must remain unloaded')

    local missing, reason = Kora.lookup.get('vehicle', 'not_in_fixture')
    harness.assertEqual(missing, nil)
    harness.assertEqual(reason, 'catalog_pending')
end)

harness.test('signed, unsigned, decimal, and hexadecimal inputs normalize to one cached record', function()
    local first = Kora.lookup.get('vehicle', -1)
    for _, value in ipairs({ 4294967295, '4294967295', '-1', '0xFFFFFFFF' }) do
        local record = Kora.lookup.get('vehicle', value)
        harness.assertTrue(rawequal(record, first), 'materialized records should be permanently cached')
    end
    harness.assertEqual(first.signedHash, -1)
    harness.assertEqual(first.hexHash, '0xFFFFFFFF')
    harness.assertEqual(loadCounts['modules/lookup/data/vehicle.lua'], 1)
end)

harness.test('every namespace and convenience helper returns curated metadata', function()
    local ped = Kora.lookup.model('test_ped', 'ped')
    local object = Kora.lookup.model('test_object', 'object')
    local weapon = Kora.lookup.weapon('weapon_test')
    local component = Kora.lookup.weaponComponent('component_test')
    local pickup = Kora.lookup.pickup('pickup_test')
    harness.assertEqual(ped.metadata.pedType, 'CIVMALE')
    harness.assertEqual(object.namespace, 'object')
    harness.assertEqual(weapon.metadata.damageType, 'BULLET')
    harness.assertEqual(component.metadata.weaponNames[1], 'WEAPON_TEST')
    harness.assertEqual(component.metadata.attachBone, 'gun_root')
    harness.assertEqual(pickup.metadata.modelName, 'P_TEST')
end)

harness.test('preload accepts one namespace or all and never reloads a bundle', function()
    Kora.lookup.preload('ped')
    Kora.lookup.preload()
    Kora.lookup.preload({ 'vehicle', 'weapon' })
    for _, namespace in ipairs(coreState.namespaceOrder) do
        local path = ('modules/lookup/data/%s.lua'):format(namespace)
        harness.assertEqual(loadCounts[path], 1, namespace .. ' should load exactly once')
    end
end)

harness.test('model and hash collisions return sorted candidates', function()
    local record, reason, candidates = Kora.lookup.model('shared_model')
    harness.assertEqual(record, nil)
    harness.assertEqual(reason, 'ambiguous')
    harness.assertEqual(#candidates, 2)
    harness.assertEqual(candidates[1].namespace, 'vehicle')
    harness.assertEqual(candidates[2].namespace, 'ped')

    record, reason, candidates = Kora.lookup.get('object', hashes.collision)
    harness.assertEqual(record, nil)
    harness.assertEqual(reason, 'ambiguous')
    harness.assertEqual(candidates[1].name, 'collision_one')
    harness.assertEqual(candidates[2].name, 'collision_two')
end)

harness.test('invalid inputs assert instead of becoming accidental names', function()
    harness.assertThrows(function() Kora.lookup.get('unknown', 1) end)
    harness.assertThrows(function() Kora.lookup.get('vehicle', '') end)
    harness.assertThrows(function() Kora.lookup.get('vehicle', '0xZZ') end)
    harness.assertThrows(function() Kora.lookup.get('vehicle', '1.5') end)
    harness.assertThrows(function() Kora.lookup.get('vehicle', 1.5) end)
    harness.assertThrows(function() Kora.lookup.get('vehicle', 4294967296) end)
    harness.assertThrows(function() Kora.lookup.model('x', 'weapon') end)
    harness.assertThrows(function() Kora.lookup.preload('unknown') end)
    harness.assertThrows(function() Kora.lookup.preload({ [2] = 'vehicle' }) end)
    harness.assertThrows(function() Kora.lookup.preload({ vehicle = true }) end)
end)

harness.test('overlay publication changes pending misses to not_found and enriches base records', function()
    local custom = {
        vehicle = {
            [hashes.vehicle] = {{
                namespace = 'vehicle', hash = hashes.vehicle, signedHash = hashes.vehicle,
                hexHash = ('0x%08X'):format(hashes.vehicle), name = 'test_vehicle',
                label = 'Overridden Vehicle', source = 'custom', resources = { 'fixture_resource' },
                metadata = { seats = 4 },
            }},
        },
    }
    coreState.setOverlay(custom, 1)
    harness.assertTrue(Kora.lookup.ready())
    local record = Kora.lookup.model('test_vehicle', 'vehicle')
    harness.assertEqual(record.source, 'base+custom')
    harness.assertEqual(record.label, 'Overridden Vehicle')
    harness.assertEqual(record.metadata.manufacturer, 'TEST')
    harness.assertEqual(record.metadata.seats, 4)
    harness.assertEqual(record.resources[1], 'fixture_resource')

    local missing, reason = Kora.lookup.get('vehicle', 'not_in_fixture')
    harness.assertEqual(missing, nil)
    harness.assertEqual(reason, 'not_found')
end)

harness.test('awaitReady succeeds immediately when ready and reports bounded timeouts', function()
    harness.assertTrue(Kora.lookup.awaitReady())
    coreState.overlayReady = false
    local ready, reason = Kora.lookup.awaitReady(0)
    harness.assertFalse(ready)
    harness.assertTrue(reason:find('timed out', 1, true) ~= nil)
    harness.assertThrows(function()
        Kora.lookup.awaitReady(math.huge)
    end, 'an infinite readiness timeout should be rejected')
    harness.assertThrows(function()
        Kora.lookup.awaitReady(false)
    end, 'an explicit non-integer timeout should not become the default')
    coreState.setOverlay({}, 2)
end)

_G.joaat = actualJoaat
local realIoOpen = io.open
local directories = {
    ['@fixture_a/'] = { 'peds.meta', 'stream', 'unreadable.meta', 'vehicles.meta', 'weapons.meta' },
    ['@fixture_a/stream'] = { 'binary.ytyp', 'excluded.ydr', 'mystery.yft', 'props.ytyp', 'shared_prop.ydr' },
    ['@fixture_b/'] = { 'stream' },
    ['@fixture_b/stream'] = { 'shared_prop.ydr' },
}
io.readdir = function(path)
    local entries = directories[path]
    if entries == nil then error('not a directory') end
    local position = 0
    return {
        lines = function()
            return function()
                position = position + 1
                return entries[position]
            end
        end,
        close = function() end,
    }
end

local resourceFiles = {
    ['fixture_a:peds.meta'] = '<CPedModelInfo><Item><Name>custom_ped</Name><Pedtype>CIVFEMALE</Pedtype></Item></CPedModelInfo>',
    ['fixture_a:vehicles.meta'] = '<CVehicleModelInfo><Item><modelName>custom_car</modelName><vehicleClass>VC_SPORT</vehicleClass><type>VEHICLE_TYPE_CAR</type><gameName>CUSTOMCAR</gameName><vehicleMakeName>TESTMAKE</vehicleMakeName></Item></CVehicleModelInfo>',
    ['fixture_a:weapons.meta'] = '<CWeaponInfo><Name>WEAPON_CUSTOM</Name><Name>COMPONENT_CUSTOM_CLIP</Name></CWeaponInfo>',
    ['fixture_a:stream/binary.ytyp'] = 'binary\0archetype',
    ['fixture_a:stream/props.ytyp'] = '<CMapTypes><archetypes><Item><name>shared_prop</name></Item><Item><name>text_prop</name></Item></archetypes></CMapTypes>',
    ['fixture_a:kora_lib.lookup.json'] = 'OVERRIDE_A',
}

local oldLoadResourceFile = LoadResourceFile
_G.LoadResourceFile = function(resource, path)
    if resource == 'kora_lib_test' then return bundles[path] end
    return resourceFiles[resource .. ':' .. path]
end

local overrides = {
    OVERRIDE_A = {
        entries = {
            { namespace = 'vehicle', name = 'custom_car', label = 'Custom Car', metadata = { seats = 4 } },
            { namespace = 'pickup', name = 'PICKUP_CUSTOM', metadata = { modelName = 'P_CUSTOM' } },
            { namespace = 'object', name = 'collision_10a4' },
            { namespace = 'object', name = 'collision_5kq0' },
            { namespace = 'object', name = 'bad_hash', hash = 1 },
        },
        exclude = { { namespace = 'object', name = 'excluded' } },
    },
}
_G.json = {
    decode = function(raw) return overrides[raw] end,
    encode = jsonEncode,
}
_G.GetNumResources = function() return 2 end
_G.GetResourceByFindIndex = function(index) return ({ 'fixture_a', 'fixture_b' })[index + 1] end

local registeredRequest
Kora.events.register = function(_, handler) registeredRequest = handler end
Kora.events.push = function() end

local warnings, realPrint = {}, print
_G.print = function(message) warnings[#warnings + 1] = tostring(message) end
dofile(repoRoot .. 'modules/lookup/server.lua')
local scannerState = Kora.lookup._state
local scannedOverlay, scannedTotal = scannerState.scanAll()
scannerState.setOverlay(scannedOverlay, 3)
_G.print = realPrint

local function warningContains(fragment)
    for _, warning in ipairs(warnings) do
        if warning:find(fragment, 1, true) then return true end
    end
    return false
end

harness.test('scanner combines metadata inference with explicit enrichment', function()
    local car = Kora.lookup.model('custom_car', 'vehicle')
    harness.assertEqual(car.label, 'Custom Car')
    harness.assertEqual(car.category, 'sport')
    harness.assertEqual(car.metadata.class, 'sport')
    harness.assertEqual(car.metadata.manufacturer, 'TESTMAKE')
    harness.assertEqual(car.metadata.type, 'car')
    harness.assertEqual(car.metadata.seats, 4)
    harness.assertEqual(car.resources[1], 'fixture_a')

    local ped = Kora.lookup.model('custom_ped', 'ped')
    local weapon = Kora.lookup.weapon('WEAPON_CUSTOM')
    local component = Kora.lookup.weaponComponent('COMPONENT_CUSTOM_CLIP')
    local pickup = Kora.lookup.pickup('PICKUP_CUSTOM')
    harness.assertEqual(ped.metadata.pedType, 'CIVFEMALE')
    harness.assertEqual(weapon.source, 'custom')
    harness.assertEqual(component.source, 'custom')
    harness.assertEqual(pickup.metadata.modelName, 'P_CUSTOM')
end)

harness.test('scanner merges duplicate streamed/text names and contributing resources', function()
    local shared = Kora.lookup.model('shared_prop', 'object')
    harness.assertEqual(shared.name, 'shared_prop')
    harness.assertEqual(#shared.resources, 2)
    harness.assertEqual(shared.resources[1], 'fixture_a')
    harness.assertEqual(shared.resources[2], 'fixture_b')
    harness.assertTrue(scannedTotal >= 8)
end)

harness.test('scanner honors exclusions, rejects bad hashes, and keeps true collision candidates', function()
    local excluded, excludedReason = Kora.lookup.model('excluded', 'object')
    local bad, badReason = Kora.lookup.model('bad_hash', 'object')
    harness.assertEqual(excluded, nil)
    harness.assertEqual(excludedReason, 'not_found')
    harness.assertEqual(bad, nil)
    harness.assertEqual(badReason, 'not_found')

    local collision, reason, candidates = Kora.lookup.get('object', actualJoaat('collision_10a4'))
    harness.assertEqual(collision, nil)
    harness.assertEqual(reason, 'ambiguous')
    harness.assertEqual(#candidates, 2)
end)

harness.test('scanner warns clearly for ambiguous, binary, and unreadable assets', function()
    harness.assertTrue(warningContains('.yft'), 'ambiguous yft files should be reported')
    harness.assertTrue(warningContains('binary .ytyp'), 'binary ytyp files should be reported')
    harness.assertTrue(warningContains('unreadable.meta'), 'unreadable files should be reported')
    harness.assertTrue(warningContains('does not match its name'), 'bad explicit hashes should be reported')
end)

harness.test('scanner caps directory traversal for an oversized resource', function()
    local originalEntries = directories['@fixture_b/stream']
    local oversizedEntries = {}
    for index = 1, 4097 do oversizedEntries[index] = ('large_%d.ydr'):format(index) end
    directories['@fixture_b/stream'] = oversizedEntries

    local scanWarnings, currentPrint = {}, print
    _G.print = function(message) scanWarnings[#scanWarnings + 1] = tostring(message) end
    local records = scannerState.scanResource('fixture_b')
    _G.print = currentPrint
    directories['@fixture_b/stream'] = originalEntries

    harness.assertEqual(#records, 4096)
    local foundLimitWarning = false
    for index = 1, #scanWarnings do
        if scanWarnings[index]:find('4,096-entry lookup scan limit', 1, true) then
            foundLimitWarning = true
            break
        end
    end
    harness.assertTrue(foundLimitWarning)
end)

harness.test('server batches remain below 24 KiB with payload headroom', function()
    local largeOverlay = {}
    for _, namespace in ipairs(scannerState.namespaceOrder) do largeOverlay[namespace] = {} end
    for index = 1, 400 do
        local name = 'large_custom_' .. index
        local modelHash = actualJoaat(name)
        local resources = { 'fixture_a' }
        if index == 1 then
            resources = {}
            for resourceIndex = 1, 80 do resources[resourceIndex] = 'fixture_' .. resourceIndex end
        end
        largeOverlay.object[modelHash] = {{
            namespace = 'object', hash = modelHash, signedHash = modelHash,
            hexHash = ('0x%08X'):format(modelHash), name = name,
            label = string.rep('x', 180), source = 'custom', resources = resources,
        }}
    end
    scannerState.setOverlay(largeOverlay, 4)
    local batches = scannerState.buildBatches()
    harness.assertTrue(#batches > 1, 'the fixture should force multiple batches')
    local attributionFragments, attributedResources = 0, 0
    for _, batch in ipairs(batches) do
        harness.assertTrue(#jsonEncode(batch) < 24 * 1024, 'each encoded batch must stay below 24 KiB')
        for _, record in ipairs(batch) do
            if record.name == 'large_custom_1' then
                attributionFragments = attributionFragments + 1
                attributedResources = attributedResources + #record.resources
            end
        end
    end
    harness.assertTrue(attributionFragments > 1, 'large attribution lists should be fragmented on the wire')
    harness.assertEqual(attributedResources, 80, 'wire fragments must retain every contributing resource')
    scannerState.setOverlay(scannedOverlay, 5)
end)

io.readdir = nil
io.open = realIoOpen
_G.LoadResourceFile = oldLoadResourceFile

net = mocks.install()
dofile(repoRoot .. 'build/initiate.lua')
dofile(repoRoot .. 'modules/logging/shared.lua')
dofile(repoRoot .. 'modules/util/shared.lua')
dofile(repoRoot .. 'modules/loops/shared.lua')

local clientBaseHash = joaat('client_base')
local clientBundles = {}
for _, namespace in ipairs({ 'vehicle', 'ped', 'object', 'weapon', 'weapon_component', 'pickup' }) do
    clientBundles['modules/lookup/data/' .. namespace .. '.lua'] = 'return {}'
end
clientBundles['modules/lookup/data/object.lua'] = ('return {[%d]={"client_base"}}'):format(clientBaseHash)
_G.LoadResourceFile = function(_, path) return clientBundles[path] end

local pushHandler, requests = nil, 0
Kora.events.onPush = function(_, handler) pushHandler = handler end
Kora.events.trigger = function() requests = requests + 1; return true end
dofile(repoRoot .. 'modules/lookup/shared.lua')
dofile(repoRoot .. 'modules/lookup/client.lua')
local clientState = Kora.lookup._state

local function customRecord(namespace, name, label)
    local modelHash = joaat(name:lower()) % 4294967296
    return {
        namespace = namespace, hash = modelHash, name = name, label = label,
        source = 'custom', resources = { 'server_fixture' },
    }
end

harness.test('client requests and retries the overlay while base hits stay available', function()
    harness.assertEqual(requests, 1, 'the first request should follow module startup')
    harness.assertFalse(Kora.lookup.ready())
    harness.assertEqual(Kora.lookup.model('client_base', 'object').name, 'client_base')
    net.step()
    harness.assertEqual(requests, 2, 'a pending client should retry')
end)

harness.test('out-of-order and duplicate batches publish atomically only when complete', function()
    local first = customRecord('object', 'custom_first', 'First')
    local second = customRecord('vehicle', 'custom_second', 'Second')
    local firstFragment = customRecord('object', 'custom_first', 'First')
    firstFragment.resources = { 'server_fixture_2' }
    pushHandler(2, 2, 2, { second, firstFragment })
    pushHandler(2, 2, 2, { second, firstFragment })
    harness.assertFalse(Kora.lookup.ready(), 'a partial snapshot must remain invisible')
    local missing, pending = Kora.lookup.model('custom_second', 'vehicle')
    harness.assertEqual(missing, nil)
    harness.assertEqual(pending, 'catalog_pending')

    pushHandler(2, 1, 2, { first })
    harness.assertTrue(Kora.lookup.ready())
    local merged = Kora.lookup.model('custom_first', 'object')
    harness.assertEqual(merged.label, 'First')
    harness.assertEqual(#merged.resources, 2, 'wire fragments should merge resource attribution')
    harness.assertEqual(Kora.lookup.model('custom_second', 'vehicle').label, 'Second')
end)

harness.test('stale batches are ignored and a newer server snapshot replaces atomically', function()
    pushHandler(1, 1, 1, { customRecord('object', 'stale_entry', 'Stale') })
    local stale, staleReason = Kora.lookup.model('stale_entry', 'object')
    harness.assertEqual(stale, nil)
    harness.assertEqual(staleReason, 'not_found')

    local replacement = customRecord('ped', 'replacement_ped', 'Replacement')
    pushHandler(3, 1, 1, { replacement })
    harness.assertEqual(clientState.overlayVersion, 3)
    harness.assertEqual(Kora.lookup.model('replacement_ped', 'ped').label, 'Replacement')
    local removed, removedReason = Kora.lookup.model('custom_first', 'object')
    harness.assertEqual(removed, nil)
    harness.assertEqual(removedReason, 'not_found')
end)

harness.test('conflicting framing and invalid records never replace the live snapshot', function()
    pushHandler(4, 1, 2, { customRecord('object', 'partial_entry', 'Partial') })
    pushHandler(4, 2, 3, { customRecord('object', 'bad_frame', 'Bad') })
    pushHandler(4, 2, 2, {{ namespace = 'object', name = 'wrong_hash', hash = 1 }})
    harness.assertEqual(clientState.overlayVersion, 3)
    harness.assertEqual(Kora.lookup.model('replacement_ped', 'ped').label, 'Replacement')
end)

harness.report('lookup')
