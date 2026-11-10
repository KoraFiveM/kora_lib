local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local repoRoot = scriptDir .. '../../'
package.path = scriptDir .. '../?.lua;' .. package.path

local harness = require('harness')

_G.exports = { kora_lib = {} }
_G.GetCurrentResourceName = function() return 'consumer' end
_G.AddEventHandler = function() end
_G.LoadResourceFile = function(resource, path)
    if resource ~= 'kora_lib' then return nil end
    local file = assert(io.open(repoRoot .. path, 'r'))
    local source = file:read('*a')
    file:close()
    return source
end

dofile(repoRoot .. 'init.lua')

harness.test('Kora is the primary global', function()
    harness.assertEqual(type(Kora), 'table')
end)

harness.report('global_alias')
