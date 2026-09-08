local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/loops/shared.lua")
dofile(repoRoot .. "local/resources/client.lua")
dofile(repoRoot .. "local/resources/server.lua")
dofile(repoRoot .. "local/events/shared.lua")
dofile(repoRoot .. "local/events/server.lua")
dofile(repoRoot .. "local/events/client.lua")

local lastNui
local thirdPartyClientPayloads = {}

-- The table-accepting wrapper (capital NUI), matching what QB.nui.send calls.
function _G.SendNUIMessage(msg) lastNui = msg end

-- notify sends through QB.nui.send (not SendNuiMessage directly -- see the
-- root AGENTS.md "UI conventions"), so modules/nui/client.lua needs to be
-- loaded too. RegisterNUICallback/SetNuiFocus are specific to that module and
-- unused by anything notify exercises here, so they're harmless no-ops.
_G.RegisterNUICallback = function() end
_G.SetNuiFocus = function() end
dofile(repoRoot .. "modules/nui/client.lua")

-- A stand-in for whatever a consumer's own third-party notify resource would
-- register on the client for this event.
_G.RegisterNetEvent("qblib:notify:send", function(payload)
    table.insert(thirdPartyClientPayloads, payload)
end)

dofile(repoRoot .. "modules/notify/shared.lua")
dofile(repoRoot .. "modules/notify/client.lua")

-- client.lua's `QB.events.onPush('notify', QB.notify.send)` already captured
-- the client version by value, but QB.notify.send itself is about to be
-- overwritten by server.lua (same module, same table slot) -- so grab a
-- direct reference to the client function before that happens.
local clientNotifySend = QB.notify.send

dofile(repoRoot .. "modules/notify/server.lua")

harness.test("assert accepts a minimal valid payload", function()
    QB.notify.assert({ message = "hello" })
end)

harness.test("assert accepts and forwards icon presentation options", function()
    local resolved = QB.notify.withDefaults({
        message = "hello",
        iconAnimation = "pulse",
        alignIcon = "top",
    })
    harness.assertEqual(resolved.iconAnimation, "pulse", "animation should be preserved")
    harness.assertEqual(resolved.alignIcon, "top", "alignment should be preserved")
    QB.notify.assert(resolved)

    harness.assertThrows(function()
        QB.notify.assert({ message = "bad", iconAnimation = "flash" })
    end, "unknown icon animation should fail")
end)

harness.test("assert rejects a payload with neither title nor message", function()
    harness.assertThrows(function()
        QB.notify.assert({})
    end, "a payload with no title or message should be rejected")
end)

harness.test("assert rejects an out-of-range duration", function()
    harness.assertThrows(function()
        QB.notify.assert({ message = "hi", duration = 999999 })
    end, "a duration over 2 minutes should be rejected")
end)

harness.test("assert accepts every documented type and position", function()
    for _, notifyType in ipairs({ "info", "success", "warning", "error" }) do
        QB.notify.assert({ message = "hi", type = notifyType })
    end

    for _, position in ipairs({ "top-left", "top-center", "top-right", "bottom-left", "bottom-center", "bottom-right" }) do
        QB.notify.assert({ message = "hi", position = position })
    end
end)

harness.test("assert rejects an unknown type or position", function()
    harness.assertThrows(function()
        QB.notify.assert({ message = "hi", type = "catastrophe" })
    end, "an unknown notification type should be rejected")

    harness.assertThrows(function()
        QB.notify.assert({ message = "hi", position = "middle" })
    end, "an unknown notification position should be rejected")
end)

harness.test("assert rejects a non-string title or message", function()
    harness.assertThrows(function()
        QB.notify.assert({ title = { nested = "table" } })
    end, "a table title would crash the NUI renderer, so it must be rejected")

    harness.assertThrows(function()
        QB.notify.assert({ message = 42 })
    end, "a numeric message should be rejected")
end)

harness.test("withDefaults fills in the configured type/position/duration without mutating the caller", function()
    local payload = { message = "hi" }
    local resolved = QB.notify.withDefaults(payload)

    harness.assertEqual(resolved.type, Config.notify.defaultType, "type should fall back to the configured default")
    harness.assertEqual(resolved.position, Config.notify.defaultPosition, "position should fall back to the configured default")
    harness.assertEqual(resolved.duration, Config.notify.defaultDuration, "duration should fall back to the configured default")
    harness.assertEqual(payload.type, nil, "the caller's own table must not be mutated")

    local explicit = QB.notify.withDefaults({ message = "hi", type = "error", position = "bottom-left", duration = 1000 })
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
    harness.assertTrue(lastNui == nil, "the NUI path should be skipped when third-party notify is on")

    Config.third_party_notify = false
end)

harness.test("server send pushes to the client and shows a NUI notification", function()
    lastNui = nil
    QB.notify.send(mocks.SOURCE, { title = "Server said hi" })

    harness.assertTrue(lastNui ~= nil, "server send should reach the client via the events push and show a NUI notification")
    harness.assertEqual(lastNui.data.title, "Server said hi", "the payload should survive the round trip")
end)

harness.test("server sendToAll also reaches the client", function()
    lastNui = nil
    QB.notify.sendToAll({ message = "everyone" })
    harness.assertTrue(lastNui ~= nil, "sendToAll should still reach the mock client")
end)

harness.test("server send uses the third-party client event when configured", function()
    Config.third_party_notify = true
    lastNui = nil
    thirdPartyClientPayloads = {}

    QB.notify.send(mocks.SOURCE, { message = "server third party" })

    harness.assertEqual(#thirdPartyClientPayloads, 1, "the third-party client event should have fired once")
    harness.assertTrue(lastNui == nil, "the NUI path should be skipped when third-party notify is on")

    Config.third_party_notify = false
end)

harness.report("notify")
