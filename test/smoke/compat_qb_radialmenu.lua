local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")

local sentItems = nil
local nextRadialResult = nil

Kora.nui = {
    openRadialMenu = function(items)
        sentItems = items
        local answer = nextRadialResult
        nextRadialResult = { cancelled = true }
        local p = promise.new()
        p:resolve(answer)
        return p
    end,
}

local progressCompletes = true
Kora.progressbar = { start = function() return progressCompletes end }
Kora.keybind = {
    add = function(options)
        net.commands[options.name] = options.onPressed
        return { remove = function() return true end }
    end,
}

dofile(repoRoot .. "compat/shared.lua")

local playerJob = { name = nil, onduty = false }
local playerMetadata = {}
local jobDefs = { police = { type = "leo" }, ambulance = { type = "ems" }, unemployed = { type = "civ" } }

_G.exports = {
    kora_core = {
        getPlayerData = function(_, path)
            if type(path) == "table" and path[1] == "job" then return playerJob end
            if type(path) == "table" and path[1] == "metadata" then return playerMetadata end
            return {}
        end,
        getShared = function(_, collection, key)
            if collection == "jobs" then return jobDefs[key] end
            return nil
        end,
    },
}

local vehicleState = {
    pedVehicle = 0,
    nearestVehicle = 0,
    onAllWheels = true,
    seatCount = 4,
    speed = 0,
    doorAngle = {},
    extraExists = {},
    extraOn = {},
    seatFree = {},
}

_G.PlayerPedId = function() return 1 end
_G.GetEntityCoords = function() return { x = 0.0, y = 0.0, z = 0.0 } end
_G.GetOffsetFromEntityInWorldCoords = function() return { x = 0.0, y = 20.0, z = 0.0 } end
_G.CastRayPointToPoint = function() return 1 end
_G.GetRaycastResult = function() return 1, false, nil, nil, vehicleState.nearestVehicle end
_G.GetVehiclePedIsIn = function() return vehicleState.pedVehicle end
_G.IsVehicleOnAllWheels = function() return vehicleState.onAllWheels end
_G.IsPedInAnyVehicle = function() return vehicleState.pedVehicle ~= 0 end
_G.GetVehicleModelNumberOfSeats = function() return vehicleState.seatCount end
_G.GetEntityModel = function() return 1 end
_G.GetPedInVehicleSeat = function(_, seat) if seat == -1 then return vehicleState.pedVehicle ~= 0 and 1 or 0 end; return 0 end
_G.GetVehicleDoorAngleRatio = function(_, door) return vehicleState.doorAngle[door] or 0.0 end
_G.SetVehicleDoorShut = function(_, door) vehicleState.doorAngle[door] = 0.0 end
_G.SetVehicleDoorOpen = function(_, door) vehicleState.doorAngle[door] = 1.0 end
_G.DoesExtraExist = function(_, extra) return vehicleState.extraExists[extra] ~= false end
_G.IsVehicleExtraTurnedOn = function(_, extra) return vehicleState.extraOn[extra] == true end
_G.SetVehicleExtra = function(_, extra, state) vehicleState.extraOn[extra] = (state == 0) end
_G.SetVehicleAutoRepairDisabled = function() end
_G.IsVehicleSeatFree = function(_, seat) return vehicleState.seatFree[seat] ~= false end
_G.GetEntitySpeed = function() return vehicleState.speed end
_G.SetPedIntoVehicle = function() end
_G.SetVehicleOnGroundProperly = function() end

dofile(repoRoot .. "compat/client/qb-radialmenu.lua")

local function getExport(providedResource, exportName)
    local handlers = net.eventHandlers[("__cfx_export_%s_%s"):format(providedResource, exportName)]
    harness.assertTrue(handlers ~= nil and handlers[1] ~= nil, exportName .. " should be registered")

    local captured
    handlers[1](function(fn) captured = fn end)
    return captured
end

local AddOption = getExport("qb-radialmenu", "AddOption")
local RemoveOption = getExport("qb-radialmenu", "RemoveOption")

local function itemById(items, id)
    for _, item in ipairs(items) do
        if item.id == tostring(id) then return item end
    end
    return nil
end

