local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")

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

_G.RegisterNUICallback = function(name, fn)
    nuiCallbacks[name] = fn
end

_G.SendNUIMessage = function(payload)
    table.insert(sentMessages, payload)
end

_G.SetNuiFocus = function(mouse, keyboard)
    table.insert(focusCalls, { mouse = mouse, keyboard = keyboard })
end

dofile(repoRoot .. "modules/nui/client.lua")

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

-- The qblib:nui:theme callback now lives in modules/theme/client.lua (see
-- test/smoke/theme.lua) -- this file no longer dofiles that module, so those
-- assertions moved rather than duplicated.

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
    }
    QB.nui.openMenu({ { id = "a", label = "A" } }, "Compact", opts)

    local payload = sentMessages[#sentMessages].data.payload
    harness.assertEqual(payload.position, opts.position, "position should be forwarded as-is")
    harness.assertEqual(payload.maxWidth, 400, "maxWidth should be forwarded")
    harness.assertEqual(payload.maxHeight, 680, "maxHeight should be forwarded")
end)

harness.test("openMenu grants focus while open and releases it once answered", function()
    QB.nui.openMenu({ { id = "a", label = "A" } })

    local grant = focusCalls[#focusCalls]
    harness.assertTrue(grant.mouse and grant.keyboard, "focus should be granted when the menu opens")

    respondOk(lastRequestId(), { selectedId = "a" })

    local release = focusCalls[#focusCalls]
    harness.assertFalse(release.mouse or release.keyboard, "focus should be released the moment the menu is answered")
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
    QB.nui.openContextMenu(items, 100, 200)

    local sent = sentMessages[#sentMessages]
    harness.assertEqual(sent.action, "openContextMenu", "openContextMenu should send the openContextMenu action")
    harness.assertEqual(sent.data.payload.x, 100, "x should be forwarded as-is")
    harness.assertEqual(sent.data.payload.y, 200, "y should be forwarded as-is")
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
    local fields = { { id = "amount", label = "Amount", type = "number" } }
    local p = QB.nui.openInputDialog(fields, "Enter amount", "How much?")

    local sent = sentMessages[#sentMessages]
    harness.assertEqual(sent.action, "openInputDialog", "openInputDialog should send the openInputDialog action")
    harness.assertEqual(sent.data.payload.fields, fields, "the fields table should be forwarded as-is")
    harness.assertEqual(sent.data.payload.description, "How much?", "the description should be forwarded as-is")

    respondOk(lastRequestId(), { values = { amount = 5 } })
    harness.assertEqual(p.value.values.amount, 5, "should resolve with the NUI's raw InputDialogResult")
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

harness.test("withFocus releases focus even when fn errors, then re-raises", function()
    harness.assertThrows(function()
        QB.nui.withFocus(true, true, function() error("nope") end)
    end, "the error should propagate out of withFocus")

    harness.assertEqual(focusCalls[#focusCalls].mouse, false, "focus should still be released after an error")
end)

harness.report("nui")
