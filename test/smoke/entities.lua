local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/util/shared.lua")
dofile(repoRoot .. "modules/loops/shared.lua")

local PED_MODEL = 1001
local VEHICLE_MODEL = 2001
local OBJECT_MODEL = 3001
local STUCK_MODEL = 9999 -- never reports as loaded, to exercise entities.create's failure path
local DELAYED_MODEL = 4001 -- streams after the scope exits, to exercise the async cleanup path
local THROW_MODEL = 5001

local modelType = { [PED_MODEL] = "ped", [VEHICLE_MODEL] = "vehicle" }
local neverLoads = { [STUCK_MODEL] = true }
local delayedLoads = { [DELAYED_MODEL] = true }

local existingEntities = {}
local entityCalls = {}
local nextEntity = 0
local throwSpawn = false

function _G.IsModelValid() return true end
function _G.HasModelLoaded(model) return not neverLoads[model] and not delayedLoads[model] end
function _G.RequestModel() end
function _G.SetModelAsNoLongerNeeded() end

function _G.IsModelAPed(model) return modelType[model] == "ped" end
function _G.IsModelAVehicle(model) return modelType[model] == "vehicle" end

local function spawn()
    nextEntity = nextEntity + 1
    existingEntities[nextEntity] = true
    return nextEntity
end

function _G.CreatePed() return spawn() end
function _G.CreateObjectNoOffset(model)
    if model == THROW_MODEL and throwSpawn then error('simulated spawn failure') end
    return spawn()
end
function _G.CreateVehicle() return spawn() end
function _G.DoesEntityExist(e) return existingEntities[e] == true end
function _G.DeleteEntity(e) existingEntities[e] = nil end
function _G.SetEntityHeading() end

function _G.FreezeEntityPosition(e, on)
    entityCalls[e] = entityCalls[e] or {}
    entityCalls[e].freeze = on
end

function _G.SetBlockingOfNonTemporaryEvents(e, on)
    entityCalls[e] = entityCalls[e] or {}
    entityCalls[e].blockNonTempEvents = on
end

function _G.SetEntityInvincible(e, on)
    entityCalls[e] = entityCalls[e] or {}
    entityCalls[e].invincible = on
end
local hasNetworkControl = true
function _G.NetworkHasControlOfEntity() return hasNetworkControl end
function _G.NetworkRequestControlOfEntity() hasNetworkControl = true end
function _G.SetEntityAsMissionEntity() end

dofile(repoRoot .. "modules/stream/client.lua")
dofile(repoRoot .. "local/resources/client.lua")

