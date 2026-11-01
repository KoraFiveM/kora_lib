local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

-- Each direction has its own handshake token and request registry, but register/trigger
-- are defined on both realms under the same names, so the second dofile wins the table
-- slot. Each direction's pair is captured by reference right after its own file loads.
local net = mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/loops/shared.lua")
dofile(repoRoot .. "modules/util/shared.lua")
dofile(repoRoot .. "local/resources/client.lua")
dofile(repoRoot .. "local/resources/server.lua")
dofile(repoRoot .. "local/callback/shared.lua")

dofile(repoRoot .. "local/callback/server.lua")
local serverRegister = Kora.callback.register
local serverTrigger = Kora.callback.trigger
local serverUnregister = Kora.callback.unregister

dofile(repoRoot .. "local/callback/client.lua") -- its startup CreateThread completes the client->server handshake synchronously
local clientRegister = Kora.callback.register
local clientTrigger = Kora.callback.trigger

local INVOKE = "kora_lib:callback:invoke"

local function namedUpvalue(fn, wanted)
    local index = 1
    while true do
        local name, value = debug.getupvalue(fn, index)
        if not name then return nil end
        if name == wanted then return value end
        index = index + 1
    end
end

local consumeRateLimit = namedUpvalue(net.netHandlers[INVOKE][1], 'consumeRateLimit')
local rateBuckets = consumeRateLimit and namedUpvalue(consumeRateLimit, 'rateBuckets')
assert(rateBuckets, 'could not inspect callback rate buckets')
local serverTokens = namedUpvalue(net.netHandlers[INVOKE][1], 'tokens')
assert(serverTokens, 'could not inspect callback tokens')

harness.test("client asks server: resolves with the handler's return value", function()
    serverRegister("smoke:double", function(src, n)
        return src, n * 2
    end)

    local p = clientTrigger("smoke:double", 21)

    harness.assertEqual(p.state, "resolved", "the promise should resolve synchronously over the mock network")
    harness.assertEqual(p.value, mocks.SOURCE, "only the handler's first return value should be sent back")
end)

harness.test("client asks server: rejects when the handler errors", function()
    serverRegister("smoke:boom", function() error("kaboom") end)

    local p = clientTrigger("smoke:boom")

    harness.assertEqual(p.state, "rejected", "the promise should reject when the handler errors")
    harness.assertTrue(tostring(p.value):find("kaboom") ~= nil, "the rejection should carry the error message")
end)

harness.test("client asks server: handler errors are logged and sent without file positions", function()
    serverRegister("smoke:positioned", function() error("attempt to index nil") end)
    local printed = {}
    local realPrint = print
    print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
    local p = clientTrigger("smoke:positioned")
    print = realPrint

    harness.assertEqual(p.state, "rejected")
    harness.assertEqual(tostring(p.value), "attempt to index nil", "the file:line prefix must not reach the client")
    harness.assertTrue(#printed >= 1 and printed[1]:find("smoke:positioned", 1, true) ~= nil,
        "the full error should be logged on the server")
end)

harness.test("callback handshake is rate limited per player", function()
    local source = mocks.SOURCE + 500
    local issued = 0
    for _ = 1, 8 do
        local before = #net.triggeredClientEvents
        _G.source = source
        for _, fn in ipairs(net.netHandlers["kora_lib:callback:handshake"]) do fn() end
        _G.source = nil
        for index = before + 1, #net.triggeredClientEvents do
            if net.triggeredClientEvents[index].name == "kora_lib:callback:handshake:response" then issued = issued + 1 end
        end
    end
    harness.assertEqual(issued, 5, "only five handshakes per minute may be answered")

    -- The single-process mock delivers every client event to the simulated
    -- client, so give it back its own token.
    _G.source = mocks.SOURCE
    for _, fn in ipairs(net.netHandlers["kora_lib:callback:handshake"]) do fn() end
    _G.source = nil
end)

