local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/util/shared.lua")
dofile(repoRoot .. "local/resources/shared.lua")
dofile(repoRoot .. "local/resources/client.lua")
dofile(repoRoot .. "local/resources/server.lua")

harness.test("isStarted reports only the started state", function()
    _G.GetResourceState = function(name) return name == "ready" and "started" or "stopped" end
    harness.assertTrue(Kora.resources.isStarted("ready"))
    harness.assertFalse(Kora.resources.isStarted("waiting"))
    harness.assertThrows(function() Kora.resources.isStarted(string.rep('x', 257)) end)
end)

harness.test("awaitStarted distinguishes started, missing, and timeout", function()
    _G.GetResourceState = function(name)
        if name == "ready" then return "started" end
        if name == "absent" then return "missing" end
        return "stopped"
    end

    harness.assertTrue(Kora.resources.awaitStarted("ready"))
    local absent, absentReason = Kora.resources.awaitStarted("absent")
    harness.assertFalse(absent)
    harness.assertEqual(absentReason, "missing")
    local waiting, waitingReason = Kora.resources.awaitStarted("waiting", { timeout = 10, interval = 5 })
    harness.assertFalse(waiting)
    harness.assertEqual(waitingReason, "timeout")
end)

harness.test('awaitStarted honors explicit zero timeout and interval values', function()
    local getResourceState, wait = GetResourceState, Wait
    local calls, waited = 0, nil
    _G.GetResourceState = function()
        calls = calls + 1
        return 'stopped'
    end
    _G.Wait = function(ms) waited = ms end

    local ready, reason = Kora.resources.awaitStarted('waiting', { timeout = 0, interval = 0 })
    harness.assertFalse(ready)
    harness.assertEqual(reason, 'timeout')
    harness.assertEqual(calls, 1, 'a zero timeout should make exactly one immediate state check')
    harness.assertEqual(waited, nil, 'a zero timeout must not wait')

    calls, waited = 0, nil
    _G.GetResourceState = function()
        calls = calls + 1
        return calls == 1 and 'stopped' or 'started'
    end
    ready = Kora.resources.awaitStarted('starting', { timeout = 100, interval = 0 })
    _G.GetResourceState, _G.Wait = getResourceState, wait

    harness.assertTrue(ready)
    harness.assertEqual(waited, 0, 'an explicit zero interval should reach Wait unchanged')
end)

harness.test('awaitStarted rejects an explicit non-table options value', function()
    harness.assertThrows(function()
        Kora.resources.awaitStarted('waiting', false)
    end)
end)

harness.test("track then owner reports the tracking resource", function()
    local disposed = {}
    local registry = Kora.resources.registry(function(id) table.insert(disposed, id) end)

    registry.track("resource_a", 1)

    harness.assertEqual(registry.owner(1), "resource_a", "owner should report the resource that tracked the id")
end)

