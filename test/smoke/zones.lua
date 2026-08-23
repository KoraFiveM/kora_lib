local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")

-- The mock player never moves from the origin. ensureTickThread only ever
-- starts one CreateThread for the life of the module, and our CreateThread
-- mock resumes it exactly once -- so only the very first zone created below
-- (the box at the origin) actually gets ticked; later zones are checked via
-- their pure `contains` function instead.
_G.PlayerPedId = function() return 1 end
_G.GetEntityCoords = function() return { x = 0, y = 0, z = 0 } end
_G.GetEntitySpeed = function() return 0.0 end
local drawLineCalls = 0
local drawMarkerCalls = 0
local drawPolyCalls = 0

_G.DrawLine = function() drawLineCalls = drawLineCalls + 1 end
_G.DrawMarker = function() drawMarkerCalls = drawMarkerCalls + 1 end
_G.DrawPoly = function() drawPolyCalls = drawPolyCalls + 1 end

-- The zone creator's own natives. Placement now goes through the real
-- QB.raycast.fromCamera (modules/raycast), so these are dofile'd here too --
-- the mock player/camera never moves and nothing is ever aimed at, so the
-- ray consistently misses (hit = 0), enough for the creator's startup/guard
-- behavior below without needing a real hit-testing simulation.
-- `registeredCommands` captures every RegisterCommand handler by name so a
-- test can drive the creator the same way a keybind would (see the cancel
-- call at the end of the guard test).
local registeredCommands = {}
_G.RegisterCommand = function(name, handler) registeredCommands[name] = handler end
_G.RegisterKeyMapping = function() end
_G.GetGameplayCamCoord = function() return { x = 0, y = 0, z = 0 } end
_G.GetGameplayCamRot = function() return { x = 0, y = 0, z = 0 } end
_G.StartShapeTestRay = function() return 1 end
_G.GetShapeTestResult = function() return 0, 0, { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }, 0 end
_G.IsControlJustPressed = function() return false end
_G.IsControlPressed = function() return false end
_G.CreateCamWithParams = function() return 1 end
_G.SetCamActive = function() end
_G.RenderScriptCams = function() end
_G.DestroyCam = function() end
_G.FreezeEntityPosition = function() end
_G.DisableControlAction = function() end
_G.GetDisabledControlNormal = function() return 0.0 end
_G.GetFrameTime = function() return 0.0 end
_G.GetGameplayCamFov = function() return 50.0 end
_G.SetCamCoord = function() end
_G.SetCamRot = function() end
_G.GetCamCoord = function() return { x = 0, y = 0, z = 0 } end
_G.GetCamRot = function() return { x = 0, y = 0, z = 0 } end
-- Recorded rather than ignored: hiding the minimap during placement is only
-- correct if it's also restored on teardown, and a creator that leaves a
-- player with no map is exactly the kind of thing that goes unnoticed in a
-- manual test.
local radarCalls = {}
_G.DisplayRadar = function(shown) radarCalls[#radarCalls + 1] = shown end

dofile(repoRoot .. "modules/raycast/client.lua")
dofile(repoRoot .. "local/resources/client.lua")
-- QB.theme isn't otherwise loaded by this test file -- the debug/creator-preview
-- draw path now reads QB.theme.accentColor() (see zoneDebugColor in
-- modules/zones/client.lua), and without this the QB proxy in build/initiate.lua
-- would auto-vivify QB.theme as an empty table, leaving accentColor nil.
dofile(repoRoot .. "modules/theme/shared.lua")
dofile(repoRoot .. "modules/zones/client.lua")

-- Real QB.nui isn't loaded here (that's modules/nui's own smoke test) -- the
-- creator only needs somewhere to send/request against, so this is a minimal
-- stand-in rather than the full request/response bridge. `nextNuiResponse`
-- lets a test drive the confirm dialog to a specific outcome: since the mock
-- Citizen.Await only supports an already-settled promise (see mocks.lua), the
-- response has to be resolved synchronously, before QB.nui.request returns.
local nextNuiResponse = nil
QB.nui = {
    send = function() end,
    request = function()
        local p = promise.new()
        if nextNuiResponse ~= nil then p:resolve(nextNuiResponse) end
        return p
    end,
    withFocus = function(_, _, fn) return fn() end,
}

harness.test("box zone contains points inside it and is entered by the first tick", function()
    local zone = QB.zones.box({ coords = { x = 0, y = 0, z = 0 }, size = { x = 10, y = 10, z = 10 } })

    harness.assertTrue(zone.contains({ x = 0, y = 0, z = 0 }), "the zone's own center should be inside it")
    harness.assertFalse(zone.contains({ x = 100, y = 100, z = 0 }), "a far point should be outside the box")
    harness.assertTrue(zone.isInside(), "the mock player sits at the zone's center, so the first tick should enter it")

    zone.remove()
end)

harness.test("sphere zone contains points within its radius", function()
    local zone = QB.zones.sphere({ coords = { x = 100, y = 100, z = 0 }, radius = 5 })

    harness.assertTrue(zone.contains({ x = 100, y = 100, z = 0 }), "the sphere's center should be inside it")
    harness.assertFalse(zone.contains({ x = 200, y = 200, z = 0 }), "a far point should be outside the sphere")

    zone.remove()
end)

harness.test("poly zone respects both its footprint and its height band", function()
    local zone = QB.zones.poly({
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

harness.test("poly thickness extends upward from the lowest point, not centred on the average", function()
    -- Deliberately sloped: the lowest point is at z=0 and the highest at z=6,
    -- so an average-centred band (the old behaviour) would have run from z=1
    -- to z=5 -- leaving the ground at the lowest corner OUTSIDE its own zone,
    -- and burying the bottom half of the zone under the hill at the high end.
    local zone = QB.zones.poly({
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
    local zone = QB.zones.poly({
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
    local zone = QB.zones.point({ coords = { x = 50, y = 50, z = 0 } })

    harness.assertEqual(zone.type, "sphere", "a point zone should be a sphere under the hood")
    harness.assertTrue(zone.contains({ x = 50.5, y = 50, z = 0 }), "a point just inside the default radius should be contained")
    harness.assertFalse(zone.contains({ x = 52, y = 50, z = 0 }), "a point well outside the default radius should not be contained")

    zone.remove()
end)

harness.test("zones get unique ids", function()
    local a = QB.zones.sphere({ coords = { x = 0, y = 0, z = 0 }, radius = 1 })
    local b = QB.zones.sphere({ coords = { x = 0, y = 0, z = 0 }, radius = 1 })

    harness.assertTrue(a.id ~= b.id, "two zones should never share an id")

    a.remove()
    b.remove()
end)

harness.test("box zone requires coords and size", function()
    harness.assertThrows(function()
        QB.zones.box({})
    end, "a box zone with no coords/size should raise")
end)

harness.test("removing a zone twice is a harmless no-op", function()
    local zone = QB.zones.sphere({ coords = { x = 0, y = 0, z = 0 }, radius = 1 })
    zone.remove()
    zone.remove()
end)

harness.test("getInside reports the zones the player is currently standing in", function()
    harness.assertEqual(#QB.zones.getInside(), 0, "nothing should be inside before any zone exists here")

    -- The mock player sits at the origin: the box contains it, the sphere is
    -- far away. net.step() advances the (already-running) tick loop one more
    -- iteration so enter/exit tracking sees these newly created zones.
    local zone = QB.zones.box({ coords = { x = 0, y = 0, z = 0 }, size = { x = 10, y = 10, z = 10 } })
    local far = QB.zones.sphere({ coords = { x = 500, y = 500, z = 0 }, radius = 2 })
    net.step()

    local inside = QB.zones.getInside()
    harness.assertEqual(#inside, 1, "only the zone containing the player should be reported")
    harness.assertEqual(inside[1], zone, "getInside should hand back the very same handle the constructor returned")

    harness.assertEqual(#QB.zones.getInside("qblib_test"), 1, "filtering by the owning resource should still match")
    harness.assertEqual(#QB.zones.getInside("some_other_resource"), 0, "filtering by a different resource should match nothing")

    zone.remove()
    far.remove()
    harness.assertEqual(#QB.zones.getInside(), 0, "a removed zone should drop out of getInside")
end)

harness.test("getInside rejects a non-string resource filter", function()
    harness.assertThrows(function() QB.zones.getInside(42) end, "a numeric resource filter should raise")
end)

harness.test("generateSnippet formats a box zone", function()
    local snippet = QB.zones.generateSnippet("box", {
        coords = { x = 100, y = 200, z = 30 },
        size = { x = 4, y = 4, z = 3 },
        rotation = 45,
    })

    harness.assertTrue(snippet:find("QB.zones.box(", 1, true) ~= nil, "should generate a QB.zones.box call")
    harness.assertTrue(snippet:find("vector3(100.00, 200.00, 30.00)", 1, true) ~= nil, "coords should be formatted as vector3(...)")
    harness.assertTrue(snippet:find("rotation = 45.00", 1, true) ~= nil, "rotation should be included")
end)

harness.test("generateSnippet formats a sphere zone", function()
    local snippet = QB.zones.generateSnippet("sphere", { coords = { x = 1, y = 2, z = 3 }, radius = 5 })

    harness.assertTrue(snippet:find("QB.zones.sphere(", 1, true) ~= nil, "should generate a QB.zones.sphere call")
    harness.assertTrue(snippet:find("radius = 5.00", 1, true) ~= nil, "radius should be included")
end)

harness.test("generateSnippet formats a poly zone with one line per point", function()
    local snippet = QB.zones.generateSnippet("poly", {
        points = {
            { x = 0,  y = 0,  z = 0 },
            { x = 10, y = 0,  z = 0 },
            { x = 0,  y = 10, z = 0 },
        },
        thickness = 4,
    })

    harness.assertTrue(snippet:find("QB.zones.poly(", 1, true) ~= nil, "should generate a QB.zones.poly call")
    local _, count = snippet:gsub("vector3%(", "")
    harness.assertEqual(count, 3, "should emit one vector3(...) per point")
end)

harness.test("generateSnippet rejects an unknown zone type", function()
    harness.assertThrows(function()
        QB.zones.generateSnippet("cylinder", {})
    end, "an unsupported zone type should raise")
end)

harness.test("startCreator rejects a second call while a creator is already running", function()
    local first = QB.zones.startCreator("box")
    harness.assertEqual(first.state, "pending", "the first creator should still be running")

    local second = QB.zones.startCreator("box")
    harness.assertEqual(second.state, "rejected", "a second concurrent creator should be rejected immediately")

    -- Cancel the first via the same handler its keybind would call, so it
    -- doesn't leak state into later tests.
    registeredCommands["qblib_zonecreator_cancel"]()
    harness.assertEqual(first.state, "resolved", "cancelling should resolve the first creator's promise")
    harness.assertEqual(first.value, nil, "a cancelled creator should resolve with nil, not an error")
end)

harness.test("the creator restores the minimap when it ends", function()
    radarCalls = {}

    local p = QB.zones.startCreator("box")
    net.step() -- run one iteration of the creator's per-frame thread

    harness.assertTrue(radarCalls[1] == false, "the minimap should be hidden while placing")

    registeredCommands["qblib_zonecreator_cancel"]()
    net.step() -- let the loop observe creatorState changing and fall through to teardown

    harness.assertEqual(p.state, "resolved", "sanity check: the creator should have ended")
    harness.assertTrue(radarCalls[#radarCalls] == true,
        "the minimap must be restored on teardown -- leaving it hidden strands the player with no map")
end)

harness.test("startCreator rejects an invalid zone type", function()
    harness.assertThrows(function()
        QB.zones.startCreator("cylinder")
    end, "an unsupported zone type should raise")
end)

harness.test("startCreator rejects when the creator is disabled via config", function()
    Config.zones.creator.enabled = false

    local p = QB.zones.startCreator("box")
    harness.assertEqual(p.state, "rejected", "startCreator should reject immediately when disabled")

    Config.zones.creator.enabled = true
end)

harness.test("startCreator raises synchronously on malformed seed opts", function()
    harness.assertThrows(function()
        QB.zones.startCreator("sphere", { radius = -5 })
    end, "a negative seeded radius should raise before the creator starts")

    harness.assertThrows(function()
        local tooMany = {}
        for i = 1, Config.zones.creator.maxPolyPoints + 1 do
            tooMany[i] = { x = i, y = i, z = 0 }
        end
        QB.zones.startCreator("poly", { points = tooMany })
    end, "seeding past the poly point cap should raise")

    -- Neither failed seed may leave a half-started creator behind.
    local p = QB.zones.startCreator("box")
    harness.assertEqual(p.state, "pending", "a fresh creator should start cleanly after failed seeds")
    registeredCommands["qblib_zonecreator_cancel"]()
end)

harness.test("startCreator(type, existingOpts) seeds the creator from an existing zone", function()
    local existing = {
        coords = { x = 10, y = 20, z = 30 },
        size = { x = 6, y = 6, z = 4 },
        rotation = 90,
    }

    local p = QB.zones.startCreator("box", existing)
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

harness.test("a debug box zone draws one wireframe line per edge plus wall faces", function()
    drawLineCalls = 0
    drawPolyCalls = 0

    -- Creating the zone starts the debug thread, and the mock CreateThread
    -- resumes it once immediately -- one draw pass happens synchronously,
    -- no net.step() needed.
    local zone = QB.zones.box({ coords = { x = 100, y = 100, z = 30 }, size = { x = 4, y = 4, z = 3 }, debug = true })

    -- 12 box edges, one line each -- no thickness faking, the wall fill
    -- below is what carries visibility.
    harness.assertEqual(drawLineCalls, 12, "each of the box's 12 edges should be drawn once")
    -- 6 faces, 2 triangles each, drawn twice (both windings) for double-sided visibility.
    harness.assertEqual(drawPolyCalls, 24, "each of the box's 6 faces should draw 2 triangles x 2 windings")

    zone.remove()
end)

harness.test("a debug poly zone draws a wall face per edge", function()
    local zone = QB.zones.poly({
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

harness.test("starting the creator activates a scripted camera with an eased transition", function()
    local renderCalls = {}
    local originalRender = RenderScriptCams
    _G.RenderScriptCams = function(...) table.insert(renderCalls, { ... }) end

    local p = QB.zones.startCreator("box")
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

    local p = QB.zones.startCreator("box")
    net.step()

    registeredCommands["qblib_zonecreator_cancel"]()
    net.step() -- outer thread falls through to teardown, spawns the ease-out thread
    net.step() -- the ease-out thread's Wait(cameraTransitionMs) elapses, DestroyCam runs

    harness.assertTrue(#destroyedCams >= 1, "the camera should eventually be destroyed once the ease-out finishes")

    _G.DestroyCam = originalDestroy
end)

harness.report("zones")
