local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

-- QB.timers is a shared module that picks its ownership registry by realm at
-- first use. mocks.lua deliberately doesn't define IsDuplicityVersion (it is a
-- realm marker, not a module native), so this file pins the client realm and
-- loads local/resources/client.lua to match.
function _G.IsDuplicityVersion() return false end

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "local/resources/client.lua")
dofile(repoRoot .. "modules/timers/shared.lua")

harness.test("setInterval fires once per tick and keeps going", function()
    local runs = 0
    local id = QB.timers.setInterval(function() runs = runs + 1 end, 100)

    harness.assertEqual(runs, 0, "the first run must be a full interval away, not immediate")

    net.step()
    harness.assertEqual(runs, 1, "one step should produce one tick")

    net.step()
    harness.assertEqual(runs, 2, "the interval should keep running after its first tick")

    QB.timers.clearInterval(id)
end)

harness.test("clearInterval stops the timer without firing one extra tick", function()
    local runs = 0
    local id = QB.timers.setInterval(function() runs = runs + 1 end, 100)

    net.step()
    harness.assertEqual(runs, 1, "sanity: the interval ran once")

    local cancelled = QB.timers.clearInterval(id)
    harness.assertTrue(cancelled, "clearInterval should report that it cancelled a live timer")

    -- The coroutine is parked inside Wait() at this point. Resuming it must
    -- observe the flag and return rather than run the body one last time --
    -- that post-wait re-check is the whole point of the record indirection.
    net.step()
    harness.assertEqual(runs, 1, "a cancelled interval must not fire again after its parked Wait resumes")
end)

harness.test("clearInterval reports false for an unknown or already-cancelled id", function()
    harness.assertFalse(QB.timers.clearInterval(999999), "an id that was never live should report false")

    local id = QB.timers.setInterval(function() end, 100)
    QB.timers.clearInterval(id)
    harness.assertFalse(QB.timers.clearInterval(id), "cancelling twice should report false the second time")
end)

harness.test("setTimeout fires exactly once", function()
    local runs = 0
    QB.timers.setTimeout(function() runs = runs + 1 end, 50)

    harness.assertEqual(runs, 0, "a timeout must not fire synchronously")

    net.step()
    harness.assertEqual(runs, 1, "the timeout should fire on its first resume")

    net.step()
    harness.assertEqual(runs, 1, "a one-shot must not fire again")
end)

harness.test("a fired timeout untracks itself", function()
    local before = QB.timers.count()
    QB.timers.setTimeout(function() end, 50)
    harness.assertEqual(QB.timers.count(), before + 1, "a pending timeout should be counted")

    net.step()
    harness.assertEqual(QB.timers.count(), before, "a fired one-shot must drop out of tracking, not leak an entry")
end)

harness.test("clearTimeout prevents a pending timeout from firing", function()
    local runs = 0
    local id = QB.timers.setTimeout(function() runs = runs + 1 end, 50)

    harness.assertTrue(QB.timers.clearTimeout(id), "clearTimeout should cancel a pending one-shot")

    net.step()
    harness.assertEqual(runs, 0, "a cancelled timeout must never run")
end)

harness.test("timers are cancelled when their owning resource stops", function()
    local runs = 0

    _G.GetInvokingResource = function() return "some_other_resource" end
    QB.timers.setInterval(function() runs = runs + 1 end, 100)
    _G.GetInvokingResource = function() return nil end

    net.step()
    harness.assertEqual(runs, 1, "sanity: the interval is live before its resource stops")

    net.fire("onClientResourceStop", "some_other_resource")

    net.step()
    harness.assertEqual(runs, 1, "the interval must stop once its owning resource does")
end)

harness.test("setInterval contains a handler error and keeps ticking", function()
    local runs = 0
    local id = QB.timers.setInterval(function()
        runs = runs + 1
        error("boom")
    end, 100)

    net.step()
    net.step()

    harness.assertEqual(runs, 2, "an erroring tick must not kill the interval")
    QB.timers.clearInterval(id)
end)

harness.test("setInterval accepts a cross-resource callable table", function()
    local runs = 0
    -- What FXServer actually hands back for a function that crossed an exports
    -- boundary: a table with a __call metamethod, which type(x) == "function"
    -- would reject outright.
    local callable = setmetatable({}, { __call = function() runs = runs + 1 end })

    local id = QB.timers.setInterval(callable, 100)
    net.step()

    harness.assertEqual(runs, 1, "a __call table must be accepted like a plain function")
    QB.timers.clearInterval(id)
end)

harness.test("setInterval rejects a non-callable and a negative interval", function()
    harness.assertThrows(function() QB.timers.setInterval("not a function", 100) end,
        "a string handler should be refused")
    harness.assertThrows(function() QB.timers.setInterval(function() end, -1) end,
        "a negative interval should be refused")
end)

