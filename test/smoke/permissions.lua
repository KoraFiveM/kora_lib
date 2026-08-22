local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

mocks.install()

-- src -> set of granted principal strings, e.g. { ["qbcore.admin"] = true }
local grants = {}
_G.IsPlayerAceAllowed = function(src, principal)
    return grants[src] ~= nil and grants[src][principal] == true
end

local function grant(src, principal)
    grants[src] = grants[src] or {}
    grants[src][principal] = true
end

dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/permissions/server.lua")

local LEVELS = { "god", "admin", "mod", "user" }

harness.test("getLevel falls back to 'user' with no grants", function()
    grants = {}
    harness.assertEqual(QB.permissions.getLevel(1, LEVELS, "qbcore"), "user", "no ace grants means the lowest level")
end)

harness.test("getLevel returns the highest matching level via the prefix namespace", function()
    grants = {}
    grant(1, "qbcore.mod")
    harness.assertEqual(QB.permissions.getLevel(1, LEVELS, "qbcore"), "mod", "the mod principal should resolve to 'mod'")

    grant(1, "qbcore.admin")
    harness.assertEqual(QB.permissions.getLevel(1, LEVELS, "qbcore"), "admin", "the higher admin principal should now win")
end)

harness.test("getLevel also matches via the shared group.<level> namespace", function()
    grants = {}
    grant(2, "group.god")
    harness.assertEqual(QB.permissions.getLevel(2, LEVELS, "qbcore"), "god", "a group.god grant should resolve to 'god' regardless of prefix")
end)

harness.test("getLevel is scoped by prefix: a grant under a different prefix does not match", function()
    grants = {}
    grant(3, "otherresource.admin")
    harness.assertEqual(QB.permissions.getLevel(3, LEVELS, "qbcore"), "user", "a grant under a different prefix should not leak across namespaces")
end)

harness.test("hasPermission always allows 'user'", function()
    grants = {}
    harness.assertTrue(QB.permissions.hasPermission(9, "user", "qbcore"), "'user' should always be allowed")
end)

harness.test("hasPermission checks <prefix>.<permission> and group.<permission>", function()
    grants = {}
    harness.assertFalse(QB.permissions.hasPermission(4, "admin", "qbcore"), "no grant should deny")

    grant(4, "qbcore.admin")
    harness.assertTrue(QB.permissions.hasPermission(4, "admin", "qbcore"), "a prefix-namespaced grant should allow")

    grants = {}
    grant(5, "group.admin")
    harness.assertTrue(QB.permissions.hasPermission(5, "admin", "qbcore"), "a group grant should allow")
end)

harness.test("hasPermission falls back to command.<permission>", function()
    grants = {}
    grant(6, "command.admin")
    harness.assertTrue(QB.permissions.hasPermission(6, "admin", "qbcore"), "a command-scoped grant should allow just that permission")
end)

harness.report("permissions")
