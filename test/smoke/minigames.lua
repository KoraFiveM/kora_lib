local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

-- Same dual-realm-in-one-process trick test/smoke/callback.lua uses: load the
-- server half of local/callback while QB.callback.register/trigger still
-- resolve to the server versions (so modules/minigames/server.lua's
-- QB.callback.register(...) calls, made at load time, bind into the SERVER's
-- own registry), then load the client half (which overwrites the same table
-- slot) before modules/minigames/client.lua loads, so QB.minigames.play's
-- QB.callback.trigger calls -- made later, at CALL time -- resolve to the
-- CLIENT version instead.
local net = mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/util/shared.lua")
dofile(repoRoot .. "local/resources/client.lua")
dofile(repoRoot .. "local/resources/server.lua")
dofile(repoRoot .. "local/callback/shared.lua")

dofile(repoRoot .. "local/callback/server.lua")
dofile(repoRoot .. "modules/minigames/shared.lua")
local skillAdjustment = nil
QB.skills = {
    adjustMinigame = function(...)
        if skillAdjustment then return skillAdjustment(...) end
        local options = select(select('#', ...), ...)
        return options
    end,
}
dofile(repoRoot .. "modules/minigames/server.lua")

dofile(repoRoot .. "local/callback/client.lua") -- its startup CreateThread completes the client->server handshake synchronously

-- Real QB.nui isn't loaded here (that's modules/nui's own smoke test) --
-- minigames only needs somewhere to send/request against. `roundResponder`,
-- when set, is called synchronously with the "minigames:round" request data
-- and its return value settles the request immediately -- since every
-- QB.callback.trigger call in this mock environment ALSO resolves
-- synchronously (see mocks.lua), an entire multi-round QB.minigames.play()
-- flow runs to completion within one CreateThread resume, with no need for
-- net.step(). Left nil, a "minigames:round" request is simply never answered.
local sentMessages = {}
local roundResponder = nil

QB.nui = {
    send = function(action, data) table.insert(sentMessages, { action = action, data = data }) end,
    request = function(action, data)
        local p = promise.new()
        if action == "minigames:round" and roundResponder then
            p:resolve(roundResponder(data))
        end
        return p
    end,
    requestAsync = function(action, data)
        return QB.nui.request(action, data)
    end,
    cancelRequest = function(request, result, rejection)
        if request.state ~= 'pending' then return false end
        if rejection then request:reject(rejection) else request:resolve(result) end
        return true
    end,
    withFocus = function(_, _, fn) return fn() end,
}

dofile(repoRoot .. "modules/minigames/client.lua")

-- Each test starts outside every configured callback window so the production
-- quotas stay enabled without unrelated test cases sharing one mock player's
-- bucket. Dedicated tests below still exercise a full window deliberately.
local rawTest = harness.test
harness.test = function(name, fn)
    rawTest(name, function()
        local longestWindow = math.max(
            Config.minigames.callbackRateLimits.start.window,
            Config.minigames.callbackRateLimits.submit.window,
            Config.minigames.callbackRateLimits.cancel.window
        )
        Wait(longestWindow + 1)
        fn()
    end)
end

local function findUpvalue(fn, wanted)
    for index = 1, 100 do
        local name, value = debug.getupvalue(fn, index)
        if name == nil then break end
        if name == wanted then return value end
    end
    error("missing upvalue: " .. wanted)
end

local callbackDefinitions = findUpvalue(net.netHandlers["qblib:callback:invoke"][1], "registry")

local function serverCall(name, src, ...)
    return callbackDefinitions[name].handler(src, ...)
end

local defaultGetInvokingResource = _G.GetInvokingResource
local function asResource(resource, fn)
    _G.GetInvokingResource = function() return resource end
    local results = table.pack(pcall(fn))
    _G.GetInvokingResource = defaultGetInvokingResource
    if not results[1] then error(results[2], 0) end
    return table.unpack(results, 2, results.n)
end

local function mashAttempt(required)
    local timestamps = {}
    for i = 1, required do
        timestamps[i] = (i - 1) * Config.minigames.mash.minPressInterval
    end
    return { pressTimestamps = timestamps }
end

-- Inverts QB.minigames.triangleWave for a known target: pos = phase*2 for
-- phase < 0.5, so phase = target/2 always lands on the rising branch (target
-- is always < 1, so phase is always < 0.5) -- lets a test hit an exact,
-- server-generated random target without needing to predict or mock the RNG.
local function elapsedForTarget(target, speed)
    return (target / 2) * 1000 / speed
end

harness.test("triangleWave is a symmetric triangle over one full cycle", function()
    harness.assertEqual(QB.minigames.triangleWave(0, 1), 0, "phase 0 should be at the bottom")
    harness.assertEqual(QB.minigames.triangleWave(250, 1), 0.5, "phase 0.25 should be at the midpoint, rising")
    harness.assertEqual(QB.minigames.triangleWave(500, 1), 1, "phase 0.5 should be at the top")
    harness.assertEqual(QB.minigames.triangleWave(750, 1), 0.5, "phase 0.75 should be at the midpoint, falling")
end)