local function openRadial()
    harness.assertTrue(net.commands ~= nil and net.commands["qblib_radialmenu_open"] ~= nil,
        "qblib_radialmenu_open should be registered")
    net.commands["qblib_radialmenu_open"](0, {}, "")
end

harness.test("AddOption returns a generated id and RemoveOption clears it from the wheel", function()
    local anchorId = AddOption({ title = "Anchor" })
    local id = AddOption({ title = "Repair" })
    harness.assertTrue(id ~= nil, "AddOption should return an id")

    nextRadialResult = { cancelled = true }
    openRadial()
    harness.assertTrue(itemById(sentItems, id) ~= nil, "the option should appear in the wheel")

    RemoveOption(id)
    nextRadialResult = { cancelled = true }
    openRadial()
    harness.assertTrue(itemById(sentItems, id) == nil, "a removed option should not appear in the wheel")
    harness.assertTrue(itemById(sentItems, anchorId) ~= nil, "an unrelated option should survive the removal")

    RemoveOption(anchorId)
end)

harness.test("AddOption's non-boolean second argument is an explicit id, matching real qb-radialmenu", function()
    local id = AddOption({ title = "Job Menu" }, "jobinteractions")
    harness.assertEqual(id, "jobinteractions", "a string second argument should become the option's id")

    local id2 = AddOption({ title = "Job Menu (on duty)" }, "jobinteractions")
    harness.assertEqual(id2, "jobinteractions")

    nextRadialResult = { cancelled = true }
    openRadial()
    local matches = 0
    for _, item in ipairs(sentItems) do
        if item.id == "jobinteractions" then matches = matches + 1 end
    end
    harness.assertEqual(matches, 1, "re-registering at the same explicit id should not duplicate the entry")
    harness.assertEqual(itemById(sentItems, "jobinteractions").label, "Job Menu (on duty)",
        "the update-in-place registration should win")

    RemoveOption("jobinteractions")
end)

harness.test("AddOption's boolean second argument is still honoured as shouldClose", function()
    local id = AddOption({ title = "Stay Open" }, false)
    local option = nil
    harness.assertTrue(id ~= "false" and id ~= "true", "a boolean second argument should not become the id")
    RemoveOption(id)
end)

