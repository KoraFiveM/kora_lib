local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
require('mocks').install()
dofile(repoRoot .. 'build/initiate.lua')
dofile(repoRoot .. 'modules/logging/shared.lua')

harness.test('internal callable detection accepts native and Cfx funcref shapes', function()
    harness.assertTrue(Kora.compat.isCallable(function() end))
    harness.assertTrue(Kora.compat.isCallable({ __cfx_functionReference = 'ref:1' }))
    harness.assertTrue(Kora.compat.isCallable(setmetatable({}, { __call = function() end })))
end)

harness.test('internal callable detection follows nested callable proxies safely', function()
    local nested = setmetatable({}, { __call = { __cfx_functionReference = 'ref:2' } })
    harness.assertTrue(Kora.compat.isCallable(nested))

    local cyclic = {}
    setmetatable(cyclic, { __call = cyclic })
    harness.assertFalse(Kora.compat.isCallable(cyclic), 'a cyclic proxy must terminate and fail closed')
end)

harness.test('internal callable detection rejects non-callable values', function()
    for _, value in ipairs({ false, 1, 'function', {}, coroutine.create(function() end) }) do
        harness.assertFalse(Kora.compat.isCallable(value))
    end
end)

harness.test('internal token generation stays opaque and validates length', function()
    local token = Kora.compat.generateToken()
    harness.assertEqual(#token, 32)
    harness.assertTrue(token:match('^[%w]+$') ~= nil)
    harness.assertEqual(#Kora.compat.generateToken(12), 12)
    harness.assertThrows(function() Kora.compat.generateToken(0) end)
end)

harness.test('internal token generation does not repeat and works without os', function()
    local seen = {}
    for _ = 1, 200 do
        local token = Kora.compat.generateToken(24)
        harness.assertEqual(#token, 24)
        harness.assertFalse(seen[token], 'tokens must not repeat')
        seen[token] = true
    end

    local realOs = os
    os = nil
    local ok, token = pcall(Kora.compat.generateToken, 16)
    os = realOs
    harness.assertTrue(ok, 'token generation must not raise without os')
    harness.assertEqual(#token, 16)
    harness.assertTrue(token:match('^[%w]+$') ~= nil)
end)

harness.report('internal compatibility')