harness.test("client asks server: the gateway drops a request carrying the wrong token", function()
    local ran = false
    serverRegister("smoke:should-not-run", function() ran = true end)

    _G.source = mocks.SOURCE
    for _, fn in ipairs(net.netHandlers[INVOKE]) do
        fn("not-the-real-token", 999, "smoke:should-not-run")
    end
    _G.source = nil

    harness.assertFalse(ran, "the handler must not run when the token is wrong")
end)

harness.test('client asks server: the gateway drops oversized names before dispatch', function()
    local ran = false
    serverRegister('smoke:short-name', function() ran = true end)

    _G.source = mocks.SOURCE
    for _, fn in ipairs(net.netHandlers[INVOKE]) do
        fn(serverTokens[mocks.SOURCE], 1000, string.rep('x', 129))
    end
    _G.source = nil

    harness.assertFalse(ran, 'oversized callback names must not reach a handler')
    harness.assertThrows(function() Kora.callback.assertName(string.rep('x', 129)) end)
end)

harness.test("callback handshake and gateway discard malformed server sources", function()
    local handshakeHandlers = net.netHandlers["kora_lib:callback:handshake"]
    local invokeHandlers = net.netHandlers[INVOKE]
    local ok = pcall(function()
        for _, src in ipairs({ 0, -1, 1.5, 0 / 0, math.huge, -math.huge }) do
            _G.source = src
            for _, fn in ipairs(handshakeHandlers) do fn() end
            for _, fn in ipairs(invokeHandlers) do fn("ignored", 1, "smoke:noop") end
        end
        _G.source = nil
    end)

    _G.source = nil
    harness.assertTrue(ok, "malformed sources must be ignored before callback token-table access")
end)

harness.test("client asks server: the gateway drops malformed request IDs", function()
    local calls = 0
    serverRegister("smoke:valid-id-only", function() calls = calls + 1 end)

    local invokeEntry = mocks.lastEntry(net.triggeredServerEvents, INVOKE)
    harness.assertTrue(invokeEntry ~= nil, "the client handshake should have issued a real callback token")
    local token = invokeEntry[1]

    _G.source = mocks.SOURCE
    for _, requestId in ipairs({ 0, -1, 1.5, 0 / 0, math.huge, -math.huge }) do
        for _, fn in ipairs(net.netHandlers[INVOKE]) do
            fn(token, requestId, "smoke:valid-id-only")
        end
    end
    _G.source = nil

    harness.assertEqual(calls, 0, "invalid request IDs must be discarded before callback dispatch")
end)

harness.test("client callback receiver drops malformed response IDs without faulting", function()
    local responseHandlers = net.netHandlers["kora_lib:callback:response"]
    local ok = pcall(function()
        for _, requestId in ipairs({ 0, -1, 1.5, 0 / 0, math.huge, -math.huge }) do
            for _, fn in ipairs(responseHandlers) do fn(requestId, true, "ignored") end
        end
    end)

    harness.assertTrue(ok, "malformed response IDs must be ignored before the pending table lookup")
end)

harness.test("client callback receiver drops malformed invocations without faulting", function()
    local invokeHandlers = net.netHandlers["kora_lib:callback:clientInvoke"]
    local triggeredCount = #net.triggeredServerEvents
    local ok = pcall(function()
        for _, fn in ipairs(invokeHandlers) do
            fn(0 / 0, "smoke:noop")
            fn(1, 0 / 0)
            fn(1, string.rep('x', 129))
        end
    end)

    harness.assertTrue(ok, "malformed client callback input must be ignored before registry lookup")
    harness.assertEqual(#net.triggeredServerEvents, triggeredCount,
        'an oversized callback name must not be echoed back to the server')
end)

