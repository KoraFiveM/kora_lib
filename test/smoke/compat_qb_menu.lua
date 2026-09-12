local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")

-- Controllable mock qbcore shared-item registry -- imageFor (in
-- compat/client/qb-menu.lua) reads item definitions via
-- exports.qbcore:getShared('items', key), pcall-guarded, same pattern as
-- compat_qb_radialmenu.lua's exports.qbcore mock.
local sharedItems = {}
_G.exports = {
    qbcore = {
        getShared = function(_, collection, key)
            if collection == 'items' then return sharedItems[key] end
            return nil
        end,
    },
}

-- Real modules/nui/client.lua isn't loaded here (that's modules/nui's own
-- smoke test) -- same "mock QB.nui directly, resolve synchronously" trick
-- test/smoke/minigames.lua uses, since compat/client/qb-menu.lua's openMenu
-- has to consume QB.nui.openMenu's result itself (to know which legacy
-- event to fire), not just hand a promise back to its own caller.
local sentItems = nil
local nextMenuResult = nil
local sentActions = {}
local playerFocus

QB.nui = {
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
QB.keybind = { add = function(options)
    if options.name == 'playerfocus' then playerFocus = options.onPressed end
    return { remove = function() return true end }
end }

dofile(repoRoot .. "compat/shared.lua")
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

-- A `function` value on `item.action` set by ANOTHER resource crosses the
-- exports['qb-menu']:openMenu(...) boundary as a table with a __call
-- metamethod, not a real function -- FXServer's own funcref marshalling, the
-- same shape test/smoke/funcref.lua in qbinventory exercises for the
-- identical reason. A masked action must still fire, matching a real
-- (same-resource, unmasked) function action.
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
    harness.assertTrue(sentItems == nil, "QB.nui.openMenu should never be reached for a non-table menu")
end)

harness.test("openMenu silently no-ops on nil, matching real qb-menu", function()
    sentItems = nil
    local ok = pcall(openMenu, nil)
    harness.assertTrue(ok, "a nil menu should not error")
    harness.assertTrue(sentItems == nil, "QB.nui.openMenu should never be reached for a nil menu")
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

-- Real qb-menu items sometimes carry a shared-item NAME as `icon` rather
-- than a real icon; imageFor looks that name up via
-- exports.qbcore:getShared('items', icon). If the matched definition has a real
-- `imageUrl`, it's used as-is (not exercised here). But if the definition
-- only has the LEGACY local-file `image` field (no `imageUrl`), imageFor
-- used to fall back to building a `nui://qb-inventory/html/images/%s` URL --
-- dead, because qbinventory (the resource that actually provides the
-- 'qb-inventory' identity) ships no such files and never exposes that path
-- in its fxmanifest.lua `files{}` block. That URL always 404s in the NUI, so
-- imageFor now drops the icon entirely in this case instead, matching its
-- own "the icon is simply dropped" philosophy for the Font-Awesome-vs-lucide
-- case above it.
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

-- During a genuine export call, QB.nui.openMenu has already awaited its own
-- promise before returning here. A second Citizen.Await on this plain result
-- would return nil in CfxLua, so the compatibility layer must consume it
-- directly. The event-path test above separately covers the promise path.
harness.test("the export path consumes QB.nui.openMenu's already-settled result directly", function()
    local received
    AddEventHandler("export:test:fired", function() received = true end)

    _G.GetInvokingResource = function() return "consumer-resource" end
    QB.nui.openMenu = function(items)
        sentItems = items
        return { selectedId = "1" }
    end

    openMenu({ { header = "Go", params = { event = "export:test:fired" } } })

    harness.assertTrue(received, "the selected item should dispatch from the plain export result")
    _G.GetInvokingResource = function() return nil end
end)

harness.report("compat_qb_menu")
