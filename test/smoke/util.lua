local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")

_G.json = {
    decode = function(value)
        if value == '{"ok":true}' then return { ok = true } end
        error('malformed')
    end,
}

dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/util/shared.lua")

local projection = { onScreen = true, x = 0.25, y = 0.75 }
function _G.World3dToScreen2d(_, _, _) return projection.onScreen, projection.x, projection.y end
function _G.GetActiveScreenResolution() return 1920, 1080 end

dofile(repoRoot .. "modules/util/client.lua")

harness.test("deepClone copies nested tables, not references", function()
    local original = { a = 1, nested = { b = 2 } }
    local copy = Kora.util.deepClone(original)

    copy.nested.b = 99

    harness.assertEqual(original.nested.b, 2, "mutating the copy must not affect the original")
    harness.assertEqual(copy.a, 1, "top-level scalar fields should still be copied")
end)

harness.test("deepClone passes non-table values through unchanged", function()
    harness.assertEqual(Kora.util.deepClone(5), 5, "numbers pass through")
    harness.assertEqual(Kora.util.deepClone("x"), "x", "strings pass through")
end)

harness.test("deepClone preserves shared and circular table references", function()
    local child = { value = 1 }
    local original = { first = child, second = child }
    original.self = original

    local copy = Kora.util.deepClone(original)

    harness.assertTrue(copy ~= original, "the outer table must still be copied")
    harness.assertTrue(copy.first == copy.second, "shared children must remain shared in the copy")
    harness.assertTrue(copy.first ~= child, "the shared child must be cloned")
    harness.assertTrue(copy.self == copy, "a circular reference must point to the copied table")
end)

harness.test("fnv1a returns a stable lowercase checksum", function()
    harness.assertEqual(Kora.util.fnv1a("hello"), "4f9f2cab")
    harness.assertEqual(Kora.util.fnv1a(""), "811c9dc5")
    harness.assertThrows(function() Kora.util.fnv1a({}) end, "non-string input must be rejected")
end)

harness.test("isCallable accepts functions and callable tables", function()
    harness.assertTrue(Kora.util.isCallable(function() end))
    harness.assertTrue(Kora.util.isCallable(setmetatable({}, { __call = function() end })))
    harness.assertFalse(Kora.util.isCallable({}))
    harness.assertFalse(Kora.util.isCallable("function"))
end)

harness.test("trim preserves non-strings and removes edge whitespace", function()
    harness.assertEqual(Kora.util.trim("  hello world\n"), "hello world")
    harness.assertEqual(Kora.util.trim(7), 7)
end)

harness.test("cleanText applies the shared external-text policy", function()
    harness.assertEqual(Kora.util.cleanText("  hello\t\0world  "), "hello world")
    harness.assertEqual(Kora.util.cleanText("éclair", { maxLength = 2 }), "éc")
    harness.assertEqual(Kora.util.cleanText("   "), nil)
    harness.assertEqual(Kora.util.cleanText(7), nil)
end)

harness.test("cleanText rejects an explicit non-table options value", function()
    harness.assertThrows(function() Kora.util.cleanText("text", false) end)
end)

harness.test("truncateUtf8 counts characters and rejects malformed text", function()
    harness.assertEqual(Kora.util.truncateUtf8("héllo", 2), "hé")
    harness.assertEqual(Kora.util.truncateUtf8("short", 20), "short")
    local value, reason = Kora.util.truncateUtf8("\255", 1)
    harness.assertEqual(value, nil)
    harness.assertEqual(reason, "invalid_utf8")
end)

harness.test("isFiniteNumber rejects non-numbers, NaN, and infinities", function()
    harness.assertTrue(Kora.util.isFiniteNumber(0))
    harness.assertTrue(Kora.util.isFiniteNumber(-12.5))
    harness.assertFalse(Kora.util.isFiniteNumber("12"))
    harness.assertFalse(Kora.util.isFiniteNumber(0 / 0))
    harness.assertFalse(Kora.util.isFiniteNumber(math.huge))
    harness.assertFalse(Kora.util.isFiniteNumber(-math.huge))
end)

harness.test("isInteger accepts only finite whole numbers", function()
    harness.assertTrue(Kora.util.isInteger(3))
    harness.assertTrue(Kora.util.isInteger(-2))
    harness.assertFalse(Kora.util.isInteger(1.5))
    harness.assertFalse(Kora.util.isInteger(math.huge))
    harness.assertFalse(Kora.util.isInteger("3"))
end)

harness.test("decodeJson returns a stable recoverable failure", function()
    local decoded = Kora.util.decodeJson('{"ok":true}')
    harness.assertTrue(decoded.ok)
    local invalid, reason = Kora.util.decodeJson('{')
    harness.assertEqual(invalid, nil)
    harness.assertEqual(reason, 'invalid_json')
end)

