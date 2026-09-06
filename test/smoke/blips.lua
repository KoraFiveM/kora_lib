local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")

local existingBlips = {}
local blipCalls = {}
local textEntries = {}
local nextBlip = 0

local function recordCall(blip, key, value)
    blipCalls[blip] = blipCalls[blip] or {}
    blipCalls[blip][key] = value
end

function _G.AddBlipForCoord(x, y, z)
    nextBlip = nextBlip + 1
    existingBlips[nextBlip] = true
    blipCalls[nextBlip] = { coords = { x = x, y = y, z = z } }
    return nextBlip
end

function _G.DoesBlipExist(blip) return existingBlips[blip] == true end
function _G.RemoveBlip(blip) existingBlips[blip] = nil end

function _G.SetBlipSprite(blip, sprite) recordCall(blip, "sprite", sprite) end
function _G.SetBlipColour(blip, color) recordCall(blip, "color", color) end
function _G.SetBlipScale(blip, scale) recordCall(blip, "scale", scale) end
function _G.SetBlipAsShortRange(blip, on) recordCall(blip, "shortRange", on) end
function _G.SetBlipCategory(blip, category) recordCall(blip, "category", category) end
function _G.SetBlipRoute(blip, on) recordCall(blip, "route", on) end
function _G.SetBlipRouteColour(blip, color) recordCall(blip, "routeColor", color) end
function _G.AddTextEntry(key, value) textEntries[key] = value end

function _G.BeginTextCommandSetBlipName(_) end
function _G.AddTextComponentSubstringPlayerName(text) _G.__lastLabelText = text end
function _G.EndTextCommandSetBlipName(blip) recordCall(blip, "label", _G.__lastLabelText) end

dofile(repoRoot .. "local/resources/client.lua")
dofile(repoRoot .. "modules/blips/client.lua")

harness.test("creates a blip with config defaults when no options are given", function()
    local blip, err = QB.blips.create({ x = 1, y = 2, z = 3 })
    harness.assertTrue(blip ~= false, "expected a real blip handle, got error: " .. tostring(err))
    harness.assertEqual(blipCalls[blip].sprite, Config.blips.defaultSprite, "should use the default sprite")
    harness.assertEqual(blipCalls[blip].color, Config.blips.defaultColor, "should use the default color")
    harness.assertEqual(blipCalls[blip].scale, Config.blips.defaultScale, "should use the default scale")
    harness.assertEqual(blipCalls[blip].shortRange, Config.blips.defaultShortRange, "should use the default shortRange")
end)

harness.test("creates a blip honoring every explicit option", function()
    local blip = QB.blips.create({ x = 0, y = 0, z = 0 }, {
        sprite = 42,
        color = 5,
        scale = 2.0,
        shortRange = false,
        category = 7,
        label = "Test Blip",
        route = true,
    })

    harness.assertEqual(blipCalls[blip].sprite, 42, "sprite should match the explicit option")
    harness.assertEqual(blipCalls[blip].color, 5, "color should match the explicit option")
    harness.assertEqual(blipCalls[blip].scale, 2.0, "scale should match the explicit option")
    harness.assertEqual(blipCalls[blip].shortRange, false, "shortRange should match the explicit option")
    harness.assertEqual(blipCalls[blip].category, 7, "category should match the explicit option")
    harness.assertEqual(blipCalls[blip].label, "Test Blip", "label should match the explicit option")
    harness.assertEqual(blipCalls[blip].route, true, "route should be enabled")
    harness.assertEqual(blipCalls[blip].routeColor, 5, "route color should match the explicit color option")
end)

harness.test("route without an explicit color does not set a route color", function()
    local blip = QB.blips.create({ x = 0, y = 0, z = 0 }, { route = true })
    harness.assertEqual(blipCalls[blip].route, true, "route should still be enabled")
    harness.assertEqual(blipCalls[blip].routeColor, nil, "route color should be left unset without an explicit color")
end)

harness.test("groups matching named categories under one custom legend entry", function()
    local first = QB.blips.create({ x = 0, y = 0, z = 0 }, { category = "Ammu-Nation" })
    local second = QB.blips.create({ x = 1, y = 1, z = 1 }, { category = "Ammu-Nation" })
    local third = QB.blips.create({ x = 2, y = 2, z = 2 }, { category = "Clothing Store" })

    harness.assertEqual(blipCalls[first].category, Config.blips.namedCategoryStart,
        "the first named category should use the start of GTA's custom range")
    harness.assertEqual(blipCalls[second].category, blipCalls[first].category,
        "matching category names should share one legend group")
    harness.assertEqual(blipCalls[third].category, Config.blips.namedCategoryStart + 1,
        "a different category name should get a different legend group")
    harness.assertEqual(textEntries["BLIP_CAT_" .. Config.blips.namedCategoryStart], "Ammu-Nation",
        "the custom category should have a visible legend label")
end)

harness.test("remove deletes a tracked blip", function()
    local blip = QB.blips.create({ x = 0, y = 0, z = 0 })
    local ok = QB.blips.remove(blip)
    harness.assertTrue(ok, "remove should report success")
    harness.assertFalse(_G.DoesBlipExist(blip), "the blip should no longer exist after remove")
end)

harness.test("remove reports failure for an already-removed blip", function()
    local blip = QB.blips.create({ x = 0, y = 0, z = 0 })
    QB.blips.remove(blip)
    local ok, err = QB.blips.remove(blip)
    harness.assertFalse(ok, "removing twice should fail the second time")
    harness.assertEqual(err, "Blip is not tracked by QB.blips.", "should explain why removal failed")
end)

harness.test("remove refuses a blip this module never created", function()
    local foreignBlip = 424242
    existingBlips[foreignBlip] = true

    local ok, err = QB.blips.remove(foreignBlip)

    harness.assertFalse(ok, "an untracked blip must be refused, not removed")
    harness.assertEqual(err, "Blip is not tracked by QB.blips.", "should explain the refusal")
    harness.assertTrue(_G.DoesBlipExist(foreignBlip), "the foreign blip must still exist")

    existingBlips[foreignBlip] = nil
end)

harness.test("blips are auto-removed when their owning resource stops", function()
    _G.GetInvokingResource = function() return "some_other_resource" end
    local blip = QB.blips.create({ x = 0, y = 0, z = 0 })
    _G.GetInvokingResource = function() return nil end

    harness.assertTrue(_G.DoesBlipExist(blip), "the blip should exist before its resource stops")

    net.fire("onClientResourceStop", "some_other_resource")

    harness.assertFalse(_G.DoesBlipExist(blip), "the blip should be removed once its owning resource stops")
end)

harness.report("blips")