harness.test("registry accepts a callable-table disposer like a FiveM funcref", function()
    local disposed = {}
    local callable = setmetatable({}, {
        __call = function(_, id) disposed[#disposed + 1] = id end,
    })
    local registry = Kora.resources.registry(callable)
    registry.track("resource_a", 7)
    net.fire("onClientResourceStop", "resource_a")
    harness.assertEqual(disposed[1], 7)
end)

harness.test('registry factories reject invalid disposers immediately', function()
    harness.assertThrows(function() Kora.resources.registry(false) end)
    harness.assertThrows(function() Kora.resources.serverRegistry(nil) end)
end)

harness.test('registry methods reject invalid owners and ids immediately', function()
    local client = Kora.resources.registry(function() end)
    local server = Kora.resources.serverRegistry(function() end)
    for _, registry in ipairs({ client, server }) do
        harness.assertThrows(function() registry.track('', 1) end)
        harness.assertThrows(function() registry.track(string.rep('x', 257), 1) end)
        harness.assertThrows(function() registry.track('resource_a', nil) end)
        harness.assertThrows(function() registry.untrack(nil) end)
        harness.assertThrows(function() registry.owner(nil) end)
    end
end)

harness.test("untrack drops tracking and returns the prior owner, without calling onDispose", function()
    local disposed = {}
    local registry = Kora.resources.registry(function(id) table.insert(disposed, id) end)

    registry.track("resource_a", 1)
    local owner = registry.untrack(1)

    harness.assertEqual(owner, "resource_a", "untrack should return the resource the id was owned by")
    harness.assertEqual(registry.owner(1), nil, "the id should no longer be tracked")
    harness.assertEqual(#disposed, 0, "untrack should not call onDispose")
end)

harness.test("untrack on an untracked id returns nil", function()
    local registry = Kora.resources.registry(function() end)
    local owner = registry.untrack(999)
    harness.assertEqual(owner, nil, "untrack on an id that was never tracked should return nil")
end)

harness.test("re-tracking an id under a different resource transfers ownership, not just adds it", function()
    local disposed = {}
    local registry = Kora.resources.registry(function(id) table.insert(disposed, id) end)

    registry.track("resource_a", "shared_name")
    registry.track("resource_b", "shared_name")

    harness.assertEqual(registry.owner("shared_name"), "resource_b", "the second track should win ownership")

    net.fire("onClientResourceStop", "resource_a")
    harness.assertEqual(#disposed, 0, "resource_a no longer owns the id, so its stop must not dispose it")
    harness.assertEqual(registry.owner("shared_name"), "resource_b", "resource_b's ownership must survive resource_a stopping")

    net.fire("onClientResourceStop", "resource_b")
    harness.assertEqual(#disposed, 1, "resource_b still owned the id, so its stop should dispose it")
    harness.assertEqual(disposed[1], "shared_name", "the disposed id should be the shared name")
end)

harness.test("re-tracking an id under its own resource is a harmless no-op", function()
    local disposed = {}
    local registry = Kora.resources.registry(function(id) table.insert(disposed, id) end)

    registry.track("resource_a", 1)
    registry.track("resource_a", 1)

    net.fire("onClientResourceStop", "resource_a")
    harness.assertEqual(#disposed, 1, "re-tracking under the same owner should not duplicate the disposal")
end)

harness.test("onDispose fires for everything a resource still owns when it stops", function()
    local disposed = {}
    local registry = Kora.resources.registry(function(id) table.insert(disposed, id) end)

    registry.track("resource_a", 1)
    registry.track("resource_a", 2)
    registry.track("resource_b", 3)

    net.fire("onClientResourceStop", "resource_a")

    table.sort(disposed)
    harness.assertEqual(#disposed, 2, "only resource_a's ids should be disposed")
    harness.assertEqual(disposed[1], 1, "id 1 should have been disposed")
    harness.assertEqual(disposed[2], 2, "id 2 should have been disposed")
    harness.assertEqual(registry.owner(3), "resource_b", "resource_b's id should be untouched")
end)

harness.test("onDispose does not fire for ids already untracked before their resource stops", function()
    local disposed = {}
    local registry = Kora.resources.registry(function(id) table.insert(disposed, id) end)

    registry.track("resource_a", 1)
    registry.untrack(1)

    net.fire("onClientResourceStop", "resource_a")

    harness.assertEqual(#disposed, 0, "an already-untracked id should not be disposed again")
end)

harness.test('a disposer cannot recreate ownership for its stopping resource', function()
    for _, realm in ipairs({
        { create = Kora.resources.registry, event = 'onClientResourceStop' },
        { create = Kora.resources.serverRegistry, event = 'onResourceStop' },
    }) do
        local registry
        registry = realm.create(function()
            registry.track('resource_a', 'replacement')
        end)
        registry.track('resource_a', 'original')

        net.fire(realm.event, 'resource_a')

        harness.assertEqual(registry.owner('original'), nil)
        harness.assertEqual(registry.owner('replacement'), nil)
    end
end)

harness.test("two registries track independent id spaces", function()
    local disposedA, disposedB = {}, {}
    local registryA = Kora.resources.registry(function(id) table.insert(disposedA, id) end)
    local registryB = Kora.resources.registry(function(id) table.insert(disposedB, id) end)

    registryA.track("resource_a", 1)
    registryB.track("resource_a", 1)

    net.fire("onClientResourceStop", "resource_a")

    harness.assertEqual(#disposedA, 1, "registryA should dispose its own id")
    harness.assertEqual(#disposedB, 1, "registryB should dispose its own id")
end)

harness.test("a client registry disposes tracked state when its creating resource stops", function()
    local disposed = {}
    local registry = Kora.resources.registry(function(id) disposed[#disposed + 1] = id end)

    registry.track("resource_a", 1)
    net.fire("onClientResourceStop", "kora_lib_test")
    net.fire("onClientResourceStop", "resource_a")

    harness.assertEqual(#disposed, 1, "creator shutdown must release its tracked state")
    harness.assertEqual(registry.owner(1), nil, "creator shutdown should clear its bookkeeping")
end)

harness.test("a server registry disposes tracked state when its creating resource stops", function()
    local disposed = {}
    local registry = Kora.resources.serverRegistry(function(id) disposed[#disposed + 1] = id end)

    registry.track("resource_a", 1)
    net.fire("onResourceStop", "kora_lib_test")
    net.fire("onResourceStop", "resource_a")

    harness.assertEqual(#disposed, 1, "creator shutdown must release its tracked state")
    harness.assertEqual(registry.owner(1), nil, "creator shutdown should clear its bookkeeping")
end)

harness.test("a disposal failure cannot abort the rest of a server registry sweep", function()
    local attempted = {}
    local registry = Kora.resources.serverRegistry(function(id)
        attempted[id] = true
        if id == "bad" then error("simulated cleanup failure") end
    end)

    registry.track("resource_a", "bad")
    registry.track("resource_a", "good")
    net.fire("onResourceStop", "resource_a")

    harness.assertTrue(attempted.bad, "the failing disposal should be attempted")
    harness.assertTrue(attempted.good, "the sweep should continue after another disposal fails")
    harness.assertEqual(registry.owner("bad"), nil, "the failed id should still be untracked")
    harness.assertEqual(registry.owner("good"), nil, "the successful id should be untracked")
end)

-- H5: onStart / onStop / off. The realm is chosen on first use, so the client
-- realm is pinned here and the server realm gets a fresh load further down.
local resourceStates = {}
_G.GetResourceState = function(name) return resourceStates[name] or "missing" end
_G.IsDuplicityVersion = function() return false end

local function asResource(name, fn)
    local previous = _G.GetInvokingResource
    _G.GetInvokingResource = function() return name end
    local results = table.pack(fn())
    _G.GetInvokingResource = previous
    return table.unpack(results, 1, results.n)
end

harness.test("onStart runs now when the resource is started, then again on every restart", function()
    resourceStates.kora_target = "started"
    local runs = {}
    asResource("consumer_a", function()
        return Kora.resources.onStart("kora_target", function(name) runs[#runs + 1] = name end)
    end)
    harness.assertEqual(#runs, 1, "runNow defaults to true for a started resource")
    harness.assertEqual(runs[1], "kora_target", "the handler receives the resource name")

    net.fire("onClientResourceStart", "something_else")
    harness.assertEqual(#runs, 1, "other resources must not trigger the handler")
    net.fire("onClientResourceStart", "kora_target")
    harness.assertEqual(#runs, 2)
    net.fire("onClientResourceStart", "kora_target")
    harness.assertEqual(#runs, 3)
end)

harness.test("onStart waits for a stopped resource and honours runNow = false", function()
    resourceStates.late = "stopped"
    resourceStates.early = "started"
    local lateRuns, earlyRuns = 0, 0
    asResource("consumer_b", function()
        Kora.resources.onStart("late", function() lateRuns = lateRuns + 1 end)
        Kora.resources.onStart("early", function() earlyRuns = earlyRuns + 1 end, { runNow = false })
    end)
    harness.assertEqual(lateRuns, 0, "a stopped resource does not run now")
    harness.assertEqual(earlyRuns, 0, "runNow = false skips the immediate run")
    net.fire("onClientResourceStart", "late")
    net.fire("onClientResourceStart", "early")
    harness.assertEqual(lateRuns, 1)
    harness.assertEqual(earlyRuns, 1)
end)

harness.test("onStop runs when the watched resource stops", function()
    local stops = 0
    asResource("consumer_c", function()
        Kora.resources.onStop("kora_inventory", function() stops = stops + 1 end)
    end)
    net.fire("onClientResourceStop", "kora_inventory")
    harness.assertEqual(stops, 1)
end)

harness.test("handlers are dropped when the registering resource stops", function()
    resourceStates.watched = "stopped"
    local starts, stops = 0, 0
    asResource("consumer_d", function()
        Kora.resources.onStart("watched", function() starts = starts + 1 end)
        Kora.resources.onStop("watched", function() stops = stops + 1 end)
    end)
    net.fire("onClientResourceStop", "consumer_d")
    net.fire("onClientResourceStart", "watched")
    net.fire("onClientResourceStop", "watched")
    harness.assertEqual(starts, 0)
    harness.assertEqual(stops, 0)
end)

harness.test("off removes one handler; only its owner can remove it", function()
    resourceStates.watched2 = "stopped"
    local runs = 0
    local id = asResource("consumer_e", function()
        return Kora.resources.onStart("watched2", function() runs = runs + 1 end)
    end)
    harness.assertFalse(asResource("intruder", function() return Kora.resources.off(id) end),
        "another resource cannot remove the handler")
    harness.assertTrue(asResource("consumer_e", function() return Kora.resources.off(id) end))
    harness.assertFalse(asResource("consumer_e", function() return Kora.resources.off(id) end))
    net.fire("onClientResourceStart", "watched2")
    harness.assertEqual(runs, 0)
end)

harness.test("an erroring handler is logged and does not block the others", function()
    resourceStates.flaky = "stopped"
    local otherRuns = 0
    asResource("consumer_f", function()
        Kora.resources.onStart("flaky", function() error("boom") end)
        Kora.resources.onStart("flaky", function() otherRuns = otherRuns + 1 end)
    end)
    local printed = {}
    local originalPrint = print
    _G.print = function(message) printed[#printed + 1] = tostring(message) end
    net.fire("onClientResourceStart", "flaky")
    _G.print = originalPrint
    harness.assertEqual(otherRuns, 1)
    harness.assertTrue(printed[1] and printed[1]:find("boom", 1, true) ~= nil)
end)

harness.test("onStart/onStop reject invalid arguments", function()
    harness.assertThrows(function() Kora.resources.onStart("", function() end) end)
    harness.assertThrows(function() Kora.resources.onStart("x", "nope") end)
    harness.assertThrows(function() Kora.resources.onStart("x", function() end, { runNow = 1 }) end)
    harness.assertThrows(function() Kora.resources.onStop("x", nil) end)
end)

harness.test("server realm listens to onResourceStart/onResourceStop", function()
    local serverNet = mocks.install()
    _G.GetResourceState = function() return "stopped" end
    _G.IsDuplicityVersion = function() return true end
    dofile(repoRoot .. "build/initiate.lua")
    dofile(repoRoot .. "modules/util/shared.lua")
    dofile(repoRoot .. "local/resources/shared.lua")
    dofile(repoRoot .. "local/resources/server.lua")

    local starts, stops = 0, 0
    Kora.resources.onStart("kora_core", function() starts = starts + 1 end)
    Kora.resources.onStop("kora_core", function() stops = stops + 1 end)
    serverNet.fire("onClientResourceStart", "kora_core")
    serverNet.fire("onResourceStart", "kora_core")
    serverNet.fire("onResourceStop", "kora_core")
    harness.assertEqual(starts, 1)
    harness.assertEqual(stops, 1)
end)

harness.report("resources")
