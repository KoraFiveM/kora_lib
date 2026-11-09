local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/loops/shared.lua")
dofile(repoRoot .. "modules/util/shared.lua")
dofile(repoRoot .. "local/resources/client.lua")
dofile(repoRoot .. "local/resources/server.lua")
dofile(repoRoot .. "local/events/shared.lua")
dofile(repoRoot .. "local/events/server.lua")
dofile(repoRoot .. "local/events/client.lua")

local GATEWAY = "kora_lib:events:invoke"

local function namedUpvalue(fn, wanted)
    local index = 1
    while true do
        local name, value = debug.getupvalue(fn, index)
        if not name then return nil end
        if name == wanted then return value end
        index = index + 1
    end
end

local consumeRateLimit = namedUpvalue(net.netHandlers[GATEWAY][1], 'consumeRateLimit')
local rateBuckets = consumeRateLimit and namedUpvalue(consumeRateLimit, 'rateBuckets')
assert(rateBuckets, 'could not inspect event rate buckets')
local serverTokens = namedUpvalue(net.netHandlers[GATEWAY][1], 'tokens')
assert(serverTokens, 'could not inspect event tokens')

harness.test("the handshake completes on load, so trigger succeeds immediately", function()
    local ok, err = Kora.events.trigger("smoke:noop")
    harness.assertTrue(ok, "trigger should succeed once the handshake token has arrived")
    harness.assertEqual(err, nil, "there should be no error on the happy path")
end)

harness.test("register/trigger round trip delivers src and forwarded args", function()
    local seen
    Kora.events.register("smoke:add", function(src, a, b)
        seen = { src = src, sum = a + b }
    end)

    local ok = Kora.events.trigger("smoke:add", 2, 3)

    harness.assertTrue(ok, "trigger should succeed")
    harness.assertTrue(seen ~= nil, "the registered handler should have run")
    harness.assertEqual(seen.src, mocks.SOURCE, "the handler should see the real triggering player, not a client-supplied one")
    harness.assertEqual(seen.sum, 5, "the handler should receive the forwarded args")
end)

harness.test("push delivers to a registered onPush handler", function()
    local received
    Kora.events.onPush("smoke:ping", function(payload) received = payload end)

    Kora.events.push(mocks.SOURCE, "smoke:ping", "pong")

    harness.assertEqual(received, "pong", "the onPush handler should receive the pushed payload")
end)

harness.test("push rejects malformed targets before dispatch", function()
    for _, target in ipairs({ 0, -2, 1.5, 0 / 0, math.huge, -math.huge }) do
        harness.assertThrows(function()
            Kora.events.push(target, "smoke:ping", "ignored")
        end, "invalid push targets must not reach the native event")
    end
end)

harness.test("client push receiver drops malformed names without faulting", function()
    local pushHandlers = net.netHandlers["kora_lib:events:push"]
    local ok = pcall(function()
        for _, fn in ipairs(pushHandlers) do fn(0 / 0, "ignored") end
    end)

    harness.assertTrue(ok, "a malformed push name must be ignored before the registry lookup")
end)

