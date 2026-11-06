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
dofile(repoRoot .. "modules/util/shared.lua")

-- RegisterNUICallback/SendNUIMessage/SetNuiFocus are module-specific, so mocked here.
-- `nuiCallbacks` captures callbacks by name to simulate the NUI calling back;
-- `sentMessages` records every SendNUIMessage payload.
--
-- SendNUIMessage (capital NUI) is the table-accepting wrapper the module must call, NOT
-- the SendNuiMessage native (pre-encoded JSON string). It is deliberately not mocked, so a
-- regression to the native fails loudly here instead of stringifying tables in-game.
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

-- kora_lib imports kora_theme's bridge before this module in production. Model the
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
-- `kora_lib:nui:response` channel every Kora.nui.request call resolves through.
local function respond(requestId, token, ok, resultOrError)
    local field = ok and "result" or "error"
    nuiCallbacks["kora_lib:nui:response"](
        { requestId = requestId, token = token, ok = ok, [field] = resultOrError },
        function() end
    )
end

-- Every Kora.nui.request call sends { action, data = { requestId, token, payload } };
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

harness.test("finalise exposes every registered-app lifecycle export", function()
    harness.assertEqual(registeredExports.nui_registerApp, Kora.nui.registerApp,
        "registerApp should cross the kora_lib export boundary")
    harness.assertEqual(registeredExports.nui_unregisterApp, Kora.nui.unregisterApp,
        "unregisterApp should cross the kora_lib export boundary")
    harness.assertEqual(registeredExports.nui_openApp, Kora.nui.openApp,
        "openApp should cross the kora_lib export boundary")
    harness.assertEqual(registeredExports.nui_updateApp, Kora.nui.updateApp,
        "updateApp should cross the kora_lib export boundary")
    harness.assertEqual(registeredExports.nui_closeApp, Kora.nui.closeApp,
        "closeApp should cross the kora_lib export boundary")
    harness.assertEqual(registeredExports.nui_isAppOpen, Kora.nui.isAppOpen,
        "isAppOpen should cross the kora_lib export boundary")
end)

