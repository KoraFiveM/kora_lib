local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
local mocks = require('mocks')

mocks.install()

local state = 'missing'
_G.GetResourceState = function(name)
    harness.assertEqual(name, 'kora_skills', 'the bridge should only inspect qbskills')
    return state
end

_G.exports = {
    kora_skills = {
        getRep = function(_, src, skill) return { source = src, name = skill, level = 20 } end,
        getAllRep = function(_, src) return { mining = { source = src, level = 20 } } end,
        isLevel = function(_, src, _, level) return src == 1 and level <= 20 end,
        addRep = function(_, src, skill, amount) return src == 1 and skill == 'mining' and amount == 25, nil end,
        getSkillCheckOptions = function(_, src, skill, gameType, options)
            local copy = {}
            for key, value in pairs(options) do copy[key] = value end
            copy.zoneSize = copy.zoneSize + 0.1
            return copy, { source = src, name = skill, gameType = gameType }
        end,
    },
}

dofile(repoRoot .. 'build/initiate.lua')
dofile(repoRoot .. 'modules/util/shared.lua')
dofile(repoRoot .. 'modules/skills/server.lua')

harness.test('skills bridge is a no-op when qbskills is unavailable', function()
    harness.assertFalse(QB.skills.isAvailable(), 'the optional resource should report unavailable')
    harness.assertEqual(QB.skills.get(1, 'mining'), nil, 'unavailable resources should not be called')
    local ok, err = QB.skills.add(1, 'mining', 25)
    harness.assertFalse(ok, 'awards must fail closed without qbskills')
    harness.assertEqual(err, 'qbskills is not started', 'the unavailable result should be actionable')
end)

harness.test('skills bridge forwards only after qbskills has started', function()
    state = 'started'
    harness.assertTrue(QB.skills.isAvailable(), 'started qbskills should be available')
    harness.assertEqual(QB.skills.get(1, 'mining').level, 20, 'single-skill reads should forward')
    harness.assertTrue(QB.skills.hasLevel(1, 'mining', 20), 'level checks should forward')
    harness.assertTrue(QB.skills.add(1, 'mining', 25), 'server awards should forward')
    local adjusted, skill = QB.skills.adjustMinigame(1, 'mining', 'skillbar', { zoneSize = 0.2 })
    harness.assertTrue(math.abs(adjusted.zoneSize - 0.3) < 0.000001,
        'minigame options should use the backend modifier')
    harness.assertEqual(skill.name, 'mining', 'the backend skill snapshot should be returned')
end)

harness.test('server skills calls reject invalid sources and awards before forwarding', function()
    state = 'started'
    harness.assertThrows(function() QB.skills.get(math.huge, 'mining') end)
    harness.assertThrows(function() QB.skills.adjustMinigame(math.huge, 'mining', 'skillbar', {}) end)
    harness.assertThrows(function() QB.skills.add(1, 'mining', 0 / 0) end)
    harness.assertThrows(function() QB.skills.add(1, 'mining', 0) end)
    harness.assertThrows(function() QB.skills.add(1, 'mining', 1.5) end)
    harness.assertThrows(function() QB.skills.get(1, false) end)
    harness.assertThrows(function() QB.skills.hasLevel(1, '', 1) end)
    harness.assertThrows(function() QB.skills.hasLevel(1, 'mining', 0) end)
    harness.assertThrows(function() QB.skills.add(1, '', 1) end)
    harness.assertThrows(function() QB.skills.add(1, 'mining', 1, { x = 1, y = 2, z = math.huge }) end)
    harness.assertThrows(function() QB.skills.add(1, 'mining', 1, nil, false) end)
    harness.assertThrows(function() QB.skills.adjustMinigame(1, '', 'skillbar', {}) end)
    harness.assertThrows(function() QB.skills.adjustMinigame(1, 'mining', '', {}) end)
end)

_G.exports.kora_skills = {
    getRep = function(_, skill) return { name = skill, level = 20 } end,
    getAllRep = function() return { mining = { level = 20 } } end,
    isLevel = function(_, skill, level) return skill == 'mining' and level <= 20 end,
    getSkillCheckOptions = function(_, skill, gameType, options)
        local copy = {}
        for key, value in pairs(options or {}) do copy[key] = value end
        copy.skill, copy.gameType = skill, gameType
        return copy
    end,
}
dofile(repoRoot .. 'modules/skills/client.lua')

harness.test('client skills bridge validates inputs before forwarding', function()
    state = 'started'
    harness.assertEqual(QB.skills.get('mining').level, 20)
    harness.assertTrue(QB.skills.hasLevel('mining', 20))
    harness.assertEqual(QB.skills.adjustMinigame('mining', 'skillbar', { zoneSize = 0.2 }).skill, 'mining')
    harness.assertThrows(function() QB.skills.get(false) end)
    harness.assertThrows(function() QB.skills.hasLevel('', 1) end)
    harness.assertThrows(function() QB.skills.hasLevel('mining', 0) end)
    harness.assertThrows(function() QB.skills.adjustMinigame('mining', '', {}) end)
    harness.assertThrows(function() QB.skills.adjustMinigame('mining', 'skillbar', false) end)
end)

harness.report('skills')
