local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

local registeredCommands = {}
_G.RegisterCommand = function(name, handler) registeredCommands[name] = handler end

local invokingResource = nil
_G.GetInvokingResource = function() return invokingResource end

dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "local/resources/server.lua")

local notifyCalls = {}
QB.notify = { send = function(src, payload) table.insert(notifyCalls, { src = src, payload = payload }) end }

dofile(repoRoot .. "modules/commands/server.lua")

local function run(name, source, ...)
    return registeredCommands[name](source, { ... }, name .. " " .. table.concat({ ... }, " "))
end

harness.test("add() registers a chat suggestion", function()
    QB.commands.add("hello", "says hello", nil, false, function() end)

    local suggestion = mocks.lastEntry(net.triggeredClientEvents, "chat:addSuggestion")
    harness.assertTrue(suggestion ~= nil, "a chat:addSuggestion event should have fired")
    harness.assertEqual(suggestion[1], "/hello", "the suggestion should be for /hello")
end)

harness.test("a 'user' permission command runs for anyone, including a real player source", function()
    local ran = false
    QB.commands.add("ping", "", nil, false, function() ran = true end)

    run("ping", 1)

    harness.assertTrue(ran, "a default 'user' command should run for a normal player source")
end)

harness.test("source == 0 (console) bypasses permission checks entirely", function()
    local ran = false
    QB.commands.add("consoleonly", "", nil, false, function() ran = true end, { permission = "admin" })

    run("consoleonly", 0)

    harness.assertTrue(ran, "source 0 (server console) should bypass permission gating")
end)

harness.test("a gated command with no checkPermission fails closed", function()
    local ran = false
    QB.commands.add("gated", "", nil, false, function() ran = true end, { permission = "admin" })

    run("gated", 1)

    harness.assertFalse(ran, "a non-user permission with no checkPermission should deny by default")
    local notified = notifyCalls[#notifyCalls]
    harness.assertEqual(notified.payload.type, "error", "a denial should notify with an error type")
end)

harness.test("a gated command allows when checkPermission returns true", function()
    local ran = false
    QB.commands.add("allowed", "", nil, false, function() ran = true end, {
        permission = "admin",
        checkPermission = function() return true end,
    })

    run("allowed", 1)

    harness.assertTrue(ran, "checkPermission returning true should allow the command")
end)

harness.test("a custom notify callback overrides the default QB.notify.send path", function()
    local customNotified = {}
    QB.commands.add("customdeny", "", nil, false, function() end, {
        permission = "admin",
        notify = function(src, message, type_) table.insert(customNotified, { src = src, message = message, type = type_ }) end,
    })

    notifyCalls = {}
    run("customdeny", 1)

    harness.assertEqual(#notifyCalls, 0, "the default notify path should not have been used")
    harness.assertEqual(#customNotified, 1, "the custom notify callback should have been used instead")
end)

harness.test("argsRequired rejects too few arguments before the handler runs", function()
    local ran = false
    QB.commands.add("needsargs", "", { { name = "target" } }, true, function() ran = true end)

    registeredCommands["needsargs"](1, {}, "needsargs")

    harness.assertFalse(ran, "the handler should not run when a required arg is missing")
end)

harness.test("a handler error is caught, not propagated", function()
    QB.commands.add("broken", "", nil, false, function() error("boom") end)

    local ok = pcall(run, "broken", 1)
    harness.assertTrue(ok, "a handler error should be caught internally, not thrown out of RegisterCommand's handler")
end)

harness.test("list() reports every registered command", function()
    local names = {}
    for _, entry in ipairs(QB.commands.list()) do names[entry.name] = true end

    harness.assertTrue(names["hello"], "hello should be listed")
    harness.assertTrue(names["ping"], "ping should be listed")
end)

harness.test("refresh() re-sends suggestions to one target source", function()
    QB.commands.refresh(42)

    local sawTarget42 = false
    for _, e in ipairs(net.triggeredClientEvents) do
        if e.name == "chat:addSuggestion" and e.target == 42 then sawTarget42 = true end
    end
    harness.assertTrue(sawTarget42, "refresh should re-send suggestions targeted at the given source")
end)

harness.test("remove() drops the command and its chat suggestion", function()
    QB.commands.add("removable", "", nil, false, function() end)

    QB.commands.remove("removable")

    local removed = mocks.lastEntry(net.triggeredClientEvents, "chat:removeSuggestion")
    harness.assertTrue(removed ~= nil, "removing a command should fire chat:removeSuggestion")
    harness.assertEqual(removed[1], "/removable", "the removal should target /removable")

    local stillListed = false
    for _, entry in ipairs(QB.commands.list()) do
        if entry.name == "removable" then stillListed = true end
    end
    harness.assertFalse(stillListed, "a removed command should no longer be listed")
end)

harness.test("resource stop disposes exactly the commands still owned by that resource", function()
    invokingResource = "resource_a"
    QB.commands.add("a_cmd", "", nil, false, function() end)

    invokingResource = "resource_b"
    QB.commands.add("b_cmd", "", nil, false, function() end)

    invokingResource = nil
    net.fire("onResourceStop", "resource_a")

    local removed = mocks.lastEntry(net.triggeredClientEvents, "chat:removeSuggestion")
    harness.assertTrue(removed ~= nil, "stopping resource_a should remove its command's suggestion")
    harness.assertEqual(removed[1], "/a_cmd", "only a_cmd (owned by resource_a) should have been removed")

    local stillHasB = false
    for _, entry in ipairs(QB.commands.list()) do
        if entry.name == "b_cmd" then stillHasB = true end
    end
    harness.assertTrue(stillHasB, "b_cmd, owned by resource_b, must survive resource_a stopping")

    local aGone = true
    for _, entry in ipairs(QB.commands.list()) do
        if entry.name == "a_cmd" then aGone = false end
    end
    harness.assertTrue(aGone, "a_cmd should no longer be listed after its owning resource stopped")
end)

harness.report("commands")
