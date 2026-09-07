local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')

local function readFile(path)
    local file = assert(io.open(path, 'r'))
    local contents = file:read('*a')
    file:close()
    return contents
end

local loaderSource = readFile(repoRoot .. 'modules/require/loader.lua')
local configConsumerSource = readFile(repoRoot .. 'modules/config/consumer.lua')
local resourceFiles = {
    ['qbapartments\0config.lua'] = "return { name = 'apartments' }",
    ['qbapartments\0public/data.lua'] = "return { first = 'alta' }",
    ['qbapartments\0params.lua'] = 'return 42',
    ['consumer\0config.lua'] = "return 'consumer config'",
    ['consumer\0folder/init.lua'] = "return 'folder module'",
    ['consumer\0nothing.lua'] = 'local loaded = true',
    ['consumer\0false.lua'] = 'falseExecutions = (falseExecutions or 0) + 1; return false',
    ['consumer\0cached.lua'] = 'cacheExecutions = (cacheExecutions or 0) + 1; return cacheExecutions',
    ['consumer\0circular.lua'] = "return QB.require.current('circular')",
    ['restartable\0value.lua'] = "return 'old'",
}
local readCounts = {}
local stopHandlers = {}
local exportCalls = {}

_G.LoadResourceFile = function(resource, path)
    if resource == 'qblib' and path == 'modules/require/loader.lua' then return loaderSource end
    if resource == 'qblib' and path == 'modules/config/consumer.lua' then return configConsumerSource end

    local key = resource .. '\0' .. path
    readCounts[key] = (readCounts[key] or 0) + 1
    return resourceFiles[key]
end

_G.GetCurrentResourceName = function() return 'consumer' end
_G.AddEventHandler = function(name, handler)
    stopHandlers[name] = stopHandlers[name] or {}
    stopHandlers[name][#stopHandlers[name] + 1] = handler
end

_G.exports = {
    qblib = {
        ping_echo = function(_, value)
            exportCalls[#exportCalls + 1] = value
            return value
        end,
    },
}

dofile(repoRoot .. 'init.lua')

harness.test('load returns one value per requested path in order', function()
    local config, data, params = QB.require.load('qbapartments', { 'config', 'public/data', 'params' })
    harness.assertEqual(config.name, 'apartments')
    harness.assertEqual(data.first, 'alta')
    harness.assertEqual(params, 42)
end)

harness.test('load accepts a single path and an explicit lua extension', function()
    local config = QB.require.load('qbapartments', 'config.lua')
    harness.assertEqual(config.name, 'apartments')
    harness.assertEqual(readCounts['qbapartments\0config.lua'], 1)
end)

harness.test('current and the bracket-form local alias resolve the consumer resource', function()
    harness.assertEqual(QB.require.current('config'), 'consumer config')
    harness.assertEqual(QB.require['local']('config'), 'consumer config')
end)

harness.test('a directory module falls back to init.lua', function()
    harness.assertEqual(QB.require.current('folder'), 'folder module')
end)

harness.test('modules are cached and false is retained as a real return value', function()
    harness.assertEqual(QB.require.current('cached'), 1)
    harness.assertEqual(QB.require.current('cached'), 1)
    harness.assertFalse(QB.require.current('false'))
    harness.assertFalse(QB.require.current('false'))
    harness.assertEqual(cacheExecutions, 1)
    harness.assertEqual(falseExecutions, 1)
end)

harness.test('a module with no return value resolves to true', function()
    harness.assertTrue(QB.require.current('nothing'))
end)

harness.test('resource stop invalidates cached modules from that resource', function()
    harness.assertEqual(QB.require.load('restartable', 'value'), 'old')
    resourceFiles['restartable\0value.lua'] = "return 'new'"
    harness.assertEqual(QB.require.load('restartable', 'value'), 'old')

    for _, handler in ipairs(stopHandlers.onResourceStop or {}) do handler('restartable') end
    harness.assertEqual(QB.require.load('restartable', 'value'), 'new')
end)

harness.test('missing modules report every attempted file', function()
    local ok, err = pcall(QB.require.current, 'missing')
    harness.assertFalse(ok)
    harness.assertTrue(tostring(err):find("no file '@consumer/missing.lua'", 1, true) ~= nil)
    harness.assertTrue(tostring(err):find("no file '@consumer/missing/init.lua'", 1, true) ~= nil)
end)

harness.test('circular modules fail clearly and can be retried after correction', function()
    local ok, err = pcall(QB.require.current, 'circular')
    harness.assertFalse(ok)
    harness.assertTrue(tostring(err):find('circular dependency', 1, true) ~= nil)

    resourceFiles['consumer\0circular.lua'] = "return 'fixed'"
    harness.assertEqual(QB.require.current('circular'), 'fixed')
end)

harness.test('invalid resources, paths, and path arrays are rejected', function()
    harness.assertThrows(function() QB.require.load('../other', 'config') end)
    harness.assertThrows(function() QB.require.current('../config') end)
    harness.assertThrows(function() QB.require.current({ 'config', [3] = 'params' }) end)
    harness.assertThrows(function() QB.require.current({}) end)
end)

harness.test('ordinary QB modules still dispatch through qblib exports', function()
    harness.assertEqual(QB.ping.echo('hello'), 'hello')
    harness.assertEqual(exportCalls[#exportCalls], 'hello')
end)

harness.report('require')
