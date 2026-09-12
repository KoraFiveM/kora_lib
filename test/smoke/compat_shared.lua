local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local repoRoot = scriptDir .. '../../'
package.path = scriptDir .. '../?.lua;' .. package.path

local harness = require('harness')
local handlers = {}

_G.AddEventHandler = function(name, handler) handlers[name] = handler end

dofile(repoRoot .. 'build/initiate.lua')
dofile(repoRoot .. 'modules/util/shared.lua')
dofile(repoRoot .. 'compat/shared.lua')

harness.test('provideExport registers callable values under another identity', function()
    local expected = function() return true end
    QB.compat.provideExport('legacy-resource', 'action', expected)
    local provided
    handlers['__cfx_export_legacy-resource_action'](function(value) provided = value end)
    harness.assertEqual(provided, expected)
end)

harness.test('the consumer-local provider exposes the same registration contract', function()
    local createProvider = dofile(repoRoot .. 'compat/provider.lua')
    local provider = createProvider()
    local expected = setmetatable({}, { __call = function() end })
    provider.provideExport('consumer-alias', 'callable', expected)
    local provided
    handlers['__cfx_export_consumer-alias_callable'](function(value) provided = value end)
    harness.assertEqual(provided, expected)
end)

harness.report('compat_shared')
