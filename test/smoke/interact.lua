local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local mockHandle = mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")
dofile(repoRoot .. "local/resources/client.lua")

local nuiCallbacks = {}
local nuiMessages = {}
local focusCalls = {}
local pressedControls = {}
local disabledControls = {}
local sphereOptions = {}
local boxOptions = {}
local player = { job = { name = "police" }, gang = { name = "ballas" }, citizenid = "CID-1" }
local inventory = { key = true }
local removedZones = 0
local targetRegistrations = {}

_G.RegisterNUICallback = function(name, fn) nuiCallbacks[name] = fn end
_G.SendNUIMessage = function(message) nuiMessages[#nuiMessages + 1] = message end
_G.SetNuiFocus = function(mouse, keyboard) focusCalls[#focusCalls + 1] = { mouse, keyboard } end
_G.DisableControlAction = function(_, control) disabledControls[control] = true end
_G.PlayerId = function() return 1 end
_G.DisablePlayerFiring = function() end
_G.IsDisabledControlJustPressed = function(_, control) return pressedControls[control] == true end

_G.exports = {
    ["qb-core"] = {
        GetPlayerData = function() return player end,
    },
    ["qb-inventory"] = {
        HasItem = function(_, item) return inventory[item] == true end,
    },
    qbtarget = {
        addEntity = function(_, entity, options, distance)
            targetRegistrations[#targetRegistrations + 1] = { kind = 'entity', value = entity, options = options, distance = distance }
            return #targetRegistrations
        end,
        addModel = function(_, model, options, distance)
            targetRegistrations[#targetRegistrations + 1] = { kind = 'model', value = model, options = options, distance = distance }
            return #targetRegistrations
        end,
        removeEntity = function() return true end,
        removeModel = function() return true end,
    },
}

local function newZone(options)
    return {
        remove = function()
            removedZones = removedZones + 1
        end,
        options = options,
    }
end

QB.zones = {
    sphere = function(options)
        sphereOptions[#sphereOptions + 1] = options
        return newZone(options)
    end,
    box = function(options)
        boxOptions[#boxOptions + 1] = options
        return newZone(options)
    end,
}

_G.GetGamePool = function() return { 101 } end
_G.GetEntityModel = function(entity) return entity == 101 and 12345 or 0 end
_G.GetHashKey = function(model) return model == "prop_locker" and 12345 or 0 end
_G.GetEntityCoords = function(entity) return { x = entity, y = 20, z = 30 } end
_G.GetEntityHeading = function() return 45 end

dofile(repoRoot .. "modules/nui/client.lua")
dofile(repoRoot .. "modules/controls/client.lua")
dofile(repoRoot .. "modules/interact/client.lua")

local function reset()
    QB.interact.close()
    Config.ui.interact = true
    nuiMessages = {}
    focusCalls = {}
    pressedControls = {}
    disabledControls = {}
    sphereOptions = {}
    boxOptions = {}
    removedZones = 0
    targetRegistrations = {}
    player = { job = { name = "police" }, gang = { name = "ballas" }, citizenid = "CID-1" }
    inventory = { key = true }
end

local function lastMessage()
    return nuiMessages[#nuiMessages]
end

harness.test("open sends compact labels without taking NUI focus", function()
    reset()

    local opened = QB.interact.open({
        { label = "Inspect", event = "ignored", args = { "private" } },
        { label = "Open", action = function() end },
    })

    harness.assertTrue(opened, "an available option should open the selector")
    harness.assertEqual(lastMessage().action, "openInteract", "the selector should receive its legacy open action")
    harness.assertEqual(lastMessage().data[1].label, "Inspect", "only labels should reach the browser")
    harness.assertTrue(lastMessage().data[1].event == nil, "NUI must never receive a dispatch event")
    harness.assertEqual(#focusCalls, 0, "a game-input selector must never change NUI focus")

    for _, control in ipairs(Config.interact.selectControls) do
        harness.assertTrue(disabledControls[control] == true, "active selector controls should be disabled at the game layer")
    end
end)

harness.test('aim-target facade translates qblib actions and restrictions', function()
    reset()
    local selected = 0
    local id = QB.interact.addEntity(202, {
        { label = 'Use', job = 'police', action = function() selected = selected + 1 end },
    }, 2.0)
    local registration = targetRegistrations[id]
    harness.assertEqual(registration.kind, 'entity', 'should register through qbtarget')
    harness.assertEqual(registration.distance, 2.0, 'should retain default distance')
    harness.assertTrue(registration.options[1].canInteract(202, 1.0, {}), 'job restriction should be evaluated by qblib')
    registration.options[1].onSelect(202, {})
    harness.assertEqual(selected, 1, 'target selection should dispatch the qblib action')
end)

harness.test("selectOption dispatches the selected client event once and hides", function()
    reset()
    local dispatches = 0
    AddEventHandler("interact:client", function(value)
        if value == "hello" then dispatches = dispatches + 1 end
    end)

    QB.interact.open({
        { label = "First" },
        { label = "Second", event = "interact:client", args = { "hello" } },
    })

    local response
    nuiCallbacks.selectOption(2, function(value) response = value end)

    harness.assertEqual(dispatches, 1, "the selected option should dispatch its client event")
    harness.assertFalse(QB.interact.isActive(), "selection should settle the active session")
    harness.assertEqual(lastMessage().action, "hideInteract", "selection should close the selector before dispatch")
    harness.assertTrue(type(response) == "table", "the NUI callback should always respond")
end)

-- exports.qblib:addCircleZone(...)/addBoxZone(...) are real cross-resource
-- entry points -- a `function` value another resource puts on `option.action`
-- or `option.canInteract` crosses that boundary as a table with a __call
-- metamethod, not a real function (FXServer's own funcref marshalling; see
-- compat/client/qb-menu.lua's identical fix and its test for the same
-- pattern). dispatch()/isAvailable() already route both fields through the
-- local isCallable() here, but nothing exercised that until now.
harness.test("dispatch still invokes a masked cross-resource function action", function()
    reset()
    local fired = 0
    local maskedAction = setmetatable({}, { __call = function(_) fired = fired + 1 end })

    QB.interact.open({ { label = "Only", action = maskedAction } })
    nuiCallbacks.selectOption(1, function() end)

    harness.assertEqual(fired, 1, "a masked cross-resource function action should still be invoked")
end)

harness.test("isAvailable still honours a masked cross-resource canInteract", function()
    reset()
    local maskedAllow = setmetatable({}, { __call = function(_) return true end })
    local maskedDeny = setmetatable({}, { __call = function(_) return false end })

    QB.interact.open({
        { label = "Allowed", canInteract = maskedAllow },
        { label = "Denied", canInteract = maskedDeny },
    })

    harness.assertEqual(#lastMessage().data, 1, "only the option whose masked canInteract returns true should be offered")
    harness.assertEqual(lastMessage().data[1].label, "Allowed", "the allowed option should be the one that reaches the NUI")
end)

harness.test("game controls and mouse scroll/select without NUI focus", function()
    reset()
    QB.interact.open({ { label = "First" }, { label = "Second" } })

    pressedControls[22] = true -- INPUT_JUMP / Space
    mockHandle.step()
    harness.assertEqual(lastMessage().action, "openInteract", "Space must not select the highlighted option")

    pressedControls = { [Config.interact.selectControls[1]] = true }
    mockHandle.step()
    harness.assertEqual(lastMessage().action, "select", "E should select the highlighted option")

    pressedControls = { [Config.interact.nextControls[1]] = true }
    mockHandle.step()
    harness.assertEqual(lastMessage().action, "scroll", "down control should send a scroll message")
    harness.assertEqual(lastMessage().data, 1, "down control should move forward")

    pressedControls = { [15] = true } -- INPUT_WEAPON_WHEEL_PREV / Mouse wheel up
    mockHandle.step()
    harness.assertEqual(lastMessage().action, "scroll", "mouse wheel up should send a scroll message")
    harness.assertEqual(lastMessage().data, -1, "mouse wheel up should move backward")

    pressedControls = { [14] = true } -- INPUT_WEAPON_WHEEL_NEXT / Mouse wheel down
    mockHandle.step()
    harness.assertEqual(lastMessage().action, "scroll", "mouse wheel down should send a scroll message")
    harness.assertEqual(lastMessage().data, 1, "mouse wheel down should move forward")

    pressedControls = { [24] = true } -- INPUT_ATTACK / Left mouse button
    mockHandle.step()
    harness.assertEqual(lastMessage().action, "select", "left-click should select the highlighted option")

    pressedControls = { [Config.interact.cancelControls[1]] = true }
    mockHandle.step()
    harness.assertEqual(lastMessage().action, "hideInteract", "cancel should hide the selector")
    harness.assertFalse(QB.interact.isActive(), "cancel should clear the session")
    harness.assertEqual(#focusCalls, 0, "control handling must remain focus-free")
end)

harness.test("closing and replacing a selector release its control lease", function()
    reset()
    QB.interact.open({ { label = "First" } })
    QB.interact.open({ { label = "Replacement" } })
    QB.interact.close()

    disabledControls = {}
    mockHandle.step()
    harness.assertTrue(next(disabledControls) == nil,
        "no interaction controls should remain disabled after the replacement closes")
end)

harness.test("the invoking resource stopping closes its selector and releases controls", function()
    reset()
    _G.GetInvokingResource = function() return "consumer_resource" end
    QB.interact.open({ { label = "Owned" } })
    _G.GetInvokingResource = function() return nil end

    mockHandle.fire("onClientResourceStop", "consumer_resource")
    harness.assertFalse(QB.interact.isActive(), "the stopped resource's selector should close")

    disabledControls = {}
    mockHandle.step()
    harness.assertTrue(next(disabledControls) == nil, "resource cleanup should release the selector's controls")
end)

harness.test("circle zones filter unavailable options and close only their own session", function()
    reset()
    local zone = QB.interact.addCircleZone("locker", { x = 0, y = 0, z = 0 }, 2, {
        { label = "Police locker", job = "police", item = "key" },
        { label = "Ballas locker", gang = "lostmc" },
        { label = "Unavailable", canInteract = function() return false end },
    }, false)

    harness.assertTrue(zone ~= nil, "circle zone should be created through QB.zones")
    sphereOptions[1].onEnter()
    harness.assertEqual(lastMessage().action, "openInteract", "zone entry should open the selector")
    harness.assertEqual(#lastMessage().data, 1, "unavailable options must be omitted without sparse-array holes")
    harness.assertEqual(lastMessage().data[1].label, "Police locker", "the matching option should remain")

    sphereOptions[1].onExit()
    harness.assertEqual(lastMessage().action, "hideInteract", "leaving the active zone should close its selector")
end)

harness.test("box zones pass coords, size, and rotation straight through", function()
    reset()
    QB.interact.addBoxZone("counter", { x = 10, y = 20, z = 30 }, { x = 4, y = 6, z = 10, w = 90 },
        { { label = "Use" } }, false)

    local box = boxOptions[1]
    harness.assertEqual(box.coords.x, 10, "the zone centre x should match the given coords")
    harness.assertEqual(box.coords.y, 20, "the zone centre y should match the given coords")
    harness.assertEqual(box.coords.z, 30, "the zone centre z should match the given coords")
    harness.assertEqual(box.size.x, 4, "size.x should pass through unchanged")
    harness.assertEqual(box.size.y, 6, "size.y should pass through unchanged")
    harness.assertEqual(box.size.z, 10, "size.z should pass through unchanged")
    harness.assertEqual(box.rotation, 90, "size.w should map to qblib rotation")
end)

harness.test("named zones replace and remove cleanly", function()
    reset()
    QB.interact.addCircleZone("replace-me", { x = 0, y = 0, z = 0 }, 1, {}, { options = { { label = "One" } } })
    QB.interact.addCircleZone("replace-me", { x = 1, y = 1, z = 1 }, 1, {}, { options = { { label = "Two" } } })

    harness.assertEqual(removedZones, 1, "replacing a name should remove its prior zone")
    harness.assertTrue(QB.interact.removeZone("replace-me"), "removing an existing name should succeed")
    harness.assertEqual(removedZones, 2, "removeZone should call the underlying handle")
    harness.assertFalse(QB.interact.removeZone("replace-me"), "removed names should not be removed twice")
end)

harness.test("target model and entity helpers create static box zones", function()
    reset()
    local modelZones = QB.interact.addTargetModel("prop_locker", { x = 2, y = 4, z = 6, w = 45 },
        { { label = "Open" } }, false)
    local entityZone = QB.interact.addTargetEntity(202, { x = 3, y = 3, z = 4, w = 45 },
        { { label = "Use" } }, false)

    harness.assertEqual(#modelZones, 1, "a streamed matching object should receive a zone")
    harness.assertTrue(entityZone ~= nil, "an entity should receive a static zone")
    harness.assertEqual(boxOptions[1].size.x, 2, "model helper should preserve custom X size")
    harness.assertEqual(boxOptions[1].size.y, 4, "model helper should preserve custom Y size")
    harness.assertEqual(boxOptions[1].size.z, 6, "model helper should preserve custom Z size")
end)

harness.test("disabled interact mode creates no zones or UI", function()
    reset()
    Config.ui.interact = false

    harness.assertFalse(QB.interact.open({ { label = "Nope" } }), "open should no-op while disabled")
    harness.assertTrue(QB.interact.addCircleZone("off", { x = 0, y = 0, z = 0 }, 1, {}, { options = { { label = "Nope" } } }) == nil,
        "zones should not be created while disabled")
    harness.assertEqual(#nuiMessages, 0, "disabled mode should leave the NUI untouched")
end)

harness.report("interact")
