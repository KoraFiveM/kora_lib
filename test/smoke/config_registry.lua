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

H.test('catalog rejects malformed registration revisions', function()
    for _, revision in ipairs({ 0, -1, 1.5, 0 / 0, math.huge, -math.huge }) do
        H.assertThrows(function()
            QB.config.register({
                resource = 'sample', schema = {}, configured = {}, client = {}, revision = revision,
            })
        end)
    end
end)

H.test('config snapshots reject malformed client sources and request IDs', function()
    local request = net.netHandlers['qblib:server:configRequested'][1]
    local sent = #net.triggeredClientEvents
    _G.source = nil
    request('sample')
    for _, invalidSource in ipairs({ 0, -1, 1.5, 0 / 0, math.huge, -math.huge }) do
        _G.source = invalidSource
        request('sample')
    end
    _G.source = 1
    request('sample')
    for _, invalidRequestId in ipairs({ 0, -1, 1.5, 0 / 0, math.huge, -math.huge }) do
        request('sample', invalidRequestId)
    end
    _G.source = nil
    H.assertEqual(#net.triggeredClientEvents, sent)
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

H.test('catalog discovery and refresh preserve the revision invariant', function()
    _G.exports.invalid_revision = {
        qblib_configRead = function()
            return {
                resource = 'invalid_revision', schema = {}, configured = {}, client = {}, revision = 1.5,
            }
        end,
    }
    _G.GetNumResources = function() return 1 end
    _G.GetResourceByFindIndex = function(index) return index == 0 and 'invalid_revision' or nil end
    _G.GetResourceState = function() return 'started' end
    for _, entry in ipairs(QB.config.catalog()) do
        H.assertFalse(entry.resource == 'invalid_revision')
    end

    local revision
    for _, entry in ipairs(QB.config.catalog()) do
        if entry.resource == 'sample' then revision = entry.revision break end
    end
    local read = bridge.qblib_configRead
    bridge.qblib_configRead = function()
        return { configured = {}, values = {}, client = {}, revision = math.huge }
    end
    H.assertEqual(QB.config.read('sample').revision, revision)
    bridge.qblib_configRead = read
end)

H.test('invalid successful bridge revisions do not update the catalog', function()
    local revision
    for _, entry in ipairs(QB.config.catalog()) do
        if entry.resource == 'sample' then revision = entry.revision break end
    end
    local commit, reset = bridge.qblib_configCommit, bridge.qblib_configReset
    bridge.qblib_configCommit = function() return { ok = true, revision = math.huge } end
    bridge.qblib_configReset = function() return { ok = true, revision = 1.5 } end
    H.assertFalse(QB.config.commit('sample', {}).ok)
    H.assertFalse(QB.config.reset('sample', {}).ok)
    bridge.qblib_configCommit, bridge.qblib_configReset = commit, reset
    for _, entry in ipairs(QB.config.catalog()) do
        if entry.resource == 'sample' then H.assertEqual(entry.revision, revision) end
    end
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

H.test('own bootstrap survives a resource-driven restart without granting callers ownership', function()
    invoker = 'qbcompat-control'
    _G.GetCurrentResourceName = function() return 'qblib' end
    _G.IsDuplicityVersion = function() return true end
    _G.GetNumResources = function() return 0 end
    _G.LoadResourceFile = function(resource, path)
        H.assertEqual(resource, 'qblib')
        if path ~= 'modules/config/consumer.lua' then return nil end
        local file = assert(io.open(repoRoot .. path, 'r'))
        local contents = file:read('*a')
        file:close()
        return contents
    end
    local owned = {}
    _G.exports = setmetatable({}, { __call = function(_, name, fn) owned[name] = fn end })
    _G.Config = { enabled = true, discord = { secret = 'server-only' } }
    dofile(repoRoot .. 'modules/config/server.lua')
    local catalog = QB.config.catalog()
    H.assertEqual(#catalog, 1)
    H.assertEqual(catalog[1].resource, 'qblib')
    H.assertTrue(Config.enabled)
    local snapshot = owned.qblib_configRead()
    H.assertEqual(snapshot.client.discord, nil)
    H.assertEqual(snapshot.configured.discord.secret, 'server-only')
    H.assertThrows(function()
        QB.config.register({ resource = 'qblib', schema = {}, configured = {}, client = {}, revision = 1 })
    end)
    H.assertTrue(QB.config.register({
        resource = 'qbcompat-control', schema = {}, configured = {}, client = {}, revision = 1,
    }))
end)

H.report('config_registry')