harness.test("selecting an option with an event fires TriggerEvent/TriggerServerEvent", function()
    local clientId = AddOption({ title = "Client Action", type = "client", event = "test:client:action" })
    local serverId = AddOption({ title = "Server Action", type = "server", event = "test:server:action" })

    local clientFired, serverFired = false, false
    net.eventHandlers["test:client:action"] = { function() clientFired = true end }

    nextRadialResult = { selectedId = tostring(clientId) }
    openRadial()
    harness.assertTrue(clientFired, "a client-type option should fire TriggerEvent")

    nextRadialResult = { selectedId = tostring(serverId) }
    openRadial()
    harness.assertTrue(net.triggeredServerEvents[#net.triggeredServerEvents].name == "test:server:action",
        "a server-type option should fire TriggerServerEvent")

    RemoveOption(clientId)
    RemoveOption(serverId)
end)

harness.test("a registered option's nested items[] becomes a submenu, and a nested leaf still dispatches", function()
    local fired = false
    net.eventHandlers["test:nested:repair"] = { function() fired = true end }

    local id = AddOption({
        title = "Vehicle",
        items = {
            { title = "Repair", type = "client", event = "test:nested:repair" },
        },
    })

    nextRadialResult = { cancelled = true }
    openRadial()

    local branch = itemById(sentItems, id)
    harness.assertTrue(branch ~= nil, "the branch option should appear at the top level")
    harness.assertTrue(branch.submenu ~= nil, "an option with nested items should translate to a submenu")
    harness.assertEqual(branch.submenu.title, "Vehicle", "submenu title should default to the branch's own title")
    harness.assertEqual(#branch.submenu.items, 1, "the nested item should appear inside the submenu")

    local leafId = branch.submenu.items[1].id
    harness.assertTrue(leafId ~= nil, "a nested leaf should get a stable id even if the caller didn't set one")

    nextRadialResult = { selectedId = leafId, path = { id, leafId } }
    openRadial()
    harness.assertTrue(fired, "selecting a nested leaf (by its own id, from the result's path) must still dispatch")

    RemoveOption(id)
end)

harness.test("the qb-radialmenu:client:AddOption/RemoveOption net events mirror the exports", function()
    local anchorId = AddOption({ title = "Anchor" })
    local id

    net.fire("qb-radialmenu:client:AddOption", { title = "Via Event" })

    nextRadialResult = { cancelled = true }
    openRadial()
    harness.assertTrue(#sentItems >= 1, "the net event should register an option the same as the export")

    for _, item in ipairs(sentItems) do
        if item.label == "Via Event" then id = item.id end
    end
    harness.assertTrue(id ~= nil, "the net-event-registered option should be findable")

    net.fire("qb-radialmenu:client:RemoveOption", id)
    nextRadialResult = { cancelled = true }
    openRadial()
    harness.assertTrue(itemById(sentItems, id) == nil, "the net event should remove the option the same as the export")

    RemoveOption(anchorId)
end)

local function resetVehicleState()
    vehicleState.pedVehicle = 0
    vehicleState.nearestVehicle = 0
    vehicleState.onAllWheels = true
    vehicleState.seatCount = 4
    vehicleState.speed = 0
    vehicleState.doorAngle = {}
    vehicleState.extraExists = {}
    vehicleState.extraOn = {}
    vehicleState.seatFree = {}
end

local function resetPlayerData()
    playerJob.name = nil
    playerJob.onduty = false
    playerMetadata = {}
end

harness.test("no Vehicle/Work submenu appears with no nearby vehicle and no job", function()
    resetVehicleState()
    resetPlayerData()

    sentItems = nil
    nextRadialResult = { cancelled = true }
    openRadial()
    harness.assertTrue(sentItems == nil, "an empty wheel should never call Kora.nui.openRadialMenu")
end)

harness.test("a nearby vehicle produces a Vehicle submenu with doors and extras nested, but no flip/seats", function()
    resetVehicleState()
    resetPlayerData()
    vehicleState.nearestVehicle = 99

    nextRadialResult = { cancelled = true }
    openRadial()

    local vehicleItem = itemById(sentItems, "qblib_radialmenu_vehicle")
    harness.assertTrue(vehicleItem ~= nil, "a nearby vehicle should produce the built-in Vehicle option")
    harness.assertTrue(vehicleItem.submenu ~= nil, "the Vehicle option should be a submenu")

    local doors = itemById(vehicleItem.submenu.items, "vehicledoors")
    harness.assertTrue(doors ~= nil and doors.submenu ~= nil, "Vehicle Doors should be nested inside")
    harness.assertEqual(#doors.submenu.items, 6, "all 6 real qb-radialmenu door entries should be present")

    local extras = itemById(vehicleItem.submenu.items, "vehicleextras")
    harness.assertTrue(extras ~= nil and #extras.submenu.items == 13, "13 extras should be present by default")

    harness.assertTrue(itemById(vehicleItem.submenu.items, "vehicle-flip") == nil,
        "flip should not appear while the vehicle is on all wheels")
    harness.assertTrue(itemById(vehicleItem.submenu.items, "vehicleseats") == nil,
        "seats should not appear while not occupying the vehicle")
end)

harness.test("flip appears only when off its wheels, seats only while occupying it", function()
    resetVehicleState()
    resetPlayerData()
    vehicleState.pedVehicle = 99
    vehicleState.onAllWheels = false
    vehicleState.seatCount = 2

    nextRadialResult = { cancelled = true }
    openRadial()

    local vehicleItem = itemById(sentItems, "qblib_radialmenu_vehicle")
    harness.assertTrue(itemById(vehicleItem.submenu.items, "vehicle-flip") ~= nil,
        "flip should appear once the vehicle is not on all its wheels")

    local seats = itemById(vehicleItem.submenu.items, "vehicleseats")
    harness.assertTrue(seats ~= nil, "seats should appear while occupying the vehicle")
    harness.assertEqual(#seats.submenu.items, 2, "one entry per real seat, matching GetVehicleModelNumberOfSeats")
end)

harness.test("selecting a door toggles it via the real vehicle-door natives", function()
    resetVehicleState()
    resetPlayerData()
    vehicleState.pedVehicle = 99

    nextRadialResult = { cancelled = true }
    openRadial()
    local vehicleItem = itemById(sentItems, "qblib_radialmenu_vehicle")
    local doorsSubmenu = itemById(vehicleItem.submenu.items, "vehicledoors").submenu.items
    local trunk = itemById(doorsSubmenu, "door5")
    harness.assertTrue(trunk ~= nil, "the trunk door entry should exist")

    harness.assertEqual(vehicleState.doorAngle[5] or 0.0, 0.0, "the trunk should start closed")
    nextRadialResult = { selectedId = trunk.id }
    openRadial()
    harness.assertEqual(vehicleState.doorAngle[5], 1.0, "selecting a closed door should open it")

    nextRadialResult = { selectedId = trunk.id }
    openRadial()
    harness.assertEqual(vehicleState.doorAngle[5], 0.0, "selecting an open door should shut it")
end)

harness.test("selecting an extra toggles it only for the driver", function()
    resetVehicleState()
    resetPlayerData()
    vehicleState.pedVehicle = 99

    nextRadialResult = { cancelled = true }
    openRadial()
    local vehicleItem = itemById(sentItems, "qblib_radialmenu_vehicle")
    local extrasSubmenu = itemById(vehicleItem.submenu.items, "vehicleextras").submenu.items
    local extra1 = itemById(extrasSubmenu, "extra1")

    nextRadialResult = { selectedId = extra1.id }
    openRadial()
    harness.assertTrue(vehicleState.extraOn[1], "the driver should be able to toggle an extra on")
end)

harness.test("flipping a vehicle runs the progress bar and only flips it on completion", function()
    resetVehicleState()
    resetPlayerData()
    vehicleState.pedVehicle = 99
    vehicleState.onAllWheels = false
    local grounded = false
    _G.SetVehicleOnGroundProperly = function() grounded = true end

    nextRadialResult = { cancelled = true }
    openRadial()
    local vehicleItem = itemById(sentItems, "qblib_radialmenu_vehicle")
    local flip = itemById(vehicleItem.submenu.items, "vehicle-flip")

    progressCompletes = false
    nextRadialResult = { selectedId = flip.id }
    openRadial()
    harness.assertFalse(grounded, "a cancelled progress bar should not flip the vehicle")

    progressCompletes = true
    nextRadialResult = { selectedId = flip.id }
    openRadial()
    harness.assertTrue(grounded, "a completed progress bar should flip the vehicle")

    _G.SetVehicleOnGroundProperly = function() end
end)

harness.test("the Work submenu only appears while on duty in a configured job", function()
    resetVehicleState()
    resetPlayerData()
    playerJob.name = "ambulance"
    playerJob.onduty = false

    nextRadialResult = { cancelled = true }
    openRadial()
    harness.assertTrue(sentItems == nil or itemById(sentItems, "qblib_radialmenu_job") == nil,
        "an off-duty job should not show the Work submenu")

    playerJob.onduty = true
    nextRadialResult = { cancelled = true }
    openRadial()
    local work = itemById(sentItems, "qblib_radialmenu_job")
    harness.assertTrue(work ~= nil, "an on-duty configured job should show the Work submenu")
    harness.assertTrue(itemById(work.submenu.items, "revivep") ~= nil, "ambulance's configured entries should be nested")
end)

harness.test("an 'leo'-type job collapses onto the 'police' JobInteractions key", function()
    resetVehicleState()
    resetPlayerData()
    playerJob.name = "police"
    playerJob.onduty = true

    nextRadialResult = { cancelled = true }
    openRadial()
    local work = itemById(sentItems, "qblib_radialmenu_job")
    harness.assertTrue(work ~= nil, "an on-duty leo-type job should show the Work submenu")
    harness.assertTrue(itemById(work.submenu.items, "emergencybutton") ~= nil,
        "the police JobInteractions entry should be reachable via the leo type override")
end)

harness.test("selecting a 'command'-type option runs it through ExecuteCommand, not TriggerEvent", function()
    resetVehicleState()
    resetPlayerData()
    playerJob.name = "police"
    playerJob.onduty = true

    local backupCalled = false
    net.commands["backup"] = function() backupCalled = true end

    nextRadialResult = { cancelled = true }
    openRadial()
    local work = itemById(sentItems, "qblib_radialmenu_job")
    local emergency = itemById(work.submenu.items, "emergencybutton")

    nextRadialResult = { selectedId = emergency.id }
    openRadial()
    harness.assertTrue(backupCalled, "a type='command' option should ExecuteCommand its event, not TriggerEvent it")
end)

harness.test("a downed non-police/EMS player cannot open the wheel at all", function()
    resetVehicleState()
    resetPlayerData()
    playerMetadata.isdead = true

    nextRadialResult = { selectedId = "should-not-be-read" }
    sentItems = nil
    openRadial()
    harness.assertTrue(sentItems == nil, "a downed civilian should never reach Kora.nui.openRadialMenu at all")
end)

harness.test("a downed police/EMS player sees only the emergency button, bypassing the normal registry", function()
    resetVehicleState()
    resetPlayerData()
    playerJob.name = "ambulance"
    playerJob.onduty = true
    playerMetadata.inlaststand = true
    vehicleState.nearestVehicle = 99

    local backupCalled = false
    net.commands["backup"] = function() backupCalled = true end

    nextRadialResult = { cancelled = true }
    openRadial()
    harness.assertEqual(#sentItems, 1, "downed police/EMS should see exactly the emergency button, nothing else")
    harness.assertTrue(itemById(sentItems, "qblib_radialmenu_vehicle") == nil,
        "the normal registry (Vehicle/Work/anything registered) must be bypassed while downed")

    nextRadialResult = { selectedId = sentItems[1].id }
    openRadial()
    harness.assertTrue(backupCalled, "selecting the downed emergency button should still dispatch it")
end)

harness.test("a handcuffed player cannot open the wheel", function()
    resetVehicleState()
    resetPlayerData()
    vehicleState.nearestVehicle = 99
    playerMetadata.ishandcuffed = true

    sentItems = nil
    nextRadialResult = { cancelled = true }
    openRadial()
    harness.assertTrue(sentItems == nil, "a handcuffed player should never reach Kora.nui.openRadialMenu")
end)

resetVehicleState()
resetPlayerData()

harness.test("AddOption without an id returns a numeric id", function()
    local id = AddOption({ title = "Numeric" })
    harness.assertEqual(math.type(id), "integer", "a generated id should be numeric, as upstream")
    RemoveOption(id)
end)

harness.test("onRadialmenuOpen and onRadialmenuClose fire around the wheel", function()
    local log = {}
    net.eventHandlers["qb-radialmenu:client:onRadialmenuOpen"] = { function() log[#log + 1] = "open" end }
    net.eventHandlers["qb-radialmenu:client:onRadialmenuClose"] = { function() log[#log + 1] = "close" end }
    local id = AddOption({ title = "Evented" })
    nextRadialResult = { cancelled = true }
    openRadial()
    harness.assertEqual(table.concat(log, ","), "open,close", "open then close should fire once each")
    RemoveOption(id)
    net.eventHandlers["qb-radialmenu:client:onRadialmenuOpen"] = nil
    net.eventHandlers["qb-radialmenu:client:onRadialmenuClose"] = nil
end)

harness.test("changeSeat is refused while HasHarness is true", function()
    local seated = 0
    _G.SetPedIntoVehicle = function() seated = seated + 1 end
    _G.GetVehiclePedIsIn = function() return 7 end
    _G.IsVehicleSeatFree = function() return true end
    _G.GetEntitySpeed = function() return 0.0 end
    local harnessOn = true
    _G.exports["qb-smallresources"] = { HasHarness = function() return harnessOn end }
    net.fire("kora_lib:radialmenuCompat:client:changeSeat", { seatIndex = 0 })
    harness.assertEqual(seated, 0, "a harnessed player must not switch seats")
    harnessOn = false
    net.fire("kora_lib:radialmenuCompat:client:changeSeat", { seatIndex = 0 })
    harness.assertEqual(seated, 1, "without a harness the seat change should proceed")
    _G.exports["qb-smallresources"] = nil
end)

harness.report("compat_qb_radialmenu")