harness.test('client-to-server callbacks reject immediately when rate limited', function()
    local calls = 0
    serverRegister('smoke:limited', function()
        calls = calls + 1
        return calls
    end, { rateLimit = { max = 1, window = 1000 } })

    local first = clientTrigger('smoke:limited')
    local second = clientTrigger('smoke:limited')
    harness.assertEqual(first.state, 'resolved')
    harness.assertEqual(second.state, 'rejected', 'a limited callback must reject instead of timing out')
    harness.assertTrue(tostring(second.value):find('retry in', 1, true) ~= nil)
    harness.assertEqual(calls, 1)

    Wait(1000)
    local third = clientTrigger('smoke:limited')
    harness.assertEqual(third.state, 'resolved')
    harness.assertEqual(calls, 2, 'the sliding window should expire')
end)

harness.test('callback rate buckets keep only quota-sized timestamp storage', function()
    serverRegister('smoke:ring-storage', function() return true end, {
        rateLimit = { max = 3, window = 1 },
    })

    for _ = 1, 20 do
        clientTrigger('smoke:ring-storage')
        Wait(1)
    end

    local bucket = rateBuckets['smoke:ring-storage'][mocks.SOURCE]
    local stored = 0
    for _ in pairs(bucket.timestamps) do stored = stored + 1 end
    harness.assertTrue(bucket.count <= 3 and stored <= 3,
        'a rolling quota must not grow its timestamp storage over time')
    serverUnregister('smoke:ring-storage')
end)

harness.test('callback rate limits reject non-finite values at registration', function()
    for _, rateLimit in ipairs({
        { max = math.huge, window = 1000 },
        { max = 1, window = math.huge },
        { max = 10001, window = 1000 },
        { max = 1, window = 86400001 },
    }) do
        harness.assertThrows(function()
            serverRegister('smoke:invalid-limit', function() return true end, { rateLimit = rateLimit })
        end, 'rate-limit values must be finite')
    end
end)