harness.test("play rejects an invalid game type", function()
    harness.assertThrows(function() QB.minigames.play("cardgame", {}) end, "an unsupported game type should raise")
end)

harness.test("play rejects non-table opts", function()
    harness.assertThrows(function() QB.minigames.play("mash", "fast") end, "a non-table opts should raise")
end)

harness.test("skill checks capture the server-adjusted difficulty in their authorization", function()
    skillAdjustment = function(src, skill, gameType, options)
        harness.assertEqual(src, 1, 'the adjustment should use the authorized player')
        harness.assertEqual(skill, 'mining', 'the requested skill should be forwarded')
        harness.assertEqual(gameType, 'skillbar', 'the requested minigame should be forwarded')
        local adjusted = {}
        for key, value in pairs(options) do adjusted[key] = value end
        adjusted.zoneSize = 0.6
        return adjusted, { name = skill, level = 99 }
    end

    local authorization = asResource('mining-resource', function()
        return QB.minigames.authorizeSkillCheck(1, 'mining', 'skillbar', { zoneSize = 0.1, attempts = 1 })
    end)
    local started = serverCall('qblib:minigames:start', 1, 'skillbar', { zoneSize = 0.05 }, authorization)
    skillAdjustment = nil

    harness.assertTrue(math.abs((started.public.zoneEnd - started.public.zoneStart) - 0.6) < 1e-9,
        'the client options must not replace the skill-adjusted authorized configuration')
    Citizen.Await(QB.callback.trigger('qblib:minigames:cancel', started.sessionId))
end)

harness.test("lockpick: succeeds on the first correct attempt", function()
    roundResponder = function(data)
        local pin = data.puzzle.pins[1]
        return { presses = { { index = 1, elapsed = elapsedForTarget(pin.target, data.puzzle.speed) } } }
    end

    local p = QB.minigames.play("lockpick", { pinCount = 1 })
    roundResponder = nil

    harness.assertEqual(p.state, "resolved", "the promise should resolve within the mocked synchronous flow")
    harness.assertTrue(p.value.success, "a correctly-timed single pin should succeed")
    harness.assertEqual(p.value.attempts, 1, "should succeed on the very first attempt")
    harness.assertTrue(p.value.proof == nil, "a legacy unauthorized success must not mint a proof")
end)

harness.test("lockpick: a malformed first attempt fails gracefully and a correct retry then succeeds", function()
    local round = 0
    roundResponder = function(data)
        round = round + 1
        if round == 1 then
            return { presses = {} } -- wrong shape (no pins pressed at all)
        end
        local pin = data.puzzle.pins[1]
        return { presses = { { index = 1, elapsed = elapsedForTarget(pin.target, data.puzzle.speed) } } }
    end

    sentMessages = {}
    local p = QB.minigames.play("lockpick", { pinCount = 1, attempts = 3 })
    roundResponder = nil

    harness.assertEqual(p.state, "resolved", "a malformed attempt must not error the whole play() call")
    harness.assertTrue(p.value.success, "the correct retry should still succeed")
    harness.assertEqual(p.value.attempts, 2, "should have taken exactly 2 attempts")

    local closeCount = 0
    for _, msg in ipairs(sentMessages) do
        if msg.action == "minigames:close" then closeCount = closeCount + 1 end
    end
    harness.assertEqual(closeCount, 1, "the overlay should close exactly once, after the final result -- not between rounds")
end)

harness.test("mash: fails and exhausts every attempt when never enough presses are reported", function()
    roundResponder = function() return { pressTimestamps = {} } end

    local p = QB.minigames.play("mash", { attempts = 2, requiredPresses = 5 })
    roundResponder = nil

    harness.assertEqual(p.state, "resolved", "running out of attempts should still resolve, not reject")
    harness.assertFalse(p.value.success, "should fail when never enough presses are reported")
    harness.assertEqual(p.value.attempts, 2, "should have used every allotted attempt")
end)

harness.test("cancelling a round ends the session immediately without consuming an attempt", function()
    sentMessages = {}
    roundResponder = function() return { cancelled = true } end

    local p = QB.minigames.play("mash", { attempts = 3 })
    roundResponder = nil

    harness.assertEqual(p.state, "resolved", "a cancel should resolve cleanly, not reject")
    harness.assertFalse(p.value.success, "a cancelled session cannot succeed")
    harness.assertTrue(p.value.cancelled, "the result should be flagged cancelled")
    harness.assertEqual(p.value.attempts, 0, "cancelling before ever submitting should have used zero attempts")

    local closedWithCancelled = false
    for _, msg in ipairs(sentMessages) do
        if msg.action == "minigames:close" and msg.data and msg.data.result == "cancelled" then
            closedWithCancelled = true
        end
    end
    harness.assertTrue(closedWithCancelled, "the overlay should close with result = cancelled")

    -- Proves the SERVER session was actually freed right away rather than
    -- left for expiresAt/the 30s sweep -- a fresh session must be obtainable
    -- immediately, not rejected by the per-player concurrency guard.
    local fresh = Citizen.Await(QB.callback.trigger("qblib:minigames:start", "mash", { attempts = 1 }))
    harness.assertTrue(fresh.sessionId ~= nil, "a fresh session should start immediately after cancelling, proving the old one was freed")
    Citizen.Await(QB.callback.trigger("qblib:minigames:submit", fresh.sessionId, { pressTimestamps = {} }))
end)

