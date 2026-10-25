local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
require('mocks').install()
dofile(repoRoot .. 'build/initiate.lua')

harness.test('internal callable detection accepts native and Cfx funcref shapes', function()
    harness.assertTrue(QB.compat.isCallable(function() end))
    harness.assertTrue(QB.compat.isCallable({ __cfx_functionReference = 'ref:1' }))
    harness.assertTrue(QB.compat.isCallable(setmetatable({}, { __call = function() end })))
end)

harness.test('internal callable detection follows nested callable proxies safely', function()
    local nested = setmetatable({}, { __call = { __cfx_functionReference = 'ref:2' } })
    harness.assertTrue(QB.compat.isCallable(nested))

    local cyclic = {}
    setmetatable(cyclic, { __call = cyclic })
    harness.assertFalse(QB.compat.isCallable(cyclic), 'a cyclic proxy must terminate and fail closed')
end)

harness.test('internal callable detection rejects non-callable values', function()
    for _, value in ipairs({ false, 1, 'function', {}, coroutine.create(function() end) }) do
        harness.assertFalse(QB.compat.isCallable(value))
    end
end)

harness.test('internal token generation stays opaque and validates length', function()
    local token = QB.compat.generateToken()
    harness.assertEqual(#token, 32)
    harness.assertTrue(token:match('^[%w]+$') ~= nil)
    harness.assertEqual(#QB.compat.generateToken(12), 12)
    harness.assertThrows(function() QB.compat.generateToken(0) end)
end)

harness.test('internal token generation does not repeat and works without os', function()
    local seen = {}
    for _ = 1, 200 do
        local token = QB.compat.generateToken(24)
        harness.assertEqual(#token, 24)
        harness.assertFalse(seen[token], 'tokens must not repeat')
        seen[token] = true
    end

    -- The client realm has no os library; stirring must still work there.
    local realOs = os
    os = nil
    local ok, token = pcall(QB.compat.generateToken, 16)
    os = realOs
    harness.assertTrue(ok, 'token generation must not raise without os')
    harness.assertEqual(#token, 16)
    harness.assertTrue(token:match('^[%w]+$') ~= nil)
end)

harness.report('internal compatibility')
