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

local modelType = { [PED_MODEL] = "ped", [VEHICLE_MODEL] = "vehicle" }
local neverLoads = { [STUCK_MODEL] = true }

local existingEntities = {}
local entityCalls = {}
local nextEntity = 0

function _G.IsModelValid() return true end
function _G.HasModelLoaded(model) return not neverLoads[model] end
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

dofile(repoRoot .. "modules/stream/client.lua")
dofile(repoRoot .. "local/resources/client.lua")
dofile(repoRoot .. "modules/entities/client.lua")

harness.test("creates a ped with the static preset frozen and blocked", function()
    local entity, err = QB.entities.create(PED_MODEL, { x = 1, y = 2, z = 3 }, { preset = "static" })
    harness.assertTrue(entity ~= false, "expected a real entity handle, got error: " .. tostring(err))
    harness.assertTrue(_G.DoesEntityExist(entity), "the created entity should exist")
    harness.assertEqual(entityCalls[entity].freeze, true, "the static preset should freeze the ped")
    harness.assertEqual(entityCalls[entity].blockNonTempEvents, true, "the static preset should block non-temp events on a ped")
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

harness.report("entities")
