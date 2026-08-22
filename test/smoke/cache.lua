local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")

-- Scenario baked into these mocks: player 5 (server id 42), ped 100, sitting
-- in vehicle 200's seat 1 (not the driver, and not seat 0 -- proves
-- computeSeat's scan doesn't just check the first candidate), armed with
-- weapon hash 999. All specific to this module, so mocked here rather than
-- in test/mocks.lua per the root AGENTS.md testing convention.
_G.PlayerId = function() return 5 end
_G.GetPlayerServerId = function(playerId) return playerId == 5 and 42 or -1 end
_G.PlayerPedId = function() return 100 end
_G.IsPedInAnyVehicle = function() return true end
_G.GetVehiclePedIsIn = function() return 200 end
_G.GetVehicleMaxNumberOfPassengers = function() return 2 end
_G.GetPedInVehicleSeat = function(vehicle, seat)
    if seat == 1 then return 100 end -- our ped
    return 999999 -- someone/something else, or nobody
end
_G.GetSelectedPedWeapon = function() return 999 end
_G.GetEntityHealth = function() return 175 end
_G.GetPedArmour = function() return 50 end
_G.GetEntityCoords = function() return { x = 1.0, y = 2.0, z = 3.0 } end

dofile(repoRoot .. "local/resources/client.lua")
dofile(repoRoot .. "modules/cache/client.lua")

harness.test("playerId/serverId are read from the natives", function()
    harness.assertEqual(QB.cache.playerId(), 5, "playerId should come from PlayerId()")
    harness.assertEqual(QB.cache.serverId(), 42, "serverId should come from GetPlayerServerId(PlayerId())")
end)

harness.test("ped is read from PlayerPedId()", function()
    harness.assertEqual(QB.cache.ped(), 100, "ped should come from PlayerPedId()")
end)

harness.test("vehicle/seat are computed from the mocked scenario", function()
    harness.assertEqual(QB.cache.vehicle(), 200, "vehicle should come from GetVehiclePedIsIn")
    harness.assertEqual(QB.cache.seat(), 1, "seat should be found by scanning, not hardcoded to the driver seat")
end)

harness.test("weapon is read from GetSelectedPedWeapon()", function()
    harness.assertEqual(QB.cache.weapon(), 999, "weapon should come from GetSelectedPedWeapon()")
end)

harness.test("health/armour are read from the mocked natives via the shared ped local", function()
    harness.assertEqual(QB.cache.health(), 175, "health should come from GetEntityHealth(ped)")
    harness.assertEqual(QB.cache.armour(), 50, "armour should come from GetPedArmour(ped)")
end)

harness.test("set rejects every reserved built-in key outright", function()
    local reservedKeys = { "playerId", "serverId", "ped", "vehicle", "seat", "weapon", "health", "armour" }

    for _, key in ipairs(reservedKeys) do
        local before = QB.cache.get(key)
        QB.cache.set(key, "poisoned")
        harness.assertEqual(QB.cache.get(key), before, ("QB.cache.set('%s', ...) must be rejected, not applied"):format(key))
    end
end)

harness.test("get returns nil for a key nothing has set", function()
    harness.assertEqual(QB.cache.get("never-set"), nil, "an unset key should read as nil")
end)

harness.test("set stores a value retrievable via get", function()
    QB.cache.set("custom:value", "hello")
    harness.assertEqual(QB.cache.get("custom:value"), "hello", "set should be readable back via get")
end)

harness.test("set requires a non-empty string key", function()
    harness.assertThrows(function() QB.cache.set("", "x") end, "an empty key should be rejected")
    harness.assertThrows(function() QB.cache.set(nil, "x") end, "a nil key should be rejected")
end)

harness.test("onChange fires with the new and old value when set actually changes something", function()
    QB.cache.set("watched", "a")

    local seenNew, seenOld
    QB.cache.onChange("watched", function(newValue, oldValue)
        seenNew, seenOld = newValue, oldValue
    end)

    QB.cache.set("watched", "b")

    harness.assertEqual(seenNew, "b", "the handler should see the new value")
    harness.assertEqual(seenOld, "a", "the handler should see the previous value")
end)

harness.test("onChange does not fire when set is called with the same value", function()
    QB.cache.set("stable", "same")

    local calls = 0
    QB.cache.onChange("stable", function() calls = calls + 1 end)

    QB.cache.set("stable", "same")
    QB.cache.set("stable", "same")

    harness.assertEqual(calls, 0, "setting the same value again should not fire onChange")
end)

harness.test("multiple onChange handlers for the same key all run", function()
    local firstRan, secondRan = false, false
    QB.cache.onChange("multi", function() firstRan = true end)
    QB.cache.onChange("multi", function() secondRan = true end)

    QB.cache.set("multi", "go")

    harness.assertTrue(firstRan, "the first handler should have run")
    harness.assertTrue(secondRan, "the second handler should have run")
end)

harness.test("an erroring onChange handler doesn't stop other handlers or set itself", function()
    local secondRan = false
    QB.cache.onChange("boom", function() error("kaboom") end)
    QB.cache.onChange("boom", function() secondRan = true end)

    QB.cache.set("boom", "value")

    harness.assertTrue(secondRan, "a later handler should still run after an earlier one errors")
    harness.assertEqual(QB.cache.get("boom"), "value", "the value should still be stored despite a handler erroring")
end)

harness.test("offChange removes the calling resource's handlers for that key", function()
    local calls = 0
    QB.cache.onChange("off-target", function() calls = calls + 1 end)
    QB.cache.offChange("off-target")

    QB.cache.set("off-target", "changed")
    harness.assertEqual(calls, 0, "a removed handler must not fire")
end)

-- Placed last: fires onClientResourceStop for the mocked resource name
-- ("qblib_test", from GetCurrentResourceName()), which sweeps every handler
-- registered by any earlier test still holding one.
harness.test("onChange handlers are swept when their owning resource stops", function()
    local calls = 0
    QB.cache.onChange("sweep-target", function() calls = calls + 1 end)

    net.fire("onClientResourceStop", "some_other_resource")
    QB.cache.set("sweep-target", "first")
    harness.assertEqual(calls, 1, "an unrelated resource stopping must not sweep this handler")

    net.fire("onClientResourceStop", "qblib_test")
    QB.cache.set("sweep-target", "second")
    harness.assertEqual(calls, 1, "the owning resource stopping must sweep the handler")
end)

harness.report("cache")
