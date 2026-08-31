local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")
local mockHandle = mocks.install()

dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "local/resources/client.lua")

local disabled = {}
local firingCalls = 0
local playerIdCalls = 0

function _G.DisableControlAction(group, control)
    disabled[#disabled + 1] = { group = group, control = control }
end

function _G.PlayerId()
    playerIdCalls = playerIdCalls + 1
    return 7
end

function _G.DisablePlayerFiring(player, disabledValue)
    harness.assertEqual(player, 7, "the current player ID should be forwarded")
    harness.assertTrue(disabledValue, "firing suppression should always pass true")
    firingCalls = firingCalls + 1
end

dofile(repoRoot .. "modules/controls/client.lua")

local function countControl(group, control)
    local count = 0
    for _, entry in ipairs(disabled) do
        if entry.group == group and entry.control == control then count = count + 1 end
    end
    return count
end

harness.test("acquire validates its inputs", function()
    harness.assertThrows(function() QB.controls.acquire({}) end, "an empty lease should fail")
    harness.assertThrows(function() QB.controls.acquire({ -1 }) end, "negative control IDs should fail")
    harness.assertThrows(function() QB.controls.acquire({ 1, [3] = 2 }) end, "sparse arrays should fail")
    harness.assertThrows(function() QB.controls.acquire({ 1 }, { inputGroup = 0.5 }) end,
        "fractional input groups should fail")
end)

harness.test("acquire applies immediately and the loop reapplies every frame", function()
    disabled = {}
    local lease = QB.controls.acquire({ 24, 24, 25 })

    harness.assertTrue(countControl(0, 24) >= 1, "attack should be disabled before acquire returns")
    harness.assertEqual(countControl(0, 24), countControl(0, 25), "duplicate IDs should be normalized")

    local before = countControl(0, 24)
    mockHandle.step()
    harness.assertTrue(countControl(0, 24) > before, "active controls should be reapplied on the next frame")
    harness.assertTrue(QB.controls.release(lease), "the lease should release once")
    harness.assertFalse(QB.controls.release(lease), "release should be idempotent")
end)

harness.test("overlapping leases retain shared controls until the final release", function()
    disabled = {}
    local first = QB.controls.acquire({ 30 })
    local second = QB.controls.acquire({ 30, 31 })

    QB.controls.release(first)
    disabled = {}
    mockHandle.step()
    harness.assertTrue(countControl(0, 30) > 0, "the second lease should retain the shared control")

    QB.controls.release(second)
    disabled = {}
    mockHandle.step()
    harness.assertEqual(#disabled, 0, "the loop should stop after the final lease releases")
end)

harness.test("input groups and firing suppression are forwarded", function()
    disabled = {}
    firingCalls = 0
    playerIdCalls = 0
    local lease = QB.controls.acquire({ 1 }, { inputGroup = 2, disablePlayerFiring = true })

    harness.assertTrue(countControl(2, 1) > 0, "the requested input group should be used")
    harness.assertTrue(firingCalls > 0 and playerIdCalls > 0, "firing should be disabled immediately")
    QB.controls.release(lease)
end)

harness.test("resource stop releases only that resource's leases", function()
    local currentOwner = "resource_a"
    _G.GetInvokingResource = function() return currentOwner end

    local a = QB.controls.acquire({ 40 })
    currentOwner = "resource_b"
    local b = QB.controls.acquire({ 41 })

    mockHandle.fire("onClientResourceStop", "resource_a")
    harness.assertFalse(QB.controls.release(a), "the stopped resource's lease should already be gone")
    harness.assertTrue(QB.controls.release(b), "another resource's lease should remain active")

    _G.GetInvokingResource = function() return nil end
end)

harness.test("the shared loop can restart after becoming idle", function()
    disabled = {}
    local lease = QB.controls.acquire({ 50 })
    QB.controls.release(lease)
    mockHandle.step()

    disabled = {}
    local restarted = QB.controls.acquire({ 51 })
    harness.assertTrue(countControl(0, 51) > 0, "a later lease should restart control handling")
    QB.controls.release(restarted)
end)

harness.report("controls")
