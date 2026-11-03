-- Kora.onReady / Kora.offReady live in init.lua (consumer side), not in a
-- module, so this loads init.lua the way a consumer does and fakes kora_lib's
-- export side. F#187: registrations made through kora_lib exports are lost
-- when kora_lib restarts; onReady must re-run so they can be re-attached.
local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
local mocks = require('mocks')

local function loadConsumer(isServer)
    local net = mocks.install()

    -- kora_lib's side: one cache-listener registry that a restart wipes.
    local library = { listeners = {} }
    function library:cache_onChange(key, handler)
        self.listeners[#self.listeners + 1] = { key = key, handler = handler }
    end
    function library:restart()
        self.listeners = {}
        _G.TriggerEvent(isServer and 'kora_lib:server:updated' or 'kora_lib:client:updated')
    end

    _G.exports = { kora_lib = library }
    _G.IsDuplicityVersion = function() return isServer end
    _G.GetCurrentResourceName = function() return 'consumer' end
    _G.LoadResourceFile = function(resource, path)
        if resource ~= 'kora_lib' then return nil end
        local file = assert(io.open(repoRoot .. path, 'r'))
        local source = file:read('*a')
        file:close()
        return source
    end

    dofile(repoRoot .. 'init.lua')
    return library, net
end

harness.test('onReady runs the handler immediately and returns an id', function()
    loadConsumer(false)
    local runs = 0
    local id = Kora.onReady(function() runs = runs + 1 end)
    harness.assertEqual(runs, 1, 'the handler should run once straight away')
    harness.assertTrue(type(id) == 'number', 'onReady should return an id')
end)

harness.test('onReady re-attaches listeners after a kora_lib restart (client)', function()
    local library = loadConsumer(false)
    local runs = 0
    Kora.onReady(function()
        runs = runs + 1
        Kora.cache.onChange('vehicle', function() end)
    end)
    harness.assertEqual(#library.listeners, 1)

    library:restart()
    harness.assertEqual(runs, 2, 'the handler should run again after the restart')
    harness.assertEqual(#library.listeners, 1, 'the listener should be registered again')

    library:restart()
    harness.assertEqual(runs, 3)
    harness.assertEqual(#library.listeners, 1)
end)

harness.test('onReady listens to the server update event on the server', function()
    local library = loadConsumer(true)
    local runs = 0
    Kora.onReady(function() runs = runs + 1 end)

    _G.TriggerEvent('kora_lib:client:updated')
    harness.assertEqual(runs, 1, 'the client event must not re-run a server handler')

    library:restart()
    harness.assertEqual(runs, 2)
end)

harness.test('offReady stops later re-runs', function()
    local library = loadConsumer(false)
    local runs = 0
    local id = Kora.onReady(function() runs = runs + 1 end)

    harness.assertTrue(Kora.offReady(id), 'removing a live handler returns true')
    harness.assertFalse(Kora.offReady(id), 'removing it twice returns false')
    library:restart()
    harness.assertEqual(runs, 1)
end)

harness.test('a failing handler does not stop the others from re-running', function()
    local library = loadConsumer(false)
    local failNext = false
    local otherRuns = 0
    Kora.onReady(function()
        if failNext then error('boom') end
    end)
    Kora.onReady(function() otherRuns = otherRuns + 1 end)

    failNext = true
    local printed = {}
    local originalPrint = print
    _G.print = function(message) printed[#printed + 1] = message end
    library:restart()
    _G.print = originalPrint

    harness.assertEqual(otherRuns, 2)
    harness.assertTrue(printed[1] and printed[1]:find('boom', 1, true) ~= nil, 'the error should be logged')
end)

harness.test('offReady from inside a handler skips a handler that has not run yet', function()
    local library = loadConsumer(false)
    local secondRuns = 0
    local secondId
    Kora.onReady(function()
        if secondId then Kora.offReady(secondId) end
    end)
    secondId = Kora.onReady(function() secondRuns = secondRuns + 1 end)

    library:restart()
    harness.assertEqual(secondRuns, 1, 'the removed handler must not run again')
end)

harness.test('onReady rejects a non-function', function()
    loadConsumer(false)
    harness.assertThrows(function() Kora.onReady('nope') end)
end)

harness.report('ready')
