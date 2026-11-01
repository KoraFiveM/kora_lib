local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/util/shared.lua")

-- The mock player starts at the origin. ensureTickThread only ever
-- starts one CreateThread for the life of the module, and our CreateThread
-- mock resumes it exactly once -- so only the very first zone created below
-- (the box at the origin) actually gets ticked; later zones are checked via
-- their pure `contains` function instead.
_G.PlayerPedId = function() return 1 end
local playerCoords = { x = 0, y = 0, z = 0 }
_G.GetEntityCoords = function() return playerCoords end
_G.GetEntitySpeed = function() return 0.0 end
local drawLineCalls = 0
local drawMarkerCalls = 0
local drawPolyCalls = 0

_G.DrawLine = function() drawLineCalls = drawLineCalls + 1 end
_G.DrawMarker = function() drawMarkerCalls = drawMarkerCalls + 1 end
_G.DrawPoly = function() drawPolyCalls = drawPolyCalls + 1 end

-- The zone creator's own natives. Placement now goes through the real
-- Kora.raycast.fromCamera (modules/raycast), so these are dofile'd here too --
-- the mock player/camera never moves and nothing is ever aimed at, so the
-- ray consistently misses (hit = 0), enough for the creator's startup/guard
-- behavior below without needing a real hit-testing simulation.
-- `registeredCommands` captures every RegisterCommand handler by name so a
-- test can drive the creator the same way a keybind would (see the cancel
-- call at the end of the guard test).
local registeredCommands = {}
_G.RegisterCommand = function(name, handler) registeredCommands[name] = handler end
_G.RegisterKeyMapping = function() end
Kora.keybind = {
    add = function(options)
        registeredCommands[options.name] = options.onPressed
        return { name = options.name, remove = function() return true end }
    end,
}
local placementActive = false
Kora.placement = {
    isActive = function() return placementActive end,
}
_G.GetGameplayCamCoord = function() return { x = 0, y = 0, z = 0 } end
_G.GetGameplayCamRot = function() return { x = 0, y = 0, z = 0 } end
_G.StartShapeTestRay = function() return 1 end
_G.GetShapeTestResult = function() return 2, 0, { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }, 0 end
_G.IsControlJustPressed = function() return false end
_G.IsControlPressed = function() return false end
_G.CreateCamWithParams = function() return 1 end
_G.DoesCamExist = function() return true end
_G.SetCamActive = function() end
_G.RenderScriptCams = function() end
_G.DestroyCam = function() end
_G.FreezeEntityPosition = function() end
local disabledControls = {}
_G.DisableControlAction = function(group, control)
    disabledControls[("%d:%d"):format(group, control)] = true
