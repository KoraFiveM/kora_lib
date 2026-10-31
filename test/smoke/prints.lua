local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
local mocks = require('mocks')
mocks.install()

dofile(repoRoot .. 'build/initiate.lua')

local output = {}
_G.print = function(message) output[#output + 1] = message end
_G.json = {
    encode = function(value)
        if value.fail then error('cannot encode') end
        return '{"ok":true}'
    end,
}

dofile(repoRoot .. 'modules/prints/shared.lua')

harness.test('print helpers format encodable tables', function()
    Kora.print.info('ready', { ok = true })
    harness.assertEqual(output[#output], '^4[INFO]^0 ready {"ok":true}')
end)

harness.test('print helpers contain table encoding failures', function()
    local value = { fail = true }
    local ok = pcall(Kora.print.error, value)
    harness.assertTrue(ok, 'diagnostic output must not throw when JSON encoding fails')
    harness.assertTrue(output[#output]:find('^1[ERROR]^0 table:', 1, true) ~= nil)
end)

harness.report('prints')
