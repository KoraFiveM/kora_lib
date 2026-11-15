local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

mocks.install()

local grants = {}
_G.IsPlayerAceAllowed = function(src, principal)
    return grants[src] ~= nil and grants[src][principal] == true
end

local function grant(src, principal)
    grants[src] = grants[src] or {}
    grants[src][principal] = true
end

dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/logging/shared.lua")
dofile(repoRoot .. "modules/permissions/server.lua")

local LEVELS = { "god", "admin", "mod", "user" }

harness.test("getLevel falls back to 'user' with no grants", function()
    grants = {}
    harness.assertEqual(Kora.permissions.getLevel(1, LEVELS, "kora_core"), "user", "no ace grants means the lowest level")
end)

harness.test('permission APIs reject malformed player sources before ACE checks', function()
    for _, src in ipairs({ 0, -1, 1.5, 0 / 0, math.huge, -math.huge }) do
        harness.assertThrows(function() Kora.permissions.getLevel(src, LEVELS, 'kora_core') end)
        harness.assertThrows(function() Kora.permissions.hasLevel(src, 'mod', LEVELS, 'kora_core') end)
        harness.assertThrows(function() Kora.permissions.hasPermission(src, 'user', 'kora_core') end)
        harness.assertThrows(function() Kora.permissions.explain(src, LEVELS, 'kora_core') end)
    end
end)

harness.test('explain rejects malformed levels before calling ACE', function()
    local aceCalls = 0
    _G.IsPlayerAceAllowed = function()
        aceCalls = aceCalls + 1
        return false
    end

    harness.assertThrows(function() Kora.permissions.explain(1, { 'admin', '' }, 'kora_core') end)
    harness.assertEqual(aceCalls, 0, 'malformed levels should not reach the ACE native')

    harness.assertThrows(function() Kora.permissions.explain(1, { 'admin', [3] = 'user' }, 'kora_core') end)
    harness.assertEqual(aceCalls, 0, 'sparse level lists should not reach the ACE native')

    _G.IsPlayerAceAllowed = function(src, principal)
        return grants[src] ~= nil and grants[src][principal] == true
    end
end)

harness.test('permission checks reject oversized level hierarchies before ACE lookup', function()
    local levels = {}
    for index = 1, 33 do levels[index] = 'level' .. index end
    local aceCalls = 0
    _G.IsPlayerAceAllowed = function() aceCalls = aceCalls + 1; return false end

    harness.assertThrows(function() Kora.permissions.getLevel(1, levels, 'kora_core') end)
    harness.assertEqual(aceCalls, 0)

    _G.IsPlayerAceAllowed = function(src, principal)
        return grants[src] ~= nil and grants[src][principal] == true
    end
end)

harness.test("getLevel returns the highest matching level via the prefix namespace", function()
    grants = {}
    grant(1, "kora_core.mod")
    harness.assertEqual(Kora.permissions.getLevel(1, LEVELS, "kora_core"), "mod", "the mod principal should resolve to 'mod'")

    grant(1, "kora_core.admin")
    harness.assertEqual(Kora.permissions.getLevel(1, LEVELS, "kora_core"), "admin", "the higher admin principal should now win")
end)

harness.test("getLevel also matches via the shared group.<level> namespace", function()
    grants = {}
    grant(2, "group.god")
    harness.assertEqual(Kora.permissions.getLevel(2, LEVELS, "kora_core"), "god", "a group.god grant should resolve to 'god' regardless of prefix")
end)

harness.test("group.admin ACE remains authoritative when Discord is enabled", function()
    grants = {}
    grant(7, "group.admin")
    local discordChecks = 0
    Kora.discord.hasAnyRole = function()
        discordChecks = discordChecks + 1
        error("Discord cache unavailable")
    end

    local options = { prefix = "kora_core", discordRoles = { admin = { "Administrator" } } }
    harness.assertEqual(Kora.permissions.getLevel(7, LEVELS, options), "admin", "group.admin must grant admin")
    harness.assertTrue(Kora.permissions.hasPermission(7, "admin", options), "group.admin must pass exact checks")
    harness.assertEqual(discordChecks, 0, "an ACE grant should not depend on Discord")
end)

harness.test("Discord roles optionally grant mapped levels and cascade", function()
    grants = {}
    Kora.discord.hasAnyRole = function(src, roles)
        return src == 8 and roles[1] == "Administrator"
    end

    local options = {
        prefix = "kora_core",
        discordRoles = { admin = { "Administrator", "Owner" } },
    }
    harness.assertEqual(Kora.permissions.getLevel(8, LEVELS, options), "admin", "mapped role should resolve its level")
    harness.assertTrue(Kora.permissions.hasLevel(8, "mod", LEVELS, options), "admin should satisfy the lower mod level")
    harness.assertFalse(Kora.permissions.hasLevel(8, "god", LEVELS, options), "admin should not satisfy god")
    harness.assertTrue(Kora.permissions.hasPermission(8, "admin", options), "mapped role should pass an exact check")
end)

harness.test("Discord failures fail closed without granting access", function()
    grants = {}
    Kora.discord.hasAnyRole = function() return false, "Discord member role cache is stale." end
    local options = { prefix = "kora_core", discordRoles = { admin = "Administrator" } }

    harness.assertEqual(Kora.permissions.getLevel(10, LEVELS, options), "user", "stale roles must not resolve a level")
    harness.assertFalse(Kora.permissions.hasPermission(10, "admin", options), "stale roles must not grant access")
end)

harness.test('Discord role arrays must be dense strings before lookup', function()
    grants = {}
    Kora.discord.hasAnyRole = function() error('malformed roles must not reach Discord') end

    harness.assertThrows(function()
        Kora.permissions.getLevel(10, LEVELS, { discordRoles = { admin = { 'Administrator', [3] = 'Owner' } } })
    end)
    harness.assertThrows(function()
        Kora.permissions.getLevel(10, LEVELS, { discordRoles = { admin = { false } } })
    end)
end)

harness.test("getLevel is scoped by prefix: a grant under a different prefix does not match", function()
    grants = {}
    grant(3, "otherresource.admin")
    harness.assertEqual(Kora.permissions.getLevel(3, LEVELS, "kora_core"), "user", "a grant under a different prefix should not leak across namespaces")
end)

harness.test("hasPermission always allows 'user'", function()
    grants = {}
    harness.assertTrue(Kora.permissions.hasPermission(9, "user", "kora_core"), "'user' should always be allowed")
end)

harness.test("hasPermission checks <prefix>.<permission> and group.<permission>", function()
    grants = {}
    harness.assertFalse(Kora.permissions.hasPermission(4, "admin", "kora_core"), "no grant should deny")

    grant(4, "kora_core.admin")
    harness.assertTrue(Kora.permissions.hasPermission(4, "admin", "kora_core"), "a prefix-namespaced grant should allow")

    grants = {}
    grant(5, "group.admin")
    harness.assertTrue(Kora.permissions.hasPermission(5, "admin", "kora_core"), "a group grant should allow")
end)

harness.test("hasPermission falls back to command.<permission>", function()
    grants = {}
    grant(6, "command.admin")
    harness.assertTrue(Kora.permissions.hasPermission(6, "admin", "kora_core"), "a command-scoped grant should allow just that permission")
end)

harness.test("prefix is optional while shared group ACEs still work", function()
    grants = {}
    grant(11, "group.admin")
    harness.assertTrue(Kora.permissions.hasPermission(11, "admin"), "group.admin should not require a resource prefix")
end)

harness.report("permissions")
