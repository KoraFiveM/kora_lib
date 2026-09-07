local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/loops/shared.lua")

local PED_MODEL = 1001
local VEHICLE_MODEL = 2001
local OBJECT_MODEL = 3001
local STUCK_MODEL = 9999 -- never reports as loaded, to exercise entities.create's failure path
local DELAYED_MODEL = 4001 -- streams after the scope exits, to exercise the async cleanup path

local modelType = { [PED_MODEL] = "ped", [VEHICLE_MODEL] = "vehicle" }
local neverLoads = { [STUCK_MODEL] = true }
local delayedLoads = { [DELAYED_MODEL] = true }

local existingEntities = {}
local entityCalls = {}
local nextEntity = 0

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
function _G.CreateObjectNoOffset() return spawn() end
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
function _G.NetworkHasControlOfEntity() return true end
function _G.NetworkRequestControlOfEntity() end
function _G.SetEntityAsMissionEntity() end

dofile(repoRoot .. "modules/stream/client.lua")
dofile(repoRoot .. "local/resources/client.lua")

-- Scoped entities delegate distance tracking to zones. Keep this test focused
-- on the entity lifecycle by using a tiny zone double and triggering its
-- enter/exit callbacks explicitly; zones.lua covers the real spatial grid.
local scopedZones = {}
QB.zones = {
    sphere = function(opts)
        local zone = { removed = false, opts = opts }
        function zone.remove() zone.removed = true end
        scopedZones[#scopedZones + 1] = zone
        return zone
    end,
}

dofile(repoRoot .. "modules/entities/client.lua")

harness.test("creates a ped with the static preset frozen, blocked, and invincible", function()
    local entity, err = QB.entities.create(PED_MODEL, { x = 1, y = 2, z = 3 }, { preset = "static" })
    harness.assertTrue(entity ~= false, "expected a real entity handle, got error: " .. tostring(err))
    harness.assertTrue(_G.DoesEntityExist(entity), "the created entity should exist")
    harness.assertEqual(entityCalls[entity].freeze, true, "the static preset should freeze the ped")
    harness.assertEqual(entityCalls[entity].blockNonTempEvents, true, "the static preset should block non-temp events on a ped")
    harness.assertEqual(entityCalls[entity].invincible, true, "the static preset should make the ped invincible")
end)

harness.test("creates an object without freezing it by default", function()
    local entity = QB.entities.create(OBJECT_MODEL, { x = 0, y = 0, z = 0 })
    harness.assertTrue(entity ~= false, "expected the object to be created")
    harness.assertTrue(entityCalls[entity] == nil or entityCalls[entity].freeze == nil, "an object should not be frozen without an explicit option")
end)

harness.test("an explicit freeze overrides having no preset", function()
    local entity = QB.entities.create(VEHICLE_MODEL, { x = 0, y = 0, z = 0 }, { freeze = true })
    harness.assertEqual(entityCalls[entity].freeze, true, "explicit freeze=true should apply even without a preset")
end)

harness.test("an explicit invincible=false overrides the static preset", function()
    local entity = QB.entities.create(PED_MODEL, { x = 0, y = 0, z = 0 }, { preset = "static", invincible = false })
    harness.assertTrue(entityCalls[entity].invincible == nil, "explicit invincible=false should prevent the static preset applying it")
end)

harness.test("remove deletes a tracked entity", function()
    local entity = QB.entities.create(OBJECT_MODEL, { x = 0, y = 0, z = 0 })
    local ok = QB.entities.remove(entity)
    harness.assertTrue(ok, "remove should report success")
    harness.assertFalse(_G.DoesEntityExist(entity), "the entity should no longer exist after remove")
end)

harness.test("remove reports failure for an already-removed entity", function()
    local entity = QB.entities.create(OBJECT_MODEL, { x = 0, y = 0, z = 0 })
    QB.entities.remove(entity)
    local ok, err = QB.entities.remove(entity)
    harness.assertFalse(ok, "removing twice should fail the second time")
    harness.assertEqual(err, "Entity is not tracked by QB.entities.", "should explain why removal failed")
end)

harness.test("remove refuses an entity this module never created", function()
    local foreignEntity = 424242
    existingEntities[foreignEntity] = true

    local ok, err = QB.entities.remove(foreignEntity)

    harness.assertFalse(ok, "an untracked entity must be refused, not deleted")
    harness.assertEqual(err, "Entity is not tracked by QB.entities.", "should explain the refusal")
    harness.assertTrue(_G.DoesEntityExist(foreignEntity), "the foreign entity must still exist")

    existingEntities[foreignEntity] = nil
end)

harness.test("create propagates a streaming failure for a model that never loads", function()
    local entity, err = QB.entities.create(STUCK_MODEL, { x = 0, y = 0, z = 0 })
    harness.assertFalse(entity, "entity creation should fail when the model never streams in")
    harness.assertTrue(err ~= nil, "a streaming failure should come with an error message")
end)

harness.test("entities are auto-deleted when their owning resource stops", function()
    _G.GetInvokingResource = function() return "some_other_resource" end
    local entity = QB.entities.create(OBJECT_MODEL, { x = 0, y = 0, z = 0 })
    _G.GetInvokingResource = function() return nil end

    harness.assertTrue(_G.DoesEntityExist(entity), "the entity should exist before its resource stops")

    net.fire("onClientResourceStop", "some_other_resource")

    harness.assertFalse(_G.DoesEntityExist(entity), "the entity should be deleted once its owning resource stops")
end)

harness.test("scoped entities spawn on entry, despawn on exit, and respawn with a fresh handle", function()
    local scope = QB.entities.createScoped(OBJECT_MODEL, { x = 20, y = 30, z = 40 }, { radius = 75.0, freeze = true })
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
    local scope = QB.entities.createScoped(OBJECT_MODEL, { x = 20, y = 30, z = 40 }, { radius = 10.0 })
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

harness.test("scoped entities require a positive radius", function()
    local ok = pcall(QB.entities.createScoped, OBJECT_MODEL, { x = 0, y = 0, z = 0 }, {})
    harness.assertFalse(ok, "a scoped entity without a radius must be rejected")
end)

harness.test("a scope exit while streaming never leaves a late entity behind", function()
    local scope = QB.entities.createScoped(DELAYED_MODEL, { x = 20, y = 30, z = 40 }, { radius = 10.0 })
    local zone = scopedZones[#scopedZones]

    zone.opts.onEnter()
    harness.assertTrue(scope.entity == nil, "the delayed model should not be spawned yet")

    zone.opts.onExit()
    delayedLoads[DELAYED_MODEL] = nil
    net.step()

    harness.assertTrue(scope.entity == nil, "the completed stream must not create an entity after exit")
    scope.remove()
end)

harness.test('delete removes an authorized networked entity', function()
    local foreignEntity = 424243
    existingEntities[foreignEntity] = true
    local ok, err = QB.entities.delete(foreignEntity)
    harness.assertTrue(ok, tostring(err))
    harness.assertFalse(_G.DoesEntityExist(foreignEntity), 'the authorized entity should be deleted')
end)

harness.report("entities")
