local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/util/shared.lua")

local playerCoords = { x = 0, y = 0, z = 0 }
_G.PlayerPedId = function() return 1 end
_G.GetEntityCoords = function() return playerCoords end

-- Every text/draw-origin native is recorded as a spy call rather than
-- actually rendering anything -- there's nothing to assert visually, only
-- that the right calls happened with the right arguments in the right order.
local calls

local function spy(name)
    return function(...)
        table.insert(calls, { name = name, ... })
    end
end

for _, name in ipairs({
    "SetTextScale", "SetTextFont", "SetTextProportional", "SetTextColour",
    "SetTextCentre", "SetTextOutline", "SetTextEntry", "AddTextComponentString",
    "SetDrawOrigin", "EndTextCommandDisplayText", "ClearDrawOrigin",
}) do
    _G[name] = spy(name)
end

dofile(repoRoot .. "modules/drawing/client.lua")

local function callNamed(name)
    for _, call in ipairs(calls) do
        if call.name == name then return call end
    end
    return nil
end

harness.test("text3d skips every native call beyond maxDistance", function()
    calls = {}
    playerCoords = { x = 0, y = 0, z = 0 }

    QB.drawing.text3d({ x = 100, y = 0, z = 0 }, "too far", { maxDistance = 10.0 })

    harness.assertEqual(#calls, 0, "no drawing native should run beyond maxDistance")
end)

harness.test("text3d rejects non-finite coordinates and culling ranges", function()
    calls = {}
    harness.assertThrows(function()
        QB.drawing.text3d({ x = math.huge, y = 0, z = 0 }, "invalid")
    end, "infinite draw origins must be rejected")
    harness.assertThrows(function()
        QB.drawing.text3d({ x = 0, y = 0, z = 0 }, "invalid", { maxDistance = 0 / 0 })
    end, "NaN culling ranges must be rejected")
    harness.assertEqual(#calls, 0, "invalid drawing inputs must not run natives")
end)

harness.test("text3d validates every native option before drawing", function()
    calls = {}
    harness.assertThrows(function()
        QB.drawing.text3d({ x = 0, y = 0, z = 0 }, "invalid", { font = 1.5 })
    end)
    harness.assertThrows(function()
        QB.drawing.text3d({ x = 0, y = 0, z = 0 }, "invalid", { scale = math.huge })
    end)
    harness.assertThrows(function()
        QB.drawing.text3d({ x = 0, y = 0, z = 0 }, "invalid", { color = { r = 0, g = 0, b = 256, a = 0 } })
    end)
    harness.assertThrows(function()
        QB.drawing.text3d({ x = 0, y = 0, z = 0 }, "invalid", { outline = 'yes' })
    end)
    harness.assertThrows(function()
        QB.drawing.text3d({ x = 0, y = 0, z = 0 }, "invalid", false)
    end)
    harness.assertThrows(function()
        QB.drawing.text3d({ x = 0, y = 0, z = 0 }, "invalid", { maxDistance = false })
    end)
    harness.assertThrows(function()
        QB.drawing.text3d({ x = 0, y = 0, z = 0 }, "invalid", { font = false })
    end)
    harness.assertThrows(function()
        QB.drawing.text3d({ x = 0, y = 0, z = 0 }, "invalid", { scale = false })
    end)
    harness.assertThrows(function()
        QB.drawing.text3d({ x = 0, y = 0, z = 0 }, "invalid", { color = false })
    end)
    harness.assertEqual(#calls, 0, "invalid options must not run drawing natives")
end)

harness.test("text3d draws when within maxDistance", function()
    calls = {}
    playerCoords = { x = 0, y = 0, z = 0 }

    QB.drawing.text3d({ x = 5, y = 0, z = 0 }, "[E] Open", { maxDistance = 10.0 })

    harness.assertTrue(#calls > 0, "drawing natives should run when within range")

    local text = callNamed("AddTextComponentString")
    harness.assertTrue(text ~= nil, "AddTextComponentString should have been called")
    harness.assertEqual(text[1], "[E] Open", "the given text should be passed through")

    local origin = callNamed("SetDrawOrigin")
    harness.assertTrue(origin ~= nil, "SetDrawOrigin should have been called")
    harness.assertEqual(origin[1], 5, "SetDrawOrigin should use the given coords")
end)

harness.test("text3d draws exactly at maxDistance", function()
    calls = {}
    playerCoords = { x = 0, y = 0, z = 0 }

    QB.drawing.text3d({ x = 3, y = 4, z = 0 }, "at range", { maxDistance = 5.0 })

    harness.assertTrue(#calls > 0, "the culling boundary should remain inclusive")
end)

harness.test("text3d uses Config.drawing.text3d defaults when options is omitted", function()
    calls = {}
    playerCoords = { x = 0, y = 0, z = 0 }

    QB.drawing.text3d({ x = 1, y = 0, z = 0 }, "hello")

    local font = callNamed("SetTextFont")
    harness.assertEqual(font[1], Config.drawing.text3d.font, "font should default from config")

    local color = callNamed("SetTextColour")
    harness.assertEqual(color[1], Config.drawing.text3d.color.r, "color.r should default from config")
    harness.assertEqual(color[4], Config.drawing.text3d.color.a, "color.a should default from config")

    harness.assertTrue(callNamed("SetTextOutline") ~= nil, "outline defaults to true in config")
end)

harness.test("text3d option overrides reach the underlying natives", function()
    calls = {}
    playerCoords = { x = 0, y = 0, z = 0 }

    QB.drawing.text3d({ x = 1, y = 0, z = 0 }, "hello", {
        font = 7,
        scale = 0.9,
        color = { r = 1, g = 2, b = 3, a = 4 },
        outline = false,
    })

    harness.assertEqual(callNamed("SetTextFont")[1], 7, "an explicit font should be used as-is")
    harness.assertEqual(callNamed("SetTextScale")[1], 0.9, "an explicit scale should be used as-is")
    harness.assertEqual(callNamed("SetTextColour")[1], 1, "an explicit color should be used as-is")
    harness.assertTrue(callNamed("SetTextOutline") == nil, "outline = false should skip SetTextOutline")
end)

harness.report("drawing")