harness.test("clamp bounds a value within min/max", function()
    harness.assertEqual(Kora.util.clamp(5, 0, 10), 5, "in-range value is unchanged")
    harness.assertEqual(Kora.util.clamp(-5, 0, 10), 0, "below-min clamps to min")
    harness.assertEqual(Kora.util.clamp(15, 0, 10), 10, "above-max clamps to max")
end)

harness.test("clamp rejects non-finite or reversed bounds", function()
    harness.assertThrows(function() Kora.util.clamp(math.huge, 0, 1) end)
    harness.assertThrows(function() Kora.util.clamp(0, 1, 0) end)
end)

harness.test("round rounds to the given decimal places", function()
    harness.assertEqual(Kora.util.round(1.2345, 2), 1.23, "rounds down correctly")
    harness.assertEqual(Kora.util.round(1.25, 1), 1.3, "rounds half up")
    harness.assertEqual(Kora.util.round(1.6), 2, "defaults to zero decimals")
end)

harness.test("round rejects non-finite values and fractional decimal places", function()
    harness.assertThrows(function() Kora.util.round(math.huge) end)
    harness.assertThrows(function() Kora.util.round(1.25, 0.5) end)
    harness.assertThrows(function() Kora.util.round(1.25, false) end)
    harness.assertThrows(function() Kora.util.round(1.25, 1000) end)
    harness.assertThrows(function() Kora.util.round(1.25, -1000) end)
    harness.assertThrows(function() Kora.util.round(1e308, 1) end)
end)

harness.test("randomFloat stays within its bounds", function()
    for _ = 1, 50 do
        local v = Kora.util.randomFloat(2.0, 4.0)
        harness.assertTrue(v >= 2.0 and v <= 4.0, "randomFloat result must stay within [min, max]")
    end
end)

harness.test("randomFloat remains finite across the full finite range", function()
    local value = Kora.util.randomFloat(-1e308, 1e308)
    harness.assertTrue(Kora.util.isFiniteNumber(value), "a finite range must return a finite value")
    harness.assertTrue(value >= -1e308 and value <= 1e308, "result must stay within the wide finite range")
end)

harness.test("randomFloat rejects non-finite or reversed bounds", function()
    for _, bounds in ipairs({ { math.huge, 1 }, { 1, -math.huge }, { 4, 2 } }) do
        harness.assertThrows(function()
            Kora.util.randomFloat(bounds[1], bounds[2])
        end, "bounds must be finite and ordered")
    end
end)

harness.test("weightedChoice only ever returns a listed value", function()
    local list = { { "a", 1 }, { "b", 10 } }
    for _ = 1, 50 do
        local v = Kora.util.weightedChoice(list)
        harness.assertTrue(v == "a" or v == "b", "result must be one of the listed values")
    end
end)

harness.test("weightedChoice rejects a non-positive weight", function()
    harness.assertThrows(function()
        Kora.util.weightedChoice({ { "a", 0 } })
    end, "a zero weight should be rejected")
end)

harness.test('weightedChoice rejects sparse and malformed pair lists', function()
    harness.assertThrows(function()
        Kora.util.weightedChoice({ { 'first', 1 }, [3] = { 'third', 1 } })
    end, 'a sparse list must not silently ignore a pair')
    harness.assertThrows(function()
        Kora.util.weightedChoice({ 'not-a-pair' })
    end, 'every entry must be a pair table')
end)

harness.test("weightedChoice rejects non-finite weights", function()
    for _, weight in ipairs({ math.huge, -math.huge, 0 / 0 }) do
        harness.assertThrows(function()
            Kora.util.weightedChoice({ { "a", weight } })
        end, "non-finite weights must be rejected")
    end
end)

harness.test("weightedChoice rejects finite weights whose total overflows", function()
    harness.assertThrows(function()
        Kora.util.weightedChoice({ { "a", 1e308 }, { "b", 1e308 } })
    end, "the accumulated weight must remain finite")
end)

harness.test("tableContains finds a present value and rejects an absent one", function()
    local t = { "x", "y", "z" }
    harness.assertTrue(Kora.util.tableContains(t, "y"), "should find a present value")
    harness.assertFalse(Kora.util.tableContains(t, "q"), "should not find an absent value")
end)

local function assertClose(actual, expected, message)
    harness.assertTrue(math.abs(actual - expected) < 1e-9,
        ("%s (expected %s, got %s)"):format(message, tostring(expected), tostring(actual)))
end

