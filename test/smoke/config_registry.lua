local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local H = require('harness')
local mocks = require('mocks')
local net = mocks.install()

local invoker = 'sample'
_G.GetInvokingResource = function() return invoker end

local bridge = {
    qblib_configRead = function()
        return {
            schema = { kind = 'object', fields = {} }, configured = { enabled = true },
            values = { enabled = false }, revision = 1,
        }
    end,
    qblib_configCommit = function(_, request)
        return { ok = true, revision = request.revision + 1, configured = { enabled = request.value } }
    end,
    qblib_configReset = function(_, request)
        return { ok = true, revision = request.revision + 1, configured = { enabled = true }, values = { enabled = true } }
    end,
}
_G.exports = { sample = bridge }

dofile(repoRoot .. 'build/initiate.lua')
dofile(repoRoot .. 'modules/config/server.lua')

H.test('catalog records a resource only from its own bridge', function()
    H.assertTrue(QB.config.register({
        resource = 'sample', schema = { kind = 'object', fields = {} }, configured = { enabled = true },
        client = { enabled = true }, revision = 1,
    }))
    local catalog = QB.config.catalog()
    H.assertEqual(#catalog, 1)
    H.assertEqual(catalog[1].resource, 'sample')
end)

H.test('commit and reset are delegated to the target resource bridge', function()
    local changes = {}
    AddEventHandler('qblib:server:configChanged', function(resource, values, revision)
        changes[#changes + 1] = { resource = resource, values = values, revision = revision }
    end)
    local read = QB.config.read('sample')
    H.assertFalse(read.values.enabled)
    local committed = QB.config.commit('sample', { path = { 'enabled' }, value = false, revision = 1 })
    H.assertTrue(committed.ok)
    H.assertEqual(committed.revision, 2)
    local reset = QB.config.reset('sample', { path = { 'enabled' }, revision = 2 })
    H.assertTrue(reset.ok)
    H.assertEqual(reset.configured.enabled, true)
    H.assertEqual(#changes, 2)
    H.assertEqual(changes[2].resource, 'sample')
    H.assertTrue(changes[2].values.enabled)
    H.assertEqual(changes[2].revision, 3)
end)

H.test('another resource cannot register a forged catalog entry', function()
    invoker = 'other'
    H.assertThrows(function()
        QB.config.register({
            resource = 'sample', schema = {}, configured = {}, client = {}, revision = 1,
        })
    end)
    invoker = 'sample'
end)

H.test('catalog discovers a started qblib consumer that missed its startup announcement', function()
    local reads = 0
    _G.exports.late = {
        qblib_configRead = function()
            reads = reads + 1
            return {
                resource = 'late', schema = { kind = 'object', fields = {} }, configured = { enabled = true },
                client = { enabled = true }, revision = 1,
            }
        end,
    }
    _G.GetNumResources = function() return 1 end
    _G.GetResourceByFindIndex = function(index) return index == 0 and 'late' or nil end
    _G.GetResourceState = function() return 'started' end

    local catalog = QB.config.catalog()
    local discovered
    for _, entry in ipairs(catalog) do
        if entry.resource == 'late' then discovered = entry break end
    end
    H.assertTrue(discovered ~= nil)
    H.assertEqual(discovered.schema.kind, 'object')
    QB.config.catalog()
    H.assertEqual(reads, 1, 'registered resources should not be probed again on every catalog read')
end)

H.test('an on-demand read discovers a resource whose announcement raced startup', function()
    _G.exports.on_demand = {
        qblib_configRead = function()
            return {
                resource = 'on_demand', schema = { kind = 'object', fields = {} },
                configured = { enabled = true }, values = { enabled = true },
                client = { enabled = true }, revision = 4,
            }
        end,
    }
    _G.GetNumResources = function() return 1 end
    _G.GetResourceByFindIndex = function(index) return index == 0 and 'on_demand' or nil end
    _G.GetResourceState = function() return 'started' end

    local entry = QB.config.read('on_demand')
    H.assertEqual(entry.resource, 'on_demand')
    H.assertEqual(entry.revision, 4)
    H.assertTrue(entry.values.enabled)
end)

H.report('config_registry')
