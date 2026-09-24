local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")
local mockHandle = mocks.install()

dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "local/resources/client.lua")
dofile(repoRoot .. "modules/util/shared.lua")

local disabled = {}
local firingCalls = 0
local playerIdCalls = 0
local weaponWheelCalls = 0

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

function _G.HudWeaponWheelIgnoreSelection() weaponWheelCalls = weaponWheelCalls + 1 end

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
    harness.assertThrows(function() QB.controls.acquire({ 1 }, false) end, "options must be a table")
    harness.assertThrows(function() QB.controls.acquire({ 1 }, { inputGroup = false }) end,
        "input groups must be integers")
    harness.assertThrows(function() QB.controls.acquire({ math.huge }) end,
        "infinite control IDs should fail")
    harness.assertThrows(function() QB.controls.acquire({ 1 }, { inputGroup = math.huge }) end,
        "infinite input groups should fail")
    for _, leaseId in ipairs({ 0, -1, 1.5, math.huge, '1' }) do
        harness.assertFalse(QB.controls.release(leaseId), "malformed lease IDs should be ignored")
    end
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

harness.test("weapon wheel suppression is composed and released", function()
    weaponWheelCalls = 0
    local lease = QB.controls.acquire({}, { ignoreWeaponWheel = true })
    harness.assertTrue(weaponWheelCalls > 0, "weapon wheel suppression should apply immediately")
    QB.controls.release(lease)
    local before = weaponWheelCalls
    mockHandle.step()
    harness.assertEqual(weaponWheelCalls, before, "released suppression should not run again")
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

harness.test("a resource cannot release another resource's lease", function()
    local currentOwner = "lease_owner"
    _G.GetInvokingResource = function() return currentOwner end
    local lease = QB.controls.acquire({ 42 })

    currentOwner = "other_resource"
    harness.assertFalse(QB.controls.release(lease), "a foreign resource must not release the lease")

    currentOwner = "lease_owner"
    harness.assertTrue(QB.controls.release(lease), "the owner should release its lease")
    _G.GetInvokingResource = function() return nil end
end)

harness.test('captured-owner cleanup releases an asynchronous consumer lease', function()
    local lease = QB.compat.acquireControls({ 43 }, nil, 'async_owner')

    _G.GetInvokingResource = function() return nil end
    harness.assertFalse(QB.controls.release(lease), 'the qblib continuation must not impersonate the consumer publicly')
    harness.assertTrue(QB.compat.releaseControlLease(lease, 'async_owner'),
        'the captured owner should release its lease after the export call has ended')
    harness.assertFalse(QB.compat.releaseControlLease(lease, 'other_owner'),
        'a mismatched captured owner must not release a lease')
end)

harness.test('a stopped asynchronous consumer releases its captured-owner lease', function()
    local lease = QB.compat.acquireControls({ 44 }, nil, 'stopped_async_owner')

    mockHandle.fire('onClientResourceStop', 'stopped_async_owner')
    harness.assertFalse(QB.compat.releaseControlLease(lease, 'stopped_async_owner'),
        'the resource-stop sweep should release a captured-owner lease')
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