harness.test("client push handler errors are isolated and logged", function()
    local logged = {}
    local realPrint = print
    _G.print = function(message) logged[#logged + 1] = tostring(message) end

    Kora.events.onPush("smoke:broken-push", function()
        error("push exploded")
    end)
    Kora.events.push(mocks.SOURCE, "smoke:broken-push")

    _G.print = realPrint
    harness.assertEqual(#logged, 1, "one failed push should produce one diagnostic")
    harness.assertTrue(logged[1]:find("smoke:broken-push", 1, true) ~= nil,
        "the diagnostic should identify the failing push")
    harness.assertTrue(logged[1]:find("push exploded", 1, true) ~= nil,
        "the diagnostic should include the handler error")
end)

harness.test("the gateway drops a request carrying the wrong token", function()
    local ran = false
    Kora.events.register("smoke:should-not-run", function() ran = true end)

    _G.source = mocks.SOURCE
    for _, fn in ipairs(net.netHandlers[GATEWAY]) do
        fn("not-the-real-token", "smoke:should-not-run")
    end
    _G.source = nil

    harness.assertFalse(ran, "the handler must not run when the token is wrong")
end)

harness.test('the gateway drops oversized names before dispatch', function()
    local ran = false
    Kora.events.register('smoke:short-name', function() ran = true end)

    _G.source = mocks.SOURCE
    for _, fn in ipairs(net.netHandlers[GATEWAY]) do
        fn(serverTokens[mocks.SOURCE], string.rep('x', 129))
    end
    _G.source = nil

    harness.assertFalse(ran, 'oversized event names must not reach a handler')
    harness.assertThrows(function() Kora.events.assertName(string.rep('x', 129)) end)
end)

harness.test("handshake and gateway discard malformed server sources", function()
    local gatewayHandlers = net.netHandlers[GATEWAY]
    local handshakeHandlers = net.netHandlers["kora_lib:events:handshake"]
    local ok = pcall(function()
        for _, src in ipairs({ 0, -1, 1.5, 0 / 0, math.huge, -math.huge }) do
            _G.source = src
            for _, fn in ipairs(handshakeHandlers) do fn() end
            for _, fn in ipairs(gatewayHandlers) do fn("ignored", "smoke:noop") end
        end
        _G.source = nil
    end)

    _G.source = nil
    harness.assertTrue(ok, "malformed sources must be ignored before token-table access")
end)

harness.test('server event rate limits use a sliding per-handler window', function()
    local calls = 0
    Kora.events.register('smoke:limited', function() calls = calls + 1 end, {
        rateLimit = { max = 2, window = 1000 },
    })

    Kora.events.trigger('smoke:limited')
    Kora.events.trigger('smoke:limited')
    Kora.events.trigger('smoke:limited')
    harness.assertEqual(calls, 2, 'the third request inside the window should be dropped')

    Wait(1000)
    Kora.events.trigger('smoke:limited')
    harness.assertEqual(calls, 3, 'an expired window should admit a new request')
end)

harness.test('event rate buckets keep only quota-sized timestamp storage', function()
    Kora.events.register('smoke:ring-storage', function() end, {
        rateLimit = { max = 3, window = 1 },
    })

    for _ = 1, 20 do
        Kora.events.trigger('smoke:ring-storage')
        Wait(1)
    end

    local bucket = rateBuckets['smoke:ring-storage'][mocks.SOURCE]
    local stored = 0
    for _ in pairs(bucket.timestamps) do stored = stored + 1 end
    harness.assertTrue(bucket.count <= 3 and stored <= 3,
        'a rolling quota must not grow its timestamp storage over time')
    Kora.events.unregister('smoke:ring-storage')
end)

harness.test('event rate limits reject non-finite values at registration', function()
    for _, rateLimit in ipairs({
        { max = math.huge, window = 1000 },
        { max = 1, window = math.huge },
        { max = 10001, window = 1000 },
        { max = 1, window = 86400001 },
    }) do
        harness.assertThrows(function()
            Kora.events.register('smoke:invalid-limit', function() end, { rateLimit = rateLimit })
        end, 'rate-limit values must be finite')
    end
end)

harness.test('event rate buckets expire automatically and stale timers cannot clear replacements', function()
    local realSetTimeout = SetTimeout
    local timers = {}
    _G.SetTimeout = function(delay, callback)
        timers[#timers + 1] = { delay = delay, callback = callback }
    end

    Kora.events.register('smoke:timer-cleanup', function() end, {
        rateLimit = { max = 1, window = 100 },
    })
    Kora.events.trigger('smoke:timer-cleanup')
    local expiringTimer = timers[#timers]
    local existed = rateBuckets['smoke:timer-cleanup'] ~= nil
    Wait(100)
    expiringTimer.callback()
    local expired = rateBuckets['smoke:timer-cleanup'] == nil

    timers = {}
    Kora.events.register('smoke:stale-timer', function() end, {
        rateLimit = { max = 1, window = 100 },
    })
    Kora.events.trigger('smoke:stale-timer')
    local staleTimer = timers[#timers]
    Kora.events.register('smoke:stale-timer', function() end, {
        rateLimit = { max = 1, window = 1000 },
    })
    Kora.events.trigger('smoke:stale-timer')
    local replacementBucket = rateBuckets['smoke:stale-timer'][mocks.SOURCE]
    Wait(100)
    staleTimer.callback()
    local replacementPreserved = rateBuckets['smoke:stale-timer']
        and rateBuckets['smoke:stale-timer'][mocks.SOURCE] == replacementBucket

    timers = {}
    Kora.events.register('smoke:coalesced-timer', function() end, {
        rateLimit = { max = 3, window = 1000 },
    })
    Kora.events.trigger('smoke:coalesced-timer')
    Kora.events.trigger('smoke:coalesced-timer')
    Kora.events.trigger('smoke:coalesced-timer')
    local coalescedTimerCount = #timers
    Wait(1000)
    timers[1].callback()
    local coalescedExpired = rateBuckets['smoke:coalesced-timer'] == nil

    timers = {}
    Kora.events.register('smoke:rescheduled-timer', function() end, {
        rateLimit = { max = 2, window = 1000 },
    })
    Kora.events.trigger('smoke:rescheduled-timer')
    local firstCleanup = timers[1]
    Wait(500)
    Kora.events.trigger('smoke:rescheduled-timer')
    Wait(500)
    firstCleanup.callback()
    local rescheduled = rateBuckets['smoke:rescheduled-timer'] ~= nil and #timers == 2 and timers[2].delay == 500
    Wait(500)
    timers[2].callback()
    local rescheduledExpired = rateBuckets['smoke:rescheduled-timer'] == nil

    Kora.events.unregister('smoke:timer-cleanup')
    Kora.events.unregister('smoke:stale-timer')
    Kora.events.unregister('smoke:coalesced-timer')
    Kora.events.unregister('smoke:rescheduled-timer')
    _G.SetTimeout = realSetTimeout

    harness.assertTrue(existed, 'an accepted request should create a bucket')
    harness.assertTrue(expired, 'the expiry timer should clear an idle bucket')
    harness.assertTrue(replacementPreserved, 'an old timer must not clear a replacement handler bucket')
    harness.assertEqual(coalescedTimerCount, 1, 'one bucket should schedule one cleanup timer per window')
    harness.assertTrue(coalescedExpired, 'the coalesced cleanup timer should still release an idle bucket')
    harness.assertTrue(rescheduled, 'a live bucket should schedule one follow-up timer for its next expiry')
    harness.assertTrue(rescheduledExpired, 'the follow-up cleanup timer should release the final timestamp')
end)

harness.test('invalid tokens do not consume event rate quota', function()
    local calls = 0
    Kora.events.register('smoke:invalid-free', function() calls = calls + 1 end, {
        rateLimit = { max = 1, window = 1000 },
    })

    _G.source = mocks.SOURCE
    for _, fn in ipairs(net.netHandlers[GATEWAY]) do fn('wrong-token', 'smoke:invalid-free') end
    _G.source = nil
    Kora.events.trigger('smoke:invalid-free')
    harness.assertEqual(calls, 1, 'the authenticated request should still have the full quota')
end)

harness.test('event quotas are independent per player and handler name', function()
    local firstCalls, secondCalls = 0, 0
    local limit = { rateLimit = { max = 1, window = 5000 } }
    Kora.events.register('smoke:independent-a', function() firstCalls = firstCalls + 1 end, limit)
    Kora.events.register('smoke:independent-b', function() secondCalls = secondCalls + 1 end, limit)

    Kora.events.trigger('smoke:independent-a')
    Kora.events.trigger('smoke:independent-a')
    Kora.events.trigger('smoke:independent-b')
    harness.assertEqual(firstCalls, 1, 'one name should exhaust only its own quota')
    harness.assertEqual(secondCalls, 1, 'a different name should retain independent quota')

    _G.source = mocks.SOURCE + 1
    for _, fn in ipairs(net.netHandlers['kora_lib:events:handshake']) do fn() end
    _G.source = nil
    local handshake = mocks.lastEntry(net.triggeredClientEvents, 'kora_lib:events:handshake:response')
    local secondToken = handshake[1]
    _G.source = mocks.SOURCE + 1
    for _, fn in ipairs(net.netHandlers[GATEWAY]) do fn(secondToken, 'smoke:independent-a') end
    _G.source = nil
    harness.assertEqual(firstCalls, 2, 'a different player should retain independent quota')

    _G.source = mocks.SOURCE
    for _, fn in ipairs(net.netHandlers['kora_lib:events:handshake']) do fn() end
    _G.source = nil
end)

harness.test('unregister and replacement clear event rate buckets', function()
    local calls = 0
    Kora.events.register('smoke:rate-reset', function() calls = calls + 1 end, {
        rateLimit = { max = 1, window = 5000 },
    })
    Kora.events.trigger('smoke:rate-reset')
    Kora.events.trigger('smoke:rate-reset')
    harness.assertEqual(calls, 1)

    Kora.events.unregister('smoke:rate-reset')
    Kora.events.register('smoke:rate-reset', function() calls = calls + 1 end, {
        rateLimit = { max = 1, window = 5000 },
    })
    Kora.events.trigger('smoke:rate-reset')
    harness.assertEqual(calls, 2, 'a replacement must not inherit the previous handler quota')
end)

harness.test('rate limiting remains opt-in', function()
    local calls = 0
    Kora.events.register('smoke:unlimited', function() calls = calls + 1 end)
    for _ = 1, 5 do Kora.events.trigger('smoke:unlimited') end
    harness.assertEqual(calls, 5)
end)

harness.test("playerDropped clears the token, so an old request is dropped afterwards", function()
    local ran = false
    Kora.events.register("smoke:after-drop", function() ran = true end, {
        rateLimit = { max = 2, window = 5000 },
    })

    Kora.events.trigger("smoke:after-drop")
    harness.assertTrue(ran, "sanity check: the real token should still work before the player drops")
    harness.assertTrue(rateBuckets['smoke:after-drop'] ~= nil, 'sanity check: the player should have a rate bucket')

    local gatewayEntry = mocks.lastEntry(net.triggeredServerEvents, GATEWAY)
    harness.assertTrue(gatewayEntry ~= nil, "expected to capture the real token from the trigger above")
    local capturedToken = gatewayEntry[1]

    _G.source = mocks.SOURCE
    net.fire("playerDropped")
    _G.source = nil
    harness.assertEqual(rateBuckets['smoke:after-drop'], nil, 'player drop should clear the rate bucket')

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
    Kora.events.register("smoke:contested", function() end)

    Kora.events.register("smoke:contested", function() end)
    harness.assertEqual(#logged, 0, "re-registering your own name should not warn")

    _G.GetInvokingResource = function() return "resource_b" end
    Kora.events.register("smoke:contested", function() end)

    _G.GetInvokingResource = function() return nil end
    _G.print = realPrint

    harness.assertEqual(#logged, 1, "a cross-resource overwrite should warn exactly once")
    harness.assertTrue(logged[1]:find("resource_a", 1, true) ~= nil, "the warning should name the previous owner")
    harness.assertTrue(logged[1]:find("resource_b", 1, true) ~= nil, "the warning should name the new owner")
end)

harness.test("onPush: offPush removes the handler immediately", function()
    local received
    Kora.events.onPush("smoke:offpush-target", function(payload) received = payload end)
    Kora.events.offPush("smoke:offpush-target")

    Kora.events.push(mocks.SOURCE, "smoke:offpush-target", "should not arrive")
    harness.assertEqual(received, nil, "an unregistered push handler must not run")
end)

harness.test("foreign resources cannot unregister events or push handlers", function()
    _G.GetInvokingResource = function() return "event_owner" end
    Kora.events.register("smoke:owned-event", function() end)
    Kora.events.onPush("smoke:owned-push", function() end)

    _G.GetInvokingResource = function() return "other_resource" end
    harness.assertFalse(Kora.events.unregister("smoke:owned-event"),
        "another resource must not unregister an event")
    harness.assertFalse(Kora.events.offPush("smoke:owned-push"),
        "another resource must not unregister a push handler")

    _G.GetInvokingResource = function() return "event_owner" end
    harness.assertTrue(Kora.events.unregister("smoke:owned-event"),
        "the event owner should still be able to unregister it")
    harness.assertTrue(Kora.events.offPush("smoke:owned-push"),
        "the push owner should still be able to unregister it")
    _G.GetInvokingResource = function() return nil end
end)

_G.source = mocks.SOURCE
for _, fn in ipairs(net.netHandlers["kora_lib:events:handshake"]) do fn() end
_G.source = nil

harness.test("register: a handler survives an unrelated resource stopping", function()
    local ran = false
    Kora.events.register("smoke:survives-unrelated-stop", function() ran = true end)
    net.fire("onResourceStop", "some_other_resource")

    Kora.events.trigger("smoke:survives-unrelated-stop")
    harness.assertTrue(ran, "a handler owned by a different resource must not be swept")
end)

harness.test("register: a handler is dropped when its owning resource stops", function()
    local ran = false
    Kora.events.register("smoke:dropped-on-stop", function() ran = true end, {
        rateLimit = { max = 1, window = 5000 },
    })
    Kora.events.trigger('smoke:dropped-on-stop')
    harness.assertTrue(rateBuckets['smoke:dropped-on-stop'] ~= nil, 'sanity check: the handler should own a rate bucket')
    ran = false
    net.fire("onResourceStop", "kora_lib_test")
    harness.assertEqual(rateBuckets['smoke:dropped-on-stop'], nil, 'owner cleanup should clear the rate bucket')

    Kora.events.trigger("smoke:dropped-on-stop")
    harness.assertFalse(ran, "no handler should run once it's been swept on resource stop")
end)

harness.test("onPush: a handler is dropped when its owning resource stops", function()
    local received
    Kora.events.onPush("smoke:push-dropped-on-stop", function(payload) received = payload end)
    net.fire("onClientResourceStop", "kora_lib_test")

    Kora.events.push(mocks.SOURCE, "smoke:push-dropped-on-stop", "should not arrive")
    harness.assertEqual(received, nil, "no push handler should run once it's been swept on resource stop")
end)

harness.test("the deprecated qblib: gateway and handshake names are still accepted", function()
    harness.assertEqual(net.netHandlers["qblib:events:invoke"][1], net.netHandlers[GATEWAY][1],
        "the legacy gateway should share the dispatch handler")
    _G.source = mocks.SOURCE
    for _, fn in ipairs(net.netHandlers["qblib:events:handshake"]) do fn() end
    _G.source = nil
    harness.assertTrue(mocks.lastEntry(net.triggeredClientEvents, "qblib:events:handshake:response") ~= nil,
        "a legacy handshake should answer on the legacy response event")
end)

harness.test("a trigger waiting on the handshake polls every 50ms, not every frame", function()
    local handshakeHandlers = net.netHandlers["kora_lib:events:handshake"]
    net.netHandlers["kora_lib:events:handshake"] = {}
    dofile(repoRoot .. "local/events/client.lua")
    net.netHandlers["kora_lib:events:handshake"] = handshakeHandlers

    local waits = {}
    local wait = _G.Wait
    _G.Wait = function(ms)
        waits[#waits + 1] = ms
        return wait(ms)
    end

    local ok
    CreateThread(function() ok = Kora.events.trigger("smoke:late-token") end)
    for _ = 1, 3 do net.step() end
    harness.assertEqual(ok, nil, "trigger should still be waiting for the token")
    harness.assertTrue(#waits > 0, "trigger should have yielded while waiting")
    for index = 1, #waits do
        harness.assertEqual(waits[index], 50, "each wait for the token should be 50ms")
    end

    TriggerClientEvent("kora_lib:events:handshake:response", mocks.SOURCE, "late-token")
    net.step()
    _G.Wait = wait
    harness.assertTrue(ok, "trigger should complete once the token arrives")
end)

harness.report("events")
