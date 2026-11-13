local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()
local clock = 0
_G.GetGameTimer = function() return clock end

local function advanceClock(milliseconds)
    clock = clock + milliseconds
end

dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "modules/logging/shared.lua")
dofile(repoRoot .. "modules/util/shared.lua")
dofile(repoRoot .. "local/resources/client.lua")
dofile(repoRoot .. "local/resources/server.lua")
dofile(repoRoot .. "local/events/shared.lua")
dofile(repoRoot .. "local/events/server.lua")
dofile(repoRoot .. "local/events/client.lua")

dofile(repoRoot .. "modules/status/shared.lua")

dofile(repoRoot .. "modules/status/server.lua")
local serverApply = Kora.status.apply
local serverRemove = Kora.status.remove
local serverIsActive = Kora.status.isActive
local serverGetActive = Kora.status.getActive

local ptfxStarts, ptfxStops = {}, {}
local screenStarts, screenStops = {}, {}
local animStarts, animStops = {}, {}
local nextHandle = 0
local moveRateCalls = 0

Kora.fx = {
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

Kora.anim = {
    play = function(entity, dict, clip)
        animStarts[#animStarts + 1] = { entity = entity, dict = dict, clip = clip }
        return { entity = entity, dict = dict, clip = clip }
    end,
    stop = function(entity) animStops[#animStops + 1] = entity; return true end,
}

function _G.PlayerPedId() return 1 end
function _G.SetPedMoveRateOverride(ped, mult)
    moveRateCalls = moveRateCalls + 1
    _G.__lastMoveRateOverride = { ped = ped, mult = mult }
end

dofile(repoRoot .. "modules/status/client.lua")
local clientApply = Kora.status.apply
local clientRemove = Kora.status.remove
local clientIsActive = Kora.status.isActive
local clientGetActive = Kora.status.getActive

Kora.status.registerEffect("bleeding", { duration = 1000, severityLevels = 4, movement = { speedMultiplier = 0.95 } })
Kora.status.registerEffect("injured_leg", { movement = { speedMultiplier = 0.8 } })
Kora.status.registerEffect("high_weed", { duration = 500, fx = { screen = "DrugsMichaelAliensFightIn", ptfx = { dict = "weed_fx", name = "weed_smoke" } }, anim = { dict = "weed@smoke", clip = "loop" } })
Kora.status.registerEffect("stackable", { severityLevels = 10, stacking = "stack" })
Kora.status.registerEffect("extendable", { duration = 1000, stacking = "extend" })

harness.test("registerEffect rejects an invalid stacking mode", function()
    harness.assertThrows(function()
        Kora.status.registerEffect("bad", { stacking = "nonsense" })
    end, "an unknown stacking mode should be rejected")
end)

harness.test("registerEffect validates duration and severity definitions", function()
    harness.assertThrows(function()
        Kora.status.registerEffect("bad_duration", { duration = -1 })
    end, "a negative definition duration should be rejected")
    harness.assertThrows(function()
        Kora.status.registerEffect("bad_levels", { severityLevels = 1.5 })
    end, "fractional severity levels should be rejected")
    harness.assertThrows(function()
        Kora.status.registerEffect("bad_movement", { movement = { speedMultiplier = math.huge } })
    end, "an infinite movement multiplier must fail before the per-frame loop")
    harness.assertThrows(function()
        Kora.status.registerEffect('bad_ptfx', { fx = { ptfx = { dict = 'smoke' } } })
    end, 'a particle definition without a name must fail before application')
    harness.assertThrows(function()
        Kora.status.registerEffect('bad_anim', { anim = { dict = 'anim' } })
    end, 'an animation definition without a clip must fail before application')
end)

harness.test("status definitions are owner-scoped and cleaned up on resource stop", function()
    _G.GetInvokingResource = function() return "definition_owner" end
    harness.assertTrue(Kora.status.registerEffect("owned_definition", { duration = 100 }),
        "the owner should register its definition")

    _G.GetInvokingResource = function() return "other_resource" end
    local registered, reason = Kora.status.registerEffect("owned_definition", { duration = 200 })
    harness.assertFalse(registered, "another resource must not replace the definition")
    harness.assertTrue(reason ~= nil, "the ownership refusal should explain why")
    harness.assertEqual(Kora.status.getEffectDef("owned_definition").duration, 100,
        "the foreign replacement must leave the original definition intact")

    net.fire("onClientResourceStop", "definition_owner")
    harness.assertEqual(Kora.status.getEffectDef("owned_definition"), nil,
        "stopping the owner should remove its definition")
    harness.assertTrue(Kora.status.registerEffect("owned_definition", { duration = 200 }),
        "the name should become available after cleanup")
    _G.GetInvokingResource = function() return nil end
end)

harness.test("status definitions cannot be mutated through caller tables or reads", function()
    local definition = { duration = 100, movement = { speedMultiplier = 0.8 } }
    harness.assertTrue(Kora.status.registerEffect("immutable_definition", definition),
        "the definition should register")

    definition.duration = 200
    definition.movement.speedMultiplier = 0.5
    local read = Kora.status.getEffectDef("immutable_definition")
    read.duration = 300
    read.movement.speedMultiplier = 0.2

    local stored = Kora.status.getEffectDef("immutable_definition")
    harness.assertEqual(stored.duration, 100, "caller mutations must not change the stored duration")
    harness.assertEqual(stored.movement.speedMultiplier, 0.8,
        "returned definitions must not expose nested live tables")
end)

harness.test("server apply rejects an unregistered effect name", function()
    local ok, err = serverApply(mocks.SOURCE, "not_a_real_effect")
    harness.assertFalse(ok, "applying an unknown effect should fail")
    harness.assertTrue(err ~= nil, "should explain the failure")
end)

harness.test("server status operations reject malformed target IDs", function()
    for _, operation in ipairs({ serverApply, serverRemove, serverIsActive, serverGetActive }) do
        harness.assertThrows(function()
            operation(1.5, "bleeding")
        end, "server status operations should require an integer target")
    end
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

Kora.status.apply = function() end
Kora.status.remove = function() end

harness.test("client-local apply/remove renders and tears down fx/anim/movement", function()
    clientApply("bleeding", { severity = 2 })

    harness.assertTrue(clientIsActive("bleeding"), "bleeding should be active after apply")
    harness.assertEqual(_G.__lastMoveRateOverride.mult, 0.95, "should apply the configured movement multiplier")

    local removed = clientRemove("bleeding")
    harness.assertTrue(removed, "remove should report true for an active effect")
    harness.assertFalse(clientIsActive("bleeding"), "bleeding should no longer be active after remove")
    harness.assertEqual(_G.__lastMoveRateOverride.mult, 1.0, "removing a movement-affecting effect should reset the override")
end)

harness.test('a failed visual setup rolls back earlier status visuals', function()
    Kora.status.registerEffect('rollback_visual', {
        fx = { screen = 'DrugsMichaelAliensFightIn', ptfx = { dict = 'broken_fx', name = 'broken' } },
    })
    local originalPlayPtfx = Kora.fx.playPtfx
    local stoppedBefore = #screenStops
    Kora.fx.playPtfx = function() error('ptfx setup failed') end

    harness.assertThrows(function() clientApply('rollback_visual') end)
    Kora.fx.playPtfx = originalPlayPtfx

    harness.assertEqual(#screenStops, stoppedBefore + 1,
        'a later visual failure must stop the screen effect that already started')
    harness.assertFalse(clientIsActive('rollback_visual'), 'a failed apply must not leave active state behind')
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

harness.test("status application validates public input before state changes", function()
    harness.assertThrows(function()
        serverApply(1.5, "bleeding")
    end, "a fractional server target should be rejected")
    harness.assertThrows(function()
        serverApply(mocks.SOURCE, "bleeding", { duration = -1 })
    end, "a negative server duration should be rejected")
    harness.assertThrows(function()
        serverApply(math.huge, "bleeding")
    end, "an infinite server target should be rejected")
    harness.assertThrows(function()
        serverApply(mocks.SOURCE, "bleeding", { duration = math.huge })
    end, "an infinite server duration should be rejected")
    harness.assertThrows(function()
        Kora.status.registerEffect("infinite_duration", { duration = math.huge })
    end, "an infinite definition duration should be rejected")
    harness.assertThrows(function()
        clientApply("bleeding", { severity = 1.5 })
    end, "a fractional client severity should be rejected")
    harness.assertThrows(function()
        clientApply("bleeding", { severity = math.huge })
    end, "an infinite client severity should be rejected")
    harness.assertThrows(function()
        clientApply("bleeding", "bad options")
    end, "non-table client options should be rejected")
    harness.assertThrows(function()
        serverRemove(mocks.SOURCE, false)
    end, "server removal should validate effect names")
    harness.assertThrows(function()
        serverIsActive(mocks.SOURCE, string.rep('x', 129))
    end, "server activity checks should validate effect-name length")
    harness.assertThrows(function()
        clientRemove(false)
    end, "client removal should validate effect names")
    harness.assertThrows(function()
        Kora.status.getEffectDef(false)
    end, "definition lookups should validate effect names")
end)

harness.test("severity is ignored consistently when an effect has no levels", function()
    serverApply(mocks.SOURCE, "high_weed", { severity = 1 })
    local serverEntry
    for _, entry in ipairs(serverGetActive(mocks.SOURCE)) do
        if entry.name == "high_weed" then serverEntry = entry end
    end
    harness.assertEqual(serverEntry.severity, nil, "server state should omit severity without configured levels")
    serverRemove(mocks.SOURCE, "high_weed")

    clientApply("high_weed", { severity = 1 })
    local clientEntry
    for _, entry in ipairs(clientGetActive()) do
        if entry.name == "high_weed" then clientEntry = entry end
    end
    harness.assertEqual(clientEntry.severity, nil, "client state should omit severity without configured levels")
    clientRemove("high_weed")
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
    local push = mocks.lastEntry(net.triggeredClientEvents, "kora_lib:events:push")
    harness.assertEqual(push[1], "kora_lib:status:apply")
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
    advanceClock(50)
    harness.assertFalse(serverIsActive(mocks.SOURCE, "extendable"), "an expired effect should report inactive")

    local stillThere = false
    for _, e in ipairs(serverGetActive(mocks.SOURCE)) do if e.name == "extendable" then stillThere = true end end
    harness.assertFalse(stillThere, "an expired effect should not appear in getActive")
end)

harness.test('server getActive reclaims expired entries immediately', function()
    serverApply(mocks.SOURCE, 'extendable', { duration = 10 })
    advanceClock(50)

    harness.assertEqual(#serverGetActive(mocks.SOURCE), 0)
    harness.assertFalse(serverRemove(mocks.SOURCE, 'extendable'),
        'a query must remove expired state rather than leave it for the coarse sweep')
end)

harness.test("client queries drop an expired effect before its cleanup thread runs", function()
    clientApply("extendable", { duration = 10 })
    advanceClock(50)
    harness.assertFalse(clientIsActive("extendable"), "client isActive should not report an overdue effect")
    harness.assertEqual(#clientGetActive(), 0, "client getActive should exclude overdue effects")
end)

harness.test("client getActive batches movement reconciliation for expired effects", function()
    clientApply("bleeding", { duration = 10, severity = 1 })
    clientApply("injured_leg", { duration = 10 })
    moveRateCalls = 0
    advanceClock(50)

    harness.assertEqual(#clientGetActive(), 0, "expired effects should not remain active")
    harness.assertEqual(moveRateCalls, 1, "one query cleanup should reconcile movement once")
end)

harness.test("foreign resources cannot remove status change listeners", function()
    _G.GetInvokingResource = function() return "status_listener_owner" end
    local calls = 0
    local listenerId = Kora.status.onChange(function() calls = calls + 1 end)

    _G.GetInvokingResource = function() return "other_resource" end
    harness.assertFalse(Kora.status.offChange(listenerId), "a foreign resource must not remove the listener")
    clientApply("injured_leg")
    clientRemove("injured_leg")
    harness.assertEqual(calls, 2, "the foreign removal must leave the listener active")

    _G.GetInvokingResource = function() return "status_listener_owner" end
    harness.assertTrue(Kora.status.offChange(listenerId), "the owner should remove the listener")
    _G.GetInvokingResource = function() return nil end
end)

harness.test("foreign resources cannot replace or remove active status effects", function()
    _G.GetInvokingResource = function() return "status_effect_owner" end
    harness.assertTrue(clientApply("injured_leg"), "the owner should apply its effect")

    _G.GetInvokingResource = function() return "other_resource" end
    harness.assertFalse(clientApply("injured_leg"), "a foreign resource must not replace the active effect")
    harness.assertFalse(clientRemove("injured_leg"), "a foreign resource must not remove the active effect")
    harness.assertTrue(clientIsActive("injured_leg"), "the foreign mutation must leave the effect active")

    _G.GetInvokingResource = function() return "status_effect_owner" end
    harness.assertTrue(clientRemove("injured_leg"), "the owner should remove its effect")
    _G.GetInvokingResource = function() return nil end
end)

harness.test("internal status updates can replace a locally owned effect", function()
    _G.GetInvokingResource = function() return "status_effect_owner" end
    harness.assertTrue(clientApply("injured_leg"), "the resource should apply its cosmetic effect")

    _G.GetInvokingResource = function() return nil end
    harness.assertTrue(clientApply("injured_leg"), "an internal update should replace the local effect")
    harness.assertTrue(clientRemove("injured_leg"), "kora_lib should still clean up its authoritative effect")
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