harness.test("debounce fires once, with the last call's arguments", function()
    local calls = {}
    local save = QB.timers.debounce(function(value) calls[#calls + 1] = value end, 100)

    save("first")
    save("second")
    save("third")

    harness.assertEqual(#calls, 0, "a debounced call must not run while calls are still arriving")
    harness.assertTrue(save.isPending(), "the debouncer should report a pending run")

    net.step()

    harness.assertEqual(#calls, 1, "only one run should survive three rapid calls")
    harness.assertEqual(calls[1], "third", "the LAST call's arguments are the ones used")
    harness.assertFalse(save.isPending(), "the debouncer should be idle once it has fired")
end)

harness.test("debounce cancel drops the pending run", function()
    local runs = 0
    local save = QB.timers.debounce(function() runs = runs + 1 end, 100)

    save()
    harness.assertTrue(save.cancel(), "cancel should report that it dropped a pending run")
    harness.assertFalse(save.cancel(), "cancelling with nothing pending should report false")

    net.step()
    harness.assertEqual(runs, 0, "a cancelled debounce must never run")
end)

harness.test("throttle passes the first call and drops the rest of the window", function()
    local runs = 0
    local alert = QB.timers.throttle(function() runs = runs + 1 end, 1000)

    harness.assertTrue(alert(), "the leading-edge call should pass through and report true")
    harness.assertEqual(runs, 1, "the first call runs immediately")

    harness.assertFalse(alert(), "a call inside the cooldown should be dropped and report false")
    harness.assertFalse(alert(), "still inside the cooldown")
    harness.assertEqual(runs, 1, "dropped calls must not run, and must not be queued for later either")

    -- Wait() outside a coroutine just advances the mock clock, which is what
    -- GetGameTimer (and therefore the cooldown) reads.
    Wait(1000)

    harness.assertTrue(alert(), "the next window should let a call through again")
    harness.assertEqual(runs, 2, "exactly one more run after the window elapsed")
end)

harness.test("throttle reports its remaining cooldown and can be reset", function()
    local alert = QB.timers.throttle(function() end, 1000)

    harness.assertEqual(alert.remaining(), 0, "an unused throttle is ready immediately")

    alert()
    harness.assertTrue(alert.remaining() > 0, "a just-fired throttle should report time remaining")

    alert.reset()
    harness.assertEqual(alert.remaining(), 0, "reset should clear the cooldown")
    harness.assertTrue(alert(), "and let the next call straight through")
end)

harness.test("throttle forwards arguments to the wrapped function", function()
    local seen
    local alert = QB.timers.throttle(function(a, b) seen = { a, b } end, 1000)

    alert("shots_fired", 42)

    harness.assertEqual(seen[1], "shots_fired", "first argument should be forwarded")
    harness.assertEqual(seen[2], 42, "second argument should be forwarded")
end)

-- The `__call` metamethod does not cross the export boundary, so every handle
-- must also expose a plain `.run` field -- funcrefs DO cross. Dropping `.run`
-- is what broke qbpolice's melee detector with "attempt to call a table value".
harness.test("throttle and debounce handles expose a plain .run field", function()
    local throttled = QB.timers.throttle(function() end, 1000)
    local debounced = QB.timers.debounce(function() end, 100)

    harness.assertEqual(type(throttled.run), "function",
        "throttle must expose .run as a plain function, not only __call")
    harness.assertEqual(type(debounced.run), "function",
        "debounce must expose .run as a plain function, not only __call")
end)

harness.test("throttle .run behaves exactly like calling the handle", function()
    local runs = 0
    local seen
    local alert = QB.timers.throttle(function(...) runs = runs + 1; seen = { ... } end, 1000)

    harness.assertTrue(alert.run("melee", 7), ".run should pass the leading-edge call through")
    harness.assertEqual(runs, 1, ".run must actually invoke the wrapped function")
    harness.assertEqual(seen[1], "melee", ".run should forward arguments")
    harness.assertEqual(seen[2], 7, ".run should forward every argument")

    harness.assertFalse(alert.run(), ".run must respect the cooldown like __call does")
    harness.assertEqual(runs, 1, "a dropped .run must not invoke the wrapped function")

    Wait(1000)
    harness.assertTrue(alert.run(), ".run should pass again once the window elapsed")
    harness.assertEqual(runs, 2, "exactly one more run after the window elapsed")
end)

harness.test("debounce .run behaves exactly like calling the handle", function()
    local calls = {}
    local save = QB.timers.debounce(function(value) calls[#calls + 1] = value end, 100)

    save.run("first")
    save.run("second")

    harness.assertTrue(save.isPending(), ".run should schedule a pending run")
    net.step()

    harness.assertEqual(#calls, 1, ".run should collapse rapid calls the same way __call does")
    harness.assertEqual(calls[1], "second", ".run should keep the LAST call's arguments")
end)

harness.report("timers")
