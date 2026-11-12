local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')

local files = {
    ['sample/config.lua'] = 'return { enabled = true }',
    ['sample/package/init.lua'] = 'return "package fallback"',
}
local loads = {}
local handlers = {}

_G.LoadResourceFile = function(resource, path)
    local key = resource .. '/' .. path
    loads[key] = (loads[key] or 0) + 1
    return files[key]
end
_G.AddEventHandler = function(name, handler) handlers[name] = handler end

local factory = assert(loadfile(repoRoot .. 'modules/require/loader.lua'))()
local requireApi = factory('consumer')

harness.test('loads and caches one explicit module', function()
    local first = requireApi.load('sample', 'config.lua')
    local second = requireApi.load('sample', 'config.lua')
    harness.assertTrue(first.enabled)
    harness.assertEqual(first, second, 'one consumer should receive the cached module value')
    harness.assertEqual(loads['sample/config.lua'], 1, 'cached modules must not read the resource again')
end)

harness.test('uses init.lua as the extensionless package fallback', function()
    harness.assertEqual(requireApi.load('sample', 'package'), 'package fallback')
    harness.assertEqual(loads['sample/package.lua'], 1)
    harness.assertEqual(loads['sample/package/init.lua'], 1)
end)

harness.test('rejects resource and module traversal before reading files', function()
    harness.assertThrows(function() requireApi.load('../sample', 'config') end)
    harness.assertThrows(function() requireApi.load('.', 'config') end)
    harness.assertThrows(function() requireApi.load('..', 'config') end)
    harness.assertThrows(function() requireApi.load('sample@other', 'config') end)
    harness.assertThrows(function() requireApi.load('sample', '../config') end)
    harness.assertThrows(function() requireApi.load('sample', 'folder//config') end)
end)

harness.test('resource stop releases its module cache', function()
    handlers.onResourceStop('sample')
    requireApi.load('sample', 'config.lua')
    harness.assertEqual(loads['sample/config.lua'], 2, 'stopped resources must reload on their next start')
end)

harness.report('require')