harness.test("request sends the action and payload via SendNuiMessage", function()
    Kora.nui.request("someAction", { foo = "bar" })

    local sent = sentMessages[#sentMessages]
    harness.assertEqual(sent.action, "someAction", "the action should be forwarded as-is")
    harness.assertEqual(sent.data.payload.foo, "bar", "the payload should be forwarded as-is")
end)

harness.test("request rejects unsafe timeouts before sending a message", function()
    local sentCount = #sentMessages

    harness.assertThrows(function() Kora.nui.request("someAction", {}, math.huge) end)
    harness.assertThrows(function() Kora.nui.request("someAction", {}, -1) end)
    harness.assertThrows(function() Kora.nui.request("someAction", {}, 1.5) end)

    harness.assertEqual(#sentMessages, sentCount, "an invalid timeout must not create or send a request")
end)

harness.test("request resolves once the NUI responds with ok = true and the right token", function()
    local p = Kora.nui.request("someAction", {})
    respondOk(lastRequestId(), { value = 42 })

    harness.assertEqual(p.state, "resolved", "the promise should resolve on a successful response")
    harness.assertEqual(p.value.value, 42, "the resolved value should be the NUI's result")
end)

harness.test("request rejects once the NUI responds with ok = false", function()
    local p = Kora.nui.request("someAction", {})
    respond(lastRequestId(), lastToken(), false, "something broke")

    harness.assertEqual(p.state, "rejected", "the promise should reject on a failed response")
    harness.assertEqual(p.value, "something broke", "the rejection should carry the NUI's error")
end)

harness.test("requestAsync can be cancelled and releases its focus lease", function()
    local request = Kora.nui.requestAsync("openAlert", { message = "Wait" }, false, "consumer", true)
    local requestId, token = lastRequestId(), lastToken()

    harness.assertEqual(request.state, "pending", "the asynchronous request should remain available to its composing module")
    harness.assertTrue(focusCalls[#focusCalls].mouse, "focused requests should acquire a focus lease")
    harness.assertTrue(Kora.nui.cancelRequest(request, { confirmed = false }), "a pending request should cancel")

    local cancellation = sentMessages[#sentMessages]
    harness.assertEqual(cancellation.action, "cancelNuiRequest", "cancellation should dismiss the matching browser surface")
    harness.assertEqual(cancellation.data.requestId, requestId, "cancellation should identify the request")
    harness.assertEqual(cancellation.data.token, token, "cancellation should carry the request token")
    harness.assertEqual(request.state, "resolved", "a normal cancellation should resolve the request")
    harness.assertFalse(focusCalls[#focusCalls].mouse, "settling should release the focus lease")
    harness.assertFalse(Kora.nui.cancelRequest(request), "an already-settled request should not cancel twice")
end)

harness.test("cancelRequest can reject with the ox-compatible close reason", function()
    local request = Kora.nui.requestAsync("openAlert", { message = "Wait" }, false)
    harness.assertTrue(Kora.nui.cancelRequest(request, nil, "timeout"), "a pending request should reject")
    harness.assertEqual(request.state, "rejected", "an explicit rejection should reject the promise")
    harness.assertEqual(request.value, "timeout", "the close reason should be retained")
end)

harness.test("registerCallback preserves a false handler result", function()
    local response
    Kora.nui.registerCallback("returnsFalse", function() return false end)
    nuiCallbacks.returnsFalse({}, function(result) response = result end)
    harness.assertFalse(response, "only nil should be normalized to an empty response table")
end)

harness.test('registerCallback rejects invalid registrations before reaching the native', function()
    local registrations = 0
    local registerNuiCallback = RegisterNUICallback
    _G.RegisterNUICallback = function(...)
        registrations = registrations + 1
        return registerNuiCallback(...)
    end

    harness.assertThrows(function() Kora.nui.registerCallback('', function() end) end)
    harness.assertThrows(function() Kora.nui.registerCallback('bad-handler', false) end)
    _G.RegisterNUICallback = registerNuiCallback

    harness.assertEqual(registrations, 0, 'invalid registrations must not reach the native callback registry')
end)

harness.test("every request gets a fresh, non-empty token", function()
    Kora.nui.request("someAction", {})
    local tokenA = lastToken()

    Kora.nui.request("someAction", {})
    local tokenB = lastToken()

    harness.assertTrue(type(tokenA) == "string" and #tokenA > 0, "a token should be a non-empty string")
    harness.assertTrue(tokenA ~= tokenB, "two requests should never share a token")
end)

harness.test("a response carrying the wrong token is ignored, guarding against a spoofed response", function()
    local p = Kora.nui.request("someAction", {})
    local requestId = lastRequestId()

    respond(requestId, "not-the-real-token", true, "spoofed")
    harness.assertEqual(p.state, "pending", "a response with a mismatched token must not settle the promise")

    respondOk(requestId, "real answer")
    harness.assertEqual(p.state, "resolved", "the real response, carrying the real token, should still resolve it")
    harness.assertEqual(p.value, "real answer", "the resolved value should be the real response")
end)

harness.test("a response with no token at all is ignored", function()
    local p = Kora.nui.request("someAction", {})
    local requestId = lastRequestId()

    nuiCallbacks["kora_lib:nui:response"]({ requestId = requestId, ok = true, result = "spoofed" }, function() end)
    harness.assertEqual(p.state, "pending", "a response missing its token must not settle the promise")
end)

harness.test("malformed browser callback payloads are ignored", function()
    local p = Kora.nui.request("someAction", {})
    local requestId, token = lastRequestId(), lastToken()
    local events = 0
    local eventRequest = Kora.nui.requestAsync("someAction", {}, false, nil, nil, function() events = events + 1 end)
    local eventRequestId, eventToken = lastRequestId(), lastToken()

    nuiCallbacks["kora_lib:nui:response"]("not a table", function() end)
    nuiCallbacks["kora_lib:nui:event"]("not a table", function() end)

    harness.assertEqual(p.state, "pending", "a malformed response must not settle a request")
    harness.assertEqual(events, 0, "a malformed event must not reach its handler")

    respond(requestId, token, true, "answered")
    nuiCallbacks["kora_lib:nui:event"]({ requestId = eventRequestId, token = eventToken, event = "change" }, function() end)
    harness.assertEqual(p.value, "answered", "a valid response should still settle normally")
    harness.assertEqual(events, 1, "a valid event should still reach its handler")
    Kora.nui.cancelRequest(eventRequest)
end)

harness.test("a response for an unknown requestId is a no-op", function()
    -- Must not error even though nothing is pending for this id.
    respond(999999, "irrelevant", true, "orphaned")
end)

harness.test("a second response for an already-settled request is ignored", function()
    local p = Kora.nui.request("someAction", {})
    local requestId = lastRequestId()
    local token = lastToken()

    respond(requestId, token, true, "first")
    respond(requestId, token, true, "second")

    harness.assertEqual(p.value, "first", "the first response should win; the request was already removed from pendingRequests")
end)

harness.test("copyToClipboard sends the text and resolves true on success", function()
    local p = Kora.nui.copyToClipboard("Kora.zones.box({})")

    local sent = sentMessages[#sentMessages]
    harness.assertEqual(sent.action, "copyToClipboard", "copyToClipboard should send the copyToClipboard action")
    harness.assertEqual(sent.data.payload.text, "Kora.zones.box({})", "the text to copy should be forwarded as-is")

    respondOk(lastRequestId(), true)
    harness.assertEqual(p.state, "resolved", "copyToClipboard should resolve once the NUI confirms the write")
    harness.assertEqual(p.value, true, "copyToClipboard should resolve true")
end)

harness.test("openMenu sends the items/title and resolves with the NUI's raw result", function()
    local items = { { id = "a", label = "A" }, { id = "b", label = "B" } }
    local p = Kora.nui.openMenu(items, "Pick one")

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
    local p = Kora.nui.openMenu({ { id = "a", label = "A" } }, "Compact", opts)

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
        function() Kora.nui.openMenu({ { id = "bad", label = {} } }) end,
        function() Kora.nui.openMenu({ { id = "bad", label = "Bad", disabled = "yes" } }) end,
        function() Kora.nui.openMenu({ recursive }) end,
        function() Kora.nui.openMenu({ { id = "ok", label = "Okay" } }, {}, {}) end,
        function() Kora.nui.openMenu({ { id = "ok", label = "Okay" } }, nil, { maxWidth = 0 / 0 }) end,
        function() Kora.nui.openMenu({ { id = "ok", label = "Okay" } }, nil, { presentation = "popover" }) end,
        function() Kora.nui.openContextMenu({ { id = "ok", label = "Okay" } }, math.huge, 10) end,
    }) do
        harness.assertThrows(invoke, "malformed menu data must be rejected")
    end

    harness.assertEqual(#sentMessages, beforeMessages, "invalid menus must not reach React")
    harness.assertEqual(#focusCalls, beforeFocus, "invalid menus must not acquire focus")
end)

harness.test("openMenu grants focus while open and releases it once answered", function()
    Kora.nui.openMenu({ { id = "a", label = "A" } })

    local grant = focusCalls[#focusCalls]
    harness.assertTrue(grant.mouse and grant.keyboard, "focus should be granted when the menu opens")

    respondOk(lastRequestId(), { selectedId = "a" })

    local release = focusCalls[#focusCalls]
    harness.assertFalse(release.mouse or release.keyboard, "focus should be released the moment the menu is answered")
end)

harness.test("stopping a request owner closes its surface and releases only its focus lease", function()
    local originalCurrentResourceName = GetCurrentResourceName
    _G.GetCurrentResourceName = function() return "stopping_consumer" end
    local p = Kora.nui.openMenu({ { id = "a", label = "A" } })
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
    Kora.nui.openInputDialog({ { id = "f", label = "F", type = "text" } })
    respond(lastRequestId(), lastToken(), false, "NUI exploded")

    local release = focusCalls[#focusCalls]
    harness.assertFalse(release.mouse or release.keyboard, "a rejected request must still release focus")
end)

-- The focused retry waits a short SetTimeout; the shared mock never fires it, so run short
-- delays inline here (the 30s request timeout stays unfired).
local function withImmediateTimeouts(fn)
    local original = _G.SetTimeout
    _G.SetTimeout = function(ms, cb) if ms < 1000 then cb() end end
    local ok, err = pcall(fn)
    _G.SetTimeout = original
    if not ok then error(err, 0) end
end

harness.test("copyToClipboard takes no focus when the unfocused copy succeeds", function()
    local before = #focusCalls
    local p = Kora.nui.copyToClipboard("unfocused")
    respondOk(lastRequestId(), true)
    harness.assertEqual(#focusCalls, before, "a copy the browser accepts first time needs no focus lease")
    harness.assertEqual(p.value, true, "a successful copy resolves true")
end)

harness.test("copyToClipboard retries once under a passthrough focus lease when the browser refuses", function()
    withImmediateTimeouts(function()
        local before = #focusCalls
        local p = Kora.nui.copyToClipboard("focused")
        local first = lastRequestId()
        respondOk(first, false)
        harness.assertTrue(focusCalls[#focusCalls].mouse, "the retry should hold focus so CEF permits execCommand")
        harness.assertTrue(lastRequestId() ~= first, "the retry should send a fresh request")
        respondOk(lastRequestId(), true)
        harness.assertFalse(focusCalls[#focusCalls].mouse, "the focus lease should be released once the copy settles")
        harness.assertTrue(#focusCalls > before, "focus should have been granted and released")
        harness.assertEqual(p.value, true, "a successful retry resolves true")
    end)
end)

harness.test("copyToClipboard resolves false instead of rejecting when the browser copy fails", function()
    withImmediateTimeouts(function()
        local p = Kora.nui.copyToClipboard("nope")
        respondOk(lastRequestId(), false)
        respondOk(lastRequestId(), false)
        harness.assertEqual(p.state, "resolved", "a failed copy must not reject")
        harness.assertEqual(p.value, false, "a failed copy resolves false")
        harness.assertFalse(focusCalls[#focusCalls].mouse, "focus is released after a failed copy")
    end)
end)

harness.test("copyToClipboard with clipboardUnfocusedFirst = false copies once under the lease", function()
    withImmediateTimeouts(function()
        _G.Config = { nui = { clipboardUnfocusedFirst = false } }
        local p = Kora.nui.copyToClipboard("leased")
        _G.Config = nil
        harness.assertTrue(focusCalls[#focusCalls].mouse, "the lease is taken before the only attempt")
        respondOk(lastRequestId(), false)
        harness.assertEqual(p.value, false, "a refused leased copy resolves false without another attempt")
        harness.assertFalse(focusCalls[#focusCalls].mouse, "focus is released after the attempt")
    end)
end)

harness.test("copyToClipboard honours Config.nui.clipboardFocus = false", function()
    _G.Config = { nui = { clipboardFocus = false } }
    local before = #focusCalls
    Kora.nui.copyToClipboard("invisible")
    respondOk(lastRequestId(), true)
    _G.Config = nil
    harness.assertEqual(#focusCalls, before, "no focus should be taken when the option is disabled")
end)

harness.test("openContextMenu forwards items and an (x, y) anchor", function()
    local items = { { id = "a", label = "A" } }
    local p = Kora.nui.openContextMenu(items, 100, 200)

    local sent = sentMessages[#sentMessages]
    harness.assertEqual(sent.action, "openContextMenu", "openContextMenu should send the openContextMenu action")
    harness.assertEqual(sent.data.payload.x, 100, "x should be forwarded as-is")
    harness.assertEqual(sent.data.payload.y, 200, "y should be forwarded as-is")
    respondOk(lastRequestId(), { cancelled = true })
    harness.assertEqual(p.state, "resolved", "the context-menu test should settle its request")
end)

harness.test("openRadialMenu forwards shared menu items and optional geometry", function()
    local items = { { id = "repair", label = "Repair", icon = "Wrench" } }
    local p = Kora.nui.openRadialMenu(items, { radius = 180 })

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
    local p = Kora.nui.openRadialMenu({
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

    local cancelled = Kora.nui.openRadialMenu({ { id = "close", label = "Close" } })
    respondOk(lastRequestId(), { cancelled = true })
    harness.assertTrue(cancelled.value.cancelled, "backdrop/Escape cancellation should pass through unchanged")

    local cancelRelease = focusCalls[#focusCalls]
    harness.assertFalse(cancelRelease.mouse or cancelRelease.keyboard, "cancel should release radial focus immediately")
end)

harness.test("openRadialMenu rejects malformed geometry before sending", function()
    harness.assertThrows(function()
        Kora.nui.openRadialMenu({}, { radius = 0 })
    end, "a non-positive radius should be rejected")
end)

harness.test("openInputDialog forwards fields/title/description and resolves with the NUI's raw result", function()
    local fields = {
        { id = "amount", label = "Amount", type = "number" },
        { id = "date", label = "Date", type = "date", dateMin = 1788825600000, dateMax = 1791417600000 },
    }
    local p = Kora.nui.openInputDialog(fields, "Enter amount", "How much?")

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
        Kora.nui.openInputDialog({ { id = "amount", label = "Amount", type = "number", min = 10, max = 5 } })
    end, "invalid standalone field bounds should be rejected")
    harness.assertThrows(function()
        Kora.nui.openInputDialog({ { id = "kind", label = "Kind", type = "select" } })
    end, "standalone selects should require options just like AppShell forms")
    harness.assertThrows(function()
        Kora.nui.openInputDialog({ { id = "child", label = "Child", type = "text", dependsOn = "missing" } })
    end, "standalone dependent fields should reference a declared field")

    harness.assertEqual(#sentMessages, beforeMessages, "invalid standalone fields must not reach the browser")
    harness.assertEqual(#focusCalls, beforeFocus, "invalid standalone fields must not acquire a focus lease")
end)

harness.test("openAlert forwards optional artwork and manages focus until answered", function()
    local image = "nui://example-resource/web/images/preview.png"
    local p = Kora.nui.openAlert({ message = "Proceed?", image = image })

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
    harness.assertThrows(function() Kora.nui.openAlert({ message = "Proceed?", title = {} }) end)
    harness.assertThrows(function() Kora.nui.openAlert({ message = "Proceed?", cancellable = "no" }) end)
    harness.assertEqual(#sentMessages, beforeMessages, "invalid alerts must not reach React")
    harness.assertEqual(#focusCalls, beforeFocus, "invalid alerts must not acquire focus")
end)

harness.test("copyToClipboard requires a string", function()
    harness.assertThrows(function() Kora.nui.copyToClipboard(123) end, "a non-string should be rejected before anything is sent")
end)

harness.test("registerCallback forwards the handler's return value to the NUI", function()
    Kora.nui.registerCallback("smoke:echo", function(data) return { echoed = data.value } end)

    local response
    nuiCallbacks["smoke:echo"]({ value = "hi" }, function(r) response = r end)

    harness.assertEqual(response.echoed, "hi", "the handler's return value should be passed to cb")
end)

harness.test("registerCallback catches a handler error and still responds", function()
    Kora.nui.registerCallback("smoke:boom", function() error("kaboom") end)

    local response
    local ok = pcall(function()
        nuiCallbacks["smoke:boom"]({}, function(r) response = r end)
    end)

    harness.assertTrue(ok, "an erroring handler must not propagate the error out to the NUI dispatch")
    harness.assertTrue(response ~= nil, "cb should still be called so the NUI's fetch doesn't hang")
end)

harness.test("withFocus sets focus, runs fn, and always releases focus afterward", function()
    local ran = false
    local result, middle, tail = Kora.nui.withFocus(true, true, function()
        ran = true
        return "done", nil, "tail"
    end)

    harness.assertTrue(ran, "fn should have run")
    harness.assertEqual(result, "done", "withFocus should return fn's result")
    harness.assertEqual(middle, nil, "withFocus should preserve an interior nil return")
    harness.assertEqual(tail, "tail", "withFocus should preserve every return value")
    harness.assertEqual(focusCalls[#focusCalls - 1].mouse, true, "focus should have been set before fn ran")
    harness.assertEqual(focusCalls[#focusCalls].mouse, false, "focus should be released after fn returns")
end)

harness.test('withFocus rejects invalid arguments before acquiring focus', function()
    local focusCount = #focusCalls
    harness.assertThrows(function() Kora.nui.withFocus('yes', true, function() end) end)
    harness.assertThrows(function() Kora.nui.withFocus(true, true, false) end)
    harness.assertThrows(function() Kora.nui.withFocus(true, true, function() end, '') end)
    harness.assertEqual(#focusCalls, focusCount, 'invalid calls must not alter NUI focus')
end)

harness.test("explicit focus leases compose and release independently", function()
    local releaseMouse = Kora.nui.acquireFocus(true, false, true, "mouse-owner")
    local releaseKeyboard = Kora.nui.acquireFocus(false, true, false, "keyboard-owner")
    harness.assertTrue(focusCalls[#focusCalls].mouse and focusCalls[#focusCalls].keyboard,
        "combined leases should preserve both focus capabilities")
    harness.assertTrue(keepInputCalls[#keepInputCalls], "the keep-input lease should be composed")

    Kora.nui.releaseFocus(releaseMouse)
    harness.assertFalse(focusCalls[#focusCalls].mouse, "releasing the mouse lease should remove mouse focus")
    harness.assertTrue(focusCalls[#focusCalls].keyboard, "the independent keyboard lease should remain")
    harness.assertFalse(keepInputCalls[#keepInputCalls], "releasing its lease should restore keep-input state")

    Kora.nui.releaseFocus(releaseKeyboard)
    harness.assertFalse(focusCalls[#focusCalls].keyboard, "releasing the final lease should clear focus")
end)

harness.test("the final focus lease restores a pre-existing keep-input state", function()
    SetNuiFocusKeepInput(true)
    local release = Kora.nui.acquireFocus(true, true, false, "compat-owner")
    harness.assertFalse(keepInputCalls[#keepInputCalls], "the active lease should apply its own keep-input choice")

    Kora.nui.releaseFocus(release)
    harness.assertTrue(keepInputCalls[#keepInputCalls], "releasing the final lease should restore the prior keep-input state")

    -- Keep later smoke tests independent from this simulated external overlay.
    SetNuiFocusKeepInput(false)
end)

harness.test("withFocus releases focus even when fn errors, then re-raises", function()
    harness.assertThrows(function()
        Kora.nui.withFocus(true, true, function() error("nope") end)
    end, "the error should propagate out of withFocus")

    harness.assertEqual(focusCalls[#focusCalls].mouse, false, "focus should still be released after an error")
end)

harness.test("registerApp forwards draggable fields and applies Config.ui.apps.draggableDefault", function()
    local function sentApp(id, extra)
        local definition = { id = id, title = "Drag", navigation = { { id = "home", label = "Home" } } }
        for key, value in pairs(extra or {}) do definition[key] = value end
        Kora.nui.registerApp(definition)
        Kora.nui.openApp(id)
        local app = sentMessages[#sentMessages].data.payload.app
        local requestId, token = lastRequestId(), lastToken()
        respond(requestId, token, true, { closed = true, reason = "close" })
        return app
    end

    local optedIn = sentApp("smoke:drag-in", { draggable = true, rememberPosition = true, positionKey = "smoke-key" })
    harness.assertEqual(optedIn.draggable, true, "draggable should reach the browser")
    harness.assertEqual(optedIn.rememberPosition, true, "rememberPosition should reach the browser")
    harness.assertEqual(optedIn.positionKey, "smoke-key", "positionKey should reach the browser")
    harness.assertEqual(sentApp("smoke:drag-default").draggable, nil, "apps stay fixed unless they opt in")

    _G.Config = { ui = { apps = { draggableDefault = true } } }
    harness.assertEqual(sentApp("smoke:drag-cfg").draggable, true, "the config default should make apps draggable")
    harness.assertEqual(sentApp("smoke:drag-off", { draggable = false }).draggable, false, "an explicit false beats the config default")
    _G.Config = nil

    harness.assertFalse(pcall(Kora.nui.registerApp, { id = "smoke:drag-bad", title = "Bad", draggable = "yes", navigation = { { id = "home", label = "Home" } } }),
        "a non-boolean draggable should be rejected")
end)

harness.test("hold actions report one start and one end, and are released when the app closes", function()
    local calls = {}
    Kora.nui.registerApp({
        id = "smoke:hold",
        title = "Hold",
        navigation = { { id = "home", label = "Home", content = { actions = {
            { id = "horn", label = "Test horn", hold = true },
            { id = "plain", label = "Plain" },
        } } } },
        onAction = function(actionId, context) calls[#calls + 1] = { id = actionId, hold = context.hold, itemId = context.itemId } end,
    })
    Kora.nui.openApp("smoke:hold")
    local requestId, token = lastRequestId(), lastToken()
    local function hold(actionId, state, sessionToken)
        local response
        nuiCallbacks["kora_lib:app:hold"]({ appId = "smoke:hold", token = sessionToken or token, actionId = actionId,
            viewId = "home", itemId = "row-1", state = state }, function(result) response = result end)
        return response
    end

    harness.assertFalse(hold("horn", "start", "wrong").ok, "a hold with the wrong token must be rejected")
    harness.assertFalse(hold("plain", "start").ok, "an action without hold = true cannot be held")
    harness.assertFalse(hold("horn", "sideways").ok, "an unknown hold state must be rejected")
    harness.assertEqual(#calls, 0, "rejected holds never reach the handler")

    harness.assertTrue(hold("horn", "start").ok, "a declared hold action should start")
    harness.assertTrue(hold("horn", "start").ok, "a repeated start is accepted")
    harness.assertTrue(hold("horn", "end").ok, "a declared hold action should end")
    harness.assertTrue(hold("horn", "end").ok, "a repeated end is accepted")
    harness.assertEqual(#calls, 2, "the handler sees exactly one start and one end")
    harness.assertEqual(calls[1].hold, "start", "the first call is the press")
    harness.assertEqual(calls[1].itemId, "row-1", "the item identity reaches the handler")
    harness.assertEqual(calls[2].hold, "end", "the second call is the release")

    hold("horn", "start")
    respond(requestId, token, true, { closed = true, reason = "escape" })
    harness.assertEqual(#calls, 4, "closing the app mid-hold releases the held action")
    harness.assertEqual(calls[4].hold, "end", "the release on close is an end")

    harness.assertFalse(pcall(Kora.nui.registerApp, { id = "smoke:hold-bad", title = "Bad", navigation = { { id = "home", label = "Home",
        content = { actions = { { id = "x", label = "X", hold = true, confirm = "Sure?" } } } } } }),
        "a hold action with confirm should be rejected")
    harness.assertFalse(pcall(Kora.nui.registerApp, { id = "smoke:hold-type", title = "Bad", navigation = { { id = "home", label = "Home",
        content = { actions = { { id = "x", label = "X", hold = "yes" } } } } } }),
        "a non-boolean hold should be rejected")
end)

harness.test("chat blocks validate messages and declare their composer action", function()
    local calls = {}
    local function chatApp(id, block)
        return { id = id, title = "Chat", navigation = { { id = "home", label = "Home", content = { blocks = { block } } } },
            onAction = function(actionId, context) calls[#calls + 1] = { id = actionId, value = context.value } end }
    end
    Kora.nui.registerApp(chatApp("smoke:chat", { type = "chat", id = "conv", messages = {
        { id = "1", author = "Player", text = "hi", timestamp = "12:00", unread = true },
        { id = "2", author = "Staff", text = "hello", mine = true, badge = "Staff", tone = "success" },
    }, composer = { action = { id = "send", label = "Send" }, maxLength = 500, placeholder = "Reply" } }))
    Kora.nui.openApp("smoke:chat")
    local token = lastToken()
    local response
    nuiCallbacks["kora_lib:app:action"]({ appId = "smoke:chat", token = token, actionId = "send", viewId = "home",
        value = { message = "typed" } }, function(result) response = result end)
    harness.assertTrue(response.ok, "the composer action is declared")
    harness.assertEqual(calls[1].value.message, "typed", "the composed message reaches onAction")

    harness.assertFalse(pcall(Kora.nui.registerApp, chatApp("smoke:chat-noid", { type = "chat", messages = {} })),
        "a chat block needs an id")
    harness.assertFalse(pcall(Kora.nui.registerApp, chatApp("smoke:chat-dup", { type = "chat", id = "c", messages = {
        { id = "1", author = "A", text = "x" }, { id = "1", author = "B", text = "y" } } })), "duplicate message ids are rejected")
    harness.assertFalse(pcall(Kora.nui.registerApp, chatApp("smoke:chat-text", { type = "chat", id = "c", messages = {
        { id = "1", author = "A", text = 5 } } })), "message text must be a string")
    harness.assertFalse(pcall(Kora.nui.registerApp, chatApp("smoke:chat-fields", { type = "chat", id = "c", messages = {},
        composer = { action = { id = "send", label = "Send", fields = { { id = "x", label = "X", type = "text" } } } } })),
        "a composer action cannot carry fields")
    harness.assertFalse(pcall(Kora.nui.registerApp, chatApp("smoke:chat-max", { type = "chat", id = "c", messages = {},
        composer = { action = { id = "send", label = "Send" }, maxLength = 0 } })), "maxLength must be positive")
end)

harness.test("registerApp accepts left, right and center placement and rejects others", function()
    for _, placement in ipairs({ "left", "right", "center" }) do
        harness.assertTrue(pcall(Kora.nui.registerApp, { id = "smoke:place-" .. placement, title = "Place", placement = placement, navigation = { { id = "home", label = "Home" } } }),
            placement .. " placement should be accepted")
    end
    harness.assertFalse(pcall(Kora.nui.registerApp, { id = "smoke:place-bad", title = "Place", placement = "top", navigation = { { id = "home", label = "Home" } } }),
        "an unknown placement should be rejected")
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

    harness.assertEqual(Kora.nui.registerApp(definition), definition.id, "registerApp should return the stable app id")
    local p = Kora.nui.openApp(definition.id, { viewId = "people", data = { unit = 12 } })

    local sent = sentMessages[#sentMessages]
    harness.assertEqual(sent.action, "openApp", "openApp should send its dedicated action")
    local accent = sentMessages[#sentMessages - 1]
    harness.assertEqual(accent.action, "qbtheme:override", "the app accent should be applied through kora_lib's frame")
    harness.assertEqual(accent.data, definition.accent, "the configured app accent should be forwarded")
    harness.assertEqual(sent.data.payload.app.id, definition.id, "the registered browser definition should be sent")
    harness.assertEqual(sent.data.payload.app.onAction, nil, "Lua action handlers must never enter the JSON payload")
    harness.assertEqual(sent.data.payload.viewId, "people", "the requested initial view should be forwarded")
    harness.assertEqual(sent.data.payload.data.unit, 12, "private session data should be retained for the app instance")
    harness.assertTrue(Kora.nui.isAppOpen(definition.id), "isAppOpen should report the active registered app")

    local requestId, token = lastRequestId(), lastToken()
    respond(requestId, token, true, { closed = true, reason = "close", viewId = "people" })
    harness.assertEqual(p.value.reason, "close", "the browser close result should settle openApp")
    harness.assertFalse(Kora.nui.isAppOpen(), "settling openApp should clear the active instance")
    harness.assertEqual(sentMessages[#sentMessages].action, "qbtheme:override", "closing should reset the app accent")
    harness.assertEqual(sentMessages[#sentMessages].data, playerAccent, "closing should restore the player's /theme colour")
    harness.assertFalse(focusCalls[#focusCalls].mouse, "settling openApp should release NUI focus")
    harness.assertEqual(handled, nil, "opening the app should not invoke its action handler")
end)

harness.test("openApp validates navigation identifiers before creating a request", function()
    Kora.nui.registerApp({ id = "smoke:app-options", title = "Options", navigation = { { id = "home", label = "Home" } } })
    local messageCount, focusCount = #sentMessages, #focusCalls

    harness.assertThrows(function() Kora.nui.openApp("smoke:app-options", { viewId = 1 }) end,
        'a non-string viewId must fail before opening the app')
    harness.assertThrows(function() Kora.nui.openApp("smoke:app-options", { tabId = false }) end,
        'a non-string tabId must fail before opening the app')
    harness.assertEqual(#sentMessages, messageCount, 'invalid navigation identifiers must not send an NUI request')
    harness.assertEqual(#focusCalls, focusCount, 'invalid navigation identifiers must not acquire focus')
end)

harness.test("AppShell validates and forwards optional media card grids", function()
    local block = { type = "list", layout = "cards", cardStyle = "media", columns = 3,
        items = { { id = "event", label = "Giveaway", image = "event.png" } } }
    local definition = { id = "smoke:media-cards", title = "Events", navigation = {
        { id = "home", label = "Home", content = { blocks = { block } } },
    } }
    Kora.nui.registerApp(definition)
    Kora.nui.openApp(definition.id)
    local sent = sentMessages[#sentMessages].data.payload.app.navigation[1].content.blocks[1]
    harness.assertEqual(sent.cardStyle, "media", "the browser should receive the selected card style")
    harness.assertEqual(sent.columns, 3, "the browser should receive the maximum grid columns")
    respond(lastRequestId(), lastToken(), true, { closed = true })

    block.cardStyle = "compact"
    harness.assertEqual(Kora.nui.registerApp(definition), definition.id, "explicit compact style remains supported")
    block.cardStyle = "poster"
    harness.assertThrows(function() Kora.nui.registerApp(definition) end, "unknown card styles must be rejected")
    block.cardStyle = "media"
    for _, columns in ipairs({ 0, 5, 1.5, "2", false, math.huge, 0 / 0 }) do
        block.columns = columns
        harness.assertThrows(function() Kora.nui.registerApp(definition) end, "invalid grid columns must be rejected")
    end
    block.columns = 2
    harness.assertTrue(Kora.nui.updateApp(definition.id, { navigation = definition.navigation }), "updates should accept media grids")
end)

harness.test("AppShell validates image fit on collections and nested items", function()
    local child = { id = "child", label = "Child", image = "child.png", imageFit = "cover" }
    local block = { type = "list", layout = "cards", imageFit = "contain", items = {
        { id = "parent", label = "Parent", children = { child } },
    } }
    local definition = { id = "smoke:image-fit", title = "Images", navigation = {
        { id = "home", label = "Home", content = { blocks = { block } } },
    } }
    Kora.nui.registerApp(definition)
    Kora.nui.openApp(definition.id)
    local sent = sentMessages[#sentMessages].data.payload.app.navigation[1].content.blocks[1]
    harness.assertEqual(sent.imageFit, "contain", "the browser should receive the collection image fit")
    harness.assertEqual(sent.items[1].children[1].imageFit, "cover", "nested item overrides should reach the browser")
    respond(lastRequestId(), lastToken(), true, { closed = true })

    for _, imageFit in ipairs({ "cover", "contain", "fill", "none", "scale-down" }) do
        block.imageFit, child.imageFit = imageFit, imageFit
        harness.assertEqual(Kora.nui.registerApp(definition), definition.id, "native image fit values should be supported")
    end
    for _, invalid in ipairs({ "stretch", "", false, 42, {} }) do
        block.imageFit, child.imageFit = invalid, "cover"
        harness.assertThrows(function() Kora.nui.registerApp(definition) end, "invalid collection image fit must be rejected")
        block.imageFit, child.imageFit = "contain", invalid
        harness.assertThrows(function() Kora.nui.registerApp(definition) end, "invalid nested image fit must be rejected")
    end
end)

harness.test("AppShell validates image aspect on collections and items", function()
    local item = { id = "car", label = "Car", image = "car.png", imageAspect = "wide" }
    local block = { type = "list", imageAspect = "square", items = { item } }
    local definition = { id = "smoke:image-aspect", title = "Images", navigation = {
        { id = "home", label = "Home", content = { blocks = { block } } },
    } }
    harness.assertEqual(Kora.nui.registerApp(definition), definition.id, "square and wide aspects should be supported")
    for _, invalid in ipairs({ "tall", "", false, 42, {} }) do
        block.imageAspect, item.imageAspect = invalid, "wide"
        harness.assertThrows(function() Kora.nui.registerApp(definition) end, "invalid collection image aspect must be rejected")
        block.imageAspect, item.imageAspect = "wide", invalid
        harness.assertThrows(function() Kora.nui.registerApp(definition) end, "invalid item image aspect must be rejected")
    end
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

    harness.assertEqual(Kora.nui.registerApp(definition), definition.id,
        "a valid bounded progress graph should register")
    harness.assertThrows(function()
        Kora.nui.registerApp({
            id = "smoke:bad-progress", title = "Bad progress", navigation = {
                { id = "skills", label = "Skills", content = { blocks = {
                    { type = "progress", items = { { label = "Mining", value = 101, max = 100 } }, },
                } } },
            },
        })
    end, "progress values above max must be rejected before they reach the browser")

    harness.assertThrows(function()
        Kora.nui.registerApp({
            id = "smoke:bad-progress-infinity", title = "Bad progress", navigation = {
                { id = "skills", label = "Skills", content = { blocks = {
                    { type = "progress", items = { { label = "Mining", value = 1, max = math.huge } }, },
                } } },
            },
        })
    end, "non-finite progress values must be rejected before they reach the browser")
end)

harness.test("an app without its own accent keeps the player's /theme colour", function()
    Kora.nui.registerApp({
        id = "smoke:player-theme",
        title = "Player theme",
        navigation = { { id = "home", label = "Home" } },
    })
    local p = Kora.nui.openApp("smoke:player-theme")

    local open = sentMessages[#sentMessages]
    local accent = sentMessages[#sentMessages - 1]
    harness.assertEqual(accent.action, "qbtheme:override", "opening should apply the effective theme through qbtheme")
    harness.assertEqual(accent.data, playerAccent, "an unthemed app must retain the player's saved colour")

    respond(open.data.requestId, open.data.token, true, { closed = true, reason = "close" })
    harness.assertEqual(p.value.reason, "close", "the unthemed app should still settle normally")
end)

harness.test("AppShell actions require the active token and route context to the registered handler", function()
    local receivedAction, receivedContext
    Kora.nui.registerApp({
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
    Kora.nui.openApp("smoke:actions", { data = { officer = "312" } })
    local requestId, token = lastRequestId(), lastToken()

    local forged
    nuiCallbacks["kora_lib:app:action"]({
        appId = "smoke:actions", token = "wrong", actionId = "refresh", viewId = "dashboard",
    }, function(result) forged = result end)
    harness.assertFalse(forged.ok, "an action with the wrong app token must be rejected")
    harness.assertEqual(receivedAction, nil, "a forged action must never reach the owning handler")

    local response
    nuiCallbacks["kora_lib:app:action"]({
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

harness.test("AppShell changes validate sessions and forms, update content, and keep focus", function()
    local received, update = nil, { footer = "Total: $30" }
    Kora.nui.registerApp({
        id = "smoke:changes", title = "Changes",
        navigation = { { id = "home", label = "Home", content = {
            actions = { { id = "refresh", label = "Refresh" } },
            blocks = { { type = "form", id = "fuel", fields = {
                { id = "quantity", label = "Amount", type = "range", min = 1, max = 50 },
            }, action = { id = "fill", label = "Fill", closeBeforeAction = true } } },
        } } },
        onChange = function(actionId, context)
            received = { actionId, context }
            return update
        end,
    })
    local pending = Kora.nui.openApp("smoke:changes", { data = { vehicle = 12 } })
    local requestId, token = lastRequestId(), lastToken()
    harness.assertEqual(sentMessages[#sentMessages].data.payload.app.onChange, true,
        "only the presence of the handler should enter the browser payload")
    local function change(sessionToken, actionId, value)
        local response
        nuiCallbacks["kora_lib:app:change"]({ appId = "smoke:changes", token = sessionToken,
            actionId = actionId, viewId = "home", itemId = "pump", value = value },
            function(result) response = result end)
        return response
    end
    harness.assertFalse(change("wrong", "fill", { quantity = 10 }).ok)
    harness.assertFalse(change(token, "missing", { quantity = 10 }).ok)
    harness.assertFalse(change(token, "refresh", { quantity = 10 }).ok)
    harness.assertFalse(change(token, "fill", 10).ok)
    harness.assertEqual(received, nil, "invalid changes must not invoke the handler")
    local response = change(token, "fill", { quantity = 10 })
    harness.assertTrue(response.ok)
    harness.assertEqual(received[1], "fill")
    harness.assertEqual(received[2].value.quantity, 10)
    harness.assertEqual(received[2].data.vehicle, 12)
    harness.assertEqual(received[2].itemId, "pump")
    harness.assertEqual(response.result.app.footer, "Total: $30")
    harness.assertTrue(Kora.nui.isAppOpen("smoke:changes"), "closeBeforeAction must not close on edits")
    harness.assertEqual(pending.state, "pending", "changes must not settle the open request")
    update = { navigation = {} }
    harness.assertFalse(change(token, "fill", { quantity = 20 }).ok, "invalid updates must be rejected")
    update = nil
    harness.assertTrue(change(token, "fill", { quantity = "" }).ok, "incomplete drafts can be ignored")
    harness.assertThrows(function() Kora.nui.updateApp("smoke:changes", { onChange = true }) end)
    respond(requestId, token, true, { closed = true, reason = "close" })
    harness.assertFalse(change(token, "fill", { quantity = 10 }).ok, "closed sessions must be rejected")
end)

harness.test("AppShell discards yielding change handlers after newer edits", function()
    Kora.nui.registerApp({
        id = "smoke:change-order", title = "Changes", navigation = { { id = "home", label = "Home",
            content = { actions = { { id = "edit", label = "Edit", fields = {
                { id = "quantity", label = "Amount", type = "number" },
            } } } } } },
        onChange = function(_, context)
            if context.value.quantity == 1 then coroutine.yield() end
            return { footer = tostring(context.value.quantity) }
        end,
    })
    Kora.nui.openApp("smoke:change-order")
    local token, oldResult, newResult = lastToken()
    local function change(quantity, cb)
        nuiCallbacks["kora_lib:app:change"]({ appId = "smoke:change-order", token = token,
            actionId = "edit", value = { quantity = quantity } }, cb)
    end
    local older = coroutine.create(function() change(1, function(result) oldResult = result end) end)
    harness.assertTrue(coroutine.resume(older))
    change(2, function(result) newResult = result end)
    harness.assertEqual(newResult.result.app.footer, "2")
    harness.assertTrue(coroutine.resume(older))
    harness.assertEqual(oldResult.result, nil, "an old handler must not return stale content")
    respond(lastRequestId(), token, true, { closed = true, reason = "close" })
end)

harness.test("AppShell accepts inline action field schemas and forwards submitted values", function()
    local received
    Kora.nui.registerApp({
        id = "smoke:inline-fields",
        title = "Inline fields",
        navigation = { { id = "home", label = "Home", content = { actions = {
            { id = "warn", label = "Warn", fields = { { id = "reason", label = "Reason", type = "text", required = true } }, confirm = "This is recorded." },
        } } } },
        onAction = function(_, context) received = context.value end,
    })
    Kora.nui.openApp("smoke:inline-fields")
    local _, token = lastRequestId(), lastToken()
    local response
    nuiCallbacks["kora_lib:app:action"]({
        appId = "smoke:inline-fields", token = token, actionId = "warn", viewId = "home", value = { reason = "Be civil" },
    }, function(result) response = result end)
    harness.assertTrue(response.ok, "an inline-field action should be accepted")
    harness.assertEqual(received.reason, "Be civil", "submitted inline values should reach the action handler")
end)

harness.test("updateApp refreshes an active definition and closeApp settles through the browser", function()
    Kora.nui.registerApp({
        id = "smoke:lifecycle",
        title = "Lifecycle",
        navigation = { { id = "home", label = "Home" } },
    })
    Kora.nui.openApp("smoke:lifecycle")
    local requestId, token = lastRequestId(), lastToken()

    harness.assertTrue(Kora.nui.updateApp("smoke:lifecycle", { footer = "Live" }), "a registered app should update")
    local update = sentMessages[#sentMessages]
    harness.assertEqual(update.action, "updateApp", "an active update should be pushed to the browser")
    harness.assertEqual(update.data.app.footer, "Live", "the merged definition should be pushed")
    harness.assertEqual(update.data.token, token, "the active instance token should guard updates")

    harness.assertTrue(Kora.nui.closeApp("smoke:lifecycle"), "closeApp should start closing the active app")
    local close = sentMessages[#sentMessages]
    harness.assertEqual(close.action, "closeApp", "closeApp should ask the shell to settle")
    harness.assertEqual(close.data.reason, "api", "programmatic closes should identify their reason")

    respond(requestId, token, true, { closed = true, reason = "api" })
    harness.assertFalse(Kora.nui.isAppOpen("smoke:lifecycle"), "the app should no longer be active after its response")
    harness.assertFalse(Kora.nui.closeApp("smoke:lifecycle"), "closing an inactive app should be a harmless false")
end)

harness.test("registered apps are removed and closed automatically when their owner stops", function()
    Kora.nui.registerApp({
        id = "smoke:owned",
        title = "Owned",
        navigation = { { id = "home", label = "Home" } },
    })
    local opened = Kora.nui.openApp("smoke:owned")
    local requestId, token = lastRequestId(), lastToken()

    net.fire("onClientResourceStop", "kora_lib_test")
    local close = lastMessage("closeApp")
    harness.assertEqual(close.action, "closeApp", "owner shutdown should close the visible app")
    harness.assertEqual(close.data.reason, "resourceStop", "owner shutdown should identify the close reason")
    harness.assertEqual(opened.state, "resolved", "owner shutdown should settle immediately without relying on the browser")
    harness.assertFalse(Kora.nui.isAppOpen(), "owner shutdown should release the active app immediately")
    harness.assertFalse(focusCalls[#focusCalls].mouse, "owner shutdown should release NUI focus immediately")

    respond(requestId, token, true, { closed = true, reason = "resourceStop" })
    harness.assertThrows(function() Kora.nui.openApp("smoke:owned") end,
        "an app should no longer be registered after its owner stops")
end)

harness.test("only an app owner can mutate or close its app", function()
    _G.GetInvokingResource = function() return "app_owner" end
    Kora.nui.registerApp({ id = "smoke:owned-boundary", title = "Owned", navigation = { { id = "home", label = "Home" } } })
    _G.GetInvokingResource = function() return nil end
    local opened = Kora.nui.openApp("smoke:owned-boundary")
    local requestId, token = lastRequestId(), lastToken()

    _G.GetInvokingResource = function() return "other_resource" end
    harness.assertThrows(function()
        Kora.nui.registerApp({ id = "smoke:owned-boundary", title = "Foreign", navigation = { { id = "home", label = "Home" } } })
    end, "a foreign resource must not replace the app")
    harness.assertThrows(function() Kora.nui.closeApp("smoke:owned-boundary") end,
        "a foreign resource must not close the app")
    harness.assertThrows(function() Kora.nui.updateApp("smoke:owned-boundary", { footer = "Foreign" }) end,
        "a foreign resource must not update the app")
    harness.assertThrows(function() Kora.nui.unregisterApp("smoke:owned-boundary") end,
        "a foreign resource must not unregister the app")

    _G.GetInvokingResource = function() return "app_owner" end
    harness.assertTrue(Kora.nui.closeApp("smoke:owned-boundary"), "the owner should close its app")
    respond(requestId, token, true, { closed = true, reason = "api" })
    harness.assertEqual(opened.value.reason, "api")
    _G.GetInvokingResource = function() return nil end
end)

harness.test("opening a second app releases old focus before granting focus to the new app", function()
    Kora.nui.registerApp({ id = "smoke:first", title = "First", navigation = { { id = "home", label = "Home" } } })
    Kora.nui.registerApp({ id = "smoke:second", title = "Second", navigation = { { id = "home", label = "Home" } } })

    local first = Kora.nui.openApp("smoke:first")
    local second = Kora.nui.openApp("smoke:second")
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
        Kora.nui.registerApp({
            id = "smoke:invalid",
            title = "Invalid",
            navigation = { { id = "home", label = "Home", disabled = true } },
        })
    end, "an app with no enabled view must be rejected")

    harness.assertThrows(function()
        Kora.nui.registerApp({
            id = "smoke:bad-block",
            title = "Invalid block",
            navigation = { { id = "home", label = "Home", content = { blocks = { { type = "table" } } } } },
        })
    end, "a malformed standard content block must be rejected before opening")

    harness.assertThrows(function()
        Kora.nui.registerApp({
            id = "smoke:bad-accent",
            title = "Invalid accent",
            accent = "blue",
            navigation = { { id = "home", label = "Home" } },
        })
    end, "an invalid app accent must be rejected before opening")
end)

harness.test("nested dialogs release only their own focus lease while AppShell remains open", function()
    Kora.nui.registerApp({ id = "smoke:nested-focus", title = "Nested", navigation = { { id = "home", label = "Home" } } })
    local app = Kora.nui.openApp("smoke:nested-focus")
    local appRequestId, appToken = lastRequestId(), lastToken()
    local dialog = Kora.nui.openInputDialog({ { id = "note", label = "Note", type = "text" } })

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
    Kora.nui.registerApp({
        id = "smoke:declared-actions",
        title = "Declared actions",
        navigation = { { id = "home", label = "Home", content = { actions = {
            { id = "allowed", label = "Allowed" },
        } } } },
        onAction = function() called = true end,
    })
    Kora.nui.openApp("smoke:declared-actions")
    local requestId, token = lastRequestId(), lastToken()
    local response
    nuiCallbacks["kora_lib:app:action"]({ appId = "smoke:declared-actions", token = token,
        actionId = "undeclared", viewId = "home" }, function(value) response = value end)
    harness.assertFalse(response.ok, "an undeclared action should be rejected")
    harness.assertFalse(called, "an undeclared action must not reach the owner")
    respond(requestId, token, true, { closed = true, reason = "close" })
end)

harness.test("closeBeforeAction settles AppShell and releases focus before owner code runs", function()
    local focusedDuringHandler
    Kora.nui.registerApp({
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
    local opened = Kora.nui.openApp("smoke:close-before")
    local _, token = lastRequestId(), lastToken()
    local response
    nuiCallbacks["kora_lib:app:action"]({ appId = "smoke:close-before", token = token,
        actionId = "editor", viewId = "home" }, function(value) response = value end)
    harness.assertTrue(response.ok, "a declared close-before action should run")
    harness.assertEqual(opened.state, "resolved", "the shell request should settle before the handler returns")
    harness.assertFalse(focusedDuringHandler, "the owner handler must run after AppShell releases focus")
    harness.assertFalse(Kora.nui.isAppOpen(), "the shell should no longer be active")
end)

harness.test("closeBeforeAction reports owner failures after the shell is gone", function()
    local notified
    Kora.notify.send = function(options) notified = options end
    Kora.nui.registerApp({
        id = "smoke:close-before-error",
        title = "Close before error",
        navigation = { { id = "home", label = "Home", content = { actions = {
            { id = "editor", label = "Open editor", closeBeforeAction = true },
        } } } },
        onAction = function() error("editor failed") end,
    })
    local opened = Kora.nui.openApp("smoke:close-before-error")
    local token = lastToken()
    local response
    nuiCallbacks["kora_lib:app:action"]({ appId = "smoke:close-before-error", token = token,
        actionId = "editor", viewId = "home" }, function(value) response = value end)

    harness.assertFalse(response.ok, "an owner failure should be returned to the browser callback")
    harness.assertEqual(opened.state, "resolved", "the shell should already be settled when the owner fails")
    harness.assertEqual(notified.type, "error", "a closed-shell failure must be visible as an error notification")
end)

harness.test("AppShell validates and returns navigation and notice action results", function()
    Kora.nui.registerApp({
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
    Kora.nui.openApp("smoke:result-shapes")
    local requestId, token = lastRequestId(), lastToken()
    local response
    nuiCallbacks["kora_lib:app:action"]({ appId = "smoke:result-shapes", token = token,
        actionId = "go", viewId = "home" }, function(value) response = value end)
    harness.assertTrue(response.ok, "valid result shapes should be accepted")
    harness.assertEqual(response.result.navigate.viewId, "records", "navigation should pass to the browser")
    harness.assertEqual(response.result.notice.message, "Moved.", "notice should pass to the browser")
    respond(requestId, token, true, { closed = true, reason = "close" })
end)

harness.test("AppShell declares lazy view actions and typed configuration fields", function()
    local received
    Kora.nui.registerApp({
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
    Kora.nui.openApp("smoke:lazy-view")
    local requestId, token = lastRequestId(), lastToken()
    local response
    nuiCallbacks["kora_lib:app:action"]({ appId = "smoke:lazy-view", token = token,
        actionId = "load-resource", viewId = "home", itemId = "resource" }, function(value) response = value end)
    harness.assertTrue(response.ok, "a declared view-open action should be callable")
    harness.assertEqual(received[1], "load-resource", "the lazy action should reach its owner")
    harness.assertEqual(received[2], "resource", "the opened view id should reach its owner")
    respond(requestId, token, true, { closed = true, reason = "close" })
end)

harness.test("AppShell applies updates before validating result navigation", function()
    Kora.nui.registerApp({
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
    Kora.nui.openApp("smoke:update-navigation")
    local requestId, token = lastRequestId(), lastToken()
    local response
    nuiCallbacks["kora_lib:app:action"]({ appId = "smoke:update-navigation", token = token,
        actionId = "load", viewId = "home" }, function(value) response = value end)

    harness.assertTrue(response.ok, "navigation may target a view introduced by the same result update")
    harness.assertEqual(response.result.app.navigation[2].id, "records", "the validated replacement definition should reach the browser")
    harness.assertEqual(response.result.navigate.tabId, "new", "the navigation result should remain intact")
    respond(requestId, token, true, { closed = true, reason = "close" })
end)

harness.test("AppShell recursively validates dependent fields and nested collection actions", function()
    harness.assertThrows(function()
        Kora.nui.registerApp({
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
    Kora.nui.registerApp({
        id = "smoke:nested-action",
        title = "Nested list",
        navigation = { { id = "home", label = "Home", content = { blocks = { {
            type = "list", items = { { id = "parent", label = "Parent", children = {
                { id = "child", label = "Child", action = "open-child" },
            } } },
        } } } } },
        onAction = function(action) called = action end,
    })
    Kora.nui.openApp("smoke:nested-action")
    local requestId, token = lastRequestId(), lastToken()
    local response
    nuiCallbacks["kora_lib:app:action"]({ appId = "smoke:nested-action", token = token,
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
        { id = "infinite-min", label = "Infinite min", type = "number", min = math.huge },
        { id = "infinite-step", label = "Infinite step", type = "number", step = math.huge },
        { id = "infinite-default", label = "Infinite default", type = "number", default = math.huge },
        { id = "infinite-vector", label = "Infinite vector", type = "vector", dimensions = 3,
            default = { x = 0, y = 0 / 0, z = 0 } },
        { id = "default", label = "Default", type = "multiselect", options = {}, default = "one" },
        { id = "visible", label = "Visible", type = "text", visibleWhen = { fieldId = "visible", equals = {} } },
    }
    for index, field in ipairs(invalidFields) do
        harness.assertThrows(function() Kora.nui.registerApp(appWithField("bad-field-" .. index, field)) end,
            "malformed field contracts must be rejected recursively")
    end

    harness.assertThrows(function()
        Kora.nui.registerApp({
            id = "smoke:bad-default-tab", title = "Invalid tab",
            navigation = { { id = "home", label = "Home", defaultTab = "missing", tabs = {
                { id = "present", label = "Present" },
            } } },
        })
    end, "defaultTab must name a declared tab")

    harness.assertThrows(function()
        Kora.nui.registerApp({
            id = "smoke:bad-list-layout", title = "Invalid list",
            navigation = { { id = "home", label = "Home", content = { blocks = { {
                type = "list", layout = "carousel", searchable = "yes", pageSize = 0, items = {},
            } } } } },
        })
    end, "list layout and paging/search options must use supported types")

    harness.assertThrows(function()
        Kora.nui.registerApp({
            id = "smoke:bad-table-sort", title = "Invalid table",
            navigation = { { id = "home", label = "Home", content = { blocks = { {
                type = "table", columns = { { key = "name", label = "Name", sortable = "yes" } }, rows = {},
            } } } } },
        })
    end, "table sorting options must use supported types")

    harness.assertThrows(function()
        Kora.nui.registerApp({
            id = "smoke:bad-table-empty", title = "Invalid table empty state",
            navigation = { { id = "home", label = "Home", content = { blocks = { {
                type = "table", columns = { { key = "name", label = "Name" } }, rows = {},
                empty = { title = "Not valid here" },
            } } } } },
        })
    end, "table empty states must be strings so React never receives a table child")
end)

harness.test("AppShell rejects non-finite map points before registering", function()
    harness.assertThrows(function()
        Kora.nui.registerApp({
            id = "smoke:invalid-map", title = "Invalid map",
            navigation = { { id = "home", label = "Home", content = { blocks = { {
                type = "map", tiles = { url = "https://tiles.example/{z}/{x}/{y}.png", grid = { x = math.huge, y = 1 } },
                markers = {},
            } } } } },
        })
    end, "non-finite map calibration values must be rejected")

    harness.assertThrows(function()
        Kora.nui.registerApp({
            id = "smoke:invalid-marker", title = "Invalid marker",
            navigation = { { id = "home", label = "Home", content = { blocks = { {
                type = "map", tiles = { url = "https://tiles.example/{z}/{x}/{y}.png", tileSize = 256 },
                markers = { { id = "marker", x = 0 / 0, y = 1, label = "Broken" } },
            } } } } },
        })
    end, "non-finite marker geometry must be rejected")
end)

harness.test("dispatch feed replays its latest state and cleans up only its owner without taking focus", function()
    local previousCaller = GetInvokingResource
    local previousClock = GetGameTimer
    local clock = 1000
    GetGameTimer = function() return clock end
    local caller = 'kora_dispatch'
    GetInvokingResource = function() return caller end
    local beforeFocus = #focusCalls
    local function ready()
        local result
        nuiCallbacks['kora_lib:dispatchfeed:ready']({}, function(value) result = value end)
        harness.assertEqual(result, true, 'ready acknowledges without returning incident data')
        harness.assertEqual(sentMessages[#sentMessages].action, 'qbdispatch:feed')
        return sentMessages[#sentMessages].data
    end
    harness.assertEqual(ready(), false)
    harness.assertTrue(type(registeredExports.nui_setDispatchFeed) == 'function')
    local first = { now = 100, calls = {} }
    local latest = { now = 200, calls = {}, hidden = true }
    harness.assertTrue(registeredExports.nui_setDispatchFeed(first))
    harness.assertTrue(Kora.nui.setDispatchFeed(latest))
    clock = 3500
    local replay = ready()
    harness.assertEqual(replay.now, 2700, 'late readiness includes time since publication')
    harness.assertEqual(replay.calls, latest.calls, 'replay retains the newest call data')
    harness.assertTrue(replay.hidden)
    harness.assertEqual(latest.now, 200, 'replay does not mutate the caller snapshot')

    caller = 'other'
    local beforeMessages = #sentMessages
    harness.assertFalse(Kora.nui.setDispatchFeed(first))
    harness.assertFalse(Kora.nui.setDispatchFeed(false))
    net.fire('onClientResourceStop', 'other')
    harness.assertEqual(#sentMessages, beforeMessages, 'foreign operations never alter the feed')
    harness.assertEqual(ready().now, 2700)

    caller = 'kora_dispatch'
    harness.assertTrue(Kora.nui.setDispatchFeed(false))
    caller = 'other'
    harness.assertTrue(Kora.nui.setDispatchFeed(first))
    net.fire('onClientResourceStop', 'kora_dispatch')
    harness.assertEqual(ready().now, first.now, 'an old owner cannot clear its successor')
    net.fire('onClientResourceStop', 'other')
    harness.assertEqual(ready(), false)
    harness.assertThrows(function() Kora.nui.setDispatchFeed(nil) end)
    harness.assertThrows(function() Kora.nui.setDispatchFeed(true) end)
    harness.assertThrows(function() Kora.nui.setDispatchFeed({}) end)
    harness.assertThrows(function() Kora.nui.setDispatchFeed({ now = math.huge }) end)

    caller = 'shop'
    local release = Kora.nui.acquireFocus(true, true)
    local focusedCalls = #focusCalls
    caller = 'kora_dispatch'
    Kora.nui.setDispatchFeed(first)
    ready()
    Kora.nui.setDispatchFeed(false)
    harness.assertEqual(#focusCalls, focusedCalls, 'feed publication leaves a focused interaction alone')
    release()
    harness.assertEqual(#focusCalls, beforeFocus + 2, 'only the unrelated lease acquires and releases focus')
    GetInvokingResource = previousCaller
    GetGameTimer = previousClock
end)

harness.test("pickPosition is vector-only and kora_lib:form:position answers the local position", function()
    harness.assertThrows(function()
        Kora.nui.openInputDialog({ { id = "name", label = "Name", type = "text", pickPosition = true } })
    end, "pickPosition on a non-vector field should be rejected")
    harness.assertThrows(function()
        Kora.nui.openInputDialog({ { id = "spot", label = "Spot", type = "vector", dimensions = 4, pickPosition = { vehicle = "yes" } } })
    end, "a non-boolean pickPosition.vehicle should be rejected")

    local previous = { cache = Kora.cache, exists = _G.DoesEntityExist, coords = _G.GetEntityCoords, heading = _G.GetEntityHeading }
    local seated = false
    Kora.cache = { ped = function() return 11 end, vehicle = function() return seated and 22 or false end }
    _G.DoesEntityExist = function(entity) return entity == 11 or entity == 22 end
    _G.GetEntityCoords = function(entity) return entity == 22 and { x = 5.555, y = 6, z = 7 } or { x = 10.126, y = -20.5, z = 30.005 } end
    _G.GetEntityHeading = function(entity) return entity == 22 and 270.456 or 90.114 end

    local onFoot, inVehicle, vehicleOnFoot, plain
    nuiCallbacks["kora_lib:form:position"]({ vehicle = false }, function(value) onFoot = value end)
    nuiCallbacks["kora_lib:form:position"]({ vehicle = true }, function(value) vehicleOnFoot = value end)
    seated = true
    nuiCallbacks["kora_lib:form:position"]({ vehicle = true }, function(value) inVehicle = value end)
    nuiCallbacks["kora_lib:form:position"]({}, function(value) plain = value end)

    Kora.cache, _G.DoesEntityExist, _G.GetEntityCoords, _G.GetEntityHeading = previous.cache, previous.exists, previous.coords, previous.heading

    harness.assertEqual(onFoot.x, 10.13); harness.assertEqual(onFoot.z, 30.01); harness.assertEqual(onFoot.w, 90.11)
    harness.assertEqual(vehicleOnFoot.w, 90.11, "vehicle = true on foot falls back to the ped")
    harness.assertEqual(inVehicle.x, 5.56); harness.assertEqual(inVehicle.w, 270.46)
    harness.assertEqual(plain.w, 90.11, "the vehicle is only used when asked for")
end)

harness.test("internal NUI callbacks keep answering under their deprecated qblib: names", function()
    for _, name in ipairs({ "nui:response", "nui:event", "app:action", "app:change", "dispatchfeed:ready" }) do
        harness.assertTrue(nuiCallbacks["kora_lib:" .. name] ~= nil, "missing kora_lib:" .. name)
        harness.assertTrue(nuiCallbacks["qblib:" .. name] ~= nil, "missing deprecated qblib:" .. name)
    end
end)

-- Runs last: it simulates kora_lib itself stopping.
harness.test("kora_lib stopping releases focus still leased by a consumer", function()
    Kora.nui.requestAsync("openAlert", { message = "Held" }, false, "consumer_shop", true)
    harness.assertTrue(focusCalls[#focusCalls].mouse, "sanity: the consumer request holds focus")
    net.fire("onClientResourceStop", GetCurrentResourceName())
    harness.assertFalse(focusCalls[#focusCalls].mouse, "the cursor must not outlive kora_lib's frame")
    harness.assertFalse(focusCalls[#focusCalls].keyboard, "keyboard focus must be released too")
end)

harness.report("nui")
