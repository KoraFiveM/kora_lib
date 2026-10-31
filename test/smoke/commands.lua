local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

local registeredCommands = {}
_G.RegisterCommand = function(name, handler) registeredCommands[name] = handler end

_G.GetPlayers = function() return { '1', '2' } end

local invokingResource = nil
_G.GetInvokingResource = function() return invokingResource end

dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/util/shared.lua")
dofile(repoRoot .. "local/resources/server.lua")

local notifyCalls = {}
Kora.notify = { send = function(src, payload) table.insert(notifyCalls, { src = src, payload = payload }) end }

dofile(repoRoot .. "modules/commands/server.lua")

local function run(name, source, ...)
    return registeredCommands[name](source, { ... }, name .. " " .. table.concat({ ... }, " "))
end

harness.test("add() registers a chat suggestion", function()
    Kora.commands.add("hello", "says hello", nil, false, function() end)

    local suggestion = mocks.lastEntry(net.triggeredClientEvents, "chat:addSuggestion")
    harness.assertTrue(suggestion ~= nil, "a chat:addSuggestion event should have fired")
    harness.assertEqual(suggestion[1], "/hello", "the suggestion should be for /hello")
end)

harness.test("add rejects malformed registrations before publishing a command", function()
    local suggestions = #net.triggeredClientEvents
    local invalid = {
        function() Kora.commands.add('', '', nil, false, function() end) end,
        function() Kora.commands.add('bad name', '', nil, false, function() end) end,
        function() Kora.commands.add('badhelp', false, nil, false, function() end) end,
        function() Kora.commands.add('badargs', '', false, false, function() end) end,
        function() Kora.commands.add('badargentry', '', { false }, false, function() end) end,
        function() Kora.commands.add('badargname', '', { { name = false } }, false, function() end) end,
        function() Kora.commands.add('badarghelp', '', { { name = 'target', help = false } }, false, function() end) end,
        function() Kora.commands.add('sparseargs', '', { [2] = { name = 'target' } }, false, function() end) end,
        function() Kora.commands.add('badrequired', '', nil, 'yes', function() end) end,
        function() Kora.commands.add('badhandler', '', nil, false, false) end,
        function() Kora.commands.add('badopts', '', nil, false, function() end, false) end,
        function() Kora.commands.add('badpermission', '', nil, false, function() end, { permission = false }) end,
        function() Kora.commands.add('badcheck', '', nil, false, function() end, { checkPermission = false }) end,
        function() Kora.commands.add('badnotify', '', nil, false, function() end, { notify = false }) end,
    }
    for index = 1, #invalid do harness.assertThrows(invalid[index]) end
    harness.assertEqual(#net.triggeredClientEvents, suggestions,
        'invalid registrations must not publish chat suggestions')
end)

harness.test("a 'user' permission command runs for anyone, including a real player source", function()
    local ran = false
    Kora.commands.add("ping", "", nil, false, function() ran = true end)

    run("ping", 1)

    harness.assertTrue(ran, "a default 'user' command should run for a normal player source")
end)

harness.test("source == 0 (console) bypasses permission checks entirely", function()
    local ran = false
    Kora.commands.add("consoleonly", "", nil, false, function() ran = true end, { permission = "admin" })

    run("consoleonly", 0)

    harness.assertTrue(ran, "source 0 (server console) should bypass permission gating")
end)

