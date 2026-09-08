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
local missionCreatorBlips = {}
local scaleformCalls = {}
local textureRequests = {}
local textureReleases = {}
local textEntryCalls = 0
local resourceKvps = { ['qblib:blips:category:31'] = '0' }
local nextBlip = 0
local frontendReady = false
local hoveringBlip = false
local selectedBlip = 0

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
function _G.SetBlipDisplay(blip, display) recordCall(blip, "display", display) end
function _G.SetBlipRoute(blip, on) recordCall(blip, "route", on) end
function _G.SetBlipRouteColour(blip, color) recordCall(blip, "routeColor", color) end
function _G.AddTextEntry(key, value)
    textEntryCalls = textEntryCalls + 1
    textEntries[key] = value
end
function _G.SetBlipAsMissionCreatorBlip(blip, enabled) missionCreatorBlips[blip] = enabled end

function _G.IsFrontendReadyForControl() return frontendReady end
function _G.IsHoveringOverMissionCreatorBlip() return hoveringBlip end
function _G.GetNewSelectedMissionCreatorBlip() return selectedBlip end
function _G.BeginScaleformMovieMethodOnFrontend(method)
    scaleformCalls[#scaleformCalls + 1] = method
    return true
end
function _G.ScaleformMovieMethodAddParamInt(_) end
function _G.ScaleformMovieMethodAddParamBool(_) end
function _G.PushScaleformMovieFunctionParameterString(_) end
function _G.EndScaleformMovieMethod() end
function _G.BeginTextCommandScaleformString(_) end
function _G.EndTextCommandScaleformString() end
function _G.RequestStreamedTextureDict(dictionary) textureRequests[#textureRequests + 1] = dictionary end
function _G.HasStreamedTextureDictLoaded(_) return true end
function _G.SetStreamedTextureDictAsNoLongerNeeded(dictionary) textureReleases[#textureReleases + 1] = dictionary end

function _G.BeginTextCommandSetBlipName(_) end
function _G.AddTextComponentSubstringPlayerName(text) _G.__lastLabelText = text end
function _G.EndTextCommandSetBlipName(blip) recordCall(blip, "label", _G.__lastLabelText) end
function _G.GetResourceKvpString(key) return resourceKvps[key] end
function _G.SetResourceKvp(key, value) resourceKvps[key] = value end

dofile(repoRoot .. "local/resources/client.lua")
dofile(repoRoot .. "modules/blips/shared.lua")
dofile(repoRoot .. "modules/blips/client.lua")

harness.test("the shared fixed catalogue returns a fresh canonical name-to-id map", function()
    local expected = {
        Other = 12,
        Bank = 13,
        Bar = 14,
        Business = 15,
        Clothing = 16,
        Convenience = 17,
        Dispatch = 18,
        Evidence = 19,
        Fuel = 20,
        Garage = 21,
        ['Gang Garage'] = 22,
        Grooming = 23,
        Hospital = 24,
        Impound = 25,
        Jewellery = 26,
        ['Job Garage'] = 27,
        Juice = 28,
        Liquor = 29,
        Mechanic = 30,
        Pharmacy = 31,
        Police = 32,
        Recycling = 33,
        Restaurant = 34,
        Scrapyard = 35,
        Tattoo = 36,
        ['Vehicle Dealer'] = 37,
        ['Vehicle Tracking'] = 38,
        Weapons = 39,
    }
    local first = QB.blips.getCategoryIds()
    local count = 0
    for name, id in pairs(expected) do
        count = count + 1
        harness.assertEqual(first[name], id, ('category %s must keep its stable id'):format(name))
    end
    local actualCount = 0
    for _ in pairs(first) do actualCount = actualCount + 1 end
    harness.assertEqual(actualCount, count, 'the shared catalogue should contain only the supported names')
    first.Other = 999
    harness.assertEqual(QB.blips.getCategoryIds().Other, 12, "callers must not mutate the shared source of truth")
end)

harness.test("creates a blip with config defaults when no options are given", function()
    local blip, err = QB.blips.create({ x = 1, y = 2, z = 3 })
    harness.assertTrue(blip ~= false, "expected a real blip handle, got error: " .. tostring(err))
    harness.assertEqual(blipCalls[blip].sprite, Config.blips.defaultSprite, "should use the default sprite")
    harness.assertEqual(blipCalls[blip].color, Config.blips.defaultColor, "should use the default color")
    harness.assertEqual(blipCalls[blip].scale, Config.blips.defaultScale, "should use the default scale")
    harness.assertEqual(blipCalls[blip].shortRange, Config.blips.defaultShortRange, "should use the default shortRange")
    harness.assertEqual(blipCalls[blip].category, 12, "uncategorized blips should use the fixed Other category")
    harness.assertEqual(blipCalls[blip].display, Config.blips.defaultDisplay, "visible blips should use the default display")
    harness.assertEqual(blipCalls[blip].label, "Other", "the default category should supply the map label")
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

harness.test("creates and renders an optional pause-map detail panel", function()
    local blip = QB.blips.create({ x = 0, y = 0, z = 0 }, {
        info = {
            title = "Abandoned Vehicle",
            money = "$2,500",
            image = { dictionary = "test_blips", texture = "vehicle" },
            rows = {
                { kind = "name", label = "Vehicle", value = "Buffalo STX" },
                { kind = "icon", label = "Difficulty", value = "Medium", icon = 18, color = 5 },
            },
        },
    })

    harness.assertTrue(missionCreatorBlips[blip], "detailed blips should be selectable in the pause map")
    harness.assertEqual(textureRequests[#textureRequests], "test_blips", "a panel image should request its texture dictionary")

    frontendReady = true
    hoveringBlip = true
    selectedBlip = blip
    net.step()

    harness.assertEqual(scaleformCalls[#scaleformCalls], "DISPLAY_DATA_SLOT",
        "hovering a detailed blip should render its data panel")

    local callsAfterFirstFrame = #scaleformCalls
    local labelsAfterFirstFrame = textEntryCalls
    net.step()
    harness.assertTrue(#scaleformCalls > callsAfterFirstFrame,
        "the detail panel should be reasserted while highlighted because the pause frontend rebuilds its columns")
    harness.assertEqual(scaleformCalls[#scaleformCalls], "DISPLAY_DATA_SLOT",
        "the refreshed detail panel should remain visible")
    harness.assertEqual(textEntryCalls, labelsAfterFirstFrame,
        "reasserting the panel should reuse its registered text entries")

    frontendReady = false
    hoveringBlip = false
    selectedBlip = 0
    local callsBeforeClose = #scaleformCalls
    net.step()
    harness.assertTrue(#scaleformCalls > callsBeforeClose,
        "closing the pause frontend should clear qblib's active detail column")
    harness.assertEqual(scaleformCalls[#scaleformCalls], "SHOW_COLUMN",
        "the scaleform column must not remain logically selected after the frontend closes")
end)

harness.test("only the owner can change or clear a blip detail panel", function()
    _G.GetInvokingResource = function() return "detail_owner" end
    local blip = QB.blips.create({ x = 0, y = 0, z = 0 })
    _G.GetInvokingResource = function() return nil end

    local ok, err = QB.blips.setInfo(blip, { title = "Not allowed" })
    harness.assertFalse(ok, "a different resource should not change blip details")
    harness.assertEqual(err, "Blip is not owned by the calling resource.", "should explain the ownership refusal")

    _G.GetInvokingResource = function() return "detail_owner" end
    ok, err = QB.blips.setInfo(blip, { title = "Allowed" })
    harness.assertTrue(ok, "the owner should be able to set blip details")
    ok, err = QB.blips.clearInfo(blip)
    harness.assertTrue(ok, "the owner should be able to clear blip details")
    harness.assertFalse(missionCreatorBlips[blip], "clearing details should make the blip non-selectable")
    _G.GetInvokingResource = function() return nil end
end)

harness.test("detail image dictionaries are retained until their final panel is cleared", function()
    local first = QB.blips.create({ x = 0, y = 0, z = 0 }, {
        info = { title = "First", image = { dictionary = "shared_blip_image", texture = "first" } },
    })
    local second = QB.blips.create({ x = 1, y = 1, z = 1 }, {
        info = { title = "Second", image = { dictionary = "shared_blip_image", texture = "second" } },
    })
    local releasesBefore = #textureReleases

    harness.assertTrue(QB.blips.clearInfo(first))
    harness.assertEqual(#textureReleases, releasesBefore,
        "a shared dictionary should remain loaded while another panel uses it")
    harness.assertTrue(QB.blips.clearInfo(second))
    harness.assertEqual(textureReleases[#textureReleases], "shared_blip_image",
        "the final panel should release its texture dictionary")
end)

harness.test("fixed categories and legacy aliases resolve to stable native ids", function()
    local first = QB.blips.create({ x = 0, y = 0, z = 0 }, { category = "Ammu-Nation" })
    local second = QB.blips.create({ x = 1, y = 1, z = 1 }, { category = " weapons " })
    local third = QB.blips.create({ x = 2, y = 2, z = 2 }, { category = "Clothing Store" })

    harness.assertEqual(blipCalls[first].category, 39,
        "the Ammu-Nation alias should use Weapons' fixed id")
    harness.assertEqual(blipCalls[second].category, blipCalls[first].category,
        "category matching should be trimmed and case-insensitive")
    harness.assertEqual(blipCalls[third].category, 16,
        "the Clothing Store alias should use Clothing's fixed id")
    harness.assertEqual(textEntries.BLIP_CAT_39, "Weapons",
        "the fixed category should register its canonical legend label")
end)

harness.test("unknown named categories fail clearly while numeric categories remain compatible", function()
    harness.assertThrows(function()
        QB.blips.create({ x = 0, y = 0, z = 0 }, { category = "Typo Category" })
    end, "unknown category strings should fail instead of silently changing the registry")

    local blip = QB.blips.create({ x = 0, y = 0, z = 0 }, { category = 7, name = "Legacy" })
    harness.assertEqual(blipCalls[blip].category, 7, "numeric native categories should pass through")
    harness.assertEqual(blipCalls[blip].label, "Category 7: Legacy", "numeric categories should still get a useful label")
end)

harness.test("name builds a normalized category label and explicit label remains an override", function()
    local named = QB.blips.create({ x = 0, y = 0, z = 0 }, {
        category = "Garage", name = "  Alta   Street  ",
    })
    local same = QB.blips.create({ x = 0, y = 0, z = 0 }, {
        category = "Garage", name = "garage",
    })
    local legacy = QB.blips.create({ x = 0, y = 0, z = 0 }, {
        label = "  Legacy   Marker  ",
    })

    harness.assertEqual(blipCalls[named].label, "Garage: Alta Street")
    harness.assertEqual(blipCalls[same].label, "Garage")
    harness.assertEqual(blipCalls[legacy].label, "Legacy Marker",
        "an explicit legacy label should not be prefixed with Other")
end)

harness.test("category and registered snapshots expose stable UI metadata", function()
    local blip = QB.blips.create({ x = 3, y = 4, z = 5 }, {
        category = "Bank", name = "Pacific Standard", sprite = 108, color = 2, display = 6,
    })
    local category = QB.blips.getCategory(" bank ")
    harness.assertEqual(category.key, "Bank")
    harness.assertEqual(category.name, "Bank")
    harness.assertEqual(category.label, "Bank")
    harness.assertEqual(category.id, 13)
    harness.assertTrue(category.visible)
    harness.assertEqual(category.count, 1)

    local categories = QB.blips.getCategories()
    harness.assertEqual(categories[1].id, 12, "the fixed catalogue should be returned in id order")
    harness.assertEqual(categories[#categories].id, 39)
    local registered = QB.blips.getRegistered()
    local found
    for _, record in ipairs(registered) do
        if record.handle == blip then found = record; break end
    end
    harness.assertTrue(found ~= nil, "the native handle should remain visible in the registry")
    harness.assertEqual(found.resource, GetCurrentResourceName())
    harness.assertEqual(found.category, 13)
    harness.assertEqual(found.categoryKey, "Bank")
    harness.assertEqual(found.name, "Pacific Standard")
    harness.assertEqual(found.label, "Bank: Pacific Standard")
    harness.assertEqual(found.sprite, 108)
    harness.assertEqual(found.color, 2)
    harness.assertEqual(found.display, 6)
end)

harness.test("category visibility persists, hides routes, and restores each configured display", function()
    local routed = QB.blips.create({ x = 0, y = 0, z = 0 }, {
        category = "Vehicle Tracking", name = "Suspect", display = 5, route = true, color = 6,
    })

    harness.assertTrue(QB.blips.hideCategory("vehicle tracking"))
    harness.assertFalse(QB.blips.isCategoryVisible("Vehicle Tracking"))
    harness.assertEqual(resourceKvps["qblib:blips:category:38"], "0", "the hidden preference should be persisted")
    harness.assertEqual(blipCalls[routed].display, 0)
    harness.assertEqual(blipCalls[routed].route, false, "a hidden category must not leave a route line behind")

    local later = QB.blips.create({ x = 1, y = 1, z = 1 }, {
        category = "Vehicle Tracking", name = "Later", display = 8,
    })
    harness.assertEqual(blipCalls[later].display, 0, "new blips should honor the persisted category state")

    harness.assertTrue(QB.blips.showCategory("Vehicle Tracking"))
    harness.assertEqual(resourceKvps["qblib:blips:category:38"], "1")
    harness.assertEqual(blipCalls[routed].display, 5, "show should restore the first configured display")
    harness.assertEqual(blipCalls[later].display, 8, "show should restore each blip's own configured display")
    harness.assertEqual(blipCalls[routed].route, true, "show should restore the configured route")
    harness.assertEqual(blipCalls[routed].routeColor, 6, "show should restore its route color")
end)

harness.test("a saved category preference applies before the first blip is created", function()
    local blip = QB.blips.create({ x = 0, y = 0, z = 0 }, {
        category = 'Pharmacy', display = 9, route = true, color = 3,
    })

    harness.assertFalse(QB.blips.isCategoryVisible('Pharmacy'))
    harness.assertEqual(blipCalls[blip].display, 0)
    harness.assertEqual(blipCalls[blip].route, false)
    QB.blips.showCategory('Pharmacy')
    harness.assertEqual(blipCalls[blip].display, 9)
    harness.assertEqual(blipCalls[blip].route, true)
end)

harness.test("individual hide/show respects a hidden category", function()
    local blip = QB.blips.create({ x = 0, y = 0, z = 0 }, { category = "Fuel", display = 3 })
    harness.assertTrue(QB.blips.hide(blip))
    harness.assertEqual(blipCalls[blip].display, 0)
    harness.assertTrue(QB.blips.show(blip))
    harness.assertEqual(blipCalls[blip].display, 3)

    QB.blips.hideCategory("Fuel")
    QB.blips.hide(blip)
    QB.blips.show(blip)
    harness.assertEqual(blipCalls[blip].display, 0,
        "showing one blip must not override the player's hidden category preference")
    QB.blips.showCategory("Fuel")
    harness.assertEqual(blipCalls[blip].display, 3)
end)

harness.test("remove deletes a tracked blip", function()
    local blip = QB.blips.create({ x = 0, y = 0, z = 0 })
    local ok = QB.blips.remove(blip)
    harness.assertTrue(ok, "remove should report success")
    harness.assertFalse(_G.DoesBlipExist(blip), "the blip should no longer exist after remove")
    harness.assertEqual(missionCreatorBlips[blip], nil, "remove should discard the detail panel state")
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
    for _, record in ipairs(QB.blips.getRegistered()) do
        harness.assertTrue(record.handle ~= blip, "resource cleanup should remove the registry snapshot too")
    end
end)

harness.report("blips")
