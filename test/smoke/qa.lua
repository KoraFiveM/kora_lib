local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

local invokingResource = nil
_G.GetInvokingResource = function() return invokingResource end

dofile(repoRoot .. "build/initiate.lua")

-- Stand-ins for the modules qa wraps; they record what reached them.
local nuiSent, appsOpened, menusOpened = {}, {}, {}
Kora.nui.send = function(action, data) nuiSent[#nuiSent + 1] = { action = action, data = data } end
Kora.nui.openApp = function(id) appsOpened[#appsOpened + 1] = id; return { closed = true } end
Kora.nui.openMenu = function(_, title) menusOpened[#menusOpened + 1] = title; return 'menu-result' end

local registeredCallbacks, registeredCommands = {}, {}
Kora.callback.register = function(name, handler) registeredCallbacks[name] = handler end
Kora.commands.add = function(name, _, _, _, handler) registeredCommands[name] = handler end

dofile(repoRoot .. "modules/qa/shared.lua")
local internal = Kora.compat.qa

-- Client realm first; capture its functions before the server file replaces them.
dofile(repoRoot .. "modules/qa/client.lua")
local client = {
    mark = Kora.qa.mark, active = Kora.qa.active, setActive = Kora.qa.setActive,
    send = Kora.nui.send, openApp = Kora.nui.openApp, openMenu = Kora.nui.openMenu,
}
dofile(repoRoot .. "modules/qa/server.lua")
local server = { mark = Kora.qa.mark, active = Kora.qa.active, setActive = Kora.qa.setActive }

local function countEvents(name)
    local n = 0
    for _, entry in ipairs(net.triggeredServerEvents) do
        if entry.name == name then n = n + 1 end
    end
    return n
end

harness.test("inactive client: marks and wrapped calls are pass-through no-ops", function()
    client.mark("fishing:caught", { fish = "cod" })
    client.send("notify", { message = "hello" })
    harness.assertEqual(countEvents("kora_lib:qa:client"), 0, "nothing is forwarded while inactive")
    harness.assertEqual(#nuiSent, 1, "the wrapped send still reaches the original")
    harness.assertEqual(client.openMenu({}, "Shop"), "menu-result", "wrapped calls keep their return value")
    harness.assertFalse(client.active(), "no run yet")
end)

harness.test("server mark is a no-op without handlers and active players", function()
    server.mark("anything", { a = 1 })
    server.mark("bad name!!", nil) -- not validated while inactive: free in production
end)

harness.test("only the runner may toggle run state", function()
    invokingResource = "some_other_resource"
    harness.assertThrows(function() client.setActive(true) end, "foreign client setActive must raise")
    harness.assertThrows(function() server.setActive(1, true) end, "foreign server setActive must raise")
    invokingResource = "kora_qa"
    harness.assertTrue(client.setActive(true), "kora_qa may activate")
    harness.assertTrue(client.active(), "client is active")
    invokingResource = nil
end)

harness.test("active client forwards marks, notifications and app opens", function()
    local before = countEvents("kora_lib:qa:client")
    client.mark("fishing:caught", { fish = "cod", fn = function() end })
    client.send("notify", { title = "Shop", message = "Not enough money", type = "error" })
    client.send("other", {})
    client.openApp("kora_shop:main")
    harness.assertEqual(countEvents("kora_lib:qa:client") - before, 3, "mark + notify + app")
    local last = mocks.lastEntry(net.triggeredServerEvents, "kora_lib:qa:client")[1]
    harness.assertEqual(last.type, "nui", "last event is the app open")
    harness.assertEqual(last.name, "kora_shop:main", "app id is the event name")
    harness.assertEqual(appsOpened[#appsOpened], "kora_shop:main", "the original openApp still ran")
    harness.assertThrows(function() client.mark("", nil) end, "invalid names raise while active")
    local beforeUi = countEvents("kora_lib:qa:client")
    client.send("progressStart", { label = "Fishing", duration = 5000 })
    client.send("progressCancel")
    client.send("textui:set", { text = "[E] Open", key = "E" })
    client.send("textui:set", false)
    harness.assertEqual(countEvents("kora_lib:qa:client") - beforeUi, 3, "progress start/cancel + text UI (hide ignored)")
    harness.assertEqual(mocks.lastEntry(net.triggeredServerEvents, "kora_lib:qa:client")[1].type, "textui", "text UI event type")
end)

harness.test("server accepts client events only from active players", function()
    local seen = {}
    -- Both realms share one handler table in this mocked process; client-side
    -- dispatch calls fn(event), so skip those here.
    local id = Kora.qa.onEvent(function(src, event)
        if type(src) == "table" then return end
        seen[#seen + 1] = { src = src, event = event }
    end)
    harness.assertTrue(type(id) == "number", "onEvent returns an id")

    -- mocks.SOURCE (1) is not active on the server yet: the forward is dropped.
    client.mark("one", nil)
    harness.assertEqual(#seen, 0, "inactive player's events are ignored")

    invokingResource = "kora_qa"
    server.setActive(1, true)
    invokingResource = nil
    harness.assertTrue(server.active(1) and server.active(), "player 1 is active")

    client.mark("two", { n = 2 })
    harness.assertEqual(#seen, 1, "active player's mark reaches the handler")
    harness.assertEqual(seen[1].src, 1, "with the player's source")
    harness.assertEqual(seen[1].event.side, "client", "tagged as a client event")
    harness.assertEqual(seen[1].event.data.n, 2, "data survives sanitising")

    -- Malformed payloads straight at the net event are dropped.
    net.netHandlers["kora_lib:qa:client"][1]({ type = "nope" })
    net.netHandlers["kora_lib:qa:client"][1]("string")
    harness.assertEqual(#seen, 1, "malformed client events are dropped")
    Kora.qa.offEvent(id)
end)

harness.test("server marks, callbacks and commands reach the handler for active players", function()
    local seen = {}
    -- Both realms share one handler table in this mocked process; client-side
    -- dispatch calls fn(event), so skip those here.
    local id = Kora.qa.onEvent(function(src, event)
        if type(src) == "table" then return end
        seen[#seen + 1] = { src = src, event = event }
    end)

    server.mark("shop:purchase", { item = "water" }, 1)
    server.mark("shop:purchase", { item = "water" }, 2) -- player 2 is not testing
    server.mark("global:tick")
    harness.assertEqual(#seen, 2, "targeted mark for 1 + broadcast")
    harness.assertEqual(seen[2].src, nil, "broadcast mark has no source")

    Kora.callback.register("shop:buy", function(src, item) return { ok = false, error = "no money" }, item end)
    local result, second = registeredCallbacks["shop:buy"](1, "water")
    harness.assertEqual(result.ok, false, "handler result returned unchanged")
    harness.assertEqual(second, "water", "every return value preserved")
    harness.assertEqual(seen[3].event.type, "callback", "callback recorded")
    harness.assertEqual(seen[3].event.data.okField, false, "ok field summarised")
    registeredCallbacks["shop:buy"](2, "water")
    harness.assertEqual(#seen, 3, "inactive player's callback not recorded")

    local ran = 0
    Kora.commands.add("id", "show id", nil, false, function() ran = ran + 1 end)
    registeredCommands["id"](1, {}, "id")
    registeredCommands["id"](2, {}, "id")
    harness.assertEqual(ran, 2, "command handler always runs")
    harness.assertEqual(seen[4].event.type, "command", "command recorded for the active player only")
    harness.assertEqual(#seen, 4, "one command event")
    Kora.qa.offEvent(id)
end)

harness.test("sanitize bounds data", function()
    local big = {}
    for i = 1, 100 do big[i] = i end
    local deep = { a = { b = { c = { d = { e = 1 } } } } }
    local out = internal.sanitize({ big = big, deep = deep, s = string.rep("x", 2000), f = function() end, n = 0 / 0 })
    local count = 0
    for _ in pairs(out.big) do count = count + 1 end
    harness.assertEqual(count, 32, "tables keep at most 32 keys")
    harness.assertEqual(out.deep.a.b.c, nil, "depth is capped")
    harness.assertEqual(#out.s, 512, "strings are capped")
    harness.assertEqual(out.f, nil, "functions dropped")
    harness.assertEqual(out.n, nil, "NaN dropped")
end)

harness.test("runner stop clears run state and its handlers", function()
    local id = Kora.qa.onEvent(function() end)
    invokingResource = "kora_qa"
    local id2 = Kora.qa.onEvent(function() end)
    invokingResource = nil
    local before = internal.handlerCount
    net.fire("onResourceStop", "kora_qa")
    harness.assertEqual(internal.handlerCount, before - 1, "kora_qa's handler removed")
    harness.assertFalse(server.active(1), "server run state cleared")
    net.fire("onClientResourceStop", "kora_qa")
    harness.assertFalse(client.active(), "client run state cleared")
    Kora.qa.offEvent(id)
    harness.assertFalse(Kora.qa.offEvent(id2), "already removed")
end)

harness.report("qa")