harness.test("a gated command with no checkPermission fails closed", function()
    local ran = false
    Kora.commands.add("gated", "", nil, false, function() ran = true end, { permission = "admin" })

    run("gated", 1)

    harness.assertFalse(ran, "a non-user permission with no checkPermission should deny by default")
    local notified = notifyCalls[#notifyCalls]
    harness.assertEqual(notified.payload.type, "error", "a denial should notify with an error type")
end)

harness.test("a gated command allows when checkPermission returns true", function()
    local ran = false
    Kora.commands.add("allowed", "", nil, false, function() ran = true end, {
        permission = "admin",
        checkPermission = function() return true end,
    })

    run("allowed", 1)

    harness.assertTrue(ran, "checkPermission returning true should allow the command")
end)

harness.test("a custom notify callback overrides the default Kora.notify.send path", function()
    local customNotified = {}
    Kora.commands.add("customdeny", "", nil, false, function() end, {
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
    Kora.commands.add("needsargs", "", { { name = "target" } }, true, function() ran = true end)

    registeredCommands["needsargs"](1, {}, "needsargs")

    harness.assertFalse(ran, "the handler should not run when a required arg is missing")
end)

harness.test("a handler error is caught, not propagated", function()
    Kora.commands.add("broken", "", nil, false, function() error("boom") end)

    local ok = pcall(run, "broken", 1)
    harness.assertTrue(ok, "a handler error should be caught internally, not thrown out of RegisterCommand's handler")
end)

harness.test("list() reports every registered command", function()
    local names, previous = {}, nil
    for _, entry in ipairs(Kora.commands.list()) do
        harness.assertTrue(previous == nil or previous < entry.name,
            "command listings should use a stable alphabetical order")
        names[entry.name] = true
        previous = entry.name
    end

    harness.assertTrue(names["hello"], "hello should be listed")
    harness.assertTrue(names["ping"], "ping should be listed")
end)

harness.test("refresh() re-sends suggestions to one target source", function()
    local firstEvent = #net.triggeredClientEvents + 1
    Kora.commands.refresh(42)

    local previous, sawTarget42 = nil, false
    for index = firstEvent, #net.triggeredClientEvents do
        local event = net.triggeredClientEvents[index]
        if event.name == "chat:addSuggestion" and event.target == 42 then
            local name = event[1]:sub(2)
            harness.assertTrue(previous == nil or previous < name,
                "refreshed suggestions should use a stable alphabetical order")
            previous = name
            sawTarget42 = true
        end
    end
    harness.assertTrue(sawTarget42, "refresh should re-send suggestions targeted at the given source")
end)

harness.test('refresh rejects malformed targets before emitting suggestions', function()
    local before = #net.triggeredClientEvents
    for _, source in ipairs({ 0, -1, 1.5, math.huge, '1' }) do
        harness.assertThrows(function() Kora.commands.refresh(source) end)
    end
    harness.assertEqual(#net.triggeredClientEvents, before)
end)

harness.test("remove() drops the command and its chat suggestion", function()
    Kora.commands.add("removable", "", nil, false, function() end)

    Kora.commands.remove("removable")

    local removed = mocks.lastEntry(net.triggeredClientEvents, "chat:removeSuggestion")
    harness.assertTrue(removed ~= nil, "removing a command should fire chat:removeSuggestion")
    harness.assertEqual(removed[1], "/removable", "the removal should target /removable")

    local stillListed = false
    for _, entry in ipairs(Kora.commands.list()) do
        if entry.name == "removable" then stillListed = true end
    end
    harness.assertFalse(stillListed, "a removed command should no longer be listed")
end)

harness.test("a resource cannot remove another resource's command", function()
    invokingResource = "command_owner"
    Kora.commands.add("owned_command", "Owned command", nil, false, function() end)

    invokingResource = "other_resource"
    harness.assertFalse(Kora.commands.remove("owned_command"), "a foreign resource must not remove the command")

    invokingResource = "command_owner"
    harness.assertTrue(Kora.commands.remove("owned_command"), "the owner should remove the command")
    invokingResource = nil
end)

harness.test("resource stop disposes exactly the commands still owned by that resource", function()
    invokingResource = "resource_a"
    Kora.commands.add("a_cmd", "", nil, false, function() end)

    invokingResource = "resource_b"
    Kora.commands.add("b_cmd", "", nil, false, function() end)

    invokingResource = nil
    net.fire("onResourceStop", "resource_a")

    local removed = mocks.lastEntry(net.triggeredClientEvents, "chat:removeSuggestion")
    harness.assertTrue(removed ~= nil, "stopping resource_a should remove its command's suggestion")
    harness.assertEqual(removed[1], "/a_cmd", "only a_cmd (owned by resource_a) should have been removed")

    local stillHasB = false
    for _, entry in ipairs(Kora.commands.list()) do
        if entry.name == "b_cmd" then stillHasB = true end
    end
    harness.assertTrue(stillHasB, "b_cmd, owned by resource_b, must survive resource_a stopping")

    local aGone = true
    for _, entry in ipairs(Kora.commands.list()) do
        if entry.name == "a_cmd" then aGone = false end
    end
    harness.assertTrue(aGone, "a_cmd should no longer be listed after its owning resource stopped")
end)

harness.test('suggestion payloads strip providers but advertise dynamic arguments', function()
    Kora.commands.add('lookup', 'Lookup a player', {
        { name = 'player', help = 'Player name', provider = function() return {} end },
    }, true, function() end)

    local suggestion = mocks.lastEntry(net.triggeredClientEvents, 'chat:addSuggestion')
    harness.assertTrue(suggestion[3][1].hasSuggestions)
    harness.assertEqual(suggestion[3][1].provider, nil)
end)

harness.test('suggest resolves, filters, normalizes and de-duplicates provider values', function()
    local context
    Kora.commands.add('complete', '', {
        {
            name = 'target',
            values = { 'Alice', 'Bob' },
            provider = function(src, ctx)
                context = { src = src, ctx = ctx }
                return {
                    { value = 'Alicia', label = 'Alicia (3)', help = 'server id 3' },
                    'Alice',
                    { value = string.rep('x', 129) },
                }
            end,
        },
    }, false, function() end)

    local results = Kora.commands.suggest(7, 'complete', 1, 'ali', { 'ali' })
    harness.assertEqual(#results, 2)
    harness.assertEqual(results[1].value, 'Alice')
    harness.assertEqual(results[2].value, 'Alicia')
    harness.assertEqual(context.src, 7)
    harness.assertEqual(context.ctx.query, 'ali')
end)

harness.test('suggest does not expose values for a denied command', function()
    Kora.commands.add('secretlookup', '', {
        { name = 'secret', values = { 'classified' } },
    }, false, function() end, { permission = 'admin' })

    harness.assertEqual(#Kora.commands.suggest(1, 'secretlookup', 1, '', {}), 0)
end)

harness.test('suggest rejects malformed sources and indexes before provider evaluation', function()
    local calls = 0
    Kora.commands.add('guardedsuggest', '', {
        { name = 'value', provider = function() calls = calls + 1; return { 'secret' } end },
    }, false, function() end, {
        permission = 'admin', checkPermission = function() return true end,
    })

    for _, src in ipairs({ 0, -1, 1.5, 0 / 0, math.huge, -math.huge }) do
        harness.assertEqual(#Kora.commands.suggest(src, 'guardedsuggest', 1, '', {}), 0)
    end
    for _, index in ipairs({ 0, -1, 1.5, 0 / 0, math.huge, -math.huge }) do
        harness.assertEqual(#Kora.commands.suggest(1, 'guardedsuggest', index, '', {}), 0)
    end
    harness.assertEqual(calls, 0, 'invalid suggestion requests must not invoke their provider')
end)

harness.test('suggest rejects malformed parsed arguments before provider evaluation', function()
    local calls = 0
    Kora.commands.add('parsedargs', '', {
        { name = 'value', provider = function() calls = calls + 1; return { 'safe' } end },
    }, false, function() end)

    local invalid = {
        false,
        { [2] = 'sparse' },
        { false },
        { string.rep('x', 129) },
    }
    local tooMany = {}
    for index = 1, 17 do tooMany[index] = 'value' end
    invalid[#invalid + 1] = tooMany

    for index = 1, #invalid do
        harness.assertEqual(#Kora.commands.suggest(1, 'parsedargs', 1, '', invalid[index]), 0)
    end
    harness.assertEqual(calls, 0, 'malformed parsed arguments must not invoke their provider')
end)

harness.test('suggest contains provider errors and returns static values', function()
    Kora.commands.add('providererror', '', {
        { name = 'value', values = { 'safe' }, provider = function() error('boom') end },
    }, false, function() end)

    local ok, results = pcall(Kora.commands.suggest, 1, 'providererror', 1, '', {})
    harness.assertTrue(ok)
    harness.assertEqual(results[1].value, 'safe')
end)

harness.test('suggest caps normalized responses at twenty entries', function()
    local values = {}
    for index = 1, 25 do values[index] = ('value-%02d'):format(index) end
    Kora.commands.add('cappedcomplete', '', {
        { name = 'value', values = values },
    }, false, function() end)

    harness.assertEqual(#Kora.commands.suggest(1, 'cappedcomplete', 1, '', {}), 20)
end)

harness.test('suggest fails closed when a permission callback errors', function()
    Kora.commands.add('permissionerror', '', {
        { name = 'value', values = { 'secret' } },
    }, false, function() end, {
        permission = 'admin', checkPermission = function() error('permission failure') end,
    })

    local ok, results = pcall(Kora.commands.suggest, 1, 'permissionerror', 1, '', {})
    harness.assertTrue(ok)
    harness.assertEqual(#results, 0)
end)

harness.test('a command keybind is published, listed, synchronized, and securely dispatched', function()
    local seen
    Kora.commands.add('boundcommand', 'Run bound command', nil, false, function(src, args, raw)
        seen = { src = src, args = args, raw = raw }
    end, {
        keybind = { defaultKey = 'F7', secondaryKey = 'F8' },
    })

    local published = mocks.lastEntry(net.triggeredClientEvents, 'kora_lib:commands:keybind:add')
    harness.assertEqual(published[1], 'boundcommand')
    harness.assertEqual(published[2].description, 'Run bound command')
    harness.assertEqual(published[2].defaultKey, 'F7')
    harness.assertEqual(published[2].secondaryKey, 'F8')

    local listed
    for _, entry in ipairs(Kora.commands.list()) do
        if entry.name == 'boundcommand' then listed = entry end
    end
    harness.assertEqual(listed.keybind.defaultKey, 'F7')

    TriggerServerEvent('kora_lib:commands:keybind:execute', 'boundcommand')
    harness.assertEqual(seen.src, mocks.SOURCE)
    harness.assertEqual(#seen.args, 0, 'key mappings invoke commands without arguments')
    harness.assertEqual(seen.raw, 'boundcommand')

    TriggerServerEvent('kora_lib:commands:keybind:sync')
    local synced = mocks.lastEntry(net.triggeredClientEvents, 'kora_lib:commands:keybind:add')
    harness.assertEqual(synced.target, mocks.SOURCE)
    harness.assertEqual(synced[1], 'boundcommand')
end)

harness.test('command keybind events discard malformed sources before dispatch', function()
    local ran = false
    Kora.commands.add('bound-malformed-source', '', nil, false, function() ran = true end, {
        keybind = { defaultKey = 'F12' },
    })

    local syncHandlers = net.netHandlers['kora_lib:commands:keybind:sync']
    local executeHandlers = net.netHandlers['kora_lib:commands:keybind:execute']
    local ok = pcall(function()
        for _, src in ipairs({ 0, -1, 1.5, 0 / 0, math.huge, -math.huge }) do
            _G.source = src
            for _, fn in ipairs(syncHandlers) do fn() end
            for _, fn in ipairs(executeHandlers) do fn('bound-malformed-source') end
        end
        _G.source = nil
    end)

    _G.source = nil
    harness.assertTrue(ok, 'malformed keybind sources must be ignored without handler errors')
    harness.assertFalse(ran, 'a malformed source must not dispatch a bound command')
end)

harness.test('command keybind dispatch uses the same permission and required-argument gates', function()
    local deniedRan, requiredRan = false, false
    Kora.commands.add('bounddenied', '', nil, false, function() deniedRan = true end, {
        permission = 'admin', keybind = { defaultKey = 'F9' },
    })
    local deniedMapping = mocks.lastEntry(net.triggeredClientEvents, 'kora_lib:commands:keybind:add')
    harness.assertEqual(deniedMapping[1], 'bound-malformed-source',
        'a denied permission must not publish a key mapping')
    Kora.commands.add('boundrequired', '', { { name = 'value' } }, true, function() requiredRan = true end, {
        keybind = { defaultKey = 'F10' },
    })

    notifyCalls = {}
    TriggerServerEvent('kora_lib:commands:keybind:execute', 'bounddenied')
    TriggerServerEvent('kora_lib:commands:keybind:execute', 'boundrequired')
    harness.assertFalse(deniedRan)
    harness.assertFalse(requiredRan)
    harness.assertEqual(#notifyCalls, 2, 'both ordinary command gates should notify through the usual path')

    local before = #notifyCalls
    TriggerServerEvent('kora_lib:commands:keybind:execute', 'complete')
    harness.assertEqual(#notifyCalls, before, 'an unbound command must not be reachable through the keybind transport')
end)

harness.test('privileged keybinds synchronize only to permitted players', function()
    Kora.commands.add('boundadmin', '', nil, false, function() end, {
        permission = 'admin',
        checkPermission = function(src) return src == 2 end,
        keybind = { defaultKey = 'F6' },
    })

    local published = mocks.lastEntry(net.triggeredClientEvents, 'kora_lib:commands:keybind:add')
    harness.assertEqual(published.target, 2)
    harness.assertEqual(published[1], 'boundadmin')

    local function mappingCount(target)
        local count = 0
        for _, event in ipairs(net.triggeredClientEvents) do
            if event.name == 'kora_lib:commands:keybind:add' and event.target == target and event[1] == 'boundadmin' then
                count = count + 1
            end
        end
        return count
    end

    local beforeDeniedSync = mappingCount(1)
    _G.source = 1
    for _, fn in ipairs(net.netHandlers['kora_lib:commands:keybind:sync']) do fn() end
    _G.source = nil
    harness.assertEqual(mappingCount(1), beforeDeniedSync, 'an unauthorized sync must not receive the mapping')

    local beforeAllowedSync = mappingCount(2)
    _G.source = 2
    for _, fn in ipairs(net.netHandlers['kora_lib:commands:keybind:sync']) do fn() end
    _G.source = nil
    harness.assertEqual(mappingCount(2), beforeAllowedSync + 1)
end)

harness.test('removing or replacing a bound command removes its client mapping', function()
    Kora.commands.add('bindingcleanup', '', nil, false, function() end, { keybind = { defaultKey = 'F11' } })
    Kora.commands.add('bindingcleanup', '', nil, false, function() end)
    local removed = mocks.lastEntry(net.triggeredClientEvents, 'kora_lib:commands:keybind:remove')
    harness.assertEqual(removed[1], 'bindingcleanup')

    Kora.commands.add('bindingcleanup', '', nil, false, function() end, { keybind = { defaultKey = 'F11' } })
    Kora.commands.remove('bindingcleanup')
    removed = mocks.lastEntry(net.triggeredClientEvents, 'kora_lib:commands:keybind:remove')
    harness.assertEqual(removed[1], 'bindingcleanup')
end)

harness.report("commands")
