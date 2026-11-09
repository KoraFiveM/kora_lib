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
dofile(repoRoot .. "modules/util/shared.lua")
dofile(repoRoot .. "modules/logging/server.lua")

harness.test("event() records into getStats' counts and ringSize", function()
    Kora.logging.event("money", 1, { amount = 100 })
    Kora.logging.event("money", 1, { amount = 50 })
    Kora.logging.event("job", 1, {})

    local stats = Kora.logging.getStats()
    harness.assertEqual(stats.counts.money, 2, "two money events should be counted")
    harness.assertEqual(stats.counts.job, 1, "one job event should be counted")
    harness.assertTrue(stats.ringSize >= 3, "ring size should reflect the events recorded so far")
end)

harness.test("getStats returns counters that cannot mutate logger state", function()
    local stats = Kora.logging.getStats()
    local expected = stats.counts.money
    stats.counts.money = 0
    harness.assertEqual(Kora.logging.getStats().counts.money, expected,
        "mutating a stats snapshot must not alter the live counter")
end)

harness.test("event() does not call the webhook when no webhook convar is set", function()
    convars = {}
    httpRequests = {}

    Kora.logging.event("admin", 0, {})

    harness.assertEqual(#httpRequests, 0, "no webhook URL configured means no HTTP request")
end)

harness.test("event() rejects malformed data before recording or encoding", function()
    local before = Kora.logging.getStats().ringSize
    harness.assertThrows(function() Kora.logging.event("", 0, {}) end)
    harness.assertThrows(function() Kora.logging.event("admin", -1, {}) end)
    harness.assertThrows(function() Kora.logging.event("admin", 0, false) end)
    harness.assertEqual(Kora.logging.getStats().ringSize, before,
        "invalid events must not enter the ring buffer")
end)

harness.test("event() keeps the local record when webhook encoding fails", function()
    convars = { kora_lib_log_webhook = "https://example.invalid/webhook" }
    httpRequests = {}
    local before = Kora.logging.getStats().ringSize
    local encode = json.encode
    json.encode = function(value)
        if value.fail then error("cannot encode") end
        return encode(value)
    end

    Kora.logging.event("encode_failure", 0, { fail = true })
    json.encode = encode

    harness.assertEqual(Kora.logging.getStats().ringSize, before + 1,
        "a webhook failure must not discard the local event")
    harness.assertEqual(#httpRequests, 0, "an unencodable payload must not start an HTTP request")
end)

harness.test("event() calls the webhook when kora_lib_log_webhook is set", function()
    convars = { kora_lib_log_webhook = "https://example.invalid/webhook" }
    httpRequests = {}

    Kora.logging.event("admin", 5, { action = "kick" })

    harness.assertEqual(#httpRequests, 1, "one webhook request should have fired")
    harness.assertEqual(httpRequests[1].url, "https://example.invalid/webhook", "the configured URL should be used")
    harness.assertEqual(httpRequests[1].method, "POST", "the webhook request should be a POST")
end)

harness.test("event() webhook payload disables mention parsing", function()
    convars = { kora_lib_log_webhook = "https://example.invalid/webhook" }
    httpRequests = {}

    Kora.logging.event("chat", 5, { text = "@everyone" })

    harness.assertTrue(httpRequests[1].body:find("allowed_mentions", 1, true) ~= nil,
        "the webhook payload must carry an allowed_mentions block")
end)

harness.test("event() falls back to the legacy qbcore_log_webhook convar", function()
    convars = { qbcore_log_webhook = "https://legacy.invalid/webhook" }
    httpRequests = {}

    Kora.logging.event("admin", 0, {})

    harness.assertEqual(#httpRequests, 1, "the legacy convar should still trigger the webhook")
    harness.assertEqual(httpRequests[1].url, "https://legacy.invalid/webhook", "the legacy convar's URL should be used")
end)

harness.test("event() attributes the webhook username to the invoking resource", function()
    convars = { kora_lib_log_webhook = "https://example.invalid/webhook" }
    httpRequests = {}
    invokingResource = "some-other-resource"

    Kora.logging.event("admin", 0, {})

    harness.assertTrue(httpRequests[1].body:find("some%-other%-resource", 1, false) ~= nil,
        "the webhook body should attribute the event to the invoking resource")

    invokingResource = nil
end)

harness.test('event caps only oversized webhook content', function()
    convars = { kora_lib_log_webhook = 'https://example.invalid/webhook' }
    local encode, mirroredContent = json.encode, nil
    json.encode = function(value)
        if value.content then mirroredContent = value.content end
        return encode(value)
    end

    Kora.logging.event('large', 0, { payload = string.rep('x', 3000) })
    json.encode = encode

    harness.assertEqual(#mirroredContent, 2000)
    harness.assertEqual(mirroredContent:sub(-3), '...')
end)

harness.test("event() prefers kora_lib_log_webhook, then qblib_log_webhook, then qbcore_log_webhook", function()
    convars = { qblib_log_webhook = "https://old-name.invalid/webhook", qbcore_log_webhook = "https://legacy.invalid/webhook" }
    httpRequests = {}
    Kora.logging.event("admin", 0, {})
    harness.assertEqual(httpRequests[1].url, "https://old-name.invalid/webhook", "the qblib_ name outranks qbcore_")

    convars.kora_lib_log_webhook = "https://example.invalid/webhook"
    httpRequests = {}
    Kora.logging.event("admin", 0, {})
    harness.assertEqual(httpRequests[1].url, "https://example.invalid/webhook", "the kora_lib_ name wins")
end)

harness.report("logging")
