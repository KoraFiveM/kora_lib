local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

local realWait = Wait
local waits = {}
_G.Wait = function(ms)
    waits[#waits + 1] = ms
    return realWait(ms)
end

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/util/shared.lua")

-- Scenario baked into these mocks: player 5 (server id 42), ped 100, sitting
-- in vehicle 200's seat 1 (not the driver, and not seat 0 -- proves
-- computeSeat's scan doesn't just check the first candidate), armed with
-- weapon hash 999. All specific to this module, so mocked here rather than
-- in test/mocks.lua per the root AGENTS.md testing convention.
local playerIdReads, serverIdReads, seatReads, pedReads = 0, 0, 0, 0
local networkReady = false
local occupiedSeat = 1
local coords = { x = 1.0, y = 2.0, z = 3.0 }
_G.PlayerId = function() playerIdReads = playerIdReads + 1; return 5 end
_G.GetPlayerServerId = function(playerId)
    serverIdReads = serverIdReads + 1
    return playerId == 5 and networkReady and 42 or -1
end
_G.NetworkIsSessionStarted = function() return networkReady end
_G.PlayerPedId = function() pedReads = pedReads + 1 return 100 end
_G.IsPedInAnyVehicle = function() return true end
_G.GetVehiclePedIsIn = function() return 200 end
_G.GetVehiclePedIsTryingToEnter = function() return 0 end
_G.GetSeatPedIsTryingToEnter = function() return -1 end
_G.GetVehicleMaxNumberOfPassengers = function() return 2 end
_G.GetPedInVehicleSeat = function(vehicle, seat)
    seatReads = seatReads + 1
    if seat == occupiedSeat then return 100 end -- our ped
    return 999999 -- someone/something else, or nobody
end
_G.GetSelectedPedWeapon = function() return 999 end
_G.GetEntityHealth = function() return 175 end
_G.IsPedFatallyInjured = function() return false end
_G.GetPedArmour = function() return 50 end
_G.GetPlayerStamina = function() return 87.5 end
_G.GetEntityCoords = function() return { x = coords.x, y = coords.y, z = coords.z } end

dofile(repoRoot .. "local/resources/client.lua")
dofile(repoRoot .. "modules/cache/client.lua")

harness.test("initial telemetry is sampled once before the first interval", function()
    harness.assertEqual(pedReads, 1, "starting the worker must not repeat the initial native reads")
end)

harness.test("playerId/serverId are read from the natives", function()
    harness.assertEqual(QB.cache.playerId(), 5, "playerId should come from PlayerId()")
    harness.assertEqual(QB.cache.serverId(), -1, "serverId should retain its early-session sentinel")
end)

harness.test("serverId startup retry sleeps and recovers after networking starts", function()
    local sawRetryInterval = false
    for _, ms in ipairs(waits) do
        if ms == 250 then sawRetryInterval = true end
    end
    harness.assertTrue(sawRetryInterval, "an unavailable server ID must retry at the bounded 250ms interval")

    networkReady = true
    net.step()

    harness.assertEqual(QB.cache.serverId(), 42, "the retry worker should replace -1 once networking is ready")
end)

harness.test("telemetry refresh uses the validated configured interval", function()
    local sawRefreshInterval = false
    for _, ms in ipairs(waits) do
        if ms == Config.cache.tickInterval then sawRefreshInterval = true end
    end
    harness.assertTrue(sawRefreshInterval, "the shared refresh worker must use Config.cache.tickInterval")
end)

harness.test("stable player ids are not re-read by the telemetry tick", function()
    net.step()
    net.step()
    harness.assertEqual(playerIdReads, 1, "PlayerId should be resolved once per session")
    harness.assertEqual(serverIdReads, 2, "serverId should be re-read only once after the early-session sentinel")
end)

harness.test("ped is read from PlayerPedId()", function()
    harness.assertEqual(QB.cache.ped(), 100, "ped should come from PlayerPedId()")
end)

harness.test("coords are exposed through the named cached getter", function()
    local cachedCoords = QB.cache.coords()
    harness.assertEqual(cachedCoords.x, 1.0, "coords.x should come from the shared cache refresh")
    harness.assertEqual(cachedCoords.y, 2.0, "coords.y should come from the shared cache refresh")
    harness.assertEqual(cachedCoords.z, 3.0, "coords.z should come from the shared cache refresh")
end)

harness.test("coords change only when their components change", function()
    local calls, current, previous = 0
    QB.cache.onChange("coords", function(value, oldValue)
        calls, current, previous = calls + 1, value, oldValue
    end)

    net.step()
    harness.assertEqual(calls, 0, "a fresh native vector at the same position must not notify")

    coords.x = 4.0
    net.step()
    harness.assertEqual(calls, 1, "a real position change must notify once")
    harness.assertEqual(current.x, 4.0)
    harness.assertEqual(previous.x, 1.0)
end)

harness.test("vehicle/seat are computed from the mocked scenario", function()
    harness.assertEqual(QB.cache.vehicle(), 200, "vehicle should come from GetVehiclePedIsIn")
    harness.assertEqual(QB.cache.seat(), 1, "seat should be found by scanning, not hardcoded to the driver seat")
end)

harness.test("seat refresh validates the cached slot before rescanning", function()
    local before = seatReads
    net.step()
    harness.assertEqual(seatReads - before, 1, "a stable seat should cost one validation lookup")

    occupiedSeat = 0
    before = seatReads
    net.step()
    harness.assertEqual(QB.cache.seat(), 0, "a seat change should still be discovered")
    harness.assertTrue(seatReads - before > 1, "an invalid cached seat should trigger a full scan")
end)

