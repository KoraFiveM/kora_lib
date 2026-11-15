local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/logging/shared.lua")
dofile(repoRoot .. "modules/util/shared.lua")
dofile(repoRoot .. "modules/loops/shared.lua")
dofile(repoRoot .. "local/resources/client.lua")
dofile(repoRoot .. "local/resources/server.lua")
dofile(repoRoot .. "local/events/shared.lua")
dofile(repoRoot .. "local/events/server.lua")
dofile(repoRoot .. "local/events/client.lua")

local lastNui
local thirdPartyClientPayloads = {}

function _G.SendNUIMessage(msg) lastNui = msg end

_G.RegisterNUICallback = function() end
_G.SetNuiFocus = function() end
dofile(repoRoot .. "modules/nui/client.lua")

_G.RegisterNetEvent("kora_lib:notify:send", function(payload)
    table.insert(thirdPartyClientPayloads, payload)
end)
local legacyClientPayloads = {}
_G.RegisterNetEvent("kora_lib:notify:send", function(payload)
    table.insert(legacyClientPayloads, payload)
end)

dofile(repoRoot .. "modules/notify/shared.lua")
dofile(repoRoot .. "modules/notify/client.lua")

local clientNotifySend = Kora.notify.send

dofile(repoRoot .. "modules/notify/server.lua")

harness.test("assert accepts a minimal valid payload", function()
    Kora.notify.assert({ message = "hello" })
end)

harness.test("assert accepts and forwards icon presentation options", function()
    local resolved = Kora.notify.withDefaults({
        message = "hello",
        iconAnimation = "pulse",
        alignIcon = "top",
    })
    harness.assertEqual(resolved.iconAnimation, "pulse", "animation should be preserved")
    harness.assertEqual(resolved.alignIcon, "top", "alignment should be preserved")
    Kora.notify.assert(resolved)

    harness.assertThrows(function()
        Kora.notify.assert({ message = "bad", iconAnimation = "flash" })
    end, "unknown icon animation should fail")
end)

harness.test("assert rejects a payload with neither title nor message", function()
    harness.assertThrows(function()
        Kora.notify.assert({})
    end, "a payload with no title or message should be rejected")
end)

harness.test("assert rejects an out-of-range duration", function()
    harness.assertThrows(function()
        Kora.notify.assert({ message = "hi", duration = 999999 })
    end, "a duration over 2 minutes should be rejected")
end)

harness.test("assert rejects non-finite numeric IDs", function()
    for _, id in ipairs({ math.huge, -math.huge, 0 / 0 }) do
        harness.assertThrows(function()
            Kora.notify.assert({ message = "hi", id = id })
        end, "numeric toast IDs must be finite")
    end
end)

harness.test("assert rejects fractional and non-finite durations", function()
    for _, duration in ipairs({ 1.5, math.huge, -math.huge, 0 / 0 }) do
        harness.assertThrows(function()
            Kora.notify.assert({ message = "hi", duration = duration })
        end, "duration must be a finite integer")
    end
end)

harness.test("assert rejects false defaults instead of silently replacing them", function()
    for _, payload in ipairs({
        { message = "hi", duration = false },
        { message = "hi", type = false },
        { message = "hi", position = false },
    }) do
        harness.assertThrows(function()
            Kora.notify.assert(payload)
        end)
    end
end)

harness.test("assert accepts every documented type and position", function()
    for _, notifyType in ipairs({ "info", "success", "warning", "error" }) do
        Kora.notify.assert({ message = "hi", type = notifyType })
    end

    for _, position in ipairs({
        "top-left", "top-center", "top-right", "bottom-left", "bottom-center",
        "bottom-right", "center-left", "center-right", "top", "bottom",
    }) do
        Kora.notify.assert({ message = "hi", position = position })
    end
end)

harness.test("assert accepts type aliases and normalize resolves them", function()
    Kora.notify.assert({ message = "hi", type = "inform" })
    Kora.notify.assert({ message = "hi", type = "warn" })

    local original = { message = "hi", type = "inform", duration = 1000 }
    local normalized = Kora.notify.normalize(original)
    harness.assertEqual(normalized.type, "info")
    harness.assertEqual(normalized.message, "hi")
    harness.assertEqual(normalized.duration, 1000)
    harness.assertEqual(original.type, "inform", "the caller's payload must not be mutated")
    harness.assertEqual(Kora.notify.normalize({ message = "hi", type = "warn" }).type, "warning")

    local canonical = { message = "hi", type = "success" }
    harness.assertEqual(Kora.notify.normalize(canonical), canonical, "canonical types pass through untouched")
    harness.assertEqual(Kora.notify.normalize({ message = "hi" }).type, nil)
    harness.assertEqual(Kora.notify.withDefaults({ message = "hi", type = "inform" }).type, "info")
end)

harness.test("aliases do not weaken validation of unknown types", function()
    harness.assertThrows(function()
        Kora.notify.assert(Kora.notify.normalize({ message = "hi", type = "catastrophe" }))
    end)
    harness.assertThrows(function()
        Kora.notify.assert(Kora.notify.normalize({ message = "hi", type = false }))
    end)
end)

