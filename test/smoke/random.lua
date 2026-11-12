local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')

dofile(repoRoot .. 'build/initiate.lua')
dofile(repoRoot .. 'modules/random/shared.lua')
dofile(repoRoot .. 'modules/util/shared.lua')

local function withRandom(random, fn)
    local originalRandom = math.random
    math.random = random
    local success, result = pcall(fn)
    math.random = originalRandom
    if not success then error(result, 0) end
    return result
end

harness.test('pick returns one array value directly by default', function()
    local value = withRandom(function(min, max)
        harness.assertEqual(min, 1, 'selection should start at the first index')
        harness.assertEqual(max, 3, 'selection should default to the full array')
        return 2
    end, function()
        return Kora.random.pick({ 'a', 'b', 'c' })
    end)

    harness.assertEqual(value, 'b', 'one pick should return the value, not an array')
end)

harness.test('pick honors maxIndex', function()
    local value = withRandom(function(_, max)
        harness.assertEqual(max, 2, 'maxIndex should limit the eligible array range')
        return max
    end, function()
        return Kora.random.pick({ 'a', 'b', 'c' }, { maxIndex = 2 })
    end)

    harness.assertEqual(value, 'b', 'the selected value should come from the limited range')
end)

harness.test('count greater than one returns an array and permits repeats', function()
    local values = withRandom(function() return 1 end, function()
        return Kora.random.pick({ 'a', 'b' }, { count = 3 })
    end)

    harness.assertEqual(#values, 3, 'the result should contain the requested number of picks')
    harness.assertEqual(values[1], 'a')
    harness.assertEqual(values[2], 'a')
    harness.assertEqual(values[3], 'a')
end)

harness.test('count one still returns a value directly', function()
    local value = Kora.random.pick({ 'only' }, { count = 1 })
    harness.assertEqual(value, 'only')
end)

harness.test('pick rejects invalid inputs and options', function()
    harness.assertThrows(function() Kora.random.pick({}) end, 'an empty array should be rejected')
    harness.assertThrows(function() Kora.random.pick({ 'a', [3] = 'b' }) end,
        'a sparse array must not silently omit values')
    harness.assertThrows(function() Kora.random.pick({ 'a' }, 2) end, 'options must be a table')
    harness.assertThrows(function() Kora.random.pick({ 'a' }, { count = 0 }) end, 'count must be positive')
    harness.assertThrows(function() Kora.random.pick({ 'a' }, { count = 1.5 }) end, 'count must be an integer')
    harness.assertThrows(function() Kora.random.pick({ 'a' }, { count = false }) end, 'count must be an integer')
    harness.assertThrows(function() Kora.random.pick({ 'a' }, { count = math.huge }) end,
        'count must be finite')
    harness.assertThrows(function() Kora.random.pick({ 'a' }, { count = 10001 }) end,
        'count must not allocate an unbounded result table')
    harness.assertThrows(function() Kora.random.pick({ 'a' }, { maxIndex = 0 }) end, 'maxIndex must be positive')
    harness.assertThrows(function() Kora.random.pick({ 'a' }, { maxIndex = false }) end,
        'maxIndex must be an integer')
    harness.assertThrows(function() Kora.random.pick({ 'a' }, { maxIndex = math.huge }) end,
        'maxIndex must be finite')
    harness.assertThrows(function() Kora.random.pick({ 'a' }, { maxIndex = 2 }) end,
        'maxIndex must not exceed the array length')
end)

harness.report('random')
