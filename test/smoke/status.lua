local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

-- QB.status.apply/remove are defined on BOTH realms with the same name --
-- server: apply(target, name, opts), client: apply(name, opts). Same
-- capture-by-reference-before-overwrite trick test/smoke/callback.lua uses
-- for QB.callback.register/trigger: grab the server versions right after
-- server.lua loads, before client.lua's load overwrites the same QB.status
-- table slots.
local net = mocks.install()

dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "local/resources/client.lua")
dofile(repoRoot .. "local/resources/server.lua")
dofile(repoRoot .. "local/events/shared.lua")
dofile(repoRoot .. "local/events/server.lua")
dofile(repoRoot .. "local/events/client.lua") -- its startup CreateThread completes the client<-server handshake synchronously

dofile(repoRoot .. "modules/status/shared.lua")

dofile(repoRoot .. "modules/status/server.lua")
local serverApply = QB.status.apply
local serverRemove = QB.status.remove
local serverIsActive = QB.status.isActive
local serverGetActive = QB.status.getActive

-- Fakes for QB.fx/QB.anim, standing in for their real modules (each has its
-- own smoke test already) -- status/client.lua only needs their public shape.
local ptfxStarts, ptfxStops = {}, {}
local screenStarts, screenStops = {}, {}
local animStarts, animStops = {}, {}
local nextHandle = 0