harness.test("skillbar: succeeds when the reported elapsed lands in the target zone", function()
    -- Slowed speed keeps the required elapsed comfortably above
    -- Config.minigames.skillbar.minReactionTime regardless of where the
    -- randomly-placed zone ends up.
    roundResponder = function(data)
        local mid = (data.puzzle.zoneStart + data.puzzle.zoneEnd) / 2
        return { elapsed = elapsedForTarget(mid, data.puzzle.speed) }
    end

    local p = QB.minigames.play("skillbar", { speed = 0.3 })
    roundResponder = nil

    harness.assertEqual(p.state, "resolved", "should resolve")
    harness.assertTrue(p.value.success, "hitting the middle of the target zone should succeed")
end)

harness.test("circuit: succeeds by connecting every matching color pair", function()
    roundResponder = function(data)
        local outputByColor = {}
        for _, node in ipairs(data.puzzle.nodes) do
            if node.side == "output" then outputByColor[node.color] = node.id end
        end

        local connections = {}
        local elapsed = 0
        for _, node in ipairs(data.puzzle.nodes) do
            if node.side == "input" then
                elapsed = elapsed + Config.minigames.circuit.minTimePerConnection + 10
                connections[#connections + 1] = { from = node.id, to = outputByColor[node.color], elapsed = elapsed }
            end
        end

        return { connections = connections }
    end

    local p = QB.minigames.play("circuit", { nodeCount = 3 })
    roundResponder = nil

    harness.assertEqual(p.state, "resolved", "should resolve")
    harness.assertTrue(p.value.success, "connecting every matching color pair should succeed")
end)

harness.test("submit treats an expired session as a clean failure", function()
    local round = Citizen.Await(QB.callback.trigger("qblib:minigames:start", "mash", {}))
    _G.Wait(Config.minigames.sessionTTL + 5000)

    local result = Citizen.Await(QB.callback.trigger("qblib:minigames:submit", round.sessionId, { pressTimestamps = {} }))

    harness.assertTrue(result.done, "an expired session must end the play() call")
    harness.assertFalse(result.success, "an expired session cannot succeed")
end)

harness.test("long rounds and retries outlive the minimum abandoned-session TTL", function()
    local round = Citizen.Await(QB.callback.trigger("qblib:minigames:start", "lockpick", {
        attempts = 2,
        pinCount = 1,
        timeLimit = 60000,
    }))

    _G.Wait(Config.minigames.sessionTTL + 1)
    local retry = Citizen.Await(QB.callback.trigger("qblib:minigames:submit", round.sessionId, { presses = {} }))
    harness.assertFalse(retry.done, "the first long round should be processed rather than expired")
    harness.assertEqual(retry.attempt, 2, "a failed long round should issue the next attempt")

    _G.Wait(Config.minigames.sessionTTL + 1)
    local result = Citizen.Await(QB.callback.trigger("qblib:minigames:submit", round.sessionId, { presses = {} }))
    harness.assertTrue(result.done, "the final retry should finish normally")
    harness.assertEqual(result.attemptsUsed, 2, "the refreshed retry deadline should preserve both attempts")
end)

harness.test("a rejected NUI round cancels its server session before rejecting play", function()
    local originalRequest = QB.nui.request
    QB.nui.request = function()
        local rejected = promise.new()
        rejected:reject("simulated NUI failure")
        return rejected
    end

    local result = QB.minigames.play("mash", { attempts = 1 })
    QB.nui.request = originalRequest
    harness.assertEqual(result.state, "rejected", "the NUI error should reject play")

    local fresh = serverCall("qblib:minigames:start", mocks.SOURCE, "mash", { attempts = 1 })
    harness.assertTrue(fresh.sessionId ~= nil, "the failed client round-trip must not block an immediate retry")
    serverCall("qblib:minigames:cancel", mocks.SOURCE, fresh.sessionId)
end)

harness.test("start opportunistically reclaims an expired session before its concurrency check", function()
    serverCall("qblib:minigames:start", mocks.SOURCE, "mash", { attempts = 1 })
    Wait(Config.minigames.sessionTTL + 1)

    local fresh = serverCall("qblib:minigames:start", mocks.SOURCE, "mash", { attempts = 1 })
    harness.assertTrue(fresh.sessionId ~= nil, "an expired session must not reject a valid retry")
    serverCall("qblib:minigames:cancel", mocks.SOURCE, fresh.sessionId)
end)

harness.test("submit rejects a request from a player who doesn't own the session", function()
    -- attempts = 1 so the cleanup submit below unconditionally ends the
    -- session (pass or fail) rather than leaking it into later tests.
    local round = Citizen.Await(QB.callback.trigger("qblib:minigames:start", "mash", { attempts = 1 }))

    -- Register a second simulated player with its own real handshake token,
    -- then drive the server's raw invoke handler directly as that player --
    -- this is testing session.src ~= src, not the token gate local/callback's
    -- own smoke test already covers.
    local otherSrc = mocks.SOURCE + 1
    _G.source = otherSrc
    for _, fn in ipairs(net.netHandlers["qblib:callback:handshake"]) do fn() end
    _G.source = nil

    local handshakeEntry = mocks.lastEntry(net.triggeredClientEvents, "qblib:callback:handshake:response")
    harness.assertTrue(handshakeEntry ~= nil, "expected the second player's handshake to produce a token")
    local otherToken = handshakeEntry[1]

    _G.source = otherSrc
    for _, fn in ipairs(net.netHandlers["qblib:callback:invoke"]) do
        fn(otherToken, 999999, "qblib:minigames:submit", round.sessionId, { pressTimestamps = {} })
    end
    _G.source = nil

    local responseEntry = mocks.lastEntry(net.triggeredClientEvents, "qblib:callback:response")
    harness.assertTrue(responseEntry ~= nil, "the invoke should have produced a response")
    harness.assertEqual(responseEntry.target, otherSrc, "the response should be addressed to the attacking player")
    harness.assertFalse(responseEntry[2], "a submit from a non-owning player must be rejected (ok = false)")

    -- The mock's TriggerClientEvent doesn't filter by target (only one
    -- simulated client exists), so the second player's handshake response
    -- above just overwrote the shared client's own cached token -- replay
    -- mocks.SOURCE's handshake to resync before using QB.callback.trigger
    -- normally again, exactly like test/smoke/callback.lua's own
    -- "playerDropped clears the token" test does after the same kind of
    -- token-clobbering.
    _G.source = mocks.SOURCE
    for _, fn in ipairs(net.netHandlers["qblib:callback:handshake"]) do fn() end
    _G.source = nil

    Citizen.Await(QB.callback.trigger("qblib:minigames:submit", round.sessionId, { pressTimestamps = {} }))
end)

harness.test("server rejects a second concurrent session for the same player, independent of the client-side guard", function()
    -- attempts = 1 so the cleanup submit below unconditionally ends the
    -- session (pass or fail) rather than leaking it into later tests.
    local first = Citizen.Await(QB.callback.trigger("qblib:minigames:start", "mash", { attempts = 1 }))
    harness.assertTrue(first.sessionId ~= nil, "sanity check: the first session should start")

    local p = QB.callback.trigger("qblib:minigames:start", "mash", {})
    harness.assertEqual(p.state, "rejected", "the server must reject a second concurrent session for the same player")

    Citizen.Await(QB.callback.trigger("qblib:minigames:submit", first.sessionId, { pressTimestamps = {} }))
end)

harness.test("play rejects a concurrent call while one is already in flight", function()
    local innerP = nil

    -- Still "in flight" at this point -- CreateThread's mock runs the whole
    -- body synchronously, so this responder call happens WHILE the outer
    -- play() call's CreateThread is still executing, before it has cleared
    -- its own activeSession guard.
    roundResponder = function()
        innerP = QB.minigames.play("mash", {})
        return { pressTimestamps = {} }
    end

    local outerP = QB.minigames.play("mash", { requiredPresses = 1000, attempts = 1 })
    roundResponder = nil

    harness.assertTrue(innerP ~= nil, "the responder should have attempted a concurrent call")
    harness.assertEqual(innerP.state, "rejected", "a concurrent call must be rejected, not queued")
    harness.assertEqual(outerP.state, "resolved", "the original call should still complete normally")
end)

harness.test("resource-stop cleanup clears the client-side guard and closes the overlay with result = cancelled", function()
    sentMessages = {}
    local innerP = nil

    roundResponder = function()
        net.fire("onClientResourceStop", "qblib_test")

        -- Swap in a plain (non-reentrant) responder for the inner call's own
        -- round -- reusing the outer responder here would have it fire
        -- onClientResourceStop and recurse into QB.minigames.play again,
        -- unboundedly, since the mock resolves everything synchronously.
        local outerResponder = roundResponder
        roundResponder = function() return { pressTimestamps = {} } end
        innerP = QB.minigames.play("mash", { requiredPresses = 1000, attempts = 1 })
        roundResponder = outerResponder

        return { pressTimestamps = {} }
    end

    QB.minigames.play("mash", { requiredPresses = 1000, attempts = 1 })
    roundResponder = nil

    harness.assertTrue(innerP ~= nil, "the responder should have attempted a fresh call")
    -- The outer session is still alive SERVER-side -- the server has no idea
    -- the client gave up (see this module's AGENTS.md "best-effort" note) --
    -- so the fresh attempt is still rejected, but by the SERVER's per-player
    -- check rather than the CLIENT's activeSession guard, which proves the
    -- guard itself was actually cleared rather than left stuck forever.
    harness.assertEqual(innerP.state, "rejected", "a fresh call still can't get a server session while the outer one is unresolved")
    harness.assertTrue(tostring(innerP.value):find("for this player", 1, true) ~= nil,
        "should be rejected by the SERVER's per-player check, not a stuck CLIENT-side activeSession guard")

    local closedWithCancelled = false
    for _, msg in ipairs(sentMessages) do
        if msg.action == "minigames:close" and msg.data and msg.data.result == "cancelled" then
            closedWithCancelled = true
        end
    end
    harness.assertTrue(closedWithCancelled, "the dispose handler should close the overlay with result = cancelled")
end)

harness.test("pinpad: succeeds when the submitted digits match, with human-plausible spacing", function()
    roundResponder = function(data)
        local digits = {}
        for i = 1, data.puzzle.digitCount do
            digits[i] = { value = (i == 1) and 1 or 2, elapsed = i * (Config.minigames.pinpad.minTimePerDigit + 10) }
        end
        return { digits = digits }
    end

    local p = QB.minigames.play("pinpad", { numbers = 1222 })
    roundResponder = nil

    harness.assertEqual(p.state, "resolved", "should resolve")
    harness.assertTrue(p.value.success, "matching the caller-supplied PIN should succeed")
end)

harness.test("pinpad: fails when a digit is wrong", function()
    roundResponder = function(data)
        local digits = {}
        for i = 1, data.puzzle.digitCount do
            digits[i] = { value = 9, elapsed = i * (Config.minigames.pinpad.minTimePerDigit + 10) }
        end
        return { digits = digits }
    end

    local p = QB.minigames.play("pinpad", { numbers = 1234, attempts = 1 })
    roundResponder = nil

    harness.assertEqual(p.state, "resolved", "should resolve")
    harness.assertFalse(p.value.success, "a wrong digit sequence should fail")
end)

harness.test("quiz: succeeds once enough answers are correct", function()
    local questions = {
        { question = "2+2?", answer = "4", options = { "3", "4", "5" } },
        { question = "3+3?", answer = "6", options = { "5", "6", "7" } },
    }
    roundResponder = function(data)
        local answers = {}
        for i in ipairs(data.puzzle.questions) do
            answers[i] = { choice = questions[i].answer, elapsed = i * (Config.minigames.quiz.minTimePerAnswer + 10) }
        end
        return { answers = answers }
    end

    local p = QB.minigames.play("quiz", { questions = questions, correctRequired = 2, timer = 10 })
    roundResponder = nil

    harness.assertEqual(p.state, "resolved", "should resolve")
    harness.assertTrue(p.value.success, "answering every question correctly should meet correctRequired")
end)

harness.test("wordguess: succeeds once every letter of the word is found", function()
    roundResponder = function()
        local letters = { "c", "a", "t" }
        local guesses = {}
        for i, letter in ipairs(letters) do
            guesses[i] = { letter = letter, elapsed = i * (Config.minigames.wordguess.minTimePerGuess + 10) }
        end
        return { guesses = guesses }
    end

    local p = QB.minigames.play("wordguess", { word = "cat", hint = "an animal", guesses = 5 })
    roundResponder = nil

    harness.assertEqual(p.state, "resolved", "should resolve")
    harness.assertTrue(p.value.success, "guessing every letter of the word should succeed")
end)

harness.test("wordguess: fails once wrong guesses exceed the allowance", function()
    roundResponder = function()
        local letters = { "x", "y", "z" }
        local guesses = {}
        for i, letter in ipairs(letters) do
            guesses[i] = { letter = letter, elapsed = i * (Config.minigames.wordguess.minTimePerGuess + 10) }
        end
        return { guesses = guesses }
    end

    local p = QB.minigames.play("wordguess", { word = "cat", hint = "an animal", guesses = 2, attempts = 1 })
    roundResponder = nil

    harness.assertEqual(p.state, "resolved", "should resolve")
    harness.assertFalse(p.value.success, "exceeding the wrong-guess allowance should fail")
end)

harness.test("wordscramble: succeeds when the submitted guess matches the original word", function()
    roundResponder = function()
        return { guess = "fivem", elapsed = Config.minigames.wordscramble.minSubmitTime + 10 }
    end

    local p = QB.minigames.play("wordscramble", { word = "fivem", hint = "the game modification", timer = 30 })
    roundResponder = nil

    harness.assertEqual(p.state, "resolved", "should resolve")
    harness.assertTrue(p.value.success, "matching the original word should succeed")
end)

harness.test("keys: always succeeds and reports a faults count", function()
    roundResponder = function(data)
        local presses = {}
        for i, key in ipairs(data.puzzle.pattern) do
            -- Deliberately get the first key wrong to prove faults is counted.
            local wrongOnFirst = (i == 1) and (key == "up" and "down" or "up") or key
            presses[i] = { key = wrongOnFirst, elapsed = i * (Config.minigames.keys.minTimePerPress + 10) }
        end
        return { presses = presses }
    end

    local p = QB.minigames.play("keys", { amount = 4 })
    roundResponder = nil

    harness.assertEqual(p.state, "resolved", "should resolve")
    harness.assertTrue(p.value.success, "keys always completes -- there is no pass/fail concept upstream")
    harness.assertEqual(p.value.faults, 1, "exactly one deliberately-wrong press should be counted")
end)

harness.test("hacking: succeeds when the submitted code matches the generated one", function()
    roundResponder = function(data)
        return { submitted = data.puzzle.code, elapsed = Config.minigames.hacking.minTimePerFind + 10 }
    end

    local p = QB.minigames.play("hacking", { solutionsize = 5, timeout = 30 })
    roundResponder = nil

    harness.assertEqual(p.state, "resolved", "should resolve")
    harness.assertTrue(p.value.success, "submitting the revealed code should succeed")
end)

harness.test("hacking: fails when the submitted code is wrong", function()
    roundResponder = function()
        return { submitted = "ZZZZZ", elapsed = Config.minigames.hacking.minTimePerFind + 10 }
    end

    local p = QB.minigames.play("hacking", { solutionsize = 5, timeout = 30 })
    roundResponder = nil

    harness.assertEqual(p.state, "resolved", "should resolve")
    harness.assertFalse(p.value.success, "a wrong code should fail")
end)

harness.test("minigame callbacks retain their configured per-player rate limits", function()
    for name, expected in pairs(Config.minigames.callbackRateLimits) do
        local definition = callbackDefinitions["qblib:minigames:" .. name]
        harness.assertTrue(definition ~= nil, "expected a registered " .. name .. " callback")
        harness.assertEqual(definition.rateLimit.max, expected.max, name .. " max should match config")
        harness.assertEqual(definition.rateLimit.window, expected.window, name .. " window should match config")
    end

    for _ = 1, Config.minigames.callbackRateLimits.start.max do
        local round = Citizen.Await(QB.callback.trigger("qblib:minigames:start", "mash", { attempts = 1 }))
        Citizen.Await(QB.callback.trigger("qblib:minigames:cancel", round.sessionId))
    end
    local rejected = QB.callback.trigger("qblib:minigames:start", "mash", { attempts = 1 })
    harness.assertEqual(rejected.state, "rejected", "the next start inside the same window should be rate-limited")
    harness.assertTrue(tostring(rejected.value):find("rate limit exceeded", 1, true) ~= nil,
        "the rejection should identify the callback quota")
end)

harness.test("authorized play ignores client opts and returns a bound opaque proof", function()
    local authorization = asResource("consumer_a", function()
        return QB.minigames.authorizeProof(mocks.SOURCE, "mash", {
            attempts = 1,
            requiredPresses = 6,
            timeLimit = 4000,
        })
    end)

    local seen
    roundResponder = function(data)
        seen = data
        return mashAttempt(data.puzzle.requiredPresses)
    end
    local p = QB.minigames.play("mash", { attempts = 10, requiredPresses = 3, timeLimit = 1000 }, authorization)
    roundResponder = nil

    harness.assertEqual(p.state, "resolved", "the authorized play should resolve")
    harness.assertTrue(p.value.success, "the trusted round should succeed")
    harness.assertEqual(seen.puzzle.requiredPresses, 6, "trusted server options must override easier client options")
    harness.assertEqual(seen.attempts, 1, "trusted attempt count must override the client value")
    harness.assertTrue(type(p.value.proof) == "string" and #p.value.proof == 32,
        "an authorized success should return a 32-character opaque proof")
    harness.assertTrue(p.value.proof:find(":", 1, true) == nil, "the proof must not encode player/session identifiers")

    local proof = p.value.proof
    harness.assertFalse(asResource("consumer_a", function()
        return QB.minigames.consumeProof(mocks.SOURCE + 1, proof, "mash", authorization)
    end), "a player mismatch must fail")
    harness.assertFalse(asResource("consumer_a", function()
        return QB.minigames.consumeProof(mocks.SOURCE, proof, "lockpick", authorization)
    end), "a game-type mismatch must fail")
    harness.assertFalse(asResource("consumer_a", function()
        return QB.minigames.consumeProof(mocks.SOURCE, proof, "mash", "wrong-authorization")
    end), "an authorization mismatch must fail")
    harness.assertFalse(asResource("consumer_b", function()
        return QB.minigames.consumeProof(mocks.SOURCE, proof, "mash", authorization)
    end), "an issuer mismatch must fail")
    harness.assertTrue(asResource("consumer_a", function()
        return QB.minigames.consumeProof(mocks.SOURCE, proof, "mash", authorization)
    end), "mismatches must not burn the valid proof")
    harness.assertFalse(asResource("consumer_a", function()
        return QB.minigames.consumeProof(mocks.SOURCE, proof, "mash", authorization)
    end), "a proof must be single-use")
end)

harness.test("authorization mismatches do not burn a valid single-start capability", function()
    local authorization = asResource("consumer_auth", function()
        return QB.minigames.authorizeProof(mocks.SOURCE, "mash", { attempts = 1, requiredPresses = 3 })
    end)

    harness.assertFalse(pcall(function()
        serverCall("qblib:minigames:start", mocks.SOURCE + 1, "mash", nil, authorization)
    end), "the wrong player must not start an authorized round")
    harness.assertFalse(pcall(function()
        serverCall("qblib:minigames:start", mocks.SOURCE, "lockpick", nil, authorization)
    end), "the wrong game type must not start an authorized round")

    local round = serverCall("qblib:minigames:start", mocks.SOURCE, "mash", { requiredPresses = 100 }, authorization)
    harness.assertEqual(round.public.requiredPresses, 3, "the original trusted config should remain available")
    serverCall("qblib:minigames:cancel", mocks.SOURCE, round.sessionId)

    harness.assertFalse(pcall(function()
        serverCall("qblib:minigames:start", mocks.SOURCE, "mash", nil, authorization)
    end), "a consumed authorization must not start a second session")
end)

harness.test("failed and cancelled authorized sessions never return a proof", function()
    local failedAuthorization = asResource("consumer_outcomes", function()
        return QB.minigames.authorizeProof(mocks.SOURCE, "mash", { attempts = 1, requiredPresses = 3 })
    end)
    local failedRound = serverCall("qblib:minigames:start", mocks.SOURCE, "mash", nil, failedAuthorization)
    local failed = serverCall("qblib:minigames:submit", mocks.SOURCE, failedRound.sessionId, { pressTimestamps = {} })
    harness.assertFalse(failed.success, "the intentionally empty attempt should fail")
    harness.assertTrue(failed.proof == nil, "a failed authorized session must not mint a proof")

    local cancelledAuthorization = asResource("consumer_outcomes", function()
        return QB.minigames.authorizeProof(mocks.SOURCE, "mash", { attempts = 1, requiredPresses = 3 })
    end)
    roundResponder = function() return { cancelled = true } end
    local cancelled = QB.minigames.play("mash", nil, cancelledAuthorization)
    roundResponder = nil
    harness.assertTrue(cancelled.value.cancelled, "the session should report cancellation")
    harness.assertTrue(cancelled.value.proof == nil, "a cancelled authorized session must not mint a proof")
end)

harness.test("resource stop removes pending authorizations, live sessions, and proofs", function()
    local pendingAuthorization = asResource("consumer_cleanup", function()
        return QB.minigames.authorizeProof(mocks.SOURCE, "mash", { attempts = 1, requiredPresses = 3 })
    end)
    local proofAuthorization = asResource("consumer_cleanup", function()
        return QB.minigames.authorizeProof(mocks.SOURCE, "mash", { attempts = 1, requiredPresses = 3 })
    end)
    local proofRound = serverCall("qblib:minigames:start", mocks.SOURCE, "mash", nil, proofAuthorization)
    local proofResult = serverCall("qblib:minigames:submit", mocks.SOURCE, proofRound.sessionId, mashAttempt(3))

    local activeAuthorization = asResource("consumer_cleanup", function()
        return QB.minigames.authorizeProof(mocks.SOURCE, "mash", { attempts = 1, requiredPresses = 3 })
    end)
    serverCall("qblib:minigames:start", mocks.SOURCE, "mash", nil, activeAuthorization)

    net.fire("onResourceStop", "consumer_cleanup")

    harness.assertFalse(pcall(function()
        serverCall("qblib:minigames:start", mocks.SOURCE, "mash", nil, pendingAuthorization)
    end), "a stopped resource's pending authorization must be removed")
    harness.assertFalse(asResource("consumer_cleanup", function()
        return QB.minigames.consumeProof(mocks.SOURCE, proofResult.proof, "mash", proofAuthorization)
    end), "a stopped resource's proof must be removed")

    local fresh = serverCall("qblib:minigames:start", mocks.SOURCE, "mash", { attempts = 1 })
    harness.assertTrue(fresh.sessionId ~= nil, "resource cleanup must free its active authorized session")
    serverCall("qblib:minigames:cancel", mocks.SOURCE, fresh.sessionId)
end)

harness.test("authorization and proof TTLs are enforced", function()
    local expiredAuthorization = asResource("consumer_ttl", function()
        return QB.minigames.authorizeProof(mocks.SOURCE, "mash", { attempts = 1, requiredPresses = 3 })
    end)
    Wait(Config.minigames.authorizationTTL + 1)
    harness.assertFalse(pcall(function()
        serverCall("qblib:minigames:start", mocks.SOURCE, "mash", nil, expiredAuthorization)
    end), "an expired authorization must not start a session")

    local proofAuthorization = asResource("consumer_ttl", function()
        return QB.minigames.authorizeProof(mocks.SOURCE, "mash", { attempts = 1, requiredPresses = 3 })
    end)
    local round = serverCall("qblib:minigames:start", mocks.SOURCE, "mash", nil, proofAuthorization)
    local result = serverCall("qblib:minigames:submit", mocks.SOURCE, round.sessionId, mashAttempt(3))
    Wait(Config.minigames.proofTTL + 1)
    harness.assertFalse(asResource("consumer_ttl", function()
        return QB.minigames.consumeProof(mocks.SOURCE, result.proof, "mash", proofAuthorization)
    end), "an expired proof must not be consumable")
end)

harness.test("numeric, string, and dense-array bounds reject pathological input", function()
    local finiteAuthorization = asResource("consumer_limits", function()
        return QB.minigames.authorizeProof(mocks.SOURCE, "skillbar", {
            speed = 0 / 0,
            timeLimit = math.huge,
        })
    end)
    local finiteRound = serverCall("qblib:minigames:start", mocks.SOURCE, "skillbar", nil, finiteAuthorization)
    harness.assertEqual(finiteRound.public.speed, Config.minigames.skillbar.speed,
        "NaN should fall back to the trusted default")
    harness.assertEqual(finiteRound.timeLimit, Config.minigames.skillbar.timeLimit,
        "infinity should fall back to the trusted default")
    serverCall("qblib:minigames:cancel", mocks.SOURCE, finiteRound.sessionId)

    harness.assertFalse(pcall(function()
        asResource("consumer_limits", function()
            QB.minigames.authorizeProof(mocks.SOURCE, "pinpad", { numbers = "123456789" })
        end)
    end), "PIN content beyond the digit cap must be rejected")
    harness.assertFalse(pcall(function()
        asResource("consumer_limits", function()
            QB.minigames.authorizeProof(mocks.SOURCE, "wordguess", {
                word = string.rep("a", Config.minigames.inputLimits.wordGuessBytes + 1),
            })
        end)
    end), "oversized word content must be rejected")

    local questions = {}
    for i = 1, Config.minigames.inputLimits.quizQuestions + 1 do
        questions[i] = { question = "q", answer = "a", options = { "a" } }
    end
    harness.assertFalse(pcall(function()
        asResource("consumer_limits", function()
            QB.minigames.authorizeProof(mocks.SOURCE, "quiz", { questions = questions })
        end)
    end), "oversized question arrays must be rejected")

    local sparseRound = serverCall("qblib:minigames:start", mocks.SOURCE, "mash",
        { attempts = 1, requiredPresses = 3 })
    local sparse = serverCall("qblib:minigames:submit", mocks.SOURCE, sparseRound.sessionId, {
        pressTimestamps = { [1] = 0, [3] = 120 },
    })
    harness.assertFalse(sparse.success, "a sparse attempt array must count as a failed attempt")

    local oversizedRound = serverCall("qblib:minigames:start", mocks.SOURCE, "mash",
        { attempts = 1, requiredPresses = 3 })
    local oversized = serverCall("qblib:minigames:submit", mocks.SOURCE, oversizedRound.sessionId, {
        pressTimestamps = { 0, 60, 120, 180 },
    })
    harness.assertFalse(oversized.success, "an oversized attempt array must count as a failed attempt")
end)

harness.test("playerDropped removes every minigame capability and active session", function()
    local pendingAuthorization = asResource("consumer_player", function()
        return QB.minigames.authorizeProof(mocks.SOURCE, "mash", { attempts = 1, requiredPresses = 3 })
    end)
    local proofAuthorization = asResource("consumer_player", function()
        return QB.minigames.authorizeProof(mocks.SOURCE, "mash", { attempts = 1, requiredPresses = 3 })
    end)
    local proofRound = serverCall("qblib:minigames:start", mocks.SOURCE, "mash", nil, proofAuthorization)
    local proofResult = serverCall("qblib:minigames:submit", mocks.SOURCE, proofRound.sessionId, mashAttempt(3))
    local activeAuthorization = asResource("consumer_player", function()
        return QB.minigames.authorizeProof(mocks.SOURCE, "mash", { attempts = 1, requiredPresses = 3 })
    end)
    serverCall("qblib:minigames:start", mocks.SOURCE, "mash", nil, activeAuthorization)

    _G.source = mocks.SOURCE
    net.fire("playerDropped")
    _G.source = nil

    harness.assertFalse(pcall(function()
        serverCall("qblib:minigames:start", mocks.SOURCE, "mash", nil, pendingAuthorization)
    end), "disconnect must remove pending authorizations")
    harness.assertFalse(asResource("consumer_player", function()
        return QB.minigames.consumeProof(mocks.SOURCE, proofResult.proof, "mash", proofAuthorization)
    end), "disconnect must remove proofs")
    local fresh = serverCall("qblib:minigames:start", mocks.SOURCE, "mash", { attempts = 1 })
    serverCall("qblib:minigames:cancel", mocks.SOURCE, fresh.sessionId)

    -- playerDropped also clears the callback layer's handshake token; restore
    -- the simulated player's token for any future test appended to this file.
    _G.source = mocks.SOURCE
    for _, fn in ipairs(net.netHandlers["qblib:callback:handshake"]) do fn() end
    _G.source = nil
end)

harness.report("minigames")
