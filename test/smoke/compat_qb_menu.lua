local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")

-- Real modules/nui/client.lua isn't loaded here (that's modules/nui's own
-- smoke test) -- same "mock QB.nui directly, resolve synchronously" trick
-- test/smoke/minigames.lua uses, since compat/client/qb-menu.lua's openMenu
-- has to consume QB.nui.openMenu's result itself (to know which legacy
-- event to fire), not just hand a promise back to its own caller.
local sentItems = nil
local nextMenuResult = nil

QB.nui = {
    openMenu = function(items)
        sentItems = items
        local p = promise.new()
        p:resolve(nextMenuResult)
        return p
    end,
    send = function(action)
        harness.assertEqual(action, 'closeMenu', 'closeMenu should ask the active menu to cancel')
    end,
}

dofile(repoRoot .. "compat/client/qb-menu.lua")

-- Mirrors what a real cross-resource exports['qb-menu']:Fn() call does under
-- the hood: fire the __cfx_export_ event with a setCB stub and capture what
-- gets passed to it.
local function getExport(providedResource, exportName)
    local handlers = net.eventHandlers[("__cfx_export_%s_%s"):format(providedResource, exportName)]
    harness.assertTrue(handlers ~= nil and handlers[1] ~= nil, exportName .. " should be registered")

    local captured
    handlers[1](function(fn) captured = fn end)
    return captured
end

local openMenu = getExport("qb-menu", "openMenu")
local closeMenu = getExport("qb-menu", "closeMenu")

harness.test("openMenu translates header/txt/disabled onto label/description/disabled", function()
    nextMenuResult = { cancelled = true }
    openMenu({
        { header = "Open Trunk", txt = "Pop the trunk" },
        { header = "Locked", disabled = true },
    })

    harness.assertEqual(sentItems[1].id, "1", "items should get a synthesized 1-based id")
    harness.assertEqual(sentItems[1].label, "Open Trunk", "header should map to label")
    harness.assertEqual(sentItems[1].description, "Pop the trunk", "txt should map to description")
    harness.assertFalse(sentItems[1].disabled, "an item with no disabled/isMenuHeader should not be disabled")
    harness.assertTrue(sentItems[2].disabled, "disabled should pass through")
end)

harness.test("isMenuHeader rows map onto disabled, matching real qb-menu's unselectable section labels", function()
    nextMenuResult = { cancelled = true }
    openMenu({ { header = "Section", isMenuHeader = true } })

    harness.assertTrue(sentItems[1].disabled, "isMenuHeader should map to disabled")
end)

-- TriggerEvent firing isn't recorded anywhere in test/mocks.lua (only the
-- client<->server crossing triggers are), so this registers its own listener
-- via AddEventHandler to observe what actually fired.
harness.test("selecting an item with a client event passes qb-menu's args table as one value", function()
    local received
    AddEventHandler("vehicle:repair", function(args) received = args end)

    nextMenuResult = { selectedId = "1" }
    openMenu({ { header = "Repair", params = { event = "vehicle:repair", args = { "abc", 5 } } } })

    harness.assertTrue(received ~= nil, "the client event should have fired")
    harness.assertEqual(received[1], "abc", "args should remain a table")
    harness.assertEqual(received[2], 5, "args should preserve every element")
end)

harness.test("selecting an item with isServer fires TriggerServerEvent", function()
    nextMenuResult = { selectedId = "1" }
    openMenu({ { header = "Buy", params = { event = "shop:buy", isServer = true, args = { "water" } } } })

    local sent = mocks.lastEntry(net.triggeredServerEvents, "shop:buy")
    harness.assertTrue(sent ~= nil, "TriggerServerEvent should have fired")
    harness.assertEqual(sent[1][1], "water", "args should remain one server-event table")
end)

harness.test("selecting an item with no params fires nothing and does not error", function()
    local before = #net.triggeredServerEvents
    nextMenuResult = { selectedId = "1" }
    openMenu({ { header = "Just close" } })

    harness.assertEqual(#net.triggeredServerEvents, before, "no server event should fire for a paramless item")
end)

harness.test("a cancelled result fires nothing", function()
    local before = #net.triggeredServerEvents
    nextMenuResult = { cancelled = true }
    openMenu({ { header = "Buy", params = { event = "shop:buy", isServer = true } } })

    harness.assertEqual(#net.triggeredServerEvents, before, "cancelling should never dispatch an event")
end)

harness.test("openMenu rejects a non-table menu", function()
    harness.assertThrows(function() openMenu("not a table") end, "a non-table menu should be rejected")
end)

harness.test("closeMenu force-dismisses through the NUI cancellation action", function()
    local ok = pcall(closeMenu)
    harness.assertTrue(ok, "closeMenu should not error")
end)

harness.test("the qb-menu:client:openMenu net event drives the same flow as the export", function()
    local received
    AddEventHandler("net:test:fired", function() received = true end)

    nextMenuResult = { selectedId = "1" }
    net.fire("qb-menu:client:openMenu", { { header = "Go", params = { event = "net:test:fired" } } })

    harness.assertTrue(received, "the net event should open a menu and dispatch selection the same as the export")
end)

harness.test("the qb-menu:client:closeMenu net event does not error", function()
    local ok = pcall(net.fire, "qb-menu:client:closeMenu")
    harness.assertTrue(ok, "the closeMenu net event should not error")
end)

harness.report("compat_qb_menu")
