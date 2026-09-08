local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
local mocks = require('mocks')

mocks.install()
dofile(repoRoot .. 'config.lua')
dofile(repoRoot .. 'build/initiate.lua')

local callbackName, callbackHandler, callbackOptions
QB.callback = {
    register = function(name, handler, options)
        callbackName = name
        callbackHandler = handler
        callbackOptions = options
    end,
}

local adminSource
QB.permissions = {
    hasPermission = function(src, permission)
        adminSource = src
        return src == 42 and permission == 'admin'
    end,
}

dofile(repoRoot .. 'modules/blips/server.lua')

harness.test('registers a rate-limited server callback for admin visibility', function()
    harness.assertEqual(callbackName, 'qblib:blips:isAdmin', 'callback name should be namespaced')
    harness.assertEqual(callbackOptions.rateLimit.max, 10, 'permission checks should have a bounded request rate')
end)

harness.test('returns only the server-resolved admin permission', function()
    harness.assertTrue(callbackHandler(42), 'admin permission should be returned')
    harness.assertEqual(adminSource, 42, 'permission should be checked for the callback source')
    harness.assertFalse(callbackHandler(12), 'non-admin should fail closed')
    harness.assertFalse(callbackHandler(0), 'invalid source should fail closed')
end)

harness.report('blips settings server smoke')
