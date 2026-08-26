local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")

dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/util/shared.lua")

harness.test("deepClone copies nested tables, not references", function()
    local original = { a = 1, nested = { b = 2 } }
    local copy = QB.util.deepClone(original)

    copy.nested.b = 99

    harness.assertEqual(original.nested.b, 2, "mutating the copy must not affect the original")
    harness.assertEqual(copy.a, 1, "top-level scalar fields should still be copied")
end)

harness.test("deepClone passes non-table values through unchanged", function()
    harness.assertEqual(QB.util.deepClone(5), 5, "numbers pass through")
    harness.assertEqual(QB.util.deepClone("x"), "x", "strings pass through")
end)

harness.test("clamp bounds a value within min/max", function()
    harness.assertEqual(QB.util.clamp(5, 0, 10), 5, "in-range value is unchanged")
    harness.assertEqual(QB.util.clamp(-5, 0, 10), 0, "below-min clamps to min")
    harness.assertEqual(QB.util.clamp(15, 0, 10), 10, "above-max clamps to max")
end)

harness.test("round rounds to the given decimal places", function()
    harness.assertEqual(QB.util.round(1.2345, 2), 1.23, "rounds down correctly")
    harness.assertEqual(QB.util.round(1.25, 1), 1.3, "rounds half up")
    harness.assertEqual(QB.util.round(1.6), 2, "defaults to zero decimals")
end)

harness.test("randomFloat stays within its bounds", function()
    for _ = 1, 50 do
        local v = QB.util.randomFloat(2.0, 4.0)
        harness.assertTrue(v >= 2.0 and v <= 4.0, "randomFloat result must stay within [min, max]")
    end
end)

harness.test("weightedChoice only ever returns a listed value", function()
    local list = { { "a", 1 }, { "b", 10 } }
    for _ = 1, 50 do
        local v = QB.util.weightedChoice(list)
        harness.assertTrue(v == "a" or v == "b", "result must be one of the listed values")
    end
end)

harness.test("weightedChoice rejects a non-positive weight", function()
    harness.assertThrows(function()
        QB.util.weightedChoice({ { "a", 0 } })
    end, "a zero weight should be rejected")
end)

harness.test("tableContains finds a present value and rejects an absent one", function()
    local t = { "x", "y", "z" }
    harness.assertTrue(QB.util.tableContains(t, "y"), "should find a present value")
    harness.assertFalse(QB.util.tableContains(t, "q"), "should not find an absent value")
end)

harness.report("util")
