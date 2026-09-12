local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local repoRoot = scriptDir .. '../../'
package.path = scriptDir .. '../?.lua;' .. package.path

local harness = require('harness')
local handlers = {}

_G.exports = {
    qblib = {
        util_isCallable = function(_, value) return type(value) == 'function' end,
    },
}
_G.GetCurrentResourceName = function() return 'consumer' end
_G.AddEventHandler = function(name, handler) handlers[name] = handler end
_G.LoadResourceFile = function(resource, path)
    if resource ~= 'qblib' then return nil end
    local file = assert(io.open(repoRoot .. path, 'r'))
    local source = file:read('*a')
    file:close()
    return source
end

dofile(repoRoot .. 'init.lua')

harness.test('consumer compat aliases register in the consumers environment', function()
    local expected = function() return 'ok' end
    QB.compat.provideExport('legacy', 'action', expected)
    local provided
    handlers.__cfx_export_legacy_action(function(value) provided = value end)
    harness.assertEqual(provided, expected)
end)

harness.report('compat_consumer')
