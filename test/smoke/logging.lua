local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

mocks.install()

local convars = {}
_G.GetConvar = function(name, default) return convars[name] or default end

local httpRequests = {}
_G.PerformHttpRequest = function(url, cb, method, body, headers)
    table.insert(httpRequests, { url = url, method = method, body = body, headers = headers })
    cb(200, "", {})
end

local invokingResource = nil
_G.GetInvokingResource = function() return invokingResource end

_G.json = {
    encode = function(v)
        -- Not a real JSON encoder -- just deterministic enough to assert on
        -- for this test's simple flat tables.
        if type(v) ~= "table" then return tostring(v) end
        local parts = {}
        for k, val in pairs(v) do
            table.insert(parts, tostring(k) .. "=" .. tostring(val))
        end
        table.sort(parts)
        return "{" .. table.concat(parts, ",") .. "}"
    end,
}

dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/logging/server.lua")

harness.test("event() records into getStats' counts and ringSize", function()
    QB.logging.event("money", 1, { amount = 100 })
    QB.logging.event("money", 1, { amount = 50 })
    QB.logging.event("job", 1, {})

    local stats = QB.logging.getStats()
    harness.assertEqual(stats.counts.money, 2, "two money events should be counted")
    harness.assertEqual(stats.counts.job, 1, "one job event should be counted")
    harness.assertTrue(stats.ringSize >= 3, "ring size should reflect the events recorded so far")
end)

harness.test("event() does not call the webhook when no webhook convar is set", function()
    convars = {}
    httpRequests = {}

    QB.logging.event("admin", 0, {})

    harness.assertEqual(#httpRequests, 0, "no webhook URL configured means no HTTP request")
end)

harness.test("event() calls the webhook when qblib_log_webhook is set", function()
    convars = { qblib_log_webhook = "https://example.invalid/webhook" }
    httpRequests = {}

    QB.logging.event("admin", 5, { action = "kick" })

    harness.assertEqual(#httpRequests, 1, "one webhook request should have fired")
    harness.assertEqual(httpRequests[1].url, "https://example.invalid/webhook", "the configured URL should be used")
    harness.assertEqual(httpRequests[1].method, "POST", "the webhook request should be a POST")
end)

harness.test("event() falls back to the legacy qbcore_log_webhook convar", function()
    convars = { qbcore_log_webhook = "https://legacy.invalid/webhook" }
    httpRequests = {}

    QB.logging.event("admin", 0, {})

    harness.assertEqual(#httpRequests, 1, "the legacy convar should still trigger the webhook")
    harness.assertEqual(httpRequests[1].url, "https://legacy.invalid/webhook", "the legacy convar's URL should be used")
end)

harness.test("event() attributes the webhook username to the invoking resource", function()
    convars = { qblib_log_webhook = "https://example.invalid/webhook" }
    httpRequests = {}
    invokingResource = "some-other-resource"

    QB.logging.event("admin", 0, {})

    harness.assertTrue(httpRequests[1].body:find("some%-other%-resource", 1, false) ~= nil,
        "the webhook body should attribute the event to the invoking resource")

    invokingResource = nil
end)

harness.report("logging")
