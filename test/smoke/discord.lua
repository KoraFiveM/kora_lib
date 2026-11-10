local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

local convars = {}
_G.GetConvar = function(name, default) return convars[name] or default end

local encodedValues = {}
local nextEncoded = 0
local decodedValues = {}
_G.json = {
    encode = function(value)
        nextEncoded = nextEncoded + 1
        local encoded = "encoded:" .. nextEncoded
        encodedValues[encoded] = value
        return encoded
    end,
    decode = function(value)
        if decodedValues[value] == nil then error("invalid JSON") end
        return decodedValues[value]
    end,
}

local httpRequests = {}
local responses = {}
_G.PerformHttpRequest = function(url, callback, method, body, headers)
    httpRequests[#httpRequests + 1] = { url = url, method = method, body = body, headers = headers }
    local response = table.remove(responses, 1) or { status = 204, body = "", headers = {} }
    callback(response.status, response.body, response.headers or {}, response.error)
end

local timers = {}
_G.SetTimeout = function(delay, callback)
    timers[#timers + 1] = { delay = delay, callback = callback }
end

local resourceState = "missing"
_G.GetResourceState = function() return resourceState end
local onlinePlayers = {}
local playerIdentifiers = {}
_G.GetPlayers = function() return onlinePlayers end
_G.GetNumPlayerIdentifiers = function(src) return #(playerIdentifiers[tonumber(src)] or {}) end
_G.GetPlayerIdentifier = function(src, index) return (playerIdentifiers[tonumber(src)] or {})[index + 1] end

dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/util/shared.lua")
dofile(repoRoot .. "modules/discord/server.lua")

local GUILD_ID = "123456789012345678"
local USER_ID = "223456789012345678"
local ROLE_ID = "323456789012345678"
local CHANNEL_ID = "423456789012345678"
local MESSAGE_ID = "523456789012345678"

local function resetHttp()
    httpRequests = {}
    responses = {}
    timers = {}
end

harness.test("createEmbed creates a transport-safe embed without mutating its input", function()
    local options = {
        title = "Audit",
        description = "A thing happened",
        color = "#DC143C",
        timestamp = 0,
        footer = "kora_lib",
        image = "https://example.invalid/image.png",
        fields = { { name = "Player", value = "Jamie", inline = true } },
    }

    local embed = Kora.discord.createEmbed(options)

    harness.assertEqual(embed.color, 0xDC143C, "hex colors should become Discord's integer color")
    harness.assertEqual(embed.timestamp, "1970-01-01T00:00:00Z", "Unix timestamps should become UTC ISO8601")
    harness.assertEqual(embed.footer.text, "kora_lib", "string footers should be expanded")
    harness.assertEqual(embed.image.url, options.image, "string images should be expanded")
    harness.assertTrue(embed.fields ~= options.fields, "the fields array should be copied")
    harness.assertEqual(options.color, "#DC143C", "the source table should remain unchanged")
end)

harness.test("createEmbed rejects malformed colors and more than 25 fields", function()
    harness.assertThrows(function() Kora.discord.createEmbed({ color = "red" }) end,
        "named colors are not valid Discord integer colors")
    harness.assertThrows(function() Kora.discord.createEmbed({ timestamp = math.huge }) end,
        "an infinite Unix timestamp must be rejected before formatting")

    local fields = {}
    for index = 1, 26 do fields[index] = { name = tostring(index), value = "value" } end
    harness.assertThrows(function() Kora.discord.createEmbed({ fields = fields }) end,
        "Discord only allows 25 fields")
    harness.assertThrows(function()
        Kora.discord.createEmbed({ fields = { { name = 'first', value = 'one' }, [3] = { name = 'third', value = 'three' } } })
    end, 'sparse field lists must not silently drop entries')
end)

harness.test("webhooks work without the bot convar and accept a single embed", function()
    convars = {}
    resetHttp()
    local callbackOk
    local embed = Kora.discord.createEmbed({ title = "Ready", color = 123 })

    local queued = Kora.discord.sendWebhook("https://discord.com/api/webhooks/1/token", embed, function(ok)
        callbackOk = ok
    end)

    harness.assertTrue(queued, "the webhook should be queued")
    harness.assertTrue(callbackOk, "a 204 webhook response should be successful")
    harness.assertEqual(#httpRequests, 1, "one webhook HTTP request should be made")
    harness.assertEqual(httpRequests[1].method, "POST", "webhooks should POST")
    local payload = encodedValues[httpRequests[1].body]
    harness.assertEqual(payload.embeds[1].title, "Ready", "a lone embed should be wrapped in embeds")
    harness.assertEqual(httpRequests[1].headers["Authorization"], nil, "webhooks must not receive the bot token")
end)

harness.test("a nil webhook URL uses its convar and missing config fails locally", function()
    convars = { kora_lib_discord_webhook = "https://discord.com/api/webhooks/2/token" }
    resetHttp()
    harness.assertTrue(Kora.discord.sendWebhook(nil, "hello"), "the default webhook should queue")
    harness.assertEqual(httpRequests[1].url, convars.kora_lib_discord_webhook, "the webhook convar should be used")
    harness.assertEqual(encodedValues[httpRequests[1].body].content, "hello", "string messages should become content")

    convars = {}
    resetHttp()
    local callbackOk, callbackResponse
    local queued = Kora.discord.sendWebhook(nil, "hello", function(ok, response)
        callbackOk, callbackResponse = ok, response
    end)
    harness.assertFalse(queued, "a missing default webhook should not queue")
    harness.assertFalse(callbackOk, "missing webhook config should report failure")
    harness.assertEqual(callbackResponse.status, 0, "local configuration failures use status 0")
    harness.assertEqual(#httpRequests, 0, "missing webhook config must not make an HTTP request")
end)

harness.test("the bot client is disabled and inert without its token convar", function()
    convars = { kora_lib_discord_guild_id = GUILD_ID }
    resetHttp()
    local callbackOk, callbackResponse

    harness.assertFalse(Kora.discord.botEnabled(), "botEnabled should reflect the missing token")
    local queued = Kora.discord.fetchGuildRoles(nil, function(ok, response)
        callbackOk, callbackResponse = ok, response
    end)

    harness.assertFalse(queued, "disabled bot helpers should not queue")
    harness.assertFalse(callbackOk, "disabled bot helpers should report failure")
    harness.assertTrue(callbackResponse.error:find("disabled", 1, true) ~= nil,
        "the disabled response should explain the gate")
    local cached, cacheErr = Kora.discord.getRoles(USER_ID)
    harness.assertEqual(cached, nil, "cache lookups should also be disabled without the bot convar")
    harness.assertTrue(cacheErr:find("disabled", 1, true) ~= nil, "the cache lookup should explain its gate")
    harness.assertEqual(#httpRequests, 0, "disabled bot helpers must make no HTTP request")
end)

harness.test("fetchGuildRoles uses API v10, the default guild, and bot authorization", function()
    convars = {
        kora_lib_discord_bot_token = "secret-token",
        kora_lib_discord_guild_id = GUILD_ID,
    }
    resetHttp()
    decodedValues.roles_response = { { id = ROLE_ID, name = "Police" } }
    responses = { { status = 200, body = "roles_response" } }
    local result

    harness.assertTrue(Kora.discord.fetchGuildRoles(nil, function(ok, response)
        harness.assertTrue(ok, "a 200 response should be successful")
        result = response.data
    end), "enabled bot calls should queue")

    harness.assertTrue(Kora.discord.botEnabled(), "botEnabled should reflect the configured token")
    harness.assertEqual(httpRequests[1].url,
        "https://discord.com/api/v10/guilds/" .. GUILD_ID .. "/roles", "fetchGuildRoles should use the guild roles route")
    harness.assertEqual(httpRequests[1].headers.Authorization, "Bot secret-token", "the Bot authorization scheme should be used")
    harness.assertTrue(httpRequests[1].headers["User-Agent"]:find("DiscordBot", 1, true) ~= nil,
        "bot calls should provide Discord's required user agent")
    harness.assertEqual(result[1].name, "Police", "JSON response data should reach the callback")
end)

harness.test("the console-only sync caches guild names and online member roles", function()
    local MOD_ROLE_ID = "623456789012345678"
    convars = {
        kora_lib_discord_bot_token = "secret-token",
        kora_lib_discord_guild_id = GUILD_ID,
    }
    resourceState = "missing"
    onlinePlayers = { "7" }
    playerIdentifiers = { [7] = { "license:abc", "discord:" .. USER_ID } }
    resetHttp()
    decodedValues.sync_roles = {
        { id = ROLE_ID, name = "Police", position = 10, permissions = "8" },
        { id = MOD_ROLE_ID, name = "Moderator", position = 20, permissions = "16" },
    }
    decodedValues.sync_member = { roles = { ROLE_ID } }

    net.commands.kora_lib_discord_sync(1, {}, "kora_lib_discord_sync")
    harness.assertEqual(#httpRequests, 0, "a player source must not be able to run the sync command")

    responses = {
        { status = 200, body = "sync_roles" },
        { status = 200, body = "sync_member" },
    }
    net.commands.kora_lib_discord_sync(0, {}, "kora_lib_discord_sync")

    harness.assertEqual(#httpRequests, 2, "the console sync should fetch the guild and one online member")
    local catalog = Kora.discord.getGuildRoles()
    harness.assertEqual(catalog[1].name, "Moderator", "the role catalog should be ordered highest first")
    harness.assertEqual(Kora.discord.getRole("police").id, ROLE_ID, "role names should resolve case-insensitively")

    local roles = Kora.discord.getRoles(USER_ID)
    harness.assertEqual(#roles, 1, "the member should have one cached role")
    harness.assertEqual(roles[1].name, "Police", "member role IDs should resolve to catalog names")
    harness.assertTrue(Kora.discord.hasRole(USER_ID, "Police"), "hasRole should accept a role name")
    harness.assertTrue(Kora.discord.hasRole(7, ROLE_ID), "hasRole should accept an online server ID and role ID")
    harness.assertTrue(Kora.discord.hasAnyRole(USER_ID, { "Moderator", "Police" }), "hasAnyRole should match one role")
    harness.assertFalse(Kora.discord.hasAllRoles(USER_ID, { "Moderator", "Police" }), "hasAllRoles should require both")
end)

harness.test("sync declares its schema and persists its role directory when kora_sql is available", function()
    convars = {
        kora_lib_discord_bot_token = "secret-token",
        kora_lib_discord_guild_id = GUILD_ID,
    }
    resourceState = "started"
    resetHttp()
    responses = {
        { status = 200, body = "sync_roles" },
        { status = 200, body = "sync_member" },
    }

    local sqlCalls = { schemas = {}, queries = {}, transactions = {} }
    _G.exports = { kora_sql = {} }
    function _G.exports.kora_sql:isReady() return true end
    function _G.exports.kora_sql:ensureTables(specs, callback, resource)
        sqlCalls.schemas[#sqlCalls.schemas + 1] = { resource = resource, specs = specs }
        callback({}, nil)
    end
    function _G.exports.kora_sql:query(sql, params, callback)
        sqlCalls.queries[#sqlCalls.queries + 1] = { sql = sql, params = params }
        callback({}, nil)
    end
    function _G.exports.kora_sql:transaction(statements, _, callback)
        sqlCalls.transactions[#sqlCalls.transactions + 1] = statements
        callback(true, nil)
    end

    local syncOk
    Kora.discord.syncRoles(function(ok) syncOk = ok end)

    harness.assertTrue(syncOk, "the kora_sql-backed sync should complete")
    harness.assertEqual(#sqlCalls.schemas, 1, "the Discord schema should be applied through kora_sql's ensureTables")
    local names = {}
    for _, spec in ipairs(sqlCalls.schemas[1].specs) do names[#names + 1] = spec.name end
    harness.assertEqual(table.concat(names, ","), "kora_lib_discord_roles,kora_lib_discord_members,kora_lib_discord_member_roles",
        "the schema should declare all three tables, parents first")
    harness.assertEqual(#sqlCalls.queries, 3, "startup should load role, member, and assignment caches")
    harness.assertEqual(#sqlCalls.transactions, 2, "the catalog and member snapshot should each persist atomically")
end)

harness.test("giveRole and removeRole accept names and update the authorization cache", function()
    convars = {
        kora_lib_discord_bot_token = "secret-token",
        kora_lib_discord_guild_id = GUILD_ID,
    }
    resetHttp()
    local giveOk, removeOk

    Kora.discord.giveRole(USER_ID, "Moderator", function(ok) giveOk = ok end, "Admin menu grant")
    harness.assertTrue(giveOk, "giveRole should report Discord's successful response")
    harness.assertEqual(httpRequests[1].method, "PUT", "giveRole should add the resolved role")
    harness.assertTrue(Kora.discord.hasRole(USER_ID, "Moderator"), "the granted role should be cached immediately")

    Kora.discord.removeRole(USER_ID, "Police", function(ok) removeOk = ok end, "Admin menu revoke")
    harness.assertTrue(removeOk, "removeRole should report Discord's successful response")
    harness.assertEqual(httpRequests[2].method, "DELETE", "removeRole should remove the resolved role")
    harness.assertFalse(Kora.discord.hasRole(USER_ID, "Police"), "the removed role should leave the cache immediately")
end)

harness.test("member role helpers use the correct methods and preserve string snowflakes", function()
    convars = { kora_lib_discord_bot_token = "secret-token" }
    resetHttp()

    Kora.discord.setMemberRoles(GUILD_ID, USER_ID, { ROLE_ID }, nil, "Role sync / hire")
    local setRequest = httpRequests[#httpRequests]
    harness.assertEqual(setRequest.method, "PATCH", "setMemberRoles should modify the member")
    harness.assertEqual(setRequest.url,
        "https://discord.com/api/v10/guilds/" .. GUILD_ID .. "/members/" .. USER_ID,
        "setMemberRoles should target the guild member")
    harness.assertEqual(encodedValues[setRequest.body].roles[1], ROLE_ID, "role IDs should remain strings")
    harness.assertEqual(setRequest.headers["X-Audit-Log-Reason"], "Role%20sync%20%2F%20hire",
        "audit reasons should be URL encoded")

    Kora.discord.addMemberRole(GUILD_ID, USER_ID, ROLE_ID)
    harness.assertEqual(httpRequests[#httpRequests].method, "PUT", "addMemberRole should PUT the role route")

    Kora.discord.removeMemberRole(GUILD_ID, USER_ID, ROLE_ID)
    harness.assertEqual(httpRequests[#httpRequests].method, "DELETE", "removeMemberRole should DELETE the role route")

    harness.assertThrows(function() Kora.discord.getMember(GUILD_ID, 223456789012345678) end,
        "numeric snowflakes should be rejected before precision can be lost")
end)

harness.test("role, channel, and message helpers map to Discord's REST routes", function()
    convars = { kora_lib_discord_bot_token = "secret-token" }
    resetHttp()

    Kora.discord.createRole(GUILD_ID, { name = "Mechanic" })
    harness.assertEqual(httpRequests[#httpRequests].url,
        "https://discord.com/api/v10/guilds/" .. GUILD_ID .. "/roles", "createRole should target guild roles")

    Kora.discord.createChannel(GUILD_ID, { name = "support", type = 0 })
    harness.assertEqual(httpRequests[#httpRequests].method, "POST", "createChannel should POST")
    harness.assertEqual(httpRequests[#httpRequests].url,
        "https://discord.com/api/v10/guilds/" .. GUILD_ID .. "/channels", "createChannel should target guild channels")

    Kora.discord.updateChannel(CHANNEL_ID, { topic = "Player support" })
    harness.assertEqual(httpRequests[#httpRequests].method, "PATCH", "updateChannel should PATCH")

    Kora.discord.sendMessage(CHANNEL_ID, "hello")
    harness.assertEqual(httpRequests[#httpRequests].url,
        "https://discord.com/api/v10/channels/" .. CHANNEL_ID .. "/messages", "sendMessage should target channel messages")
    harness.assertEqual(encodedValues[httpRequests[#httpRequests].body].content, "hello",
        "bot string messages should become content payloads")

    Kora.discord.editMessage(CHANNEL_ID, MESSAGE_ID, { content = "edited" })
    harness.assertEqual(httpRequests[#httpRequests].method, "PATCH", "editMessage should PATCH")

    Kora.discord.deleteMessage(CHANNEL_ID, MESSAGE_ID)
    harness.assertEqual(httpRequests[#httpRequests].method, "DELETE", "deleteMessage should DELETE")
end)

harness.test("botRequest refuses absolute routes so credentials stay on Discord", function()
    convars = { kora_lib_discord_bot_token = "secret-token" }
    resetHttp()
    harness.assertThrows(function()
        Kora.discord.botRequest("GET", "https://example.invalid/steal-token")
    end, "an absolute bot route should be rejected")
    harness.assertEqual(#httpRequests, 0, "a rejected route must not make a request")
end)

harness.test("a Discord 429 is retried once after retry_after", function()
    convars = { kora_lib_discord_bot_token = "secret-token" }
    resetHttp()
    decodedValues.rate_limited = { message = "rate limited", retry_after = 0.25 }
    decodedValues.after_retry = { id = CHANNEL_ID }
    responses = {
        { status = 429, body = "rate_limited" },
        { status = 200, body = "after_retry" },
    }
    local callbackCount, callbackOk = 0, nil

    Kora.discord.getChannel(CHANNEL_ID, function(ok)
        callbackCount, callbackOk = callbackCount + 1, ok
    end)

    harness.assertEqual(#timers, 1, "the 429 should schedule one retry")
    harness.assertEqual(timers[1].delay, 250, "retry_after seconds should become milliseconds")
    harness.assertEqual(callbackCount, 0, "the first 429 should not complete the request")
    timers[1].callback()
    harness.assertEqual(#httpRequests, 2, "the timer should repeat the request once")
    harness.assertEqual(callbackCount, 1, "only the final result should call back")
    harness.assertTrue(callbackOk, "a successful retry should report success")
end)

harness.test("a Discord 429 with a non-finite retry delay returns normally", function()
    convars = { kora_lib_discord_bot_token = "secret-token" }
    resetHttp()
    decodedValues.invalid_rate_limit = { message = "rate limited", retry_after = math.huge }
    responses = { { status = 429, body = "invalid_rate_limit" } }
    local callbackOk, callbackResponse

    Kora.discord.getChannel(CHANNEL_ID, function(ok, response)
        callbackOk, callbackResponse = ok, response
    end)

    harness.assertEqual(#timers, 0, "a non-finite retry delay must not schedule a timer")
    harness.assertFalse(callbackOk, "the original rate limit should be returned")
    harness.assertEqual(callbackResponse.status, 429, "the rate-limit status should be preserved")
end)

harness.test("exported callback references work for webhook and bot APIs", function()
    convars = { kora_lib_discord_bot_token = "test-token", kora_lib_discord_guild_id = GUILD_ID }
    resetHttp()
    local calls = 0
    local callback = setmetatable({ __cfx_functionReference = 'test:callback' }, {
        __call = function(_, ok)
            harness.assertTrue(ok)
            calls = calls + 1
        end,
    })
    Kora.discord.sendWebhook('https://example.invalid/webhook', 'test', callback)
    Kora.discord.botRequest('GET', '/users/@me', nil, callback)
    Kora.discord.getGuild(callback)
    Kora.discord.fetchGuildRoles(callback)
    Kora.discord.getChannels(callback)
    harness.assertEqual(calls, 5, 'full and shorthand APIs must invoke callable-table callbacks')
    harness.assertThrows(function() Kora.discord.sendWebhook(nil, 'test', {}) end)
end)

harness.test("deprecated kora_lib_ convars and sync command remain supported as fallbacks", function()
    convars = { kora_lib_discord_bot_token = "legacy-token", kora_lib_discord_webhook = "https://discord.com/api/webhooks/3/token" }
    resetHttp()
    harness.assertTrue(Kora.discord.botEnabled(), "the legacy bot token convar should still enable the bot")
    harness.assertTrue(Kora.discord.sendWebhook(nil, "hello"), "the legacy webhook convar should queue")
    harness.assertEqual(httpRequests[1].url, convars.kora_lib_discord_webhook, "the legacy webhook URL should be used")
    harness.assertTrue(net.commands.kora_lib_discord_sync ~= nil, "the deprecated console command should stay registered")

    convars = { kora_lib_discord_webhook = "https://discord.com/api/webhooks/4/token", kora_lib_discord_webhook = "https://discord.com/api/webhooks/3/token" }
    resetHttp()
    Kora.discord.sendWebhook(nil, "hello")
    harness.assertEqual(httpRequests[1].url, convars.kora_lib_discord_webhook, "the kora_lib_ convar wins over the legacy name")
end)

harness.report("discord")
