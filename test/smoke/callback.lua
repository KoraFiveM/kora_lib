local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

-- Client->server and server->client each get their own handshake/token pair
-- and their own request registry, but QB.callback.register/trigger are
-- defined on BOTH realms with the same name and arity (server: register(name,
-- handler) where handler gets src; client: register(name, handler) where it
-- doesn't). Loading both files into one process for the round-trip trick
-- means the second file's version wins the QB.callback table slot -- so each
-- direction's register/trigger pair is captured by reference right after its
-- own file loads, before the other file overwrites it.
local net = mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/loops/shared.lua")
dofile(repoRoot .. "local/resources/client.lua")
dofile(repoRoot .. "local/resources/server.lua")
dofile(repoRoot .. "local/callback/shared.lua")

dofile(repoRoot .. "local/callback/server.lua")
local serverRegister = QB.callback.register
local serverTrigger = QB.callback.trigger

dofile(repoRoot .. "local/callback/client.lua") -- its startup CreateThread completes the client->server handshake synchronously
local clientRegister = QB.callback.register
local clientTrigger = QB.callback.trigger

local INVOKE = "qblib:callback:invoke"

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

harness.test("client asks server: playerDropped clears the token", function()
    local ran = false
    serverRegister("smoke:after-drop", function() ran = true end)

    clientTrigger("smoke:after-drop")
    harness.assertTrue(ran, "sanity check: the real token should still work before the player drops")

    local invokeEntry = mocks.lastEntry(net.triggeredServerEvents, INVOKE)
    harness.assertTrue(invokeEntry ~= nil, "expected to capture the real token from the trigger above")
    local capturedToken = invokeEntry[1]

    _G.source = mocks.SOURCE
    net.fire("playerDropped")
    _G.source = nil

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

harness.test("server asks client: rejects when the client handler errors", function()
    clientRegister("smoke:client-boom", function() error("client kaboom") end)

    local p = serverTrigger(mocks.SOURCE, "smoke:client-boom")

    harness.assertEqual(p.state, "rejected", "the promise should reject when the client handler errors")
    harness.assertTrue(tostring(p.value):find("client kaboom") ~= nil, "the rejection should carry the error message")
end)

harness.test("server asks client: a response is only accepted from the addressed player", function()
    -- No client handler is registered for this name, so the client's
    -- clientInvoke handler finds nothing and never responds -- the promise
    -- stays pending until the response is driven manually below.
    local p = serverTrigger(mocks.SOURCE, "smoke:no-client-handler")
    harness.assertEqual(p.state, "pending", "sanity check: nothing should have answered yet")

    local invokeEntry = mocks.lastEntry(net.triggeredClientEvents, "qblib:callback:clientInvoke")
    harness.assertTrue(invokeEntry ~= nil, "expected to capture the request id from the trigger above")
    local requestId = invokeEntry[1]

    local clientResponseHandlers = net.netHandlers["qblib:callback:clientResponse"]

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
    QB.callback.unregister("smoke:manually-unregistered")

    local p = serverTrigger(mocks.SOURCE, "smoke:manually-unregistered")
    harness.assertEqual(p.state, "pending", "an unregistered handler must not answer")
end)

-- The rest of these fire onResourceStop/onClientResourceStop for the mocked
-- resource name ("qblib_test", from GetCurrentResourceName()), which sweeps
-- every handler currently owned by it -- placed last so no earlier test's
-- still-needed registration gets swept out from under it.
--
-- They also need a working client->server token, which the earlier
-- "playerDropped clears the token" test deliberately cleared server-side
-- (tokens[mocks.SOURCE]) without the client's own cached token knowing --
-- exactly like a real reconnect, replaying the handshake refreshes both
-- sides in sync.
_G.source = mocks.SOURCE
for _, fn in ipairs(net.netHandlers["qblib:callback:handshake"]) do fn() end
_G.source = nil

harness.test("client asks server: a handler survives an unrelated resource stopping", function()
    serverRegister("smoke:survives-unrelated-stop", function() return "still here" end)
    net.fire("onResourceStop", "some_other_resource")

    local p = clientTrigger("smoke:survives-unrelated-stop")
    harness.assertEqual(p.value, "still here", "a handler owned by a different resource must not be swept")
end)

harness.test("client asks server: a handler is dropped when its owning resource stops", function()
    serverRegister("smoke:dropped-on-stop", function() return "should not run" end)
    net.fire("onResourceStop", "qblib_test")

    local p = clientTrigger("smoke:dropped-on-stop")
    harness.assertEqual(p.state, "pending", "no server handler should answer once it's been swept on resource stop")
end)

harness.test("server asks client: a handler is dropped when its owning resource stops", function()
    clientRegister("smoke:client-dropped-on-stop", function() return "should not run" end)
    net.fire("onClientResourceStop", "qblib_test")

    local p = serverTrigger(mocks.SOURCE, "smoke:client-dropped-on-stop")
    harness.assertEqual(p.state, "pending", "no client handler should answer once it's been swept on resource stop")
end)

harness.test("cross-resource trigger during in-flight handshake resolves to the real value, not a raw promise", function()
    -- Regression test for the race in QB.callback.trigger (client.lua): a
    -- genuine cross-resource caller's very first call -- extremely common
    -- right at a consumer resource's startup/player-connect, before the
    -- handshake round trip has completed -- used to get the bare unresolved
    -- promise handed back across the exports() boundary instead of the
    -- awaited value.
    --
    -- GetInvokingResource() only reflects the real caller within the SAME
    -- synchronous native-call frame as the exports() call. awaitToken()'s
    -- poll loop yields (via Wait()) while the handshake token is still
    -- missing, and by the time that resumes, GetInvokingResource() has
    -- already reverted to nil even though the original call was genuinely
    -- cross-resource. The fix captures GetInvokingResource() once, before
    -- awaitToken() gets any chance to yield, and threads it through to
    -- settleForExport explicitly instead of letting settleForExport
    -- re-query it late.
    --
    -- Fresh mocks + a fresh dofile of both realms are needed here: every
    -- other test in this file runs after the real handshake already
    -- completed synchronously during the very first dofile at the top of
    -- this file, so its `token` local is never nil by the time those tests
    -- call trigger. Loading client.lua BEFORE server.lua this time means its
    -- own startup handshake attempt finds no server handler yet and leaves
    -- the token unset, instead of resolving synchronously.
    mocks.install()

    ---@type string?
    local invokerName = "consumer_resource"
    function _G.GetInvokingResource() return invokerName end

    dofile(repoRoot .. "local/callback/client.lua")
    local raceClientTrigger = QB.callback.trigger

    dofile(repoRoot .. "local/callback/server.lua")
    local raceServerRegister = QB.callback.register

    raceServerRegister("smoke:race", function() return "resolved-value" end)

    local result
    local co = coroutine.create(function()
        result = raceClientTrigger("smoke:race")
    end)

    local ok1, err1 = coroutine.resume(co)
    harness.assertTrue(ok1, ("trigger errored before yielding: %s"):format(tostring(err1)))
    harness.assertEqual(coroutine.status(co), "suspended",
        "expected the trigger call to yield inside awaitToken() while the handshake token is still missing")

    -- The real exports() call frame has ended by now -- this is the whole
    -- hazard: GetInvokingResource() reverts to nil here, exactly as it
    -- would between a real yield and its resume.
    invokerName = nil

    _G.TriggerServerEvent("qblib:callback:handshake")

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