harness.test("enteringVehicle/enteringSeat expose a current entry attempt", function()
    _G.GetVehiclePedIsTryingToEnter = function() return 300 end
    _G.GetSeatPedIsTryingToEnter = function() return -1 end

    local enteringVehicle, enteringSeat
    QB.cache.onChange("enteringVehicle", function(vehicle) enteringVehicle = vehicle end)
    QB.cache.onChange("enteringSeat", function(seat) enteringSeat = seat end)

    net.step()

    harness.assertEqual(QB.cache.enteringVehicle(), 300, "the attempted vehicle should be cached")
    harness.assertEqual(QB.cache.enteringSeat(), -1, "the attempted seat should be cached")
    harness.assertEqual(enteringVehicle, 300, "enteringVehicle should notify once on the edge")
    harness.assertEqual(enteringSeat, -1, "enteringSeat should notify once on the edge")

    _G.GetVehiclePedIsTryingToEnter = function() return 0 end
    net.step()
end)

harness.test("weapon is read from GetSelectedPedWeapon()", function()
    harness.assertEqual(QB.cache.weapon(), 999, "weapon should come from GetSelectedPedWeapon()")
end)

harness.test("health/armour are read from the mocked natives via the shared ped local", function()
    harness.assertEqual(QB.cache.health(), 175, "health should come from GetEntityHealth(ped)")
    harness.assertEqual(QB.cache.armour(), 50, "armour should come from GetPedArmour(ped)")
end)

harness.test("isDead follows IsPedFatallyInjured and notifies on the death edge", function()
    local fatallyInjured = false
    _G.IsPedFatallyInjured = function() return fatallyInjured end

    local seenNew, seenOld
    QB.cache.onChange("isDead", function(newValue, oldValue)
        seenNew, seenOld = newValue, oldValue
    end)

    fatallyInjured = true
    net.step()

    harness.assertTrue(QB.cache.isDead(), "isDead should use IsPedFatallyInjured rather than a health threshold")
    harness.assertTrue(seenNew, "the fatal-injury edge should notify subscribers")
    harness.assertFalse(seenOld, "the previous state should be alive")
end)

harness.test("stamina is read from the PLAYER index, not the ped", function()
    -- The one built-in keyed off PlayerId() rather than PlayerPedId(); a HUD
    -- reads it every tick while sprinting, so a wrong argument here would be a
    -- silently constant bar rather than an error.
    harness.assertEqual(QB.cache.stamina(), 87.5, "stamina should come from GetPlayerStamina(playerId)")
end)

harness.test("set rejects every reserved built-in key outright", function()
    local reservedKeys = { "playerId", "serverId", "ped", "vehicle", "seat", "enteringVehicle", "enteringSeat", "weapon", "health", "isDead", "armour", "stamina", "coords" }

    for _, key in ipairs(reservedKeys) do
        local before = QB.cache.get(key)
        QB.cache.set(key, "poisoned")
        harness.assertEqual(QB.cache.get(key), before, ("QB.cache.set('%s', ...) must be rejected, not applied"):format(key))
    end
end)

harness.test("get returns nil for a key nothing has set", function()
    harness.assertEqual(QB.cache.get("never-set"), nil, "an unset key should read as nil")
end)

harness.test("get requires a non-empty string key", function()
    harness.assertThrows(function() QB.cache.get("") end, "an empty key should be rejected")
    harness.assertThrows(function() QB.cache.get(nil) end, "a nil key should be rejected")
    harness.assertThrows(function() QB.cache.get(string.rep('x', 257)) end,
        'an oversized key should not enter the cache')
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

harness.test("a self-removing handler does not skip another resource's listener", function()
    local originalInvoker = GetInvokingResource
    local caller = "cache_owner"
    _G.GetInvokingResource = function() return caller end

    local ownCalls, otherCalls = 0, 0
    QB.cache.onChange("self-removing", function()
        ownCalls = ownCalls + 1
        caller = "cache_owner"
        QB.cache.offChange("self-removing")
    end)

    caller = "cache_other"
    QB.cache.onChange("self-removing", function() otherCalls = otherCalls + 1 end)

    QB.cache.set("self-removing", "first")
    harness.assertEqual(ownCalls, 1, "the self-removing listener should run once")
    harness.assertEqual(otherCalls, 1, "a shifted listener must still run")

    caller = "cache_other"
    QB.cache.set("self-removing", "second")
    harness.assertEqual(ownCalls, 1, "the removed listener must not run again")
    harness.assertEqual(otherCalls, 2, "the remaining listener should keep receiving updates")

    QB.cache.offChange("self-removing")
    _G.GetInvokingResource = originalInvoker
end)

harness.test("offChange removes the calling resource's handlers for that key", function()
    local calls = 0
    QB.cache.onChange("off-target", function() calls = calls + 1 end)
    QB.cache.offChange("off-target")

    QB.cache.set("off-target", "changed")
    harness.assertEqual(calls, 0, "a removed handler must not fire")
end)

-- Placed last: fires onClientResourceStop for the mocked resource name
-- ("kora_lib_test", from GetCurrentResourceName()), which sweeps every handler
-- registered by any earlier test still holding one.
harness.test("onChange handlers are swept when their owning resource stops", function()
    local calls = 0
    QB.cache.onChange("sweep-target", function() calls = calls + 1 end)

    net.fire("onClientResourceStop", "some_other_resource")
    QB.cache.set("sweep-target", "first")
    harness.assertEqual(calls, 1, "an unrelated resource stopping must not sweep this handler")

    net.fire("onClientResourceStop", "kora_lib_test")
    QB.cache.set("sweep-target", "second")
    harness.assertEqual(calls, 1, "the owning resource stopping must sweep the handler")
end)

harness.report("cache")
