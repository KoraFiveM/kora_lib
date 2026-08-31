local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

-- server.lua and client.lua register their net events under disjoint names
-- (register/push vs. trigger/onPush), so loading both into this one mocked
-- process gives a genuine client <-> server round trip through
-- TriggerServerEvent/TriggerClientEvent, without needing to simulate two
-- separate Lua realms. (Promise-based request/response lives in the
-- `callback` module now -- see test/smoke/callback.lua.)
local net = mocks.install()

dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/loops/shared.lua")
dofile(repoRoot .. "local/resources/client.lua")
dofile(repoRoot .. "local/resources/server.lua")
dofile(repoRoot .. "local/events/shared.lua")
dofile(repoRoot .. "local/events/server.lua")
dofile(repoRoot .. "local/events/client.lua") -- its startup CreateThread completes the handshake synchronously

local GATEWAY = "qblib:events:invoke"

harness.test("the handshake completes on load, so trigger succeeds immediately", function()
    local ok, err = QB.events.trigger("smoke:noop")
    harness.assertTrue(ok, "trigger should succeed once the handshake token has arrived")
    harness.assertEqual(err, nil, "there should be no error on the happy path")
end)

harness.test("register/trigger round trip delivers src and forwarded args", function()
    local seen
    QB.events.register("smoke:add", function(src, a, b)
        seen = { src = src, sum = a + b }
    end)

    local ok = QB.events.trigger("smoke:add", 2, 3)

    harness.assertTrue(ok, "trigger should succeed")
    harness.assertTrue(seen ~= nil, "the registered handler should have run")
    harness.assertEqual(seen.src, mocks.SOURCE, "the handler should see the real triggering player, not a client-supplied one")
    harness.assertEqual(seen.sum, 5, "the handler should receive the forwarded args")
end)

harness.test("push delivers to a registered onPush handler", function()
    local received
    QB.events.onPush("smoke:ping", function(payload) received = payload end)

    QB.events.push(mocks.SOURCE, "smoke:ping", "pong")

    harness.assertEqual(received, "pong", "the onPush handler should receive the pushed payload")
end)

harness.test("the gateway drops a request carrying the wrong token", function()
    local ran = false
    QB.events.register("smoke:should-not-run", function() ran = true end)

    _G.source = mocks.SOURCE
    for _, fn in ipairs(net.netHandlers[GATEWAY]) do
        fn("not-the-real-token", "smoke:should-not-run")
    end
    _G.source = nil

    harness.assertFalse(ran, "the handler must not run when the token is wrong")
end)

harness.test('server event rate limits use a sliding per-handler window', function()
    local calls = 0
    QB.events.register('smoke:limited', function() calls = calls + 1 end, {
        rateLimit = { max = 2, window = 1000 },
    })

    QB.events.trigger('smoke:limited')
    QB.events.trigger('smoke:limited')
    QB.events.trigger('smoke:limited')
    harness.assertEqual(calls, 2, 'the third request inside the window should be dropped')

    Wait(1000)
    QB.events.trigger('smoke:limited')
    harness.assertEqual(calls, 3, 'an expired window should admit a new request')
end)

harness.test('invalid tokens do not consume event rate quota', function()
    local calls = 0
    QB.events.register('smoke:invalid-free', function() calls = calls + 1 end, {
        rateLimit = { max = 1, window = 1000 },
    })

    _G.source = mocks.SOURCE
    for _, fn in ipairs(net.netHandlers[GATEWAY]) do fn('wrong-token', 'smoke:invalid-free') end
    _G.source = nil
    QB.events.trigger('smoke:invalid-free')
    harness.assertEqual(calls, 1, 'the authenticated request should still have the full quota')
end)

harness.test('unregister and replacement clear event rate buckets', function()
    local calls = 0
    QB.events.register('smoke:rate-reset', function() calls = calls + 1 end, {
        rateLimit = { max = 1, window = 5000 },
    })
    QB.events.trigger('smoke:rate-reset')
    QB.events.trigger('smoke:rate-reset')
    harness.assertEqual(calls, 1)

    QB.events.unregister('smoke:rate-reset')
    QB.events.register('smoke:rate-reset', function() calls = calls + 1 end, {
        rateLimit = { max = 1, window = 5000 },
    })
    QB.events.trigger('smoke:rate-reset')
    harness.assertEqual(calls, 2, 'a replacement must not inherit the previous handler quota')
end)