QB.fx = {
    playPtfx = function(def)
        nextHandle = nextHandle + 1
        ptfxStarts[#ptfxStarts + 1] = def
        return { looped = true, particleId = nextHandle }
    end,
    stop = function(handle) ptfxStops[#ptfxStops + 1] = handle.particleId; return true end,
    screenEffect = function(name, duration, looped)
        screenStarts[#screenStarts + 1] = { name = name, duration = duration, looped = looped }
        return { name = name }
    end,
    stopScreenEffect = function(handle) screenStops[#screenStops + 1] = handle.name; return true end,
}

QB.anim = {
    play = function(entity, dict, clip)
        animStarts[#animStarts + 1] = { entity = entity, dict = dict, clip = clip }
        return { entity = entity, dict = dict, clip = clip }
    end,
    stop = function(entity) animStops[#animStops + 1] = entity; return true end,
}

function _G.PlayerPedId() return 1 end
function _G.SetPedMoveRateOverride(ped, mult)
    _G.__lastMoveRateOverride = { ped = ped, mult = mult }
end

dofile(repoRoot .. "modules/status/client.lua")
local clientApply = QB.status.apply
local clientRemove = QB.status.remove
local clientIsActive = QB.status.isActive
local clientGetActive = QB.status.getActive

QB.status.registerEffect("bleeding", { duration = 1000, severityLevels = 4, movement = { speedMultiplier = 0.95 } })
QB.status.registerEffect("injured_leg", { movement = { speedMultiplier = 0.8 } })
QB.status.registerEffect("high_weed", { duration = 500, fx = { screen = "DrugsMichaelAliensFightIn", ptfx = { dict = "weed_fx", name = "weed_smoke" } }, anim = { dict = "weed@smoke", clip = "loop" } })
QB.status.registerEffect("stackable", { severityLevels = 10, stacking = "stack" })
QB.status.registerEffect("extendable", { duration = 1000, stacking = "extend" })

harness.test("registerEffect rejects an invalid stacking mode", function()
    harness.assertThrows(function()
        QB.status.registerEffect("bad", { stacking = "nonsense" })
    end, "an unknown stacking mode should be rejected")
end)

harness.test("server apply rejects an unregistered effect name", function()
    local ok, err = serverApply(mocks.SOURCE, "not_a_real_effect")
    harness.assertFalse(ok, "applying an unknown effect should fail")
    harness.assertTrue(err ~= nil, "should explain the failure")
end)

harness.test("server apply pushes the effect to the client, which renders it", function()
    local ok = serverApply(mocks.SOURCE, "high_weed")
    harness.assertTrue(ok, "server apply should succeed for a registered effect")

    harness.assertTrue(clientIsActive("high_weed"), "the client should have received and applied the push")
    harness.assertEqual(screenStarts[#screenStarts].name, "DrugsMichaelAliensFightIn", "should have started the configured screen effect")
    harness.assertEqual(ptfxStarts[#ptfxStarts].dict, "weed_fx", "should have started the configured ptfx")
    harness.assertEqual(animStarts[#animStarts].dict, "weed@smoke", "should have started the configured anim")

    clientRemove("high_weed")
end)

-- From here on, tests care about SERVER-side timer bookkeeping in isolation.
-- Neutralize the push-delivered client renderer: in this single-process mock,
-- server->client push delivery is synchronous, so a duration-bearing apply
-- would otherwise make the CLIENT's own "auto-remove after `duration`"
-- CreateThread advance the same shared mock clock the server's expiresAt was
-- just computed against -- landing exactly on the boundary and making an
-- effect look already-expired the instant it's applied. Real deployments
-- never hit this (client/server clocks are genuinely independent processes);
-- it's purely an artifact of this mock's single shared clock, which the
-- "server apply pushes..." test above already covered honestly. The
-- previously captured `clientApply`/`clientRemove`/`clientIsActive` locals
-- are unaffected -- they still call the real client implementation directly.
QB.status.apply = function() end
QB.status.remove = function() end

harness.test("client-local apply/remove renders and tears down fx/anim/movement", function()
    clientApply("bleeding", { severity = 2 })

    harness.assertTrue(clientIsActive("bleeding"), "bleeding should be active after apply")
    harness.assertEqual(_G.__lastMoveRateOverride.mult, 0.95, "should apply the configured movement multiplier")

    local removed = clientRemove("bleeding")
    harness.assertTrue(removed, "remove should report true for an active effect")
    harness.assertFalse(clientIsActive("bleeding"), "bleeding should no longer be active after remove")
    harness.assertEqual(_G.__lastMoveRateOverride.mult, 1.0, "removing a movement-affecting effect should reset the override")
end)

harness.test("simultaneous movement effects remain composed when one is removed", function()
    clientApply("bleeding", { severity = 1 })
    clientApply("injured_leg")
    harness.assertEqual(_G.__lastMoveRateOverride.mult, 0.95 * 0.8, "movement multipliers should compose")
    clientRemove("injured_leg")
    harness.assertEqual(_G.__lastMoveRateOverride.mult, 0.95, "removing one effect must preserve the other")
    clientRemove("bleeding")
end)

harness.test("movement overrides are refreshed each frame only while active", function()
    clientApply("injured_leg")
    _G.__lastMoveRateOverride = nil
    net.step()
    harness.assertEqual(_G.__lastMoveRateOverride.mult, 0.8, "an active movement override must be applied again on the next frame")
    clientRemove("injured_leg")
    _G.__lastMoveRateOverride = nil
    net.step()
    harness.assertEqual(_G.__lastMoveRateOverride, nil, "the movement loop should stop after the final effect is removed")
end)

harness.test("remove reports false for an effect that isn't active", function()
    harness.assertFalse(clientRemove("bleeding"), "removing an inactive effect should report false")
end)

harness.test("severity is validated against severityLevels", function()
    harness.assertThrows(function()
        serverApply(mocks.SOURCE, "bleeding", { severity = 99 })
    end, "an out-of-range severity should be rejected")
end)

harness.test("stacking = stack adds severity onto the existing value, capped at severityLevels", function()
    serverApply(mocks.SOURCE, "stackable", { severity = 4 })
    serverApply(mocks.SOURCE, "stackable", { severity = 4 })
    local active = serverGetActive(mocks.SOURCE)
    local entry
    for _, e in ipairs(active) do if e.name == "stackable" then entry = e end end
    harness.assertEqual(entry.severity, 8, "severities should add together under stack mode")

    serverApply(mocks.SOURCE, "stackable", { severity = 10 })
    active = serverGetActive(mocks.SOURCE)
    for _, e in ipairs(active) do if e.name == "stackable" then entry = e end end
    harness.assertEqual(entry.severity, 10, "stacked severity should cap at severityLevels")

    serverRemove(mocks.SOURCE, "stackable")
end)

harness.test("stacking = extend adds the new duration onto whatever is left", function()
    serverApply(mocks.SOURCE, "extendable")
    local firstExpiry
    for _, e in ipairs(serverGetActive(mocks.SOURCE)) do if e.name == "extendable" then firstExpiry = e.expiresAt end end

    serverApply(mocks.SOURCE, "extendable")
    local secondExpiry
    for _, e in ipairs(serverGetActive(mocks.SOURCE)) do if e.name == "extendable" then secondExpiry = e.expiresAt end end

    harness.assertTrue(secondExpiry > firstExpiry, "a second 'extend' apply should push the expiry further out")
    local push = mocks.lastEntry(net.triggeredClientEvents, "qblib:events:push")
    harness.assertEqual(push[1], "qblib:status:apply")
    harness.assertEqual(push[2], "extendable")
    harness.assertEqual(push[3].duration, secondExpiry - GetGameTimer(), "the client should receive the full authoritative remaining duration")

    serverRemove(mocks.SOURCE, "extendable")
end)

harness.test("client-local extend and stack follow the registered definitions", function()
    clientApply("extendable", { duration = 100 })
    local firstExpiry
    for _, entry in ipairs(clientGetActive()) do if entry.name == "extendable" then firstExpiry = entry.expiresAt end end
    clientApply("extendable", { duration = 100 })
    local secondExpiry
    for _, entry in ipairs(clientGetActive()) do if entry.name == "extendable" then secondExpiry = entry.expiresAt end end
    harness.assertEqual(secondExpiry, firstExpiry + 100, "client-local extend should add to the existing expiry")
    clientRemove("extendable")

    clientApply("stackable", { severity = 4 })
    clientApply("stackable", { severity = 4 })
    local severity
    for _, entry in ipairs(clientGetActive()) do if entry.name == "stackable" then severity = entry.severity end end
    harness.assertEqual(severity, 8, "client-local stack should add severity")
    clientRemove("stackable")
end)

harness.test("server isActive reports false and drops the entry once expired", function()
    serverApply(mocks.SOURCE, "extendable", { duration = 10 })
    _G.__mockAdvance = (_G.__mockAdvance or 0) -- no-op marker; GetGameTimer is advanced via Wait() below
    _G.Wait(50)
    harness.assertFalse(serverIsActive(mocks.SOURCE, "extendable"), "an expired effect should report inactive")

    local stillThere = false
    for _, e in ipairs(serverGetActive(mocks.SOURCE)) do if e.name == "extendable" then stillThere = true end end
    harness.assertFalse(stillThere, "an expired effect should not appear in getActive")
end)

harness.test("playerDropped clears everything tracked for that player", function()
    serverApply(555, "extendable")
    harness.assertTrue(serverIsActive(555, "extendable"), "sanity check: the effect should be active before the drop")

    _G.source = 555
    net.fire("playerDropped")
    _G.source = nil

    harness.assertFalse(serverIsActive(555, "extendable"), "no effect should remain active once the player has dropped")
end)

harness.report("status")