harness.test('callback rate buckets expire automatically and stale timers cannot clear replacements', function()
    local realSetTimeout = SetTimeout
    local timers = {}
    _G.SetTimeout = function(delay, callback)
        timers[#timers + 1] = { delay = delay, callback = callback }
    end

    serverRegister('smoke:timer-cleanup', function() return true end, {
        rateLimit = { max = 1, window = 100 },
    })
    clientTrigger('smoke:timer-cleanup')
    local expiringTimer
    for _, timer in ipairs(timers) do
        if timer.delay == 100 then expiringTimer = timer end
    end
    local existed = rateBuckets['smoke:timer-cleanup'] ~= nil
    Wait(100)
    expiringTimer.callback()
    local expired = rateBuckets['smoke:timer-cleanup'] == nil

    timers = {}
    serverRegister('smoke:stale-timer', function() return true end, {
        rateLimit = { max = 1, window = 100 },
    })
    clientTrigger('smoke:stale-timer')
    local staleTimer
    for _, timer in ipairs(timers) do
        if timer.delay == 100 then staleTimer = timer end
    end
    serverRegister('smoke:stale-timer', function() return true end, {
        rateLimit = { max = 1, window = 1000 },
    })
    clientTrigger('smoke:stale-timer')
    local replacementBucket = rateBuckets['smoke:stale-timer'][mocks.SOURCE]
    Wait(100)
    staleTimer.callback()
    local replacementPreserved = rateBuckets['smoke:stale-timer']
        and rateBuckets['smoke:stale-timer'][mocks.SOURCE] == replacementBucket

    timers = {}
    serverRegister('smoke:coalesced-timer', function() return true end, {
        rateLimit = { max = 3, window = 1000 },
    })
    clientTrigger('smoke:coalesced-timer')
    clientTrigger('smoke:coalesced-timer')
    clientTrigger('smoke:coalesced-timer')
    local coalescedTimerCount = 0
    local coalescedTimer
    for _, timer in ipairs(timers) do
        if timer.delay == 1000 then
            coalescedTimerCount = coalescedTimerCount + 1
            coalescedTimer = timer
        end
    end
    Wait(1000)
    coalescedTimer.callback()
    local coalescedExpired = rateBuckets['smoke:coalesced-timer'] == nil

    timers = {}
    serverRegister('smoke:rescheduled-timer', function() return true end, {
        rateLimit = { max = 2, window = 1000 },
    })
    clientTrigger('smoke:rescheduled-timer')
    local firstCleanup
    for _, timer in ipairs(timers) do
        if timer.delay == 1000 then firstCleanup = timer end
    end
    Wait(500)
    clientTrigger('smoke:rescheduled-timer')
    Wait(500)
    firstCleanup.callback()
    local followUp
    for _, timer in ipairs(timers) do
        if timer.delay == 500 then followUp = timer end
    end
    local rescheduled = rateBuckets['smoke:rescheduled-timer'] ~= nil and followUp ~= nil
    Wait(500)
    followUp.callback()
    local rescheduledExpired = rateBuckets['smoke:rescheduled-timer'] == nil

    serverUnregister('smoke:timer-cleanup')
    serverUnregister('smoke:stale-timer')
    serverUnregister('smoke:coalesced-timer')
    serverUnregister('smoke:rescheduled-timer')
    _G.SetTimeout = realSetTimeout

    harness.assertTrue(existed, 'an accepted request should create a callback bucket')
    harness.assertTrue(expired, 'the expiry timer should clear an idle callback bucket')
    harness.assertTrue(replacementPreserved, 'an old timer must not clear a replacement callback bucket')
    harness.assertEqual(coalescedTimerCount, 1, 'one bucket should schedule one cleanup timer per window')
    harness.assertTrue(coalescedExpired, 'the coalesced cleanup timer should still release an idle bucket')
    harness.assertTrue(rescheduled, 'a live bucket should schedule one follow-up timer for its next expiry')
    harness.assertTrue(rescheduledExpired, 'the follow-up cleanup timer should release the final timestamp')
end)

harness.test('invalid callback tokens do not consume quota', function()
    local calls = 0
    serverRegister('smoke:invalid-free', function() calls = calls + 1; return true end, {
        rateLimit = { max = 1, window = 1000 },
    })

    _G.source = mocks.SOURCE
    for _, fn in ipairs(net.netHandlers[INVOKE]) do
        fn('invalid-token', 991, 'smoke:invalid-free')
    end
    _G.source = nil

    local result = clientTrigger('smoke:invalid-free')
    harness.assertEqual(result.state, 'resolved')
    harness.assertEqual(calls, 1)
end)

harness.test('callback quotas are independent per player', function()
    local calls = 0
    serverRegister('smoke:per-player', function() calls = calls + 1; return true end, {
        rateLimit = { max = 1, window = 5000 },
    })
    clientTrigger('smoke:per-player')

    _G.source = mocks.SOURCE + 1
    for _, fn in ipairs(net.netHandlers['kora_lib:callback:handshake']) do fn() end
    _G.source = nil
    local handshake = mocks.lastEntry(net.triggeredClientEvents, 'kora_lib:callback:handshake:response')
    local secondToken = handshake[1]

    _G.source = mocks.SOURCE + 1
    for _, fn in ipairs(net.netHandlers[INVOKE]) do
        fn(secondToken, 992, 'smoke:per-player')
    end
    _G.source = nil
    harness.assertEqual(calls, 2, 'a different source should have its own quota')

    -- Restore the simulated client's token for later round trips.
    _G.source = mocks.SOURCE
    for _, fn in ipairs(net.netHandlers['kora_lib:callback:handshake']) do fn() end
    _G.source = nil
end)

harness.test('callback quotas are independent per handler name', function()
    local firstCalls, secondCalls = 0, 0
    local limit = { rateLimit = { max = 1, window = 5000 } }
    serverRegister('smoke:independent-a', function() firstCalls = firstCalls + 1; return true end, limit)
    serverRegister('smoke:independent-b', function() secondCalls = secondCalls + 1; return true end, limit)

    clientTrigger('smoke:independent-a')
    clientTrigger('smoke:independent-a')
    clientTrigger('smoke:independent-b')
    harness.assertEqual(firstCalls, 1, 'one callback name should exhaust only its own quota')
    harness.assertEqual(secondCalls, 1, 'a different callback name should retain independent quota')
end)

harness.test('callback replacement clears old rate buckets and limiting is opt-in', function()
    local calls = 0
    serverRegister('smoke:rate-reset', function() calls = calls + 1; return true end, {
        rateLimit = { max = 1, window = 5000 },
    })
    clientTrigger('smoke:rate-reset')
    clientTrigger('smoke:rate-reset')
    harness.assertEqual(calls, 1)

    serverRegister('smoke:rate-reset', function() calls = calls + 1; return true end, {
        rateLimit = { max = 1, window = 5000 },
    })
    clientTrigger('smoke:rate-reset')
    harness.assertEqual(calls, 2)

    local unlimited = 0
    serverRegister('smoke:unlimited', function() unlimited = unlimited + 1; return true end)
    for _ = 1, 5 do clientTrigger('smoke:unlimited') end
    harness.assertEqual(unlimited, 5)
end)

harness.test("client asks server: playerDropped clears the token", function()
    local ran = false
    serverRegister("smoke:after-drop", function() ran = true; return true end, {
        rateLimit = { max = 2, window = 5000 },
    })

    clientTrigger("smoke:after-drop")
    harness.assertTrue(ran, "sanity check: the real token should still work before the player drops")
    harness.assertTrue(rateBuckets['smoke:after-drop'] ~= nil, 'sanity check: the player should have a callback bucket')

    clientRegister("smoke:disconnect-pending", function() return "too late" end)
    local responseHandlers = net.netHandlers["kora_lib:callback:clientResponse"]
    net.netHandlers["kora_lib:callback:clientResponse"] = {}
    local pending = serverTrigger(mocks.SOURCE, "smoke:disconnect-pending")
    net.netHandlers["kora_lib:callback:clientResponse"] = responseHandlers
    harness.assertEqual(pending.state, "pending", "sanity check: the client callback should be in flight")

    local invokeEntry = mocks.lastEntry(net.triggeredServerEvents, INVOKE)
    harness.assertTrue(invokeEntry ~= nil, "expected to capture the real token from the trigger above")
    local capturedToken = invokeEntry[1]

    _G.source = mocks.SOURCE
    net.fire("playerDropped")
    _G.source = nil
    harness.assertEqual(rateBuckets['smoke:after-drop'], nil, 'player drop should clear the callback bucket')
    harness.assertEqual(pending.state, "rejected", "player drop should reject callbacks waiting on that client")
    harness.assertTrue(tostring(pending.value):find("disconnected", 1, true) ~= nil)

    ran = false
    _G.source = mocks.SOURCE
    for _, fn in ipairs(net.netHandlers[INVOKE]) do
        fn(capturedToken, 1000, "smoke:after-drop")
    end
    _G.source = nil

    harness.assertFalse(ran, "the handler must not run once the token has been cleared by playerDropped")
end)

harness.test("server asks client: resolves with the client handler's return value", function()
    clientRegister("confirm:action", function(prompt)
        return prompt == "yes"
    end)

    local p = serverTrigger(mocks.SOURCE, "confirm:action", "yes")

    harness.assertEqual(p.state, "resolved", "the promise should resolve synchronously over the mock network")
    harness.assertEqual(p.value, true, "the resolved value should be the client handler's return value")
end)

harness.test("server asks client: rejects malformed target IDs before dispatch", function()
    for _, target in ipairs({ 0, -1, 1.5, 0 / 0, math.huge, -math.huge }) do
        harness.assertThrows(function()
            serverTrigger(target, "confirm:action")
        end, "invalid player targets must not create pending callbacks")
    end
end)

harness.test("server asks client: rejects when the client handler errors", function()
    clientRegister("smoke:client-boom", function() error("client kaboom") end)

    local p = serverTrigger(mocks.SOURCE, "smoke:client-boom")

    harness.assertEqual(p.state, "rejected", "the promise should reject when the client handler errors")
    harness.assertTrue(tostring(p.value):find("client kaboom") ~= nil, "the rejection should carry the error message")
end)

harness.test("server asks client: an unknown callback rejects immediately", function()
    local p = serverTrigger(mocks.SOURCE, "smoke:no-client-handler")
    harness.assertEqual(p.state, "rejected", "an unknown client callback must not wait for the timeout")
    harness.assertTrue(tostring(p.value):find("not registered on the client", 1, true) ~= nil)
end)

harness.test("server asks client: a response is only accepted from the addressed player", function()
    -- Hold the client response so the request remains pending while the
    -- authorization check is exercised below.
    clientRegister("smoke:manual-client-response", function() return "ignored" end)
    local responseHandlers = net.netHandlers["kora_lib:callback:clientResponse"]
    net.netHandlers["kora_lib:callback:clientResponse"] = {}
    local p = serverTrigger(mocks.SOURCE, "smoke:manual-client-response")
    net.netHandlers["kora_lib:callback:clientResponse"] = responseHandlers
    harness.assertEqual(p.state, "pending", "sanity check: nothing should have answered yet")

    local invokeEntry = mocks.lastEntry(net.triggeredClientEvents, "kora_lib:callback:clientInvoke")
    harness.assertTrue(invokeEntry ~= nil, "expected to capture the request id from the trigger above")
    local requestId = invokeEntry[1]

    local clientResponseHandlers = net.netHandlers["kora_lib:callback:clientResponse"]

    _G.source = mocks.SOURCE
    local malformedOk = pcall(function()
        for _, fn in ipairs(clientResponseHandlers) do fn(0 / 0, true, "malformed") end
    end)
    _G.source = nil
    harness.assertTrue(malformedOk, "a malformed response id must be dropped without a handler error")
    harness.assertEqual(p.state, "pending", "a malformed response id must not settle another request")

    _G.source = mocks.SOURCE + 1
    for _, fn in ipairs(clientResponseHandlers) do fn(requestId, true, "spoofed") end
    _G.source = nil
    harness.assertEqual(p.state, "pending", "a response from the wrong player must be ignored")

    _G.source = mocks.SOURCE
    for _, fn in ipairs(clientResponseHandlers) do fn(requestId, true, "real answer") end
    _G.source = nil
    harness.assertEqual(p.state, "resolved", "the real response, from the addressed player, should resolve it")
    harness.assertEqual(p.value, "real answer", "the resolved value should be the real response")
end)

harness.test("server asks client: unregister removes the handler immediately", function()
    clientRegister("smoke:manually-unregistered", function() return "should not run" end)
    Kora.callback.unregister("smoke:manually-unregistered")

    local p = serverTrigger(mocks.SOURCE, "smoke:manually-unregistered")
    harness.assertEqual(p.state, "rejected", "an unregistered handler must reject immediately")
end)

harness.test("foreign resources cannot unregister callbacks in either realm", function()
    _G.GetInvokingResource = function() return "callback_owner" end
    serverRegister("smoke:owned-server", function() return true end)
    clientRegister("smoke:owned-client", function() return true end)

    _G.GetInvokingResource = function() return "other_resource" end
    harness.assertFalse(serverUnregister("smoke:owned-server"),
        "another resource must not unregister a server callback")
    harness.assertFalse(Kora.callback.unregister("smoke:owned-client"),
        "another resource must not unregister a client callback")

    _G.GetInvokingResource = function() return "callback_owner" end
    harness.assertTrue(serverUnregister("smoke:owned-server"),
        "the server callback owner should still be able to unregister it")
    harness.assertTrue(Kora.callback.unregister("smoke:owned-client"),
        "the client callback owner should still be able to unregister it")
    _G.GetInvokingResource = function() return nil end
end)

-- Placed last: these fire onResourceStop/onClientResourceStop for "kora_lib_test", which
-- sweeps every handler it owns. They also need a working client->server token; the earlier
-- "playerDropped clears the token" test cleared it server-side only, so replaying the
-- handshake (like a real reconnect) resyncs both sides.
_G.source = mocks.SOURCE
for _, fn in ipairs(net.netHandlers["kora_lib:callback:handshake"]) do fn() end
_G.source = nil

harness.test("client asks server: a handler survives an unrelated resource stopping", function()
    serverRegister("smoke:survives-unrelated-stop", function() return "still here" end)
    net.fire("onResourceStop", "some_other_resource")

    local p = clientTrigger("smoke:survives-unrelated-stop")
    harness.assertEqual(p.value, "still here", "a handler owned by a different resource must not be swept")
end)

harness.test("client asks server: a handler is dropped when its owning resource stops", function()
    serverRegister("smoke:dropped-on-stop", function() return "should not run" end, {
        rateLimit = { max = 1, window = 5000 },
    })
    clientTrigger('smoke:dropped-on-stop')
    harness.assertTrue(rateBuckets['smoke:dropped-on-stop'] ~= nil, 'sanity check: the callback should own a rate bucket')
    net.fire("onResourceStop", "kora_lib_test")
    harness.assertEqual(rateBuckets['smoke:dropped-on-stop'], nil, 'owner cleanup should clear the callback bucket')

    local p = clientTrigger("smoke:dropped-on-stop")
    harness.assertEqual(p.state, "rejected", "a swept server callback should reject immediately")
end)

harness.test("server asks client: a handler is dropped when its owning resource stops", function()
    clientRegister("smoke:client-dropped-on-stop", function() return "should not run" end)
    net.fire("onClientResourceStop", "kora_lib_test")

    local p = serverTrigger(mocks.SOURCE, "smoke:client-dropped-on-stop")
    harness.assertEqual(p.state, "rejected", "a swept client callback should reject immediately")
end)

harness.test("cross-resource trigger during in-flight handshake resolves to the real value, not a raw promise", function()
    -- Regression: a cross-resource caller's first call, made before the handshake completes,
    -- got the bare unresolved promise back across exports() instead of the awaited value.
    -- GetInvokingResource() is only valid in the same synchronous frame as the exports() call;
    -- awaitToken() yields while the token is missing, so the invoker must be captured before
    -- that and passed to settleForExport.
    --
    -- Needs fresh mocks and client.lua loaded BEFORE server.lua: its startup handshake then
    -- finds no server handler and leaves the token unset instead of resolving synchronously.
    mocks.install()

    ---@type string?
    local invokerName = "consumer_resource"
    function _G.GetInvokingResource() return invokerName end

    dofile(repoRoot .. "local/callback/client.lua")
    local raceClientTrigger = Kora.callback.trigger

    dofile(repoRoot .. "local/callback/server.lua")
    local raceServerRegister = Kora.callback.register

    raceServerRegister("smoke:race", function() return "resolved-value" end)

    local result
    local co = coroutine.create(function()
        result = raceClientTrigger("smoke:race")
    end)

    local ok1, err1 = coroutine.resume(co)
    harness.assertTrue(ok1, ("trigger errored before yielding: %s"):format(tostring(err1)))
    harness.assertEqual(coroutine.status(co), "suspended",
        "expected the trigger call to yield inside awaitToken() while the handshake token is still missing")

    -- The exports() call frame has ended: GetInvokingResource() reverts to nil, as after a real yield.
    invokerName = nil

    _G.TriggerServerEvent("kora_lib:callback:handshake")

    local ok2, err2 = coroutine.resume(co)
    harness.assertTrue(ok2, ("trigger errored after resuming: %s"):format(tostring(err2)))
    harness.assertEqual(coroutine.status(co), "dead",
        "expected the trigger call to run to completion once the token arrived")

    harness.assertEqual(result, "resolved-value",
        "a genuine cross-resource caller must get back the real resolved value, never a raw unresolved promise")
    harness.assertFalse(type(result) == "table" and result.state ~= nil,
        "the result must not be a raw promise table")
end)

harness.report("callback")