-- Scoped entities delegate distance tracking to zones. Keep this test focused
-- on the entity lifecycle by using a tiny zone double and triggering its
-- enter/exit callbacks explicitly; zones.lua covers the real spatial grid.
local scopedZones = {}
Kora.zones = {
    sphere = function(opts)
        local zone = { removed = false, opts = opts }
        function zone.remove() zone.removed = true end
        scopedZones[#scopedZones + 1] = zone
        return zone
    end,
}

dofile(repoRoot .. "modules/entities/client.lua")

harness.test("creates a ped with the static preset frozen, blocked, and invincible", function()
    local entity, err = Kora.entities.create(PED_MODEL, { x = 1, y = 2, z = 3 }, { preset = "static" })
    harness.assertTrue(entity ~= false, "expected a real entity handle, got error: " .. tostring(err))
    harness.assertTrue(_G.DoesEntityExist(entity), "the created entity should exist")
    harness.assertEqual(entityCalls[entity].freeze, true, "the static preset should freeze the ped")
    harness.assertEqual(entityCalls[entity].blockNonTempEvents, true, "the static preset should block non-temp events on a ped")
    harness.assertEqual(entityCalls[entity].invincible, true, "the static preset should make the ped invincible")
end)

harness.test("creates an object without freezing it by default", function()
    local entity = Kora.entities.create(OBJECT_MODEL, { x = 0, y = 0, z = 0 })
    harness.assertTrue(entity ~= false, "expected the object to be created")
    harness.assertTrue(entityCalls[entity] == nil or entityCalls[entity].freeze == nil, "an object should not be frozen without an explicit option")
end)

harness.test("entity creation rejects non-finite spatial inputs", function()
    harness.assertThrows(function()
        Kora.entities.create(OBJECT_MODEL, { x = math.huge, y = 0, z = 0 })
    end, "infinite coordinates must not reach entity natives")
    harness.assertThrows(function()
        Kora.entities.create(OBJECT_MODEL, { x = 0, y = 0, z = 0 }, { heading = 0 / 0 })
    end, "NaN headings must not reach entity natives")
    harness.assertThrows(function()
        Kora.entities.createScoped(OBJECT_MODEL, { x = 0, y = 0, z = 0 }, { radius = math.huge })
    end, "infinite scoped radii must not create zones")
    harness.assertThrows(function()
        Kora.entities.create(OBJECT_MODEL, { x = 0, y = 0, z = 0 }, false)
    end, "non-table create options must be rejected")
    harness.assertThrows(function()
        Kora.entities.create(OBJECT_MODEL, { x = 0, y = 0, z = 0 }, { freeze = "yes" })
    end, "non-boolean entity options must be rejected")
    harness.assertThrows(function()
        Kora.entities.createScoped(OBJECT_MODEL, { x = 0, y = 0, z = 0 }, false)
    end, "non-table scoped options must be rejected")
end)

harness.test("an explicit freeze overrides having no preset", function()
    local entity = Kora.entities.create(VEHICLE_MODEL, { x = 0, y = 0, z = 0 }, { freeze = true })
    harness.assertEqual(entityCalls[entity].freeze, true, "explicit freeze=true should apply even without a preset")
end)

harness.test("an explicit invincible=false overrides the static preset", function()
    local entity = Kora.entities.create(PED_MODEL, { x = 0, y = 0, z = 0 }, { preset = "static", invincible = false })
    harness.assertTrue(entityCalls[entity].invincible == nil, "explicit invincible=false should prevent the static preset applying it")
end)

harness.test("remove deletes a tracked entity", function()
    local entity = Kora.entities.create(OBJECT_MODEL, { x = 0, y = 0, z = 0 })
    local ok = Kora.entities.remove(entity)
    harness.assertTrue(ok, "remove should report success")
    harness.assertFalse(_G.DoesEntityExist(entity), "the entity should no longer exist after remove")
end)

harness.test("only the owner can remove a tracked entity", function()
    _G.GetInvokingResource = function() return "entity_owner" end
    local entity = Kora.entities.create(OBJECT_MODEL, { x = 0, y = 0, z = 0 })

    _G.GetInvokingResource = function() return "other_resource" end
    local ok, err = Kora.entities.remove(entity)
    harness.assertFalse(ok, "a different resource should not remove the entity")
    harness.assertEqual(err, "Entity is not owned by the calling resource.")
    harness.assertTrue(_G.DoesEntityExist(entity), "a refused removal must leave the entity intact")

    _G.GetInvokingResource = function() return "entity_owner" end
    harness.assertTrue(Kora.entities.remove(entity), "the owner should be able to remove the entity")
    _G.GetInvokingResource = function() return nil end
end)

harness.test("remove reports failure for an already-removed entity", function()
    local entity = Kora.entities.create(OBJECT_MODEL, { x = 0, y = 0, z = 0 })
    Kora.entities.remove(entity)
    local ok, err = Kora.entities.remove(entity)
    harness.assertFalse(ok, "removing twice should fail the second time")
    harness.assertEqual(err, "Entity is not tracked by Kora.entities.", "should explain why removal failed")
end)

harness.test("remove refuses an entity this module never created", function()
    local foreignEntity = 424242
    existingEntities[foreignEntity] = true

    local ok, err = Kora.entities.remove(foreignEntity)

    harness.assertFalse(ok, "an untracked entity must be refused, not deleted")
    harness.assertEqual(err, "Entity is not tracked by Kora.entities.", "should explain the refusal")
    harness.assertTrue(_G.DoesEntityExist(foreignEntity), "the foreign entity must still exist")

    existingEntities[foreignEntity] = nil
end)

harness.test("create propagates a streaming failure for a model that never loads", function()
    local entity, err = Kora.entities.create(STUCK_MODEL, { x = 0, y = 0, z = 0 })
    harness.assertFalse(entity, "entity creation should fail when the model never streams in")
    harness.assertTrue(err ~= nil, "a streaming failure should come with an error message")
end)

harness.test("entities are auto-deleted when their owning resource stops", function()
    _G.GetInvokingResource = function() return "some_other_resource" end
    local entity = Kora.entities.create(OBJECT_MODEL, { x = 0, y = 0, z = 0 })
    _G.GetInvokingResource = function() return nil end

    harness.assertTrue(_G.DoesEntityExist(entity), "the entity should exist before its resource stops")

    net.fire("onClientResourceStop", "some_other_resource")

    harness.assertFalse(_G.DoesEntityExist(entity), "the entity should be deleted once its owning resource stops")
end)

harness.test("scoped entities spawn on entry, despawn on exit, and respawn with a fresh handle", function()
    local scope = Kora.entities.createScoped(OBJECT_MODEL, { x = 20, y = 30, z = 40 }, { radius = 75.0, freeze = true })
    local zone = scopedZones[#scopedZones]

    harness.assertTrue(scope.entity == nil, "scoped entities should not exist before entering their radius")
    harness.assertFalse(scope.isSpawned(), "the scope should report no active entity before entry")

    zone.opts.onEnter()
    local firstEntity = scope.entity
    harness.assertTrue(firstEntity ~= nil and _G.DoesEntityExist(firstEntity), "entering should create the local entity")
    harness.assertTrue(scope.isSpawned(), "the scope should report its newly active entity")
    harness.assertEqual(entityCalls[firstEntity].freeze, true, "normal entity options should apply to scoped spawns")

    zone.opts.onExit()
    harness.assertTrue(scope.entity == nil, "leaving should clear the transient entity handle")
    harness.assertFalse(_G.DoesEntityExist(firstEntity), "leaving should delete the local entity")

    zone.opts.onEnter()
    harness.assertTrue(scope.entity ~= nil and scope.entity ~= firstEntity, "a later entry should create a fresh local entity")

    scope.remove()
    harness.assertTrue(scope.entity == nil, "removing the scope should clear its entity handle")
    harness.assertTrue(zone.removed, "removing the scope should remove its backing zone")
end)

harness.test("scoped entities and their zones are removed when their owner stops", function()
    _G.GetInvokingResource = function() return "some_scoped_resource" end
    local scope = Kora.entities.createScoped(OBJECT_MODEL, { x = 20, y = 30, z = 40 }, { radius = 10.0 })
    _G.GetInvokingResource = function() return nil end
    local zone = scopedZones[#scopedZones]

    zone.opts.onEnter()
    local entity = scope.entity
    harness.assertTrue(_G.DoesEntityExist(entity), "the scoped entity should be live before owner cleanup")

    net.fire("onClientResourceStop", "some_scoped_resource")

    harness.assertTrue(scope.entity == nil, "owner cleanup should clear the scope handle")
    harness.assertFalse(_G.DoesEntityExist(entity), "owner cleanup should delete the active scoped entity")
    harness.assertTrue(zone.removed, "owner cleanup should unregister the backing zone")
end)

harness.test("only the owner can remove a scoped entity registration", function()
    _G.GetInvokingResource = function() return "scoped_owner" end
    local scope = Kora.entities.createScoped(OBJECT_MODEL, { x = 20, y = 30, z = 40 }, { radius = 10.0 })
    _G.GetInvokingResource = function() return "other_resource" end

    harness.assertFalse(scope.remove(), "a different resource must not remove the scope")

    _G.GetInvokingResource = function() return "scoped_owner" end
    harness.assertTrue(scope.remove(), "the owner should be able to remove the scope")
    harness.assertFalse(scope.remove(), "removing an already removed scope should fail")
    _G.GetInvokingResource = function() return nil end
end)

harness.test("scoped onSpawn/onDespawn hooks fire for each spawn and despawn", function()
    local spawned, despawned = {}, 0
    local scope = Kora.entities.createScoped(OBJECT_MODEL, { x = 20, y = 30, z = 40 }, {
        radius = 10.0,
        onSpawn = function(entity) spawned[#spawned + 1] = entity end,
        onDespawn = function() despawned = despawned + 1 end,
    })
    local zone = scopedZones[#scopedZones]

    zone.opts.onEnter()
    harness.assertEqual(#spawned, 1)
    harness.assertEqual(spawned[1], scope.entity, "onSpawn receives the live entity")
    zone.opts.onExit()
    harness.assertEqual(despawned, 1)

    zone.opts.onEnter()
    harness.assertEqual(#spawned, 2)
    scope.remove()
    harness.assertEqual(despawned, 2, "removing a spawned scope despawns through the hook")
    scope.remove()
    harness.assertEqual(despawned, 2, "a removed scope never despawns twice")
end)

harness.test("a failing scoped hook is logged and does not break the scope", function()
    local scope = Kora.entities.createScoped(OBJECT_MODEL, { x = 20, y = 30, z = 40 }, {
        radius = 10.0,
        onSpawn = function() error("spawn hook boom") end,
        onDespawn = function() error("despawn hook boom") end,
    })
    local zone = scopedZones[#scopedZones]
    local originalPrint = print
    _G.print = function() end
    zone.opts.onEnter()
    local entity = scope.entity
    zone.opts.onExit()
    _G.print = originalPrint

    harness.assertTrue(entity ~= nil, "the entity still spawns when onSpawn errors")
    harness.assertFalse(_G.DoesEntityExist(entity), "the entity still despawns when onDespawn errors")
    harness.assertThrows(function()
        Kora.entities.createScoped(OBJECT_MODEL, { x = 0, y = 0, z = 0 }, { radius = 1, onSpawn = 5 })
    end)
    scope.remove()
end)

harness.test("scoped entities require a positive radius", function()
    local ok = pcall(Kora.entities.createScoped, OBJECT_MODEL, { x = 0, y = 0, z = 0 }, {})
    harness.assertFalse(ok, "a scoped entity without a radius must be rejected")
end)

harness.test("a scope exit while streaming never leaves a late entity behind", function()
    local scope = Kora.entities.createScoped(DELAYED_MODEL, { x = 20, y = 30, z = 40 }, { radius = 10.0 })
    local zone = scopedZones[#scopedZones]

    zone.opts.onEnter()
    harness.assertTrue(scope.entity == nil, "the delayed model should not be spawned yet")

    zone.opts.onExit()
    delayedLoads[DELAYED_MODEL] = nil
    net.step()

    harness.assertTrue(scope.entity == nil, "the completed stream must not create an entity after exit")
    scope.remove()
end)

harness.test("re-entering while a model streams retains the completed entity", function()
    delayedLoads[DELAYED_MODEL] = true
    local scope = Kora.entities.createScoped(DELAYED_MODEL, { x = 20, y = 30, z = 40 }, { radius = 10.0 })
    local zone = scopedZones[#scopedZones]

    zone.opts.onEnter()
    zone.opts.onExit()
    zone.opts.onEnter()
    delayedLoads[DELAYED_MODEL] = nil
    net.step()

    harness.assertTrue(scope.entity ~= nil and _G.DoesEntityExist(scope.entity),
        "a re-entry during streaming should keep the entity completed by the in-flight spawn")
    scope.remove()
end)

harness.test("a scoped spawn exception clears its guard so a later entry can retry", function()
    throwSpawn = true
    local scope = Kora.entities.createScoped(THROW_MODEL, { x = 20, y = 30, z = 40 }, { radius = 10.0 })
    local zone = scopedZones[#scopedZones]

    zone.opts.onEnter()
    harness.assertTrue(scope.entity == nil, "a throwing creator must not leave an entity")
    zone.opts.onExit()
    throwSpawn = false
    zone.opts.onEnter()

    harness.assertTrue(scope.entity ~= nil and _G.DoesEntityExist(scope.entity),
        "the scope should retry after a prior spawn exception")
    scope.remove()
end)

harness.test('delete removes an authorized networked entity', function()
    local foreignEntity = 424243
    existingEntities[foreignEntity] = true
    local ok, err = Kora.entities.delete(foreignEntity)
    harness.assertTrue(ok, tostring(err))
    harness.assertFalse(_G.DoesEntityExist(foreignEntity), 'the authorized entity should be deleted')
end)

harness.test('network control rejects an invalid timeout before requesting control', function()
    local requests = 0
    local originalRequestControl = NetworkRequestControlOfEntity
    _G.NetworkRequestControlOfEntity = function()
        requests = requests + 1
    end

    harness.assertThrows(function() Kora.entities.requestControl(424243, false) end)
    harness.assertEqual(requests, 0, 'an invalid timeout should not request network control')

    _G.NetworkRequestControlOfEntity = originalRequestControl
end)

harness.test('requestControl acquires control for any existing entity type', function()
    local foreignEntity = 424244
    existingEntities[foreignEntity] = true
    hasNetworkControl = false

    local controlled, err = Kora.entities.requestControl(foreignEntity, 100)
    harness.assertTrue(controlled, tostring(err))
    harness.assertTrue(hasNetworkControl, 'the network control should be acquired')
end)

harness.report("entities")