end
_G.PlayerId = function() return 1 end
_G.DisablePlayerFiring = function() end
_G.GetDisabledControlNormal = function() return 0.0 end
_G.IsDisabledControlPressed = function() return false end
_G.GetFrameTime = function() return 0.0 end
_G.GetGameplayCamFov = function() return 50.0 end
_G.SetCamCoord = function() end
_G.SetCamRot = function() end
_G.GetCamCoord = function() return { x = 0, y = 0, z = 0 } end
_G.GetCamRot = function() return { x = 0, y = 0, z = 0 } end
_G.RequestScaleformMovie = function() return 1 end
_G.HasScaleformMovieLoaded = function() return true end
_G.SetScaleformMovieAsNoLongerNeeded = function() end
_G.BeginScaleformMovieMethod = function() end
_G.EndScaleformMovieMethod = function() end
_G.ScaleformMovieMethodAddParamInt = function() end
_G.BeginTextCommandScaleformString = function() end
_G.AddTextComponentSubstringPlayerName = function() end
_G.EndTextCommandScaleformString = function() end
_G.DrawScaleformMovieFullscreen = function() end
_G.GetControlInstructionalButton = function() return 't_mock' end
-- Recorded rather than ignored: hiding the minimap during placement is only
-- correct if it's also restored on teardown, and a creator that leaves a
-- player with no map is exactly the kind of thing that goes unnoticed in a
-- manual test.
local radarCalls = {}
local radarHidden = false
_G.IsRadarHidden = function() return radarHidden end
_G.DisplayRadar = function(shown)
    radarCalls[#radarCalls + 1] = shown
    radarHidden = not shown
end

dofile(repoRoot .. "modules/raycast/client.lua")
dofile(repoRoot .. "local/resources/client.lua")
dofile(repoRoot .. "modules/controls/client.lua")
dofile(repoRoot .. "modules/freecam/client.lua")
dofile(repoRoot .. "modules/instructional/client.lua")
-- Kora.theme isn't otherwise loaded by this test file -- the debug/creator-preview
-- draw path now reads Kora.theme.accentColor() (see zoneDebugColor in
-- modules/zones/client.lua), and without this the Kora proxy in build/initiate.lua
-- would auto-vivify Kora.theme as an empty table, leaving accentColor nil.
_G.exports = { kora_theme = { getPrimaryColor = function() return "#95FF00" end } }
dofile(repoRoot .. "modules/theme/shared.lua")
dofile(repoRoot .. "modules/zones/client.lua")

-- Real Kora.nui isn't loaded here (that's modules/nui's own smoke test) -- the
-- creator only needs somewhere to send/request against, so this is a minimal
-- stand-in rather than the full request/response bridge. `nextNuiResponse`
-- lets a test drive the confirm dialog to a specific outcome: since the mock
-- Citizen.Await only supports an already-settled promise (see mocks.lua), the
-- response has to be resolved synchronously, before Kora.nui.request returns.
local nextNuiResponse = nil
Kora.nui = {
    send = function() end,
    request = function()
        local p = promise.new()
        if nextNuiResponse ~= nil then p:resolve(nextNuiResponse) end
        return p
    end,
    withFocus = function(_, _, fn) return fn() end,
}

harness.test("box zone contains points inside it and is entered by the first tick", function()
    local insideFromEnter
    local zone = Kora.zones.box({
        coords = { x = 0, y = 0, z = 0 },
        size = { x = 10, y = 10, z = 10 },
        onEnter = function()
            insideFromEnter = Kora.zones.getInside()[1]
        end,
    })

    harness.assertTrue(zone.contains({ x = 0, y = 0, z = 0 }), "the zone's own center should be inside it")
    harness.assertFalse(zone.contains({ x = 100, y = 100, z = 0 }), "a far point should be outside the box")
    harness.assertTrue(zone.isInside(), "the mock player sits at the zone's center, so the first tick should enter it")
    harness.assertEqual(insideFromEnter, zone, "onEnter should see its stable public handle immediately")

    zone.remove()
end)

harness.test("box zone can intentionally ignore elevation", function()
    local entered = 0
    playerCoords = { x = 100, y = 100, z = 99999 }
    local zone = Kora.zones.box({
        coords = { x = 100, y = 100, z = 0 },
        size = { x = 10, y = 10, z = 2 },
        ignoreZ = true,
        onEnter = function() entered = entered + 1 end,
    })

    harness.assertTrue(zone.contains({ x = 100, y = 100, z = 99999 }), "an elevation-free box must ignore Z")
    harness.assertFalse(zone.contains({ x = 106, y = 100, z = 0 }), "an elevation-free box must keep its XY bounds")
    net.step()
    harness.assertTrue(zone.isInside(), "the shared grid must not reject an elevation-free box by Z")
    harness.assertEqual(entered, 1, "an elevation-free box should enter once at any elevation")
    zone.remove()
    playerCoords = { x = 0, y = 0, z = 0 }
end)

harness.test("sphere zone contains points within its radius", function()
    local zone = Kora.zones.sphere({ coords = { x = 100, y = 100, z = 0 }, radius = 5 })

    harness.assertTrue(zone.contains({ x = 100, y = 100, z = 0 }), "the sphere's center should be inside it")
    harness.assertFalse(zone.contains({ x = 200, y = 200, z = 0 }), "a far point should be outside the sphere")

    zone.remove()
end)

harness.test("circle zone has an exact 2D boundary and ignores elevation", function()
    local entered = 0
    playerCoords = { x = 100, y = 100, z = 99999 }
    local zone = Kora.zones.circle({
        coords = { x = 100, y = 100, z = 0 },
        radius = 5,
        onEnter = function() entered = entered + 1 end,
    })

    harness.assertTrue(zone.contains({ x = 103, y = 104, z = 99999 }), "a flat circle must ignore Z, including far elevations")
    harness.assertTrue(zone.contains({ x = 105, y = 100, z = -99999 }), "points exactly on the radius must be inside")
    harness.assertFalse(zone.contains({ x = 105.01, y = 100, z = 0 }), "points beyond the radius must be outside")
    net.step()
    harness.assertTrue(zone.isInside(), "the shared grid must not reject a flat circle by elevation")
    harness.assertEqual(entered, 1, "the exact flat circle should enter once at any elevation")

    zone.remove()
    playerCoords = { x = 0, y = 0, z = 0 }
end)

harness.test("circle and sphere zones can exclude their boundary", function()
    local circle = Kora.zones.circle({ coords = { x = 0, y = 0, z = 0 }, radius = 5, includeBoundary = false })
    local sphere = Kora.zones.sphere({ coords = { x = 20, y = 0, z = 0 }, radius = 5, includeBoundary = false })

    harness.assertFalse(circle.contains({ x = 5, y = 0, z = 99999 }), "an exclusive circle must reject its exact radius")
    harness.assertTrue(circle.contains({ x = 4.99, y = 0, z = 0 }), "an exclusive circle must retain points inside its radius")
    harness.assertFalse(sphere.contains({ x = 25, y = 0, z = 0 }), "an exclusive sphere must reject its exact radius")

    circle.remove()
    sphere.remove()
end)

harness.test("predicate-only zones retain contains without entering the player tracker", function()
    local entered = 0
    local zone = Kora.zones.box({
        coords = { x = 0, y = 0, z = 0 },
        size = { x = 4, y = 4, z = 4 },
        trackPlayer = false,
        onEnter = function() entered = entered + 1 end,
    })

    harness.assertTrue(zone.contains({ x = 0, y = 0, z = 0 }),
        "predicate-only zones must retain exact containment")
    net.step()
    harness.assertEqual(entered, 0, "predicate-only zones must not run player enter callbacks")
    harness.assertFalse(zone.isInside(), "predicate-only zones must never enter player-tracked state")
    zone.remove()
end)

harness.test("trackPlayer requires a boolean", function()
    harness.assertThrows(function()
        Kora.zones.sphere({ coords = { x = 0, y = 0, z = 0 }, radius = 2, trackPlayer = "no" })
    end, "invalid trackPlayer values should be rejected")
end)

harness.test("poly zone respects both its footprint and its height band", function()
    local zone = Kora.zones.poly({
        points = {
            { x = 0,  y = 0,  z = 0 },
            { x = 10, y = 0,  z = 0 },
            { x = 0,  y = 10, z = 0 },
        },
    })

    harness.assertTrue(zone.contains({ x = 2, y = 2, z = 0 }), "a point inside the footprint and height band should be contained")
    harness.assertFalse(zone.contains({ x = 20, y = 20, z = 0 }), "a point outside the footprint should not be contained")
    harness.assertFalse(zone.contains({ x = 2, y = 2, z = 10 }), "a point above the height band should not be contained")

    zone.remove()
end)

harness.test("poly zone can intentionally ignore elevation", function()
    local zone = Kora.zones.poly({
        points = {
            { x = 100, y = 100, z = 0 },
            { x = 110, y = 100, z = 0 },
            { x = 100, y = 110, z = 0 },
        },
        ignoreZ = true,
    })

    harness.assertTrue(zone.contains({ x = 102, y = 102, z = 99999 }), "an elevation-free poly must ignore Z")
    harness.assertFalse(zone.contains({ x = 120, y = 120, z = 0 }), "an elevation-free poly must keep its XY footprint")
    zone.remove()
end)

harness.test("poly zone rejects sparse point arrays before creation", function()
    harness.assertThrows(function()
        Kora.zones.poly({
            points = {
                { x = 0, y = 0, z = 0 },
                { x = 1, y = 0, z = 0 },
                [4] = { x = 0, y = 1, z = 0 },
            },
        })
    end)
end)

harness.test("poly thickness extends upward from the lowest point, not centred on the average", function()
    -- Deliberately sloped: the lowest point is at z=0 and the highest at z=6,
    -- so an average-centred band (the old behaviour) would have run from z=1
    -- to z=5 -- leaving the ground at the lowest corner OUTSIDE its own zone,
    -- and burying the bottom half of the zone under the hill at the high end.
    local zone = Kora.zones.poly({
        points = {
            { x = 0,  y = 0,  z = 0 },
            { x = 10, y = 0,  z = 3 },
            { x = 0,  y = 10, z = 6 },
        },
        thickness = 4,
    })

    harness.assertTrue(zone.contains({ x = 2, y = 2, z = 0 }),
        "the lowest point's own ground level must be inside the zone")
    harness.assertTrue(zone.contains({ x = 2, y = 2, z = 4 }),
        "the top of the band should sit exactly thickness above the lowest point")
    harness.assertFalse(zone.contains({ x = 2, y = 2, z = -0.5 }),
        "nothing below the lowest point should be contained -- the band must not be centred")
    harness.assertFalse(zone.contains({ x = 2, y = 2, z = 4.5 }),
        "anything above lowest + thickness should be outside")

    zone.remove()
end)

harness.test("explicit minZ/maxZ still override thickness anchoring", function()
    local zone = Kora.zones.poly({
        points = {
            { x = 0,  y = 0,  z = 0 },
            { x = 10, y = 0,  z = 0 },
            { x = 0,  y = 10, z = 0 },
        },
        thickness = 4,
        minZ = 20,
        maxZ = 25,
    })

    harness.assertFalse(zone.contains({ x = 2, y = 2, z = 0 }), "ground level is outside an explicitly floating band")
    harness.assertTrue(zone.contains({ x = 2, y = 2, z = 22 }), "a point inside the explicit band should be contained")

    zone.remove()
end)

harness.test("point zone is a small-radius sphere", function()
    local opts = { coords = { x = 50, y = 50, z = 0 } }
    local zone = Kora.zones.point(opts)

    harness.assertEqual(zone.type, "sphere", "a point zone should be a sphere under the hood")
    harness.assertTrue(zone.contains({ x = 50.5, y = 50, z = 0 }), "a point just inside the default radius should be contained")
    harness.assertFalse(zone.contains({ x = 52, y = 50, z = 0 }), "a point well outside the default radius should not be contained")
    harness.assertEqual(opts.radius, nil, "point defaults must not mutate caller options")

    zone.remove()
end)

harness.test("point zone only defaults an omitted radius", function()
    harness.assertThrows(function()
        Kora.zones.point({ coords = { x = 0, y = 0, z = 0 }, radius = false })
    end)
end)

harness.test("zones get unique ids", function()
    local a = Kora.zones.sphere({ coords = { x = 0, y = 0, z = 0 }, radius = 1 })
    local b = Kora.zones.sphere({ coords = { x = 0, y = 0, z = 0 }, radius = 1 })

    harness.assertTrue(a.id ~= b.id, "two zones should never share an id")

    a.remove()
    b.remove()
end)

harness.test("box zone requires coords and size", function()
    harness.assertThrows(function()
        Kora.zones.box({})
    end, "a box zone with no coords/size should raise")
end)

harness.test("zone geometry rejects non-finite values before entering the spatial grid", function()
    harness.assertThrows(function()
        Kora.zones.box({ coords = "not coordinates", size = { x = 1, y = 1, z = 1 } })
    end, "non-vector coordinates should raise kora_lib's public contract error")
    harness.assertThrows(function()
        Kora.zones.box({ coords = { x = math.huge, y = 0, z = 0 }, size = { x = 1, y = 1, z = 1 } })
    end)
    harness.assertThrows(function()
        Kora.zones.sphere({ coords = { x = 0, y = 0, z = 0 }, radius = math.huge })
    end)
    harness.assertThrows(function()
        Kora.zones.circle({ coords = { x = 0, y = 0, z = 0 }, radius = 0 })
    end)
    harness.assertThrows(function()
        Kora.zones.circle({ coords = { x = 0, y = 0, z = 0 }, radius = 1, includeBoundary = "no" })
    end)
    harness.assertThrows(function()
        Kora.zones.box({ coords = { x = 0, y = 0, z = 0 }, size = { x = 1, y = 1, z = 1 }, ignoreZ = "no" })
    end)
    harness.assertThrows(function()
        Kora.zones.poly({ points = { { x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 }, { x = 0, y = 1, z = 0 } }, ignoreZ = "no" })
    end)
    harness.assertThrows(function()
        Kora.zones.poly({
            points = { { x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 }, { x = 0, y = 1, z = 0 } },
            minZ = 0 / 0, maxZ = 2,
        })
    end)

    local zone = Kora.zones.sphere({ coords = { x = 50, y = 50, z = 0 }, radius = 1 })
    harness.assertThrows(function() zone.contains(false) end,
        "contains should reject malformed coordinates with the same contract")
    zone.remove()
end)

harness.test("removing a zone twice is a harmless no-op", function()
    local zone = Kora.zones.sphere({ coords = { x = 0, y = 0, z = 0 }, radius = 1 })
    zone.remove()
    zone.remove()
end)

harness.test("getInside reports the zones the player is currently standing in", function()
    harness.assertEqual(#Kora.zones.getInside(), 0, "nothing should be inside before any zone exists here")

    -- The mock player sits at the origin: the box contains it, the sphere is
    -- far away. net.step() advances the (already-running) tick loop one more
    -- iteration so enter/exit tracking sees these newly created zones.
    local zone = Kora.zones.box({ coords = { x = 0, y = 0, z = 0 }, size = { x = 10, y = 10, z = 10 } })
    local far = Kora.zones.sphere({ coords = { x = 500, y = 500, z = 0 }, radius = 2 })
    net.step()

    local inside = Kora.zones.getInside()
    harness.assertEqual(#inside, 1, "only the zone containing the player should be reported")
    harness.assertEqual(inside[1], zone, "getInside should hand back the very same handle the constructor returned")

    harness.assertEqual(#Kora.zones.getInside("kora_lib_test"), 1, "filtering by the owning resource should still match")
    harness.assertEqual(#Kora.zones.getInside("some_other_resource"), 0, "filtering by a different resource should match nothing")

    zone.remove()
    far.remove()
    harness.assertEqual(#Kora.zones.getInside(), 0, "a removed zone should drop out of getInside")
end)

harness.test("getInside rejects a non-string resource filter", function()
    harness.assertThrows(function() Kora.zones.getInside(42) end, "a numeric resource filter should raise")
end)

harness.test("setDebug requires a finite integer zone id", function()
    harness.assertThrows(function() Kora.zones.setDebug(1.5, true) end)
    harness.assertThrows(function() Kora.zones.setDebug(math.huge, true) end)
end)

harness.test("Kora.zones.edit moves a box zone's coords, updating containment and the grid", function()
    local zone = Kora.zones.box({ coords = { x = 300, y = 300, z = 0 }, size = { x = 10, y = 10, z = 10 } })

    harness.assertTrue(zone.contains({ x = 300, y = 300, z = 0 }), "the zone should start at its original coords")
    harness.assertFalse(zone.contains({ x = 0, y = 0, z = 0 }), "the zone should not yet contain the origin")

    local result = Kora.zones.edit(zone, { coords = { x = 0, y = 0, z = 0 } })
    harness.assertEqual(result, zone, "edit should return the same handle it was given")

    harness.assertTrue(zone.contains({ x = 0, y = 0, z = 0 }), "contains() should reflect the new coords")
    harness.assertFalse(zone.contains({ x = 300, y = 300, z = 0 }), "contains() should no longer match the old coords")

    -- The mock player sits at the origin. isInside() only flips true if the
    -- zone was actually reinserted into the grid at its new position -- the
    -- tick loop's candidate search is grid-cell based, not a full scan -- so
    -- this proves the grid was updated, not just zone.coords/aabb.
    net.step()
    harness.assertTrue(zone.isInside(), "the zone should now be tracked as containing the player at its new position")

    zone.remove()
end)

harness.test("Kora.zones.edit rejects poly zone coords edits", function()
    local zone = Kora.zones.poly({
        points = {
            { x = 0,  y = 0,  z = 0 },
            { x = 10, y = 0,  z = 0 },
            { x = 0,  y = 10, z = 0 },
        },
    })

    harness.assertThrows(function() Kora.zones.edit(zone, { coords = { x = 1, y = 1, z = 0 } }) end,
        "poly zones should reject a coords edit")

    harness.assertTrue(zone.contains({ x = 2, y = 2, z = 0 }), "the poly's containment should be unaffected by the rejected edit")

    zone.remove()
end)

harness.test("Kora.zones.edit can attach onEnter/onExit to a zone, and false detaches them", function()
    local zone = Kora.zones.sphere({ coords = { x = 300, y = 300, z = 0 }, radius = 5 })
    local enterCount, exitCount = 0, 0

    Kora.zones.edit(zone, {
        onEnter = function() enterCount = enterCount + 1 end,
        onExit = function() exitCount = exitCount + 1 end,
    })

    Kora.zones.edit(zone, { coords = { x = 0, y = 0, z = 0 } }) -- move it onto the player
    net.step()
    harness.assertEqual(enterCount, 1, "the newly attached onEnter should fire once the player is inside")

    Kora.zones.edit(zone, { onExit = false }) -- detach onExit while still inside

    -- Move it just outside its own radius, but still within the same grid
    -- cell as the player so this specifically covers detaching the callback.
    Kora.zones.edit(zone, { coords = { x = 20, y = 0, z = 0 } })
    net.step()
    harness.assertFalse(zone.isInside(), "the zone should be tracked as exited even with no onExit callback attached")
    harness.assertEqual(exitCount, 0, "onExit was detached, so it must not fire")
    harness.assertEqual(enterCount, 1, "detaching onExit must not affect the already-attached onEnter")

    zone.remove()
end)

harness.test("leaving a grid neighbourhood still fires onExit and clears isInside", function()
    local exits = 0
    local zone = Kora.zones.sphere({
        coords = { x = 0, y = 0, z = 0 }, radius = 5,
        onExit = function() exits = exits + 1 end,
    })

    net.step()
    harness.assertTrue(zone.isInside(), "the player should enter before moving away")

    playerCoords = { x = 500, y = 500, z = 0 }
    net.step()
    playerCoords = { x = 0, y = 0, z = 0 }

    harness.assertFalse(zone.isInside(), "a far move must clear stale inside state")
    harness.assertEqual(exits, 1, "a far move must still deliver exactly one exit callback")
    zone.remove()
end)

-- The tick memoises its 3x3 candidate scan, since the answer only changes when
-- the player crosses a cell boundary or the grid itself does. That cache is
-- keyed off a grid epoch, and these are the three ways the grid can move under
-- it: a zone appearing, a zone being destroyed, and a zone being relocated.
-- Get the invalidation wrong and a newly created zone is invisible until the
-- player happens to walk into a different cell and back.
harness.test("a zone created after the candidate cache was warmed is still seen", function()
    local warm = Kora.zones.sphere({ coords = { x = 0, y = 0, z = 0 }, radius = 5 })
    net.step() -- warms the candidate cache for the player's cell

    local entered = 0
    local late = Kora.zones.sphere({
        coords = { x = 0, y = 0, z = 0 },
        radius = 5,
        onEnter = function() entered = entered + 1 end,
    })

    net.step()
    harness.assertEqual(entered, 1, "a zone created after the cache was warmed must still be ticked")
    harness.assertTrue(late.isInside(), "and must be tracked as entered")

    late.remove()
    net.step()
    harness.assertTrue(warm.isInside(), "removing one zone must not disturb the others in the same cell")

    warm.remove()
end)

harness.test("a zone destroyed mid-tick is skipped by the rest of that same tick", function()
    -- The cached candidate list is a snapshot, so a handler that destroys
    -- another zone leaves a dead reference in the array the loop is still
    -- walking. That must be skipped, not ticked.
    --
    -- Written so it does not depend on which of the two the loop reaches
    -- first: EACH removes the other, so whichever wins, the loser must never
    -- fire. Asserting "exactly one of them entered" is true under both
    -- orderings, where naming a specific victim would be a coin flip.
    local first, second
    local enters = 0
    local function onEnter(other)
        return function()
            enters = enters + 1
            local target = other()
            if target then target.remove() end
        end
    end

    first = Kora.zones.sphere({
        coords = { x = 0, y = 0, z = 0 }, radius = 5,
        onEnter = onEnter(function() return second end),
    })
    second = Kora.zones.sphere({
        coords = { x = 0, y = 0, z = 0 }, radius = 5,
        onEnter = onEnter(function() return first end),
    })

    net.step()
    harness.assertEqual(enters, 1, "a zone destroyed earlier in the same tick must not then fire onEnter")

    first.remove()
    second.remove()
end)

harness.test("Kora.zones.edit rejects an invalid onEnter and leaves coords unchanged", function()
    local zone = Kora.zones.box({ coords = { x = 0, y = 0, z = 0 }, size = { x = 10, y = 10, z = 10 } })
    net.step()
    harness.assertTrue(zone.isInside(), "the zone should start out containing the player")

    harness.assertThrows(function()
        Kora.zones.edit(zone, { coords = { x = 500, y = 500, z = 0 }, onEnter = "not-a-function" })
    end, "an invalid onEnter should reject the whole edit, including the coords change")

    harness.assertTrue(zone.contains({ x = 0, y = 0, z = 0 }), "coords must not have moved just because the call ultimately threw")
    harness.assertFalse(zone.contains({ x = 500, y = 500, z = 0 }), "the zone must not have moved to the rejected coords")

    net.step()
    harness.assertTrue(zone.isInside(), "the grid must never have been touched by the rejected edit")

    zone.remove()
end)

harness.test("Kora.zones.edit rejects an invalid onExit and leaves coords unchanged", function()
    local zone = Kora.zones.box({ coords = { x = 0, y = 0, z = 0 }, size = { x = 10, y = 10, z = 10 } })
    net.step()
    harness.assertTrue(zone.isInside(), "the zone should start out containing the player")

    harness.assertThrows(function()
        Kora.zones.edit(zone, { coords = { x = 500, y = 500, z = 0 }, onExit = 42 })
    end, "an invalid onExit should reject the whole edit, including the coords change")

    harness.assertTrue(zone.contains({ x = 0, y = 0, z = 0 }), "coords must not have moved just because the call ultimately threw")
    harness.assertFalse(zone.contains({ x = 500, y = 500, z = 0 }), "the zone must not have moved to the rejected coords")

    net.step()
    harness.assertTrue(zone.isInside(), "the grid must never have been touched by the rejected edit")

    zone.remove()
end)

harness.test("Kora.zones.edit with unchanged coords is a no-op that doesn't disturb grid tracking", function()
    local zone = Kora.zones.box({ coords = { x = 0, y = 0, z = 0 }, size = { x = 10, y = 10, z = 10 } })
    net.step()
    harness.assertTrue(zone.isInside(), "the zone should start out containing the player")

    -- A fresh table with the same numeric values, not the same Lua object --
    -- exercises the value-equality short-circuit rather than trivially
    -- skipping via reference equality.
    Kora.zones.edit(zone, { coords = { x = 0, y = 0, z = 0 } })

    harness.assertTrue(zone.contains({ x = 0, y = 0, z = 0 }), "the zone should still contain the origin")
    net.step()
    harness.assertTrue(zone.isInside(), "a same-coords edit must not have dropped the zone from the grid")

    zone.remove()
end)

harness.test("Kora.zones.edit allows onEnter/onExit edits on a poly zone", function()
    local zone = Kora.zones.poly({
        points = {
            { x = 0,  y = 0,  z = 0 },
            { x = 10, y = 0,  z = 0 },
            { x = 0,  y = 10, z = 0 },
        },
    })

    Kora.zones.edit(zone, { onEnter = function() end })

    zone.remove()
end)

harness.test("foreign resources cannot mutate or remove owned zones", function()
    local invokingResource = "zone_owner"
    _G.GetInvokingResource = function() return invokingResource end
    local zone = Kora.zones.sphere({ coords = { x = 300, y = 300, z = 0 }, radius = 5 })

    invokingResource = "other_resource"
    local edited, reason = Kora.zones.edit(zone, { coords = { x = 0, y = 0, z = 0 } })
    harness.assertEqual(edited, nil, "a foreign resource must not edit the zone")
    harness.assertEqual(reason, "Zone is owned by another resource.", "the refusal should explain ownership")
    harness.assertFalse(zone.setDebug(true), "a foreign resource must not enable debug drawing")
    harness.assertFalse(Kora.zones.setDebug(zone.id, true), "a foreign resource must not mutate debug by id")
    harness.assertFalse(Kora.zones.setDebug(nil, true), "a foreign resource must not mutate every zone's debug state")
    harness.assertFalse(zone.remove(), "a foreign resource must not remove the zone")
    harness.assertTrue(zone.contains({ x = 300, y = 300, z = 0 }), "the foreign edits must leave geometry intact")

    invokingResource = "zone_owner"
    harness.assertTrue(zone.remove(), "the owner should remove the zone")
    _G.GetInvokingResource = function() return nil end
end)

harness.test("generateSnippet formats a box zone", function()
    local snippet = Kora.zones.generateSnippet("box", {
        coords = { x = 100, y = 200, z = 30 },
        size = { x = 4, y = 4, z = 3 },
        rotation = 45,
    })

    harness.assertTrue(snippet:find("Kora.zones.box(", 1, true) ~= nil, "should generate a Kora.zones.box call")
    harness.assertTrue(snippet:find("vector3(100.00, 200.00, 30.00)", 1, true) ~= nil, "coords should be formatted as vector3(...)")
    harness.assertTrue(snippet:find("rotation = 45.00", 1, true) ~= nil, "rotation should be included")
end)

harness.test("generateSnippet formats a sphere zone", function()
    local snippet = Kora.zones.generateSnippet("sphere", { coords = { x = 1, y = 2, z = 3 }, radius = 5 })

    harness.assertTrue(snippet:find("Kora.zones.sphere(", 1, true) ~= nil, "should generate a Kora.zones.sphere call")
    harness.assertTrue(snippet:find("radius = 5.00", 1, true) ~= nil, "radius should be included")
end)

harness.test("generateSnippet formats a poly zone with one line per point", function()
    local snippet = Kora.zones.generateSnippet("poly", {
        points = {
            { x = 0,  y = 0,  z = 0 },
            { x = 10, y = 0,  z = 0 },
            { x = 0,  y = 10, z = 0 },
        },
        thickness = 4,
    })

    harness.assertTrue(snippet:find("Kora.zones.poly(", 1, true) ~= nil, "should generate a Kora.zones.poly call")
    local _, count = snippet:gsub("vector3%(", "")
    harness.assertEqual(count, 3, "should emit one vector3(...) per point")
end)

harness.test("generateSnippet preserves a poly's explicit height band and rejects non-finite values", function()
    local snippet = Kora.zones.generateSnippet("poly", {
        points = {
            { x = 0, y = 0, z = 0 }, { x = 10, y = 0, z = 0 }, { x = 0, y = 10, z = 0 },
        },
        minZ = 20, maxZ = 24,
    })

    harness.assertTrue(snippet:find("minZ = 20.00", 1, true) ~= nil, "explicit minZ should be retained")
    harness.assertTrue(snippet:find("maxZ = 24.00", 1, true) ~= nil, "explicit maxZ should be retained")
    harness.assertThrows(function()
        Kora.zones.generateSnippet("sphere", { coords = { x = 0, y = 0, z = 0 }, radius = math.huge })
    end)
end)

harness.test("generateSnippet rejects an unknown zone type", function()
    harness.assertThrows(function()
        Kora.zones.generateSnippet("cylinder", {})
    end, "an unsupported zone type should raise")
end)

harness.test("startCreator rejects a second call while a creator is already running", function()
    local first = Kora.zones.startCreator("box")
    harness.assertEqual(first.state, "pending", "the first creator should still be running")

    local second = Kora.zones.startCreator("box")
    harness.assertEqual(second.state, "rejected", "a second concurrent creator should be rejected immediately")

    -- Cancel the first via the same handler its keybind would call, so it
    -- doesn't leak state into later tests.
    registeredCommands["qblib_zonecreator_cancel"]()
    harness.assertEqual(first.state, "resolved", "cancelling should resolve the first creator's promise")
    harness.assertEqual(first.value, nil, "a cancelled creator should resolve with nil, not an error")
end)

harness.test("startCreator rejects while entity placement is active", function()
    placementActive = true
    local p = Kora.zones.startCreator("box")
    placementActive = false

    harness.assertEqual(p.state, "rejected", "zone creation must not overlap entity placement")
end)

harness.test("isCreatorActive reflects whether a creator session is running", function()
    harness.assertFalse(Kora.zones.isCreatorActive(), "no creator has been started yet")

    local p = Kora.zones.startCreator("box")
    harness.assertTrue(Kora.zones.isCreatorActive(), "a creator is now pending")

    registeredCommands["qblib_zonecreator_cancel"]()
    harness.assertEqual(p.state, "resolved", "sanity check: the creator should have ended")
    harness.assertFalse(Kora.zones.isCreatorActive(), "cancelling should clear the active session")
end)

harness.test("the creator restores the minimap when it ends", function()
    radarHidden = false
    radarCalls = {}

    local p = Kora.zones.startCreator("box")
    net.step() -- run one iteration of the creator's per-frame thread

    harness.assertTrue(radarCalls[1] == false, "the minimap should be hidden while placing")

    registeredCommands["qblib_zonecreator_cancel"]()
    net.step() -- let the loop observe creatorState changing and fall through to teardown

    harness.assertEqual(p.state, "resolved", "sanity check: the creator should have ended")
    harness.assertTrue(radarCalls[#radarCalls] == true,
        "the minimap must be restored on teardown -- leaving it hidden strands the player with no map")
end)

harness.test("the creator preserves a minimap that was already hidden", function()
    radarHidden = true
    radarCalls = {}

    local p = Kora.zones.startCreator("box")
    registeredCommands["qblib_zonecreator_cancel"]()
    net.step()

    harness.assertEqual(p.state, "resolved", "sanity check: the creator should have ended")
    harness.assertFalse(radarCalls[#radarCalls], "creator teardown must not force an originally hidden minimap on")
    radarHidden = false
end)

harness.test("the creator holds and releases its camera control lease", function()
    disabledControls = {}
    local p = Kora.zones.startCreator("box")

    harness.assertTrue(disabledControls["0:1"] == true and disabledControls["0:31"] == true,
        "creator camera controls should be disabled before startCreator returns")

    registeredCommands["qblib_zonecreator_cancel"]()
    disabledControls = {}
    net.step()

    harness.assertEqual(p.state, "resolved", "the creator should cancel normally")
    harness.assertTrue(next(disabledControls) == nil, "cancel should release every creator control")
end)

harness.test("creator controls release when the owning resource stops", function()
    local currentResource = "creator_consumer"
    _G.GetCurrentResourceName = function() return currentResource end
    local p = Kora.zones.startCreator("box")
    currentResource = "kora_lib_test"

    net.fire("onClientResourceStop", "creator_consumer")
    harness.assertEqual(p.state, "resolved", "owner shutdown should cancel the creator")

    disabledControls = {}
    net.step()
    harness.assertTrue(next(disabledControls) == nil, "owner shutdown should release creator controls")

    _G.GetCurrentResourceName = function() return "kora_lib_test" end
end)

harness.test("a creator loop crash releases its control lease", function()
    local originalGetFrameTime = GetFrameTime
    local p = Kora.zones.startCreator("box")
    _G.GetFrameTime = function() error("simulated camera failure") end

    net.step()
    harness.assertEqual(p.state, "rejected", "the crashed creator should reject its promise")

    _G.GetFrameTime = originalGetFrameTime
    disabledControls = {}
    net.step()
    harness.assertTrue(next(disabledControls) == nil, "crash cleanup should release creator controls")
end)

harness.test("startCreator rejects an invalid zone type", function()
    harness.assertThrows(function()
        Kora.zones.startCreator("cylinder")
    end, "an unsupported zone type should raise")
end)

harness.test("startCreator rejects when the creator is disabled via config", function()
    Config.zones.creator.enabled = false

    local p = Kora.zones.startCreator("box")
    harness.assertEqual(p.state, "rejected", "startCreator should reject immediately when disabled")

    Config.zones.creator.enabled = true
end)

harness.test("startCreator raises synchronously on malformed seed opts", function()
    harness.assertThrows(function()
        Kora.zones.startCreator("sphere", { radius = -5 })
    end, "a negative seeded radius should raise before the creator starts")

    harness.assertThrows(function()
        local tooMany = {}
        for i = 1, Config.zones.creator.maxPolyPoints + 1 do
            tooMany[i] = { x = i, y = i, z = 0 }
        end
        Kora.zones.startCreator("poly", { points = tooMany })
    end, "seeding past the poly point cap should raise")

    harness.assertThrows(function()
        Kora.zones.startCreator("box", { rotation = math.huge })
    end, "a non-finite seeded rotation should raise before the creator starts")

    -- Neither failed seed may leave a half-started creator behind.
    local p = Kora.zones.startCreator("box")
    harness.assertEqual(p.state, "pending", "a fresh creator should start cleanly after failed seeds")
    registeredCommands["qblib_zonecreator_cancel"]()
end)

harness.test("startCreator preserves a zero-based explicit poly height band", function()
    local p = Kora.zones.startCreator("poly", {
        points = { { x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 }, { x = 0, y = 1, z = 0 } },
        minZ = 0, maxZ = 4,
    })

    nextNuiResponse = { confirmed = true }
    registeredCommands["qblib_zonecreator_confirm"]()
    nextNuiResponse = nil

    harness.assertEqual(p.value.opts.thickness, 4, "the seed height band should retain its full thickness")
end)

harness.test("startCreator(type, existingOpts) seeds the creator from an existing zone", function()
    local existing = {
        coords = { x = 10, y = 20, z = 30 },
        size = { x = 6, y = 6, z = 4 },
        rotation = 90,
    }

    local p = Kora.zones.startCreator("box", existing)
    harness.assertEqual(p.state, "pending", "the creator should be running, seeded from the existing zone")

    -- Confirming works immediately (no placement keypress first) precisely
    -- because seeding already gave the creator a center.
    nextNuiResponse = { confirmed = true }
    registeredCommands["qblib_zonecreator_confirm"]()
    nextNuiResponse = nil

    harness.assertEqual(p.state, "resolved", "confirming a seeded creator should resolve like a normal one")
    harness.assertEqual(p.value.type, "box", "the resolved type should match")
    harness.assertEqual(p.value.opts.coords.x, 10, "the seeded coords should carry through")
    harness.assertEqual(p.value.opts.size.x, 6, "the seeded size.x should become the creator's uniform size")
    harness.assertEqual(p.value.opts.size.z, 4, "the seeded size.z should become the creator's height")
    harness.assertEqual(p.value.opts.rotation, 90, "the seeded rotation should carry through")
end)

harness.test("confirming a poly creator returns its coordinates without registering a live zone", function()
    local p = Kora.zones.startCreator("poly", {
        points = {
            { x = -10, y = -10, z = 0 },
            { x = 10,  y = -10, z = 0 },
            { x = 0,   y = 10,  z = 0 },
        },
        thickness = 4,
    })

    nextNuiResponse = { confirmed = true }
    registeredCommands["qblib_zonecreator_confirm"]()
    nextNuiResponse = nil

    harness.assertEqual(p.state, "resolved", "confirming should return the completed poly definition")
    harness.assertEqual(#p.value.opts.points, 3, "all captured poly coordinates should be returned")

    -- The mock player is at the origin, inside the polygon above. Before this
    -- regression was fixed, confirmation registered that polygon and the next
    -- zone tick reported it here even though the creator is only a builder.
    net.step()
    harness.assertEqual(#Kora.zones.getInside(), 0,
        "the creator preview must disappear without leaving a registered zone behind")
end)

harness.test("a debug box zone draws one wireframe line per edge plus wall faces", function()
    drawLineCalls = 0
    drawPolyCalls = 0

    -- Creating the zone starts the debug thread, and the mock CreateThread
    -- resumes it once immediately -- one draw pass happens synchronously,
    -- no net.step() needed.
    local zone = Kora.zones.box({ coords = { x = 100, y = 100, z = 30 }, size = { x = 4, y = 4, z = 3 }, debug = true })

    -- 12 box edges, one line each -- no thickness faking, the wall fill
    -- below is what carries visibility.
    harness.assertEqual(drawLineCalls, 12, "each of the box's 12 edges should be drawn once")
    -- 6 faces, 2 triangles each, drawn twice (both windings) for double-sided visibility.
    harness.assertEqual(drawPolyCalls, 24, "each of the box's 6 faces should draw 2 triangles x 2 windings")

    zone.remove()
end)

harness.test("a debug poly zone draws a wall face per edge", function()
    local zone = Kora.zones.poly({
        points = {
            { x = 200, y = 200, z = 30 },
            { x = 204, y = 200, z = 30 },
            { x = 202, y = 204, z = 30 },
        },
        thickness = 4,
        debug = true,
    })

    -- The debug thread is one long-lived coroutine started by the earlier
    -- box-zone test and already suspended at its Wait(0) -- it only notices
    -- this new zone (and stops seeing the earlier, since-removed box zone)
    -- on its next resumed iteration, not immediately on creation.
    drawPolyCalls = 0
    net.step()

    -- 3 edges, 2 triangles each, drawn twice (both windings).
    harness.assertEqual(drawPolyCalls, 12, "each of the poly's 3 edges should draw one wall x 2 triangles x 2 windings")

    zone.remove()
end)

harness.test("Kora.zones.setDebug(id, true) makes an already-created zone start drawing", function()
    -- Drain the debug thread the poly test above left running (suspended at
    -- its Wait(0)): that test's zone is already removed, so this resumed
    -- iteration finds debugZones empty and the thread quietly stops itself
    -- -- leaving debugThreadStarted false again before this test relies on
    -- setDebug starting a fresh one.
    net.step()

    local zone = Kora.zones.box({ coords = { x = 300, y = 300, z = 30 }, size = { x = 4, y = 4, z = 3 }, debug = false })

    drawLineCalls = 0
    zone.setDebug(true)

    -- setDebug(true) starts a fresh debug thread (none was running), and the
    -- mock CreateThread resumes it once immediately -- same as a zone
    -- created with debug = true directly, no net.step() needed for this
    -- first draw pass.
    harness.assertEqual(drawLineCalls, 12, "turning debug on for an existing zone should draw its 12 box edges")

    zone.setDebug(false)
    zone.remove()
end)

harness.test("Kora.zones.setDebug(nil, true) flips every registered zone at once", function()
    net.step() -- drain the previous test's now-empty debug thread, same as above

    -- Measure the existing registry's drawing baseline before adding this
    -- test's two zones. The assertions then check the delta they contribute
    -- rather than depending on global test state.
    Kora.zones.setDebug(nil, true)
    drawLineCalls = 0
    net.step()
    local baseline = drawLineCalls
    Kora.zones.setDebug(nil, false)
    net.step()

    local a = Kora.zones.box({ coords = { x = 320, y = 320, z = 30 }, size = { x = 4, y = 4, z = 3 } })
    local b = Kora.zones.box({ coords = { x = 340, y = 340, z = 30 }, size = { x = 4, y = 4, z = 3 } })

    -- setDebug(nil, true) starts a fresh debug thread mid-loop, over
    -- whichever zone it had already flipped into debugZones at that exact
    -- point -- so its own synchronous first draw pass can legitimately miss
    -- some of them. Every zone is unconditionally in debugZones by the time
    -- the call returns though, so resetting the counter and letting the
    -- now-running thread's next resumed iteration draw is what actually
    -- proves "every zone".
    Kora.zones.setDebug(nil, true)
    drawLineCalls = 0
    net.step()

    harness.assertEqual(drawLineCalls - baseline, 24,
        "both new zones' 12 edges each should draw once debug is flipped on globally, on top of whatever else is already registered")

    Kora.zones.setDebug(nil, false)
    drawLineCalls = 0
    net.step()

    harness.assertEqual(drawLineCalls, 0, "flipping debug back off globally should stop drawing every zone, baseline included")

    a.remove()
    b.remove()
end)

harness.test("Config.zones.debug defaults new zones into debug drawing without opts.debug", function()
    net.step() -- drain again, same reasoning as above

    local priorDefault = Config.zones.debug
    Config.zones.debug = true

    drawLineCalls = 0
    local zone = Kora.zones.box({ coords = { x = 360, y = 360, z = 30 }, size = { x = 4, y = 4, z = 3 } })

    harness.assertEqual(drawLineCalls, 12,
        "Config.zones.debug = true should enable debug drawing on a newly created zone even without opts.debug")

    Config.zones.debug = priorDefault
    zone.remove()
end)

harness.test("qb_zonedebug command toggles/sets debug drawing for every zone", function()
    net.step() -- drain again, same reasoning as above

    -- Same reasoning as the Kora.zones.setDebug(nil, ...) test above: capture
    -- the current baseline, then assert the delta from this test's own zone.
    Kora.zones.setDebug(nil, true)
    drawLineCalls = 0
    net.step()
    local baseline = drawLineCalls
    Kora.zones.setDebug(nil, false)
    net.step()

    local zone = Kora.zones.box({ coords = { x = 380, y = 380, z = 30 }, size = { x = 4, y = 4, z = 3 } })

    registeredCommands["qb_zonedebug"](nil, {})
    drawLineCalls = 0
    net.step()
    harness.assertEqual(drawLineCalls - baseline, 12, "no-arg toggle should turn debug on when nothing is currently drawing")

    registeredCommands["qb_zonedebug"](nil, {})
    drawLineCalls = 0
    net.step()
    harness.assertEqual(drawLineCalls, 0, "no-arg toggle should turn debug back off when a zone is currently drawing")

    registeredCommands["qb_zonedebug"](nil, { "on" })
    drawLineCalls = 0
    net.step()
    harness.assertEqual(drawLineCalls - baseline, 12, "'on' should enable debug drawing regardless of the current state")

    registeredCommands["qb_zonedebug"](nil, { "off" })
    drawLineCalls = 0
    net.step()
    harness.assertEqual(drawLineCalls, 0, "'off' should disable debug drawing regardless of the current state")

    zone.remove()
end)

harness.test("starting the creator activates a scripted camera with an eased transition", function()
    local renderCalls = {}
    local originalRender = RenderScriptCams
    _G.RenderScriptCams = function(...) table.insert(renderCalls, { ... }) end

    local p = Kora.zones.startCreator("box")
    net.step()

    harness.assertTrue(#renderCalls >= 1, "starting the creator should activate its scripted camera")
    harness.assertEqual(renderCalls[1][1], true, "the camera should render on")
    harness.assertEqual(renderCalls[1][2], true, "the transition into the creator's camera should ease")

    registeredCommands["qblib_zonecreator_cancel"]()
    net.step()

    harness.assertTrue(#renderCalls >= 2, "cancelling should hand the view back to the gameplay camera")
    harness.assertEqual(renderCalls[#renderCalls][1], false, "the camera should render off on teardown")
    harness.assertEqual(renderCalls[#renderCalls][2], true, "the transition back out should also ease")

    _G.RenderScriptCams = originalRender
end)

harness.test("cancelling the creator eventually destroys its scripted camera", function()
    -- Only a positive claim ("it does get destroyed"), not a timing claim
    -- ("not yet") -- net.step() resumes every still-suspended coroutine ever
    -- created in this file, including leftover ease-out threads from earlier
    -- start/cancel tests above, so asserting an exact call count/timing here
    -- would be testing thread-pool leakage rather than this feature.
    local destroyedCams = {}
    local originalDestroy = DestroyCam
    _G.DestroyCam = function(cam) table.insert(destroyedCams, cam) end

    local p = Kora.zones.startCreator("box")
    net.step()

    registeredCommands["qblib_zonecreator_cancel"]()
    net.step() -- outer thread falls through to teardown, spawns the ease-out thread
    net.step() -- the ease-out thread's Wait(cameraTransitionMs) elapses, DestroyCam runs

    harness.assertTrue(#destroyedCams >= 1, "the camera should eventually be destroyed once the ease-out finishes")

    _G.DestroyCam = originalDestroy
end)

harness.report("zones")
