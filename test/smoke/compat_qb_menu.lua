local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")

-- Controllable mock kora_core shared-item registry -- imageFor (in
-- compat/client/qb-menu.lua) reads item definitions via
-- exports.kora_core:getShared('items', key), pcall-guarded, same pattern as
-- compat_qb_radialmenu.lua's exports.kora_core mock.
local sharedItems = {}
_G.exports = {
    kora_core = {
        getShared = function(_, collection, key)
            if collection == 'items' then return sharedItems[key] end
            return nil
        end,
    },
}

-- Mock Kora.nui directly and resolve synchronously: openMenu must consume
-- Kora.nui.openMenu's result itself to know which legacy event to fire.
local sentItems = nil
local nextMenuResult = nil
local sentActions = {}
local playerFocus

Kora.nui = {
    openMenu = function(items)
        sentItems = items
        local p = promise.new()
        p:resolve(nextMenuResult)
        return p
    end,
    send = function(action, data)
        sentActions[#sentActions + 1] = { action = action, data = data }
    end,
}
Kora.keybind = { add = function(options)
    if options.name == 'playerfocus' then playerFocus = options.onPressed end
    return { remove = function() return true end }
end }

dofile(repoRoot .. "compat/shared.lua")
dofile(repoRoot .. "compat/client/qb-menu.lua")

-- Mirrors a cross-resource exports['qb-menu']:Fn(): fire __cfx_export_ with a setCB stub.
local function getExport(providedResource, exportName)
    local handlers = net.eventHandlers[("__cfx_export_%s_%s"):format(providedResource, exportName)]
    harness.assertTrue(handlers ~= nil and handlers[1] ~= nil, exportName .. " should be registered")

    local captured
    handlers[1](function(fn) captured = fn end)
    return captured
end

local openMenu = getExport("qb-menu", "openMenu")
local closeMenu = getExport("qb-menu", "closeMenu")
local showHeader = getExport("qb-menu", "showHeader")

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

-- TriggerEvent isn't recorded by test/mocks.lua, so listen via AddEventHandler.
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

-- A `function` on `item.action` from ANOTHER resource crosses the export boundary as a table
-- with a __call metamethod (FXServer funcref marshalling). A masked action must still fire.
harness.test("selecting an item with a masked cross-resource function action still fires it", function()
    local fired = 0
    local maskedAction = setmetatable({}, { __call = function(_) fired = fired + 1 end })

    nextMenuResult = { selectedId = "1" }
    openMenu({ { header = "Do it", action = maskedAction } })

    harness.assertEqual(fired, 1, "a masked cross-resource function action should still be invoked")
end)

-- Some CFX versions expose the export-boundary callable through the legacy
-- marker field too. The real runtime makes that object invocable; the mock
-- adds __call so we can exercise both recognition and dispatch here.
harness.test('a __cfx_functionReference action remains compatible', function()
    local fired = 0
    local funcref = setmetatable({ __cfx_functionReference = 'smoke-ref' }, {
        __call = function() fired = fired + 1 end,
    })
    nextMenuResult = { selectedId = '1' }
    openMenu({ { header = 'Do it', action = funcref } })
    harness.assertEqual(fired, 1, 'a CFX funcref action should still be invoked')
end)

-- Same masking, but through the isAction/params.event path (dispatch's
-- second, independent callable check) rather than item.action directly.
harness.test("selecting an item with isAction and a masked cross-resource event function still fires it", function()
    local receivedArgs
    local maskedEvent = setmetatable({}, { __call = function(_, args) receivedArgs = args end })

    nextMenuResult = { selectedId = "1" }
    openMenu({ { header = "Do it", params = { isAction = true, event = maskedEvent, args = { "x" } } } })

    harness.assertTrue(receivedArgs ~= nil, "a masked cross-resource isAction event should still be invoked")
    harness.assertEqual(receivedArgs[1], "x", "the isAction event should receive params.args")
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

-- Real qb-menu's openMenu/showHeader do `if not data or not next(data) then
-- return end` -- a nil (or non-table) menu is a silent no-op, not an error.
-- A script that conditionally builds a menu and passes nil when there's
-- nothing to show must keep working exactly like it does against the real
-- resource, not crash.
harness.test("openMenu silently no-ops on a non-table menu, matching real qb-menu", function()
    sentItems = nil
    local ok = pcall(openMenu, "not a table")
    harness.assertTrue(ok, "a non-table menu should not error")
    harness.assertTrue(sentItems == nil, "Kora.nui.openMenu should never be reached for a non-table menu")
end)

harness.test("openMenu silently no-ops on nil, matching real qb-menu", function()
    sentItems = nil
    local ok = pcall(openMenu, nil)
    harness.assertTrue(ok, "a nil menu should not error")
    harness.assertTrue(sentItems == nil, "Kora.nui.openMenu should never be reached for a nil menu")
end)

harness.test("closeMenu force-dismisses through the NUI cancellation action", function()
    local ok = pcall(closeMenu)
    harness.assertTrue(ok, "closeMenu should not error")
    harness.assertEqual(sentActions[#sentActions].action, 'closeMenu',
        'closeMenu should ask the active menu to cancel')
end)

harness.test("playerfocus turns a read-only showHeader into the interactive managed menu", function()
    local received
    AddEventHandler("header:test:fired", function(args) received = args end)
    nextMenuResult = { selectedId = "1" }

    showHeader({ { header = "Open garage", params = {
        event = "header:test:fired", args = { currentSelection = 2 },
    } } })
    harness.assertEqual(sentActions[#sentActions].action, 'showMenuHeader',
        'showHeader should remain a display-only prompt until the focus key is pressed')

    playerFocus()

    harness.assertEqual(sentItems[1].label, "Open garage",
        'the focus key should open the same translated rows interactively')
    harness.assertEqual(received.currentSelection, 2,
        'selecting the focused header should retain the original dispatch payload')
    local hidHeader = false
    for _, message in ipairs(sentActions) do
        if message.action == 'hideMenuHeader' then hidHeader = true break end
    end
    harness.assertTrue(hidHeader, 'the read-only header should hide before the interactive menu opens')
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

-- Real qb-menu items sometimes carry a shared-item NAME as `icon`; imageFor looks it up via
-- exports.kora_core:getShared('items', icon). A definition with only the legacy local-file
-- `image` (no `imageUrl`) has its icon dropped: the nui://qb-inventory/html/images URL
-- would always 404, since kora_inventory ships no such files.
harness.test("an icon naming a shared item with only a legacy `image` field is dropped, not translated to a dead nui:// URL", function()
    sharedItems = { bread = { name = "bread", image = "bread.png" } }
    nextMenuResult = { cancelled = true }
    openMenu({ { header = "Eat Bread", icon = "bread" } })

    harness.assertTrue(sentItems[1].image == nil, "a bare `image` filename with no imageUrl should resolve to nil, not a nui://qb-inventory/... URL")
end)

harness.test("an icon naming a shared item with a real imageUrl is used directly", function()
    sharedItems = { bread = { name = "bread", image = "bread.png", imageUrl = "https://example.com/bread.png" } }
    nextMenuResult = { cancelled = true }
    openMenu({ { header = "Eat Bread", icon = "bread" } })

    harness.assertEqual(sentItems[1].image, "https://example.com/bread.png", "a real imageUrl should be used as-is")
end)

-- During a genuine export call, Kora.nui.openMenu has already awaited its own
-- promise before returning here. A second Citizen.Await on this plain result
-- would return nil in CfxLua, so the compatibility layer must consume it
-- directly. The event-path test above separately covers the promise path.
harness.test("the export path consumes Kora.nui.openMenu's already-settled result directly", function()
    local received
    AddEventHandler("export:test:fired", function() received = true end)

    _G.GetInvokingResource = function() return "consumer-resource" end
    Kora.nui.openMenu = function(items)
        sentItems = items
        return { selectedId = "1" }
    end

    openMenu({ { header = "Go", params = { event = "export:test:fired" } } })

    harness.assertTrue(received, "the selected item should dispatch from the plain export result")
    _G.GetInvokingResource = function() return nil end
end)

harness.test("menuClosed fires only on a user close, not after a programmatic closeMenu", function()
    local closed = 0
    net.eventHandlers["qb-menu:client:menuClosed"] = { function() closed = closed + 1 end }

    local realOpen = Kora.nui.openMenu
    local closeDuringOpen = false
    Kora.nui.openMenu = function()
        if closeDuringOpen then closeMenu() end
        local p = promise.new()
        p:resolve({ cancelled = true })
        return p
    end

    openMenu({ { header = "One" } })
    harness.assertEqual(closed, 1, "a user cancel should fire menuClosed")

    closeDuringOpen = true
    openMenu({ { header = "Two" } })
    harness.assertEqual(closed, 1, "closeMenu while open should not fire menuClosed")

    closeDuringOpen = false
    openMenu({ { header = "Three" } })
    harness.assertEqual(closed, 2, "the silence must not leak into the next menu")

    Kora.nui.openMenu = realOpen
    net.eventHandlers["qb-menu:client:menuClosed"] = nil
end)

harness.report("compat_qb_menu")