harness.test("lerp interpolates and does not clamp", function()
    harness.assertEqual(Kora.util.lerp(0, 10, 0.5), 5, "midpoint should be halfway")
    harness.assertEqual(Kora.util.lerp(0, 10, 0), 0, "t=0 returns a")
    harness.assertEqual(Kora.util.lerp(0, 10, 1), 10, "t=1 returns b")
    harness.assertEqual(Kora.util.lerp(0, 10, 2), 20, "t is deliberately unclamped")
    harness.assertEqual(Kora.util.lerp(-1e308, 1e308, 0.5), 0, "wide finite midpoint remains finite")
end)

harness.test("lerp rejects non-finite inputs", function()
    harness.assertThrows(function() Kora.util.lerp(0, math.huge, 0.5) end)
    harness.assertThrows(function() Kora.util.lerp(-1e308, 1e308, 2) end)
end)

harness.test("vector arithmetic returns plain tables, never a vector3", function()
    local sum = Kora.util.vecAdd({ x = 1, y = 2, z = 3 }, { x = 10, y = 20, z = 30 })

    harness.assertEqual(type(sum), "table", "the result must be a plain table so it survives json/exports")
    harness.assertEqual(sum.x, 11, "x should add")
    harness.assertEqual(sum.y, 22, "y should add")
    harness.assertEqual(sum.z, 33, "z should add")

    local difference = Kora.util.vecSub({ x = 10, y = 10, z = 10 }, { x = 1, y = 2, z = 3 })
    harness.assertEqual(difference.x, 9, "x should subtract")
    harness.assertEqual(difference.y, 8, "y should subtract")
    harness.assertEqual(difference.z, 7, "z should subtract")

    local scaled = Kora.util.vecScale({ x = 1, y = 2, z = 3 }, 2)
    harness.assertEqual(scaled.x, 2, "x should scale")
    harness.assertEqual(scaled.z, 6, "z should scale")
end)

harness.test("a missing z is treated as zero", function()
    local length = Kora.util.vecLength({ x = 3, y = 4 })
    harness.assertEqual(length, 5, "a 3-4-5 triangle with an implicit z=0")
end)

harness.test("vector magnitudes remain finite for large finite coordinates", function()
    local value = Kora.util.vecLength({ x = 1e308, y = 1e308, z = 0 })
    harness.assertTrue(Kora.util.isFiniteNumber(value), "large finite length must remain finite")

    local distance = Kora.util.vecDistance2d({ x = 0, y = 0 }, { x = 1e308, y = 1e308 })
    harness.assertTrue(Kora.util.isFiniteNumber(distance), "large finite distance must remain finite")
end)

harness.test("vector helpers reject non-finite coordinates and scalar inputs", function()
    harness.assertThrows(function() Kora.util.vecLength({ x = math.huge, y = 0 }) end)
    harness.assertThrows(function() Kora.util.vecScale({ x = 1, y = 2, z = 3 }, 0 / 0) end)
    harness.assertThrows(function() Kora.util.headingToDirection(-math.huge) end)
end)

harness.test("vecDistance2d ignores height, vecDistance does not", function()
    local a = { x = 0, y = 0, z = 0 }
    local b = { x = 3, y = 4, z = 100 }

    harness.assertEqual(Kora.util.vecDistance2d(a, b), 5, "the 2D measure must ignore z entirely")
    harness.assertTrue(Kora.util.vecDistance(a, b) > 100, "the 3D measure must include z")
end)

harness.test("vecDistance uses only dimensions shared by both vectors", function()
    local vec2 = { x = 0, y = 0 }
    local vec3 = { x = 3, y = 4, z = 100 }
    local vec4 = { x = 3, y = 4, z = 12, w = 270 }

    harness.assertEqual(Kora.util.vecDistance(vec2, vec3), 5,
        "vector2 versus vector3 should ignore the unavailable z component")
    harness.assertEqual(Kora.util.vecDistance(vec3, vec4), 88,
        "vector3 versus vector4 should compare xyz and ignore heading")
    harness.assertEqual(Kora.util.vecDistance(vec4, { x = 0, y = 0, z = 0, w = -999 }), 13,
        "different vector4 headings must not affect distance")
end)

harness.test("vecNormalize produces a unit vector and survives a zero vector", function()
    local unit = Kora.util.vecNormalize({ x = 0, y = 5, z = 0 })
    assertClose(Kora.util.vecLength(unit), 1, "a normalized vector has length 1")
    harness.assertEqual(unit.y, 1, "direction should be preserved")

    local zero = Kora.util.vecNormalize({ x = 0, y = 0, z = 0 })
    harness.assertEqual(zero.x, 0.0, "a zero vector must return zeroes")
    harness.assertFalse(zero.y ~= zero.y, "and must not produce NaN")
end)