harness.test('rate limiting remains opt-in', function()
    local calls = 0
    QB.events.register('smoke:unlimited', function() calls = calls + 1 end)
    for _ = 1, 5 do QB.events.trigger('smoke:unlimited') end
    harness.assertEqual(calls, 5)
end)

harness.test("playerDropped clears the token, so an old request is dropped afterwards", function()
    local ran = false
    QB.events.register("smoke:after-drop", function() ran = true end)

    QB.events.trigger("smoke:after-drop")
    harness.assertTrue(ran, "sanity check: the real token should still work before the player drops")

    local gatewayEntry = mocks.lastEntry(net.triggeredServerEvents, GATEWAY)
    harness.assertTrue(gatewayEntry ~= nil, "expected to capture the real token from the trigger above")
    local capturedToken = gatewayEntry[1]

    _G.source = mocks.SOURCE
    net.fire("playerDropped")
    _G.source = nil

    ran = false
    _G.source = mocks.SOURCE
    for _, fn in ipairs(net.netHandlers[GATEWAY]) do
        fn(capturedToken, "smoke:after-drop")
    end
    _G.source = nil

    harness.assertFalse(ran, "the handler must not run once the token has been cleared by playerDropped")
end)

harness.test("register warns when a different resource clobbers an existing name", function()
    local logged = {}
    local realPrint = print
    _G.print = function(msg) table.insert(logged, msg) end

    _G.GetInvokingResource = function() return "resource_a" end
    QB.events.register("smoke:contested", function() end)

    -- Same resource re-registering (a restart) is normal, not a collision.
    QB.events.register("smoke:contested", function() end)
    harness.assertEqual(#logged, 0, "re-registering your own name should not warn")

    _G.GetInvokingResource = function() return "resource_b" end
    QB.events.register("smoke:contested", function() end)

    _G.GetInvokingResource = function() return nil end
    _G.print = realPrint

    harness.assertEqual(#logged, 1, "a cross-resource overwrite should warn exactly once")
    harness.assertTrue(logged[1]:find("resource_a", 1, true) ~= nil, "the warning should name the previous owner")
    harness.assertTrue(logged[1]:find("resource_b", 1, true) ~= nil, "the warning should name the new owner")
end)

harness.test("onPush: offPush removes the handler immediately", function()
    local received
    QB.events.onPush("smoke:offpush-target", function(payload) received = payload end)
    QB.events.offPush("smoke:offpush-target")

    QB.events.push(mocks.SOURCE, "smoke:offpush-target", "should not arrive")
    harness.assertEqual(received, nil, "an unregistered push handler must not run")
end)

-- The rest of these fire onResourceStop/onClientResourceStop for the mocked
-- resource name ("qblib_test", from GetCurrentResourceName()), which sweeps
-- every handler currently owned by it -- placed last so no earlier test's
-- still-needed registration gets swept out from under it. They also need a
-- working token, which "playerDropped clears the token" above deliberately
-- cleared server-side without the client's own cached token knowing --
-- exactly like a real reconnect, replaying the handshake refreshes both
-- sides in sync (see test/smoke/callback.lua for the same fix, same reason).
_G.source = mocks.SOURCE
for _, fn in ipairs(net.netHandlers["qblib:events:handshake"]) do fn() end
_G.source = nil

harness.test("register: a handler survives an unrelated resource stopping", function()
    local ran = false
    QB.events.register("smoke:survives-unrelated-stop", function() ran = true end)
    net.fire("onResourceStop", "some_other_resource")

    QB.events.trigger("smoke:survives-unrelated-stop")
    harness.assertTrue(ran, "a handler owned by a different resource must not be swept")
end)

harness.test("register: a handler is dropped when its owning resource stops", function()
    local ran = false
    QB.events.register("smoke:dropped-on-stop", function() ran = true end)
    net.fire("onResourceStop", "qblib_test")

    QB.events.trigger("smoke:dropped-on-stop")
    harness.assertFalse(ran, "no handler should run once it's been swept on resource stop")
end)

harness.test("onPush: a handler is dropped when its owning resource stops", function()
    local received
    QB.events.onPush("smoke:push-dropped-on-stop", function(payload) received = payload end)
    net.fire("onClientResourceStop", "qblib_test")

    QB.events.push(mocks.SOURCE, "smoke:push-dropped-on-stop", "should not arrive")
    harness.assertEqual(received, nil, "no push handler should run once it's been swept on resource stop")
end)

harness.report("events")
