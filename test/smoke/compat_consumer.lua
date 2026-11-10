local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local repoRoot = scriptDir .. '../../'
package.path = scriptDir .. '../?.lua;' .. package.path

local harness = require('harness')
local handlers = {}

_G.exports = {
    kora_lib = {
        util_isCallable = function(_, value) return type(value) == 'function' end,
    },
}
_G.GetCurrentResourceName = function() return 'consumer' end
_G.AddEventHandler = function(name, handler) handlers[name] = handler end
_G.LoadResourceFile = function(resource, path)
    if resource ~= 'kora_lib' then return nil end
    local file = assert(io.open(repoRoot .. path, 'r'))
    local source = file:read('*a')
    file:close()
    return source
end

dofile(repoRoot .. 'init.lua')

harness.test('consumer compat aliases register in the consumers environment', function()
    local expected = function() return 'ok' end
    Kora.compat.provideExport('legacy', 'action', expected)
    local provided
    handlers.__cfx_export_legacy_action(function(value) provided = value end)
    harness.assertEqual(provided, expected)
end)

harness.test('Kora.callback.trigger unpacks the packed export so a reason after a leading nil survives', function()
    local seen
    exports.kora_lib.callback_triggerPacked = function(_, ...)
        seen = table.pack(...)
        -- What msgpack hands a consumer for `return nil, "reason"`: a map with a hole at 1.
        return { n = 2, [2] = 'not allowed' }
    end
    exports.kora_lib.callback_trigger = function() error('the proxy must not use the multi-value export') end

    local value, reason = Kora.callback.trigger('consumer:refuse', 7)
    harness.assertEqual(seen[1], 'consumer:refuse')
    harness.assertEqual(seen[2], 7)
    harness.assertEqual(value, nil)
    harness.assertEqual(reason, 'not allowed')
    harness.assertEqual(select('#', Kora.callback.trigger('consumer:refuse')), 2)
end)

harness.report('compat_consumer')
