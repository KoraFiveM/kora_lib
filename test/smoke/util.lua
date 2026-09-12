local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")

dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/util/shared.lua")

-- The client file adds screen-projection helpers to the SAME QB.util table.
-- Safe to load both realms here because they define disjoint function names --
-- unlike QB.notify/QB.callback, where the second dofile would overwrite the
-- first realm's version of a shared name (see AGENTS.md "Testing").
local projection = { onScreen = true, x = 0.25, y = 0.75 }
function _G.World3dToScreen2d(_, _, _) return projection.onScreen, projection.x, projection.y end
function _G.GetActiveScreenResolution() return 1920, 1080 end

dofile(repoRoot .. "modules/util/client.lua")

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

harness.test("fnv1a returns a stable lowercase checksum", function()
    harness.assertEqual(QB.util.fnv1a("hello"), "4f9f2cab")
    harness.assertEqual(QB.util.fnv1a(""), "811c9dc5")
    harness.assertThrows(function() QB.util.fnv1a({}) end, "non-string input must be rejected")
end)

harness.test("isFiniteNumber rejects non-numbers, NaN, and infinities", function()
    harness.assertTrue(QB.util.isFiniteNumber(0))
    harness.assertTrue(QB.util.isFiniteNumber(-12.5))
    harness.assertFalse(QB.util.isFiniteNumber("12"))
    harness.assertFalse(QB.util.isFiniteNumber(0 / 0))
    harness.assertFalse(QB.util.isFiniteNumber(math.huge))
    harness.assertFalse(QB.util.isFiniteNumber(-math.huge))
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

-- --- vector helpers ---------------------------------------------------------

local function assertClose(actual, expected, message)
    harness.assertTrue(math.abs(actual - expected) < 1e-9,
        ("%s (expected %s, got %s)"):format(message, tostring(expected), tostring(actual)))
end

harness.test("lerp interpolates and does not clamp", function()
    harness.assertEqual(QB.util.lerp(0, 10, 0.5), 5, "midpoint should be halfway")
    harness.assertEqual(QB.util.lerp(0, 10, 0), 0, "t=0 returns a")
    harness.assertEqual(QB.util.lerp(0, 10, 1), 10, "t=1 returns b")
    harness.assertEqual(QB.util.lerp(0, 10, 2), 20, "t is deliberately unclamped")
end)

harness.test("vector arithmetic returns plain tables, never a vector3", function()
    local sum = QB.util.vecAdd({ x = 1, y = 2, z = 3 }, { x = 10, y = 20, z = 30 })

    harness.assertEqual(type(sum), "table", "the result must be a plain table so it survives json/exports")
    harness.assertEqual(sum.x, 11, "x should add")
    harness.assertEqual(sum.y, 22, "y should add")
    harness.assertEqual(sum.z, 33, "z should add")

    local difference = QB.util.vecSub({ x = 10, y = 10, z = 10 }, { x = 1, y = 2, z = 3 })
    harness.assertEqual(difference.x, 9, "x should subtract")
    harness.assertEqual(difference.y, 8, "y should subtract")
    harness.assertEqual(difference.z, 7, "z should subtract")

    local scaled = QB.util.vecScale({ x = 1, y = 2, z = 3 }, 2)
    harness.assertEqual(scaled.x, 2, "x should scale")
    harness.assertEqual(scaled.z, 6, "z should scale")
end)

harness.test("a missing z is treated as zero", function()
    -- Plenty of call sites hand over a 2D point; defaulting z avoids an
    -- arithmetic-on-nil crash deep inside the maths.
    local length = QB.util.vecLength({ x = 3, y = 4 })
    harness.assertEqual(length, 5, "a 3-4-5 triangle with an implicit z=0")
end)

harness.test("vecDistance2d ignores height, vecDistance does not", function()
    local a = { x = 0, y = 0, z = 0 }
    local b = { x = 3, y = 4, z = 100 }

    harness.assertEqual(QB.util.vecDistance2d(a, b), 5, "the 2D measure must ignore z entirely")
    harness.assertTrue(QB.util.vecDistance(a, b) > 100, "the 3D measure must include z")
end)

harness.test("vecDistance uses only dimensions shared by both vectors", function()
    local vec2 = { x = 0, y = 0 }
    local vec3 = { x = 3, y = 4, z = 100 }
    local vec4 = { x = 3, y = 4, z = 12, w = 270 }

    harness.assertEqual(QB.util.vecDistance(vec2, vec3), 5,
        "vector2 versus vector3 should ignore the unavailable z component")
    harness.assertEqual(QB.util.vecDistance(vec3, vec4), 88,
        "vector3 versus vector4 should compare xyz and ignore heading")
    harness.assertEqual(QB.util.vecDistance(vec4, { x = 0, y = 0, z = 0, w = -999 }), 13,
        "different vector4 headings must not affect distance")
end)

harness.test("vecNormalize produces a unit vector and survives a zero vector", function()
    local unit = QB.util.vecNormalize({ x = 0, y = 5, z = 0 })
    assertClose(QB.util.vecLength(unit), 1, "a normalized vector has length 1")
    harness.assertEqual(unit.y, 1, "direction should be preserved")

    local zero = QB.util.vecNormalize({ x = 0, y = 0, z = 0 })
    harness.assertEqual(zero.x, 0.0, "a zero vector must return zeroes")
    harness.assertFalse(zero.y ~= zero.y, "and must not produce NaN")
end)

harness.test("heading and direction round-trip in GTA's convention", function()
    -- Heading 0 is north (+Y); heading increases counter-clockwise, so 90 is
    -- west (-X). Getting this backwards is the classic bearing bug.
    local north = QB.util.headingToDirection(0)
    assertClose(north.x, 0, "north has no x component")
    assertClose(north.y, 1, "north is +Y")

    local west = QB.util.headingToDirection(90)
    assertClose(west.x, -1, "heading 90 points to -X (west)")
    assertClose(west.y, 0, "heading 90 has no y component")

    for _, heading in ipairs({ 0, 45, 90, 180, 270, 359 }) do
        assertClose(QB.util.directionToHeading(QB.util.headingToDirection(heading)), heading,
            ("heading %d should survive a round trip"):format(heading))
    end
end)

harness.test("bearing points from origin to target", function()
    assertClose(QB.util.bearing({ x = 0, y = 0, z = 0 }, { x = 0, y = 10, z = 0 }), 0,
        "a target due north is bearing 0")
    assertClose(QB.util.bearing({ x = 0, y = 0, z = 0 }, { x = -10, y = 0, z = 0 }), 90,
        "a target due west is bearing 90")
end)

harness.test("worldToScreen reports normalised coordinates and on-screen state", function()
    projection.onScreen, projection.x, projection.y = true, 0.25, 0.75

    local x, y, onScreen = QB.util.worldToScreen({ x = 1, y = 2, z = 3 })
    harness.assertEqual(x, 0.25, "x should be the native's normalised value")
    harness.assertEqual(y, 0.75, "y should be the native's normalised value")
    harness.assertTrue(onScreen, "on-screen should be reported")

    projection.onScreen = false
    local _, _, offScreen = QB.util.worldToScreen({ x = 1, y = 2, z = 3 })
    harness.assertFalse(offScreen, "off-screen must be reported so callers can gate on it")

    projection.onScreen = true
end)

harness.test("worldToScreenPixels scales by the active resolution", function()
    projection.onScreen, projection.x, projection.y = true, 0.5, 0.5

    local x, y = QB.util.worldToScreenPixels({ x = 0, y = 0, z = 0 })
    harness.assertEqual(x, 960, "0.5 of 1920 is 960")
    harness.assertEqual(y, 540, "0.5 of 1080 is 540")
end)

harness.report("util")
