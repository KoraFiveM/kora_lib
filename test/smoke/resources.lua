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
    harness.assertTrue(QB.resources.isStarted("ready"))
    harness.assertFalse(QB.resources.isStarted("waiting"))
end)

harness.test("awaitStarted distinguishes started, missing, and timeout", function()
    _G.GetResourceState = function(name)
        if name == "ready" then return "started" end
        if name == "absent" then return "missing" end
        return "stopped"
    end

    harness.assertTrue(QB.resources.awaitStarted("ready"))
    local absent, absentReason = QB.resources.awaitStarted("absent")
    harness.assertFalse(absent)
    harness.assertEqual(absentReason, "missing")
    local waiting, waitingReason = QB.resources.awaitStarted("waiting", { timeout = 10, interval = 5 })
    harness.assertFalse(waiting)
    harness.assertEqual(waitingReason, "timeout")
end)

harness.test("track then owner reports the tracking resource", function()
    local disposed = {}
    local registry = QB.resources.registry(function(id) table.insert(disposed, id) end)

    registry.track("resource_a", 1)

    harness.assertEqual(registry.owner(1), "resource_a", "owner should report the resource that tracked the id")
end)

harness.test("untrack drops tracking and returns the prior owner, without calling onDispose", function()
    local disposed = {}
    local registry = QB.resources.registry(function(id) table.insert(disposed, id) end)

    registry.track("resource_a", 1)
    local owner = registry.untrack(1)

    harness.assertEqual(owner, "resource_a", "untrack should return the resource the id was owned by")
    harness.assertEqual(registry.owner(1), nil, "the id should no longer be tracked")
    harness.assertEqual(#disposed, 0, "untrack should not call onDispose")
end)

harness.test("untrack on an untracked id returns nil", function()
    local registry = QB.resources.registry(function() end)
    local owner = registry.untrack(999)
    harness.assertEqual(owner, nil, "untrack on an id that was never tracked should return nil")
end)

harness.test("re-tracking an id under a different resource transfers ownership, not just adds it", function()
    local disposed = {}
    local registry = QB.resources.registry(function(id) table.insert(disposed, id) end)

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
    local registry = QB.resources.registry(function(id) table.insert(disposed, id) end)

    registry.track("resource_a", 1)
    registry.track("resource_a", 1)

    net.fire("onClientResourceStop", "resource_a")
    harness.assertEqual(#disposed, 1, "re-tracking under the same owner should not duplicate the disposal")
end)

harness.test("onDispose fires for everything a resource still owns when it stops", function()
    local disposed = {}
    local registry = QB.resources.registry(function(id) table.insert(disposed, id) end)

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
    local registry = QB.resources.registry(function(id) table.insert(disposed, id) end)

    registry.track("resource_a", 1)
    registry.untrack(1)

    net.fire("onClientResourceStop", "resource_a")

    harness.assertEqual(#disposed, 0, "an already-untracked id should not be disposed again")
end)

harness.test("two registries track independent id spaces", function()
    local disposedA, disposedB = {}, {}
    local registryA = QB.resources.registry(function(id) table.insert(disposedA, id) end)
    local registryB = QB.resources.registry(function(id) table.insert(disposedB, id) end)

    registryA.track("resource_a", 1)
    registryB.track("resource_a", 1)

    net.fire("onClientResourceStop", "resource_a")

    harness.assertEqual(#disposedA, 1, "registryA should dispose its own id")
    harness.assertEqual(#disposedB, 1, "registryB should dispose its own id")
end)

harness.test("a client registry disposes tracked state when its creating resource stops", function()
    local disposed = {}
    local registry = QB.resources.registry(function(id) disposed[#disposed + 1] = id end)

    registry.track("resource_a", 1)
    net.fire("onClientResourceStop", "qblib_test")
    net.fire("onClientResourceStop", "resource_a")

    harness.assertEqual(#disposed, 1, "creator shutdown must release its tracked state")
    harness.assertEqual(registry.owner(1), nil, "creator shutdown should clear its bookkeeping")
end)

harness.test("a server registry disposes tracked state when its creating resource stops", function()
    local disposed = {}
    local registry = QB.resources.serverRegistry(function(id) disposed[#disposed + 1] = id end)

    registry.track("resource_a", 1)
    net.fire("onResourceStop", "qblib_test")
    net.fire("onResourceStop", "resource_a")

    harness.assertEqual(#disposed, 1, "creator shutdown must release its tracked state")
    harness.assertEqual(registry.owner(1), nil, "creator shutdown should clear its bookkeeping")
end)

harness.test("a disposal failure cannot abort the rest of a server registry sweep", function()
    local attempted = {}
    local registry = QB.resources.serverRegistry(function(id)
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

harness.report("resources")
