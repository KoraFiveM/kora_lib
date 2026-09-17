local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "local/resources/client.lua")

-- RegisterNUICallback/SendNUIMessage/SetNuiFocus are specific to this module,
-- so (per the root AGENTS.md testing convention) they're mocked here rather
-- than in test/mocks.lua. `nuiCallbacks` captures every registered callback
-- by name so tests can simulate the NUI calling back into Lua; `sentMessages`
-- records every SendNUIMessage payload in order.
--
-- SendNUIMessage (capital NUI) is the table-accepting runtime wrapper --
-- that's the one the module must call, NOT the SendNuiMessage native (which
-- takes a pre-encoded JSON string). Deliberately no SendNuiMessage mock is
-- installed, so a regression back to the string-typed native fails loudly
-- here instead of silently stringifying tables in-game.
local nuiCallbacks = {}
local sentMessages = {}
local focusCalls = {}
local keepInputCalls = {}
local currentKeepInput = false

_G.RegisterNUICallback = function(name, fn)
    nuiCallbacks[name] = fn
end

_G.SendNUIMessage = function(payload)
    table.insert(sentMessages, payload)
end

_G.SetNuiFocus = function(mouse, keyboard)
    table.insert(focusCalls, { mouse = mouse, keyboard = keyboard })
end
_G.SetNuiFocusKeepInput = function(keepInput)
    currentKeepInput = keepInput
    keepInputCalls[#keepInputCalls + 1] = keepInput
end
_G.IsNuiFocusKeepingInput = function() return currentKeepInput end

-- qblib imports qbtheme's bridge before this module in production. Model the
-- bridge's important contract here: a nil app accent restores the player's
-- saved /theme colour rather than clearing the browser back to the server
-- default.
local playerAccent = "#7C3AED"
_G.QBTheme = {
    apply = function(accent)
        SendNUIMessage({ action = "qbtheme:override", data = accent or playerAccent })
    end,
}

dofile(repoRoot .. "modules/nui/client.lua")

local registeredExports = {}
_G.exports = function(name, callback)
    registeredExports[name] = callback
end
dofile(repoRoot .. "build/finalise.lua")

-- Simulates the NUI responding to the given request id/token via the shared
-- `qblib:nui:response` channel every QB.nui.request call resolves through.
local function respond(requestId, token, ok, resultOrError)
    local field = ok and "result" or "error"
    nuiCallbacks["qblib:nui:response"](
        { requestId = requestId, token = token, ok = ok, [field] = resultOrError },
        function() end
    )
end

-- Every QB.nui.request call sends { action, data = { requestId, token, payload } };
-- these pull the id/token back out of the most recently sent message, which is
-- exactly what a well-behaved NUI does to answer it.
local function lastRequestId()
    return sentMessages[#sentMessages].data.requestId
end

local function lastToken()
    return sentMessages[#sentMessages].data.token
end

-- Shorthand for the common case: respond using the real token from the last
-- sent request, so most tests don't need to thread lastToken() through by hand.
local function respondOk(requestId, result)
    respond(requestId, lastToken(), true, result)
end

local function lastMessage(action)
    for index = #sentMessages, 1, -1 do
        if sentMessages[index].action == action then return sentMessages[index] end
    end
end

-- The qblib:nui:theme callback now lives in modules/theme/client.lua (see
-- test/smoke/theme.lua) -- this file no longer dofiles that module, so those
-- assertions moved rather than duplicated.

harness.test("finalise exposes every registered-app lifecycle export", function()
    harness.assertEqual(registeredExports.nui_registerApp, QB.nui.registerApp,
        "registerApp should cross the qblib export boundary")
    harness.assertEqual(registeredExports.nui_unregisterApp, QB.nui.unregisterApp,
        "unregisterApp should cross the qblib export boundary")
    harness.assertEqual(registeredExports.nui_openApp, QB.nui.openApp,
        "openApp should cross the qblib export boundary")
    harness.assertEqual(registeredExports.nui_updateApp, QB.nui.updateApp,
        "updateApp should cross the qblib export boundary")
    harness.assertEqual(registeredExports.nui_closeApp, QB.nui.closeApp,
        "closeApp should cross the qblib export boundary")
    harness.assertEqual(registeredExports.nui_isAppOpen, QB.nui.isAppOpen,
        "isAppOpen should cross the qblib export boundary")
end)

harness.test("request sends the action and payload via SendNuiMessage", function()
    QB.nui.request("someAction", { foo = "bar" })

    local sent = sentMessages[#sentMessages]
    harness.assertEqual(sent.action, "someAction", "the action should be forwarded as-is")
    harness.assertEqual(sent.data.payload.foo, "bar", "the payload should be forwarded as-is")
end)

harness.test("request resolves once the NUI responds with ok = true and the right token", function()
    local p = QB.nui.request("someAction", {})
    respondOk(lastRequestId(), { value = 42 })

    harness.assertEqual(p.state, "resolved", "the promise should resolve on a successful response")
    harness.assertEqual(p.value.value, 42, "the resolved value should be the NUI's result")
end)

harness.test("request rejects once the NUI responds with ok = false", function()
    local p = QB.nui.request("someAction", {})
    respond(lastRequestId(), lastToken(), false, "something broke")

    harness.assertEqual(p.state, "rejected", "the promise should reject on a failed response")
    harness.assertEqual(p.value, "something broke", "the rejection should carry the NUI's error")
end)

harness.test("requestAsync can be cancelled and releases its focus lease", function()
    local request = QB.nui.requestAsync("openAlert", { message = "Wait" }, false, "consumer", true)
    local requestId, token = lastRequestId(), lastToken()

    harness.assertEqual(request.state, "pending", "the asynchronous request should remain available to its composing module")
    harness.assertTrue(focusCalls[#focusCalls].mouse, "focused requests should acquire a focus lease")
    harness.assertTrue(QB.nui.cancelRequest(request, { confirmed = false }), "a pending request should cancel")

    local cancellation = sentMessages[#sentMessages]
    harness.assertEqual(cancellation.action, "cancelNuiRequest", "cancellation should dismiss the matching browser surface")
    harness.assertEqual(cancellation.data.requestId, requestId, "cancellation should identify the request")
    harness.assertEqual(cancellation.data.token, token, "cancellation should carry the request token")
    harness.assertEqual(request.state, "resolved", "a normal cancellation should resolve the request")
    harness.assertFalse(focusCalls[#focusCalls].mouse, "settling should release the focus lease")
    harness.assertFalse(QB.nui.cancelRequest(request), "an already-settled request should not cancel twice")
end)

harness.test("cancelRequest can reject with the ox-compatible close reason", function()
    local request = QB.nui.requestAsync("openAlert", { message = "Wait" }, false)
    harness.assertTrue(QB.nui.cancelRequest(request, nil, "timeout"), "a pending request should reject")
    harness.assertEqual(request.state, "rejected", "an explicit rejection should reject the promise")
    harness.assertEqual(request.value, "timeout", "the close reason should be retained")
end)

harness.test("registerCallback preserves a false handler result", function()
    local response
    QB.nui.registerCallback("returnsFalse", function() return false end)
    nuiCallbacks.returnsFalse({}, function(result) response = result end)
    harness.assertFalse(response, "only nil should be normalized to an empty response table")
end)

harness.test("every request gets a fresh, non-empty token", function()
    QB.nui.request("someAction", {})
    local tokenA = lastToken()

    QB.nui.request("someAction", {})
    local tokenB = lastToken()

    harness.assertTrue(type(tokenA) == "string" and #tokenA > 0, "a token should be a non-empty string")
    harness.assertTrue(tokenA ~= tokenB, "two requests should never share a token")
end)

harness.test("a response carrying the wrong token is ignored, guarding against a spoofed response", function()
    local p = QB.nui.request("someAction", {})
    local requestId = lastRequestId()

    respond(requestId, "not-the-real-token", true, "spoofed")
    harness.assertEqual(p.state, "pending", "a response with a mismatched token must not settle the promise")

    respondOk(requestId, "real answer")
    harness.assertEqual(p.state, "resolved", "the real response, carrying the real token, should still resolve it")
    harness.assertEqual(p.value, "real answer", "the resolved value should be the real response")
end)

harness.test("a response with no token at all is ignored", function()
    local p = QB.nui.request("someAction", {})
    local requestId = lastRequestId()

    nuiCallbacks["qblib:nui:response"]({ requestId = requestId, ok = true, result = "spoofed" }, function() end)
    harness.assertEqual(p.state, "pending", "a response missing its token must not settle the promise")
end)

harness.test("a response for an unknown requestId is a no-op", function()
    -- Must not error even though nothing is pending for this id.
    respond(999999, "irrelevant", true, "orphaned")
end)

harness.test("a second response for an already-settled request is ignored", function()
    local p = QB.nui.request("someAction", {})
    local requestId = lastRequestId()
    local token = lastToken()

    respond(requestId, token, true, "first")
    respond(requestId, token, true, "second")

    harness.assertEqual(p.value, "first", "the first response should win; the request was already removed from pendingRequests")
end)

harness.test("copyToClipboard sends the text and resolves true on success", function()
    local p = QB.nui.copyToClipboard("QB.zones.box({})")

    local sent = sentMessages[#sentMessages]
    harness.assertEqual(sent.action, "copyToClipboard", "copyToClipboard should send the copyToClipboard action")
    harness.assertEqual(sent.data.payload.text, "QB.zones.box({})", "the text to copy should be forwarded as-is")

    respondOk(lastRequestId(), true)
    harness.assertEqual(p.state, "resolved", "copyToClipboard should resolve once the NUI confirms the write")
    harness.assertEqual(p.value, true, "copyToClipboard should resolve true")
end)

harness.test("openMenu sends the items/title and resolves with the NUI's raw result", function()
    local items = { { id = "a", label = "A" }, { id = "b", label = "B" } }
    local p = QB.nui.openMenu(items, "Pick one")

    local sent = sentMessages[#sentMessages]
    harness.assertEqual(sent.action, "openMenu", "openMenu should send the openMenu action")
    harness.assertEqual(sent.data.payload.title, "Pick one", "the title should be forwarded as-is")
    harness.assertEqual(sent.data.payload.items, items, "the items table should be forwarded as-is")

    respondOk(lastRequestId(), { selectedId = "b" })
    harness.assertEqual(p.value.selectedId, "b", "should resolve with the NUI's raw MenuResult")
end)

harness.test("openMenu forwards optional geometry without changing the existing arguments", function()
    local opts = {
        position = { horizontal = "right", vertical = "center", offsetX = 48 },
        maxWidth = 400,
        maxHeight = 680,
        presentation = "panel",
    }
    local p = QB.nui.openMenu({ { id = "a", label = "A" } }, "Compact", opts)

    local payload = sentMessages[#sentMessages].data.payload
    harness.assertEqual(payload.position, opts.position, "position should be forwarded as-is")
    harness.assertEqual(payload.maxWidth, 400, "maxWidth should be forwarded")
    harness.assertEqual(payload.maxHeight, 680, "maxHeight should be forwarded")
    harness.assertEqual(payload.presentation, "panel", "presentation should be forwarded")
    respondOk(lastRequestId(), { cancelled = true })
    harness.assertEqual(p.state, "resolved", "the geometry test should settle its menu")
end)

harness.test("menus reject render-breaking payloads before taking focus", function()
    local beforeMessages, beforeFocus = #sentMessages, #focusCalls
    local recursive = { id = "loop", label = "Loop", submenu = {} }
    recursive.submenu.items = { recursive }

    for _, invoke in ipairs({
        function() QB.nui.openMenu({ { id = "bad", label = {} } }) end,
        function() QB.nui.openMenu({ { id = "bad", label = "Bad", disabled = "yes" } }) end,
        function() QB.nui.openMenu({ recursive }) end,
        function() QB.nui.openMenu({ { id = "ok", label = "Okay" } }, {}, {}) end,
        function() QB.nui.openMenu({ { id = "ok", label = "Okay" } }, nil, { maxWidth = 0 / 0 }) end,
        function() QB.nui.openMenu({ { id = "ok", label = "Okay" } }, nil, { presentation = "popover" }) end,
        function() QB.nui.openContextMenu({ { id = "ok", label = "Okay" } }, math.huge, 10) end,
    }) do
        harness.assertThrows(invoke, "malformed menu data must be rejected")
    end

    harness.assertEqual(#sentMessages, beforeMessages, "invalid menus must not reach React")
    harness.assertEqual(#focusCalls, beforeFocus, "invalid menus must not acquire focus")
end)

harness.test("openMenu grants focus while open and releases it once answered", function()
    QB.nui.openMenu({ { id = "a", label = "A" } })

    local grant = focusCalls[#focusCalls]
    harness.assertTrue(grant.mouse and grant.keyboard, "focus should be granted when the menu opens")

    respondOk(lastRequestId(), { selectedId = "a" })

    local release = focusCalls[#focusCalls]
    harness.assertFalse(release.mouse or release.keyboard, "focus should be released the moment the menu is answered")
end)

harness.test("stopping a request owner closes its surface and releases only its focus lease", function()
    local originalCurrentResourceName = GetCurrentResourceName
    _G.GetCurrentResourceName = function() return "stopping_consumer" end
    local p = QB.nui.openMenu({ { id = "a", label = "A" } })
    local requestId, token = lastRequestId(), lastToken()
    _G.GetCurrentResourceName = originalCurrentResourceName

    net.fire("onClientResourceStop", "stopping_consumer")

    harness.assertEqual(p.state, "rejected", "the abandoned request should settle immediately")
    local cancelled = lastMessage("cancelNuiRequest")
    harness.assertEqual(cancelled.data.requestId, requestId, "the browser should close the matching request")
    harness.assertEqual(cancelled.data.token, token, "the cancellation must retain the request token")
    harness.assertFalse(focusCalls[#focusCalls].mouse or focusCalls[#focusCalls].keyboard,
        "owner shutdown should release the abandoned request's focus")

    respond(requestId, token, true, { selectedId = "a" })
    harness.assertEqual(p.state, "rejected", "a late browser response must not revive the cancelled request")
end)

harness.test("openInputDialog releases focus even when the request is rejected", function()
    QB.nui.openInputDialog({ { id = "f", label = "F", type = "text" } })
    respond(lastRequestId(), lastToken(), false, "NUI exploded")

    local release = focusCalls[#focusCalls]
    harness.assertFalse(release.mouse or release.keyboard, "a rejected request must still release focus")
end)

harness.test("copyToClipboard never touches focus", function()
    local before = #focusCalls
    QB.nui.copyToClipboard("invisible")
    respondOk(lastRequestId(), true)

    harness.assertEqual(#focusCalls, before, "an invisible clipboard write should never grant or release focus")
end)

harness.test("openContextMenu forwards items and an (x, y) anchor", function()
    local items = { { id = "a", label = "A" } }
    local p = QB.nui.openContextMenu(items, 100, 200)

    local sent = sentMessages[#sentMessages]
    harness.assertEqual(sent.action, "openContextMenu", "openContextMenu should send the openContextMenu action")
    harness.assertEqual(sent.data.payload.x, 100, "x should be forwarded as-is")
    harness.assertEqual(sent.data.payload.y, 200, "y should be forwarded as-is")
    respondOk(lastRequestId(), { cancelled = true })
    harness.assertEqual(p.state, "resolved", "the context-menu test should settle its request")
end)

harness.test("openRadialMenu forwards shared menu items and optional geometry", function()
    local items = { { id = "repair", label = "Repair", icon = "Wrench" } }
    local p = QB.nui.openRadialMenu(items, { radius = 180 })

    local sent = sentMessages[#sentMessages]
    harness.assertEqual(sent.action, "openRadialMenu", "openRadialMenu should send its dedicated action")
    harness.assertEqual(sent.data.payload.items, items, "radial items should preserve the shared MenuItem table")
    harness.assertEqual(sent.data.payload.radius, 180, "radius should be forwarded as-is")

    local grant = focusCalls[#focusCalls]
    harness.assertTrue(grant.mouse and grant.keyboard, "a radial menu should grant focus while visible")

    respondOk(lastRequestId(), { selectedId = "repair", path = { "repair" } })
    harness.assertEqual(p.value.selectedId, "repair", "the selected radial result should pass through unchanged")
    harness.assertEqual(p.value.path[1], "repair", "the result should preserve its root-first path")

    local release = focusCalls[#focusCalls]
    harness.assertFalse(release.mouse or release.keyboard, "focus should release when the radial selection settles")
end)

harness.test("openRadialMenu preserves nested paths and releases focus on cancel", function()
    local p = QB.nui.openRadialMenu({
        {
            id = "vehicle",
            label = "Vehicle",
            submenu = { items = { { id = "repair", label = "Repair" } } },
        },
    })

    respondOk(lastRequestId(), { selectedId = "repair", path = { "vehicle", "repair" } })
    harness.assertEqual(p.value.path[1], "vehicle", "a submenu result should retain the parent id")
    harness.assertEqual(p.value.path[2], "repair", "a submenu result should end with the selected leaf")

    local selectedRelease = focusCalls[#focusCalls]
    harness.assertFalse(selectedRelease.mouse or selectedRelease.keyboard, "nested selection should release focus only after its final result")

    local cancelled = QB.nui.openRadialMenu({ { id = "close", label = "Close" } })
    respondOk(lastRequestId(), { cancelled = true })
    harness.assertTrue(cancelled.value.cancelled, "backdrop/Escape cancellation should pass through unchanged")

    local cancelRelease = focusCalls[#focusCalls]
    harness.assertFalse(cancelRelease.mouse or cancelRelease.keyboard, "cancel should release radial focus immediately")
end)

harness.test("openRadialMenu rejects malformed geometry before sending", function()
    harness.assertThrows(function()
        QB.nui.openRadialMenu({}, { radius = 0 })
    end, "a non-positive radius should be rejected")
end)

harness.test("openInputDialog forwards fields/title/description and resolves with the NUI's raw result", function()
    local fields = {
        { id = "amount", label = "Amount", type = "number" },
        { id = "date", label = "Date", type = "date", dateMin = 1788825600000, dateMax = 1791417600000 },
    }
    local p = QB.nui.openInputDialog(fields, "Enter amount", "How much?")

    local sent = sentMessages[#sentMessages]
    harness.assertEqual(sent.action, "openInputDialog", "openInputDialog should send the openInputDialog action")
    harness.assertEqual(sent.data.payload.fields, fields, "the fields table should be forwarded as-is")
    harness.assertEqual(sent.data.payload.description, "How much?", "the description should be forwarded as-is")

    respondOk(lastRequestId(), { values = { amount = 5 } })
    harness.assertEqual(p.value.values.amount, 5, "should resolve with the NUI's raw InputDialogResult")
end)

harness.test("openInputDialog applies the shared field schema before taking focus", function()
    local beforeMessages, beforeFocus = #sentMessages, #focusCalls

    harness.assertThrows(function()
        QB.nui.openInputDialog({ { id = "amount", label = "Amount", type = "number", min = 10, max = 5 } })
    end, "invalid standalone field bounds should be rejected")
    harness.assertThrows(function()
        QB.nui.openInputDialog({ { id = "kind", label = "Kind", type = "select" } })
    end, "standalone selects should require options just like AppShell forms")
    harness.assertThrows(function()
        QB.nui.openInputDialog({ { id = "child", label = "Child", type = "text", dependsOn = "missing" } })
    end, "standalone dependent fields should reference a declared field")

    harness.assertEqual(#sentMessages, beforeMessages, "invalid standalone fields must not reach the browser")
    harness.assertEqual(#focusCalls, beforeFocus, "invalid standalone fields must not acquire a focus lease")
end)

harness.test("openAlert forwards optional artwork and manages focus until answered", function()
    local image = "nui://example-resource/web/images/preview.png"
    local p = QB.nui.openAlert({ message = "Proceed?", image = image })

    local sent = sentMessages[#sentMessages]
    harness.assertEqual(sent.action, "openAlert", "openAlert should send the openAlert action")
    harness.assertEqual(sent.data.payload.image, image, "the optional artwork URL should be forwarded unchanged")

    local grant = focusCalls[#focusCalls]
    harness.assertTrue(grant.mouse and grant.keyboard, "an alert should grant focus while visible")

    respondOk(lastRequestId(), { confirmed = true })
    harness.assertTrue(p.value.confirmed, "the alert result should pass through unchanged")

    local release = focusCalls[#focusCalls]
    harness.assertFalse(release.mouse or release.keyboard, "focus should release once the alert is answered")
end)

harness.test("openAlert rejects render-breaking option types before taking focus", function()
    local beforeMessages, beforeFocus = #sentMessages, #focusCalls
    harness.assertThrows(function() QB.nui.openAlert({ message = "Proceed?", title = {} }) end)
    harness.assertThrows(function() QB.nui.openAlert({ message = "Proceed?", cancellable = "no" }) end)
    harness.assertEqual(#sentMessages, beforeMessages, "invalid alerts must not reach React")
    harness.assertEqual(#focusCalls, beforeFocus, "invalid alerts must not acquire focus")
end)

harness.test("copyToClipboard requires a string", function()
    harness.assertThrows(function() QB.nui.copyToClipboard(123) end, "a non-string should be rejected before anything is sent")
end)

harness.test("registerCallback forwards the handler's return value to the NUI", function()
    QB.nui.registerCallback("smoke:echo", function(data) return { echoed = data.value } end)

    local response
    nuiCallbacks["smoke:echo"]({ value = "hi" }, function(r) response = r end)

    harness.assertEqual(response.echoed, "hi", "the handler's return value should be passed to cb")
end)

harness.test("registerCallback catches a handler error and still responds", function()
    QB.nui.registerCallback("smoke:boom", function() error("kaboom") end)

    local response
    local ok = pcall(function()
        nuiCallbacks["smoke:boom"]({}, function(r) response = r end)
    end)

    harness.assertTrue(ok, "an erroring handler must not propagate the error out to the NUI dispatch")
    harness.assertTrue(response ~= nil, "cb should still be called so the NUI's fetch doesn't hang")
end)

harness.test("withFocus sets focus, runs fn, and always releases focus afterward", function()
    local ran = false
    local result = QB.nui.withFocus(true, true, function()
        ran = true
        return "done"
    end)

    harness.assertTrue(ran, "fn should have run")
    harness.assertEqual(result, "done", "withFocus should return fn's result")
    harness.assertEqual(focusCalls[#focusCalls - 1].mouse, true, "focus should have been set before fn ran")
    harness.assertEqual(focusCalls[#focusCalls].mouse, false, "focus should be released after fn returns")
end)

harness.test("explicit focus leases compose and release independently", function()
    local releaseMouse = QB.nui.acquireFocus(true, false, true, "mouse-owner")
    local releaseKeyboard = QB.nui.acquireFocus(false, true, false, "keyboard-owner")
    harness.assertTrue(focusCalls[#focusCalls].mouse and focusCalls[#focusCalls].keyboard,
        "combined leases should preserve both focus capabilities")
    harness.assertTrue(keepInputCalls[#keepInputCalls], "the keep-input lease should be composed")

    QB.nui.releaseFocus(releaseMouse)
    harness.assertFalse(focusCalls[#focusCalls].mouse, "releasing the mouse lease should remove mouse focus")
    harness.assertTrue(focusCalls[#focusCalls].keyboard, "the independent keyboard lease should remain")
    harness.assertFalse(keepInputCalls[#keepInputCalls], "releasing its lease should restore keep-input state")

    QB.nui.releaseFocus(releaseKeyboard)
    harness.assertFalse(focusCalls[#focusCalls].keyboard, "releasing the final lease should clear focus")
end)

harness.test("the final focus lease restores a pre-existing keep-input state", function()
    SetNuiFocusKeepInput(true)
    local release = QB.nui.acquireFocus(true, true, false, "compat-owner")
    harness.assertFalse(keepInputCalls[#keepInputCalls], "the active lease should apply its own keep-input choice")

    QB.nui.releaseFocus(release)
    harness.assertTrue(keepInputCalls[#keepInputCalls], "releasing the final lease should restore the prior keep-input state")

    -- Keep later smoke tests independent from this simulated external overlay.
    SetNuiFocusKeepInput(false)
end)

harness.test("withFocus releases focus even when fn errors, then re-raises", function()
    harness.assertThrows(function()
        QB.nui.withFocus(true, true, function() error("nope") end)
    end, "the error should propagate out of withFocus")

    harness.assertEqual(focusCalls[#focusCalls].mouse, false, "focus should still be released after an error")
end)

harness.test("registerApp stores a headless definition and openApp opens it by id", function()
    local handled
    local definition = {
        id = "smoke:records",
        title = "Records",
        icon = "Database",
        accent = "#3B82F6",
        navigation = {
            { id = "people", label = "People", content = { blocks = { { type = "empty", title = "Find a person" } } } },
        },
        onAction = function(actionId) handled = actionId end,
    }

    harness.assertEqual(QB.nui.registerApp(definition), definition.id, "registerApp should return the stable app id")
    local p = QB.nui.openApp(definition.id, { viewId = "people", data = { unit = 12 } })

    local sent = sentMessages[#sentMessages]
    harness.assertEqual(sent.action, "openApp", "openApp should send its dedicated action")
    local accent = sentMessages[#sentMessages - 1]
    harness.assertEqual(accent.action, "qbtheme:override", "the app accent should be applied through qblib's frame")
    harness.assertEqual(accent.data, definition.accent, "the configured app accent should be forwarded")
    harness.assertEqual(sent.data.payload.app.id, definition.id, "the registered browser definition should be sent")
    harness.assertEqual(sent.data.payload.app.onAction, nil, "Lua action handlers must never enter the JSON payload")
    harness.assertEqual(sent.data.payload.viewId, "people", "the requested initial view should be forwarded")
    harness.assertEqual(sent.data.payload.data.unit, 12, "private session data should be retained for the app instance")
    harness.assertTrue(QB.nui.isAppOpen(definition.id), "isAppOpen should report the active registered app")

    local requestId, token = lastRequestId(), lastToken()
    respond(requestId, token, true, { closed = true, reason = "close", viewId = "people" })
    harness.assertEqual(p.value.reason, "close", "the browser close result should settle openApp")
    harness.assertFalse(QB.nui.isAppOpen(), "settling openApp should clear the active instance")
    harness.assertEqual(sentMessages[#sentMessages].action, "qbtheme:override", "closing should reset the app accent")
    harness.assertEqual(sentMessages[#sentMessages].data, playerAccent, "closing should restore the player's /theme colour")
    harness.assertFalse(focusCalls[#focusCalls].mouse, "settling openApp should release NUI focus")
    harness.assertEqual(handled, nil, "opening the app should not invoke its action handler")
end)

harness.test("registerApp accepts bounded progress graph blocks", function()
    local definition = {
        id = "smoke:progress", title = "Progress", navigation = {
            { id = "skills", label = "Skills", content = { blocks = {
                { type = "progress", id = "levels", items = {
                    { label = "Mining", value = 25, max = 100, detail = "250 / 1,000 XP", icon = "Hammer" },
                } },
            } } },
        },
    }

    harness.assertEqual(QB.nui.registerApp(definition), definition.id,
        "a valid bounded progress graph should register")
    harness.assertThrows(function()
        QB.nui.registerApp({
            id = "smoke:bad-progress", title = "Bad progress", navigation = {
                { id = "skills", label = "Skills", content = { blocks = {
                    { type = "progress", items = { { label = "Mining", value = 101, max = 100 } }, },
                } } },
            },
        })
    end, "progress values above max must be rejected before they reach the browser")
end)

harness.test("an app without its own accent keeps the player's /theme colour", function()
    QB.nui.registerApp({
        id = "smoke:player-theme",
        title = "Player theme",
        navigation = { { id = "home", label = "Home" } },
    })
    local p = QB.nui.openApp("smoke:player-theme")

    local open = sentMessages[#sentMessages]
    local accent = sentMessages[#sentMessages - 1]
    harness.assertEqual(accent.action, "qbtheme:override", "opening should apply the effective theme through qbtheme")
    harness.assertEqual(accent.data, playerAccent, "an unthemed app must retain the player's saved colour")

    respond(open.data.requestId, open.data.token, true, { closed = true, reason = "close" })
    harness.assertEqual(p.value.reason, "close", "the unthemed app should still settle normally")
end)

harness.test("AppShell actions require the active token and route context to the registered handler", function()
    local receivedAction, receivedContext
    QB.nui.registerApp({
        id = "smoke:actions",
        title = "Actions",
        navigation = { { id = "dashboard", label = "Dashboard", content = { actions = {
            { id = "open-record", label = "Open record" },
        } } } },
        onAction = function(actionId, context)
            receivedAction, receivedContext = actionId, context
            return { update = { footer = "Updated" } }
        end,
    })
    QB.nui.openApp("smoke:actions", { data = { officer = "312" } })
    local requestId, token = lastRequestId(), lastToken()

    local forged
    nuiCallbacks["qblib:app:action"]({
        appId = "smoke:actions", token = "wrong", actionId = "refresh", viewId = "dashboard",
    }, function(result) forged = result end)
    harness.assertFalse(forged.ok, "an action with the wrong app token must be rejected")
    harness.assertEqual(receivedAction, nil, "a forged action must never reach the owning handler")

    local response
    nuiCallbacks["qblib:app:action"]({
        appId = "smoke:actions",
        token = token,
        actionId = "open-record",
        viewId = "dashboard",
        tabId = "recent",
        itemId = "R-12",
        value = { id = "R-12" },
    }, function(result) response = result end)

    harness.assertTrue(response.ok, "a valid app action should succeed")
    harness.assertEqual(receivedAction, "open-record", "the action id should reach the registered handler")
    harness.assertEqual(receivedContext.itemId, "R-12", "row/list identity should reach the handler context")
    harness.assertEqual(receivedContext.data.officer, "312", "openApp's private data should reach the handler context")
    harness.assertEqual(response.result.app.footer, "Updated", "a handler update should return the refreshed definition")
    harness.assertEqual(response.result.update, nil, "the private update instruction should not be echoed to the browser")

    respond(requestId, token, true, { closed = true, reason = "close" })
end)

harness.test("AppShell accepts inline action field schemas and forwards submitted values", function()
    local received
    QB.nui.registerApp({
        id = "smoke:inline-fields",
        title = "Inline fields",
        navigation = { { id = "home", label = "Home", content = { actions = {
            { id = "warn", label = "Warn", fields = { { id = "reason", label = "Reason", type = "text", required = true } }, confirm = "This is recorded." },
        } } } },
        onAction = function(_, context) received = context.value end,
    })
    QB.nui.openApp("smoke:inline-fields")
    local _, token = lastRequestId(), lastToken()
    local response
    nuiCallbacks["qblib:app:action"]({
        appId = "smoke:inline-fields", token = token, actionId = "warn", viewId = "home", value = { reason = "Be civil" },
    }, function(result) response = result end)
    harness.assertTrue(response.ok, "an inline-field action should be accepted")
    harness.assertEqual(received.reason, "Be civil", "submitted inline values should reach the action handler")
end)

harness.test("updateApp refreshes an active definition and closeApp settles through the browser", function()
    QB.nui.registerApp({
        id = "smoke:lifecycle",
        title = "Lifecycle",
        navigation = { { id = "home", label = "Home" } },
    })
    QB.nui.openApp("smoke:lifecycle")
    local requestId, token = lastRequestId(), lastToken()

    harness.assertTrue(QB.nui.updateApp("smoke:lifecycle", { footer = "Live" }), "a registered app should update")
    local update = sentMessages[#sentMessages]
    harness.assertEqual(update.action, "updateApp", "an active update should be pushed to the browser")
    harness.assertEqual(update.data.app.footer, "Live", "the merged definition should be pushed")
    harness.assertEqual(update.data.token, token, "the active instance token should guard updates")

    harness.assertTrue(QB.nui.closeApp("smoke:lifecycle"), "closeApp should start closing the active app")
    local close = sentMessages[#sentMessages]
    harness.assertEqual(close.action, "closeApp", "closeApp should ask the shell to settle")
    harness.assertEqual(close.data.reason, "api", "programmatic closes should identify their reason")

    respond(requestId, token, true, { closed = true, reason = "api" })
    harness.assertFalse(QB.nui.isAppOpen("smoke:lifecycle"), "the app should no longer be active after its response")
    harness.assertFalse(QB.nui.closeApp("smoke:lifecycle"), "closing an inactive app should be a harmless false")
end)

harness.test("registered apps are removed and closed automatically when their owner stops", function()
    QB.nui.registerApp({
        id = "smoke:owned",
        title = "Owned",
        navigation = { { id = "home", label = "Home" } },
    })
    local opened = QB.nui.openApp("smoke:owned")
    local requestId, token = lastRequestId(), lastToken()

    net.fire("onClientResourceStop", "qblib_test")
    local close = lastMessage("closeApp")
    harness.assertEqual(close.action, "closeApp", "owner shutdown should close the visible app")
    harness.assertEqual(close.data.reason, "resourceStop", "owner shutdown should identify the close reason")
    harness.assertEqual(opened.state, "resolved", "owner shutdown should settle immediately without relying on the browser")
    harness.assertFalse(QB.nui.isAppOpen(), "owner shutdown should release the active app immediately")
    harness.assertFalse(focusCalls[#focusCalls].mouse, "owner shutdown should release NUI focus immediately")

    respond(requestId, token, true, { closed = true, reason = "resourceStop" })
    harness.assertThrows(function() QB.nui.openApp("smoke:owned") end,
        "an app should no longer be registered after its owner stops")
end)

harness.test("opening a second app releases old focus before granting focus to the new app", function()
    QB.nui.registerApp({ id = "smoke:first", title = "First", navigation = { { id = "home", label = "Home" } } })
    QB.nui.registerApp({ id = "smoke:second", title = "Second", navigation = { { id = "home", label = "Home" } } })

    local first = QB.nui.openApp("smoke:first")
    local second = QB.nui.openApp("smoke:second")
    local secondRequestId, secondToken = lastRequestId(), lastToken()

    harness.assertEqual(first.state, "resolved", "the previous app request should close cleanly before replacement")
    harness.assertEqual(first.value.reason, "superseded", "the replaced app should report the superseded close reason")
    harness.assertEqual(second.state, "pending", "the replacement app should remain active")
    harness.assertTrue(focusCalls[#focusCalls].mouse and focusCalls[#focusCalls].keyboard,
        "the replacement app must own focus after superseding the previous app")

    respond(secondRequestId, secondToken, true, { closed = true, reason = "close" })
end)

harness.test("registerApp rejects definitions that would strand focus in an unrenderable shell", function()
    harness.assertThrows(function()
        QB.nui.registerApp({
            id = "smoke:invalid",
            title = "Invalid",
            navigation = { { id = "home", label = "Home", disabled = true } },
        })
    end, "an app with no enabled view must be rejected")

    harness.assertThrows(function()
        QB.nui.registerApp({
            id = "smoke:bad-block",
            title = "Invalid block",
            navigation = { { id = "home", label = "Home", content = { blocks = { { type = "table" } } } } },
        })
    end, "a malformed standard content block must be rejected before opening")

    harness.assertThrows(function()
        QB.nui.registerApp({
            id = "smoke:bad-accent",
            title = "Invalid accent",
            accent = "blue",
            navigation = { { id = "home", label = "Home" } },
        })
    end, "an invalid app accent must be rejected before opening")
end)

harness.test("nested dialogs release only their own focus lease while AppShell remains open", function()
    QB.nui.registerApp({ id = "smoke:nested-focus", title = "Nested", navigation = { { id = "home", label = "Home" } } })
    local app = QB.nui.openApp("smoke:nested-focus")
    local appRequestId, appToken = lastRequestId(), lastToken()
    local dialog = QB.nui.openInputDialog({ { id = "note", label = "Note", type = "text" } })

    respondOk(lastRequestId(), { cancelled = true })
    harness.assertEqual(dialog.state, "resolved", "the nested dialog should settle")
    local afterDialog = focusCalls[#focusCalls]
    harness.assertTrue(afterDialog.mouse and afterDialog.keyboard,
        "settling a nested dialog must retain the app's focus lease")

    respond(appRequestId, appToken, true, { closed = true, reason = "close" })
    harness.assertEqual(app.state, "resolved", "the underlying app should still settle normally")
    harness.assertFalse(focusCalls[#focusCalls].mouse or focusCalls[#focusCalls].keyboard,
        "focus should release after the final lease closes")
end)

harness.test("AppShell rejects action ids not declared anywhere in the active definition", function()
    local called = false
    QB.nui.registerApp({
        id = "smoke:declared-actions",
        title = "Declared actions",
        navigation = { { id = "home", label = "Home", content = { actions = {
            { id = "allowed", label = "Allowed" },
        } } } },
        onAction = function() called = true end,
    })
    QB.nui.openApp("smoke:declared-actions")
    local requestId, token = lastRequestId(), lastToken()
    local response
    nuiCallbacks["qblib:app:action"]({ appId = "smoke:declared-actions", token = token,
        actionId = "undeclared", viewId = "home" }, function(value) response = value end)
    harness.assertFalse(response.ok, "an undeclared action should be rejected")
    harness.assertFalse(called, "an undeclared action must not reach the owner")
    respond(requestId, token, true, { closed = true, reason = "close" })
end)

harness.test("closeBeforeAction settles AppShell and releases focus before owner code runs", function()
    local focusedDuringHandler
    QB.nui.registerApp({
        id = "smoke:close-before",
        title = "Close before",
        navigation = { { id = "home", label = "Home", content = { actions = {
            { id = "editor", label = "Open editor", closeBeforeAction = true },
        } } } },
        onAction = function()
            local focus = focusCalls[#focusCalls]
            focusedDuringHandler = focus.mouse or focus.keyboard
            return { notice = { tone = "success", message = "Editor complete." } }
        end,
    })
    local opened = QB.nui.openApp("smoke:close-before")
    local _, token = lastRequestId(), lastToken()
    local response
    nuiCallbacks["qblib:app:action"]({ appId = "smoke:close-before", token = token,
        actionId = "editor", viewId = "home" }, function(value) response = value end)
    harness.assertTrue(response.ok, "a declared close-before action should run")
    harness.assertEqual(opened.state, "resolved", "the shell request should settle before the handler returns")
    harness.assertFalse(focusedDuringHandler, "the owner handler must run after AppShell releases focus")
    harness.assertFalse(QB.nui.isAppOpen(), "the shell should no longer be active")
end)

harness.test("closeBeforeAction reports owner failures after the shell is gone", function()
    local notified
    QB.notify.send = function(options) notified = options end
    QB.nui.registerApp({
        id = "smoke:close-before-error",
        title = "Close before error",
        navigation = { { id = "home", label = "Home", content = { actions = {
            { id = "editor", label = "Open editor", closeBeforeAction = true },
        } } } },
        onAction = function() error("editor failed") end,
    })
    local opened = QB.nui.openApp("smoke:close-before-error")
    local token = lastToken()
    local response
    nuiCallbacks["qblib:app:action"]({ appId = "smoke:close-before-error", token = token,
        actionId = "editor", viewId = "home" }, function(value) response = value end)

    harness.assertFalse(response.ok, "an owner failure should be returned to the browser callback")
    harness.assertEqual(opened.state, "resolved", "the shell should already be settled when the owner fails")
    harness.assertEqual(notified.type, "error", "a closed-shell failure must be visible as an error notification")
end)

harness.test("AppShell validates and returns navigation and notice action results", function()
    QB.nui.registerApp({
        id = "smoke:result-shapes",
        title = "Results",
        navigation = {
            { id = "home", label = "Home", content = { actions = { { id = "go", label = "Go" } } } },
            { id = "records", label = "Records", tabs = { { id = "recent", label = "Recent" } } },
        },
        onAction = function()
            return { navigate = { viewId = "records", tabId = "recent" },
                notice = { tone = "primary", message = "Moved." } }
        end,
    })
    QB.nui.openApp("smoke:result-shapes")
    local requestId, token = lastRequestId(), lastToken()
    local response
    nuiCallbacks["qblib:app:action"]({ appId = "smoke:result-shapes", token = token,
        actionId = "go", viewId = "home" }, function(value) response = value end)
    harness.assertTrue(response.ok, "valid result shapes should be accepted")
    harness.assertEqual(response.result.navigate.viewId, "records", "navigation should pass to the browser")
    harness.assertEqual(response.result.notice.message, "Moved.", "notice should pass to the browser")
    respond(requestId, token, true, { closed = true, reason = "close" })
end)

harness.test("AppShell declares lazy view actions and typed configuration fields", function()
    local received
    QB.nui.registerApp({
        id = "smoke:lazy-view",
        title = "Lazy view",
        navigation = {
            { id = "home", label = "Home" },
            { id = "resource", label = "Resource", onOpen = "load-resource", content = { blocks = { {
                type = "form", id = "typed-config", fields = {
                    { id = "position", label = "Position", type = "vector", dimensions = 3,
                        default = { x = 1, y = 2, z = 3 }, wholeNumber = false },
                    { id = "rows", label = "Rows", type = "key-value", keyMode = "integer",
                        default = { { key = "1", value = "true" } } },
                    { id = "rates", label = "Rates", type = "key-value", keyMode = "mixed",
                        requiredKeys = { "default" }, valueField = { id = "item", label = "Value", type = "number", min = 0 },
                        default = { { key = "default", value = "1" }, { key = "0", value = "2" } } },
                    { id = "classes", label = "Classes", type = "key-value", keyMode = "integer-map",
                        default = { { key = "0", value = "true" } } },
                }, action = { id = "save", label = "Save" },
            } } } },
        },
        onAction = function(action, context) received = { action, context.itemId } end,
    })
    QB.nui.openApp("smoke:lazy-view")
    local requestId, token = lastRequestId(), lastToken()
    local response
    nuiCallbacks["qblib:app:action"]({ appId = "smoke:lazy-view", token = token,
        actionId = "load-resource", viewId = "home", itemId = "resource" }, function(value) response = value end)
    harness.assertTrue(response.ok, "a declared view-open action should be callable")
    harness.assertEqual(received[1], "load-resource", "the lazy action should reach its owner")
    harness.assertEqual(received[2], "resource", "the opened view id should reach its owner")
    respond(requestId, token, true, { closed = true, reason = "close" })
end)

harness.test("AppShell applies updates before validating result navigation", function()
    QB.nui.registerApp({
        id = "smoke:update-navigation",
        title = "Update navigation",
        navigation = { { id = "home", label = "Home", content = { actions = {
            { id = "load", label = "Load" },
        } } } },
        onAction = function()
            return {
                update = { navigation = {
                    { id = "home", label = "Home" },
                    { id = "records", label = "Records", tabs = { { id = "new", label = "New" } } },
                } },
                navigate = { viewId = "records", tabId = "new" },
            }
        end,
    })
    QB.nui.openApp("smoke:update-navigation")
    local requestId, token = lastRequestId(), lastToken()
    local response
    nuiCallbacks["qblib:app:action"]({ appId = "smoke:update-navigation", token = token,
        actionId = "load", viewId = "home" }, function(value) response = value end)

    harness.assertTrue(response.ok, "navigation may target a view introduced by the same result update")
    harness.assertEqual(response.result.app.navigation[2].id, "records", "the validated replacement definition should reach the browser")
    harness.assertEqual(response.result.navigate.tabId, "new", "the navigation result should remain intact")
    respond(requestId, token, true, { closed = true, reason = "close" })
end)

harness.test("AppShell recursively validates dependent fields and nested collection actions", function()
    harness.assertThrows(function()
        QB.nui.registerApp({
            id = "smoke:bad-dependent-field",
            title = "Invalid fields",
            navigation = { { id = "home", label = "Home", content = { blocks = { {
                type = "form", id = "filters", fields = {
                    { id = "city", label = "City", type = "select", options = {}, dependsOn = "missing" },
                }, action = { id = "filter", label = "Filter" },
            } } } } },
        })
    end, "a dependent field must reference a field in its form")

    local called
    QB.nui.registerApp({
        id = "smoke:nested-action",
        title = "Nested list",
        navigation = { { id = "home", label = "Home", content = { blocks = { {
            type = "list", items = { { id = "parent", label = "Parent", children = {
                { id = "child", label = "Child", action = "open-child" },
            } } },
        } } } } },
        onAction = function(action) called = action end,
    })
    QB.nui.openApp("smoke:nested-action")
    local requestId, token = lastRequestId(), lastToken()
    local response
    nuiCallbacks["qblib:app:action"]({ appId = "smoke:nested-action", token = token,
        actionId = "open-child", viewId = "home", itemId = "child" }, function(value) response = value end)
    harness.assertTrue(response.ok, "a recursively declared child action should be accepted")
    harness.assertEqual(called, "open-child", "the nested child action should reach its owner")
    respond(requestId, token, true, { closed = true, reason = "close" })
end)

harness.test("AppShell rejects malformed field, tab, and collection contracts", function()
    local function appWithField(id, field)
        return {
            id = "smoke:" .. id,
            title = "Invalid contract",
            navigation = { { id = "home", label = "Home", content = { blocks = { {
                type = "form", id = "form", fields = { field }, action = { id = "save", label = "Save" },
            } } } } },
        }
    end

    local invalidFields = {
        { id = "pattern", label = "Pattern", type = "text", pattern = 42 },
        { id = "bounds", label = "Bounds", type = "number", min = 5, max = 1 },
        { id = "length", label = "Length", type = "text", minLength = 5, maxLength = 1 },
        { id = "options", label = "Options", type = "select", options = { { value = "one" } } },
        { id = "presets", label = "Presets", type = "number", presets = { { value = "ten" } } },
        { id = "default", label = "Default", type = "multiselect", options = {}, default = "one" },
        { id = "visible", label = "Visible", type = "text", visibleWhen = { fieldId = "visible", equals = {} } },
    }
    for index, field in ipairs(invalidFields) do
        harness.assertThrows(function() QB.nui.registerApp(appWithField("bad-field-" .. index, field)) end,
            "malformed field contracts must be rejected recursively")
    end

    harness.assertThrows(function()
        QB.nui.registerApp({
            id = "smoke:bad-default-tab", title = "Invalid tab",
            navigation = { { id = "home", label = "Home", defaultTab = "missing", tabs = {
                { id = "present", label = "Present" },
            } } },
        })
    end, "defaultTab must name a declared tab")

    harness.assertThrows(function()
        QB.nui.registerApp({
            id = "smoke:bad-list-layout", title = "Invalid list",
            navigation = { { id = "home", label = "Home", content = { blocks = { {
                type = "list", layout = "carousel", searchable = "yes", pageSize = 0, items = {},
            } } } } },
        })
    end, "list layout and paging/search options must use supported types")

    harness.assertThrows(function()
        QB.nui.registerApp({
            id = "smoke:bad-table-sort", title = "Invalid table",
            navigation = { { id = "home", label = "Home", content = { blocks = { {
                type = "table", columns = { { key = "name", label = "Name", sortable = "yes" } }, rows = {},
            } } } } },
        })
    end, "table sorting options must use supported types")

    harness.assertThrows(function()
        QB.nui.registerApp({
            id = "smoke:bad-table-empty", title = "Invalid table empty state",
            navigation = { { id = "home", label = "Home", content = { blocks = { {
                type = "table", columns = { { key = "name", label = "Name" } }, rows = {},
                empty = { title = "Not valid here" },
            } } } } },
        })
    end, "table empty states must be strings so React never receives a table child")
end)

harness.report("nui")