harness.test("assert rejects an unknown type or position", function()
    harness.assertThrows(function()
        Kora.notify.assert({ message = "hi", type = "catastrophe" })
    end, "an unknown notification type should be rejected")

    harness.assertThrows(function()
        Kora.notify.assert({ message = "hi", position = "middle" })
    end, "an unknown notification position should be rejected")
end)

harness.test("assert rejects a non-string title or message", function()
    harness.assertThrows(function()
        Kora.notify.assert({ title = { nested = "table" } })
    end, "a table title would crash the NUI renderer, so it must be rejected")

    harness.assertThrows(function()
        Kora.notify.assert({ message = 42 })
    end, "a numeric message should be rejected")
end)

harness.test("withDefaults fills in the configured type/position/duration without mutating the caller", function()
    local payload = { message = "hi" }
    local resolved = Kora.notify.withDefaults(payload)

    harness.assertEqual(resolved.type, Config.notify.defaultType, "type should fall back to the configured default")
    harness.assertEqual(resolved.position, Config.notify.defaultPosition, "position should fall back to the configured default")
    harness.assertEqual(resolved.duration, Config.notify.defaultDuration, "duration should fall back to the configured default")
    harness.assertEqual(payload.type, nil, "the caller's own table must not be mutated")

    local explicit = Kora.notify.withDefaults({ message = "hi", type = "error", position = "bottom-left", duration = 1000 })
    harness.assertEqual(explicit.type, "error", "an explicit type should win over the default")
    harness.assertEqual(explicit.position, "bottom-left", "an explicit position should win over the default")
    harness.assertEqual(explicit.duration, 1000, "an explicit duration should win over the default")
end)

harness.test("client send shows a NUI notification by default", function()
    lastNui = nil
    clientNotifySend({ title = "Hi", message = "there" })

    harness.assertTrue(lastNui ~= nil, "SendNuiMessage should have been called")
    harness.assertEqual(lastNui.action, "notify", "the NUI message should be a notify action")
    harness.assertEqual(lastNui.data.title, "Hi", "the NUI payload should carry the notification through")
end)

harness.test("client send resolves defaults before handing the payload to the NUI", function()
    lastNui = nil
    clientNotifySend({ message = "resolved?" })

    harness.assertEqual(lastNui.data.type, Config.notify.defaultType, "the NUI should receive a resolved type")
    harness.assertEqual(lastNui.data.position, Config.notify.defaultPosition, "the NUI should receive a resolved position")
    harness.assertEqual(lastNui.data.duration, Config.notify.defaultDuration, "the NUI should receive a resolved duration")
end)

harness.test("client send swallows a malformed payload instead of throwing", function()
    lastNui = nil
    clientNotifySend({})
    harness.assertTrue(lastNui == nil, "a malformed payload should never reach the NUI")
end)

harness.test("client send routes through the third-party hook when configured", function()
    Config.third_party_notify = true
    thirdPartyClientPayloads = {}
    lastNui = nil

    clientNotifySend({ message = "via third party" })

    harness.assertEqual(#thirdPartyClientPayloads, 1, "the third-party client hook should have fired once")
    harness.assertEqual(#legacyClientPayloads, 1, "the deprecated kora_lib:notify:send alias should fire too")
    harness.assertTrue(lastNui == nil, "the NUI path should be skipped when third-party notify is on")

    Config.third_party_notify = false
end)

harness.test("server send pushes to the client and shows a NUI notification", function()
    lastNui = nil
    Kora.notify.send(mocks.SOURCE, { title = "Server said hi" })

    harness.assertTrue(lastNui ~= nil, "server send should reach the client via the events push and show a NUI notification")
    harness.assertEqual(lastNui.data.title, "Server said hi", "the payload should survive the round trip")
end)

harness.test("server sendToAll also reaches the client", function()
    lastNui = nil
    Kora.notify.sendToAll({ message = "everyone" })
    harness.assertTrue(lastNui ~= nil, "sendToAll should still reach the mock client")
end)

harness.test("server send drops malformed recipients before either dispatch route", function()
    lastNui = nil
    thirdPartyClientPayloads = {}
    Config.third_party_notify = false
    Kora.notify.send(1.5, { message = "invalid recipient" })
    harness.assertEqual(lastNui, nil, "the kora_lib push route must not receive an invalid target")

    Config.third_party_notify = true
    Kora.notify.send(1.5, { message = "invalid recipient" })
    harness.assertEqual(#thirdPartyClientPayloads, 0, "the third-party route must not receive an invalid target")
    Config.third_party_notify = false
end)

harness.test("server send uses the third-party client event when configured", function()
    Config.third_party_notify = true
    lastNui = nil
    thirdPartyClientPayloads = {}

    Kora.notify.send(mocks.SOURCE, { message = "server third party" })

    harness.assertEqual(#thirdPartyClientPayloads, 1, "the third-party client event should have fired once")
    harness.assertTrue(lastNui == nil, "the NUI path should be skipped when third-party notify is on")

    Config.third_party_notify = false
end)

harness.report("notify")