harness.test("heading and direction round-trip in GTA's convention", function()
    local north = Kora.util.headingToDirection(0)
    assertClose(north.x, 0, "north has no x component")
    assertClose(north.y, 1, "north is +Y")

    local west = Kora.util.headingToDirection(90)
    assertClose(west.x, -1, "heading 90 points to -X (west)")
    assertClose(west.y, 0, "heading 90 has no y component")

    for _, heading in ipairs({ 0, 45, 90, 180, 270, 359 }) do
        assertClose(Kora.util.directionToHeading(Kora.util.headingToDirection(heading)), heading,
            ("heading %d should survive a round trip"):format(heading))
    end
end)

harness.test("bearing points from origin to target", function()
    assertClose(Kora.util.bearing({ x = 0, y = 0, z = 0 }, { x = 0, y = 10, z = 0 }), 0,
        "a target due north is bearing 0")
    assertClose(Kora.util.bearing({ x = 0, y = 0, z = 0 }, { x = -10, y = 0, z = 0 }), 90,
        "a target due west is bearing 90")
end)

harness.test("nearest finds the closest entry within range", function()
    local list = {
        { id = "a", coords = { x = 0, y = 0, z = 0 } },
        { id = "b", coords = { x = 10, y = 0, z = 0 } },
        { id = "c", coords = { x = 2, y = 0, z = 0 } },
    }

    local entry, distance = Kora.util.nearest(list, { x = 0, y = 0, z = 0 }, {
        coordsOf = function(item) return item.coords end,
    })
    harness.assertEqual(entry.id, "a", "the exact match is nearest")
    harness.assertEqual(distance, 0)

    local other = Kora.util.nearest(list, { x = 3, y = 0, z = 0 }, {
        coordsOf = function(item) return item.coords end,
    })
    harness.assertEqual(other.id, "c", "the closer of two remaining candidates wins")
end)

harness.test("nearest respects radius and bucket filters", function()
    local list = {
        { id = "far", coords = { x = 100, y = 0, z = 0 }, bucket = 1 },
        { id = "wrongBucket", coords = { x = 1, y = 0, z = 0 }, bucket = 2 },
        { id = "match", coords = { x = 1, y = 0, z = 0 }, bucket = 1 },
    }
    local options = {
        coordsOf = function(item) return item.coords end,
        bucketOf = function(item) return item.bucket end,
        bucket = 1,
        radius = 5,
    }

    local entry = Kora.util.nearest(list, { x = 0, y = 0, z = 0 }, options)
    harness.assertEqual(entry.id, "match", "only the in-radius, matching-bucket entry qualifies")

    local none = Kora.util.nearest({ list[1] }, { x = 0, y = 0, z = 0 }, options)
    harness.assertEqual(none, nil, "an out-of-radius entry is not a match")
end)

harness.test("rateLimiter allows up to max within a window, then blocks", function()
    local limiter = Kora.util.rateLimiter(2, 1000)

    harness.assertTrue(limiter:consume("a", 0))
    harness.assertTrue(limiter:consume("a", 100))
    local ok, retryAfter = limiter:consume("a", 200)
    harness.assertFalse(ok, "a third request within the window is blocked")
    harness.assertTrue(retryAfter > 0, "a blocked request reports a positive retry delay")
end)

harness.test("rateLimiter tracks keys independently and recovers once the window passes", function()
    local limiter = Kora.util.rateLimiter(1, 1000)

    harness.assertTrue(limiter:consume("a", 0))
    harness.assertTrue(limiter:consume("b", 0), "a different key has its own bucket")
    harness.assertFalse(limiter:consume("a", 500))
    harness.assertTrue(limiter:consume("a", 1001), "the window has fully elapsed")
end)

harness.test("worldToScreen reports normalised coordinates and on-screen state", function()
    projection.onScreen, projection.x, projection.y = true, 0.25, 0.75

    local x, y, onScreen = Kora.util.worldToScreen({ x = 1, y = 2, z = 3 })
    harness.assertEqual(x, 0.25, "x should be the native's normalised value")
    harness.assertEqual(y, 0.75, "y should be the native's normalised value")
    harness.assertTrue(onScreen, "on-screen should be reported")

    projection.onScreen = false
    local _, _, offScreen = Kora.util.worldToScreen({ x = 1, y = 2, z = 3 })
    harness.assertFalse(offScreen, "off-screen must be reported so callers can gate on it")

    projection.onScreen = true
end)

harness.test("worldToScreen rejects non-finite coordinates", function()
    harness.assertThrows(function()
        Kora.util.worldToScreen({ x = 0, y = math.huge, z = 0 })
    end)
end)

harness.test("worldToScreenPixels scales by the active resolution", function()
    projection.onScreen, projection.x, projection.y = true, 0.5, 0.5

    local x, y = Kora.util.worldToScreenPixels({ x = 0, y = 0, z = 0 })
    harness.assertEqual(x, 960, "0.5 of 1920 is 960")
    harness.assertEqual(y, 540, "0.5 of 1080 is 540")
end)

harness.report("util")
