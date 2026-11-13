local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
local mocks = require('mocks')

mocks.install()
dofile(repoRoot .. 'config.lua')
dofile(repoRoot .. 'build/initiate.lua')
dofile(repoRoot .. 'modules/logging/shared.lua')

local callbackName, callbackHandler, callbackOptions
local registeredNames = {}
Kora.callback = {
    register = function(name, handler, options)
        callbackName = callbackName or name
        registeredNames[#registeredNames + 1] = name
        callbackHandler = handler
        callbackOptions = options
    end,
}

local adminSource
Kora.permissions = {
    hasPermission = function(src, permission)
        adminSource = src
        return src == 42 and permission == 'admin'
    end,
}

dofile(repoRoot .. 'modules/blips/server.lua')

harness.test('registers a rate-limited server callback for admin visibility', function()
    harness.assertEqual(callbackName, 'kora_lib:blips:isAdmin', 'callback name should be namespaced')
    harness.assertEqual(callbackOptions.rateLimit.max, 10, 'permission checks should have a bounded request rate')
end)

harness.test('returns only the server-resolved admin permission', function()
    harness.assertTrue(callbackHandler(42), 'admin permission should be returned')
    harness.assertEqual(adminSource, 42, 'permission should be checked for the callback source')
    harness.assertFalse(callbackHandler(12), 'non-admin should fail closed')
    harness.assertFalse(callbackHandler(0), 'invalid source should fail closed')
end)

harness.test('rejects malformed sources before resolving permissions', function()
    adminSource = nil
    for _, source in ipairs({ -1, 1.5, 0 / 0, math.huge, -math.huge }) do
        harness.assertFalse(callbackHandler(source))
    end
    harness.assertEqual(adminSource, nil, 'invalid sources must not reach the permission helper')
end)

harness.report('blips settings server smoke')
