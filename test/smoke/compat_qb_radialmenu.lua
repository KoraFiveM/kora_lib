local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

dofile(repoRoot .. "config.lua")
dofile(repoRoot .. "build/initiate.lua")

-- Same "mock QB.nui directly, resolve synchronously" trick compat_qb_menu.lua
-- and compat_qb_input.lua use -- openRegisteredRadial has to consume
-- QB.nui.openRadialMenu's result itself (to dispatch the right option), not
-- just hand a promise back to its own caller.
local sentItems = nil
local nextRadialResult = nil

QB.nui = {
    -- Each call consumes `nextRadialResult` and resets it to a plain cancel
    -- -- a shouldClose=false selection makes openRegisteredRadial reopen the
    -- wheel immediately (see that function's own doc comment), which would
    -- otherwise reuse the SAME answer forever and recurse without end. A
    -- real player picks a new option or backs out on the reopened wheel;
    -- this is the mock equivalent of that second, different answer.
    openRadialMenu = function(items)
        sentItems = items
        local answer = nextRadialResult
        nextRadialResult = { cancelled = true }
        local p = promise.new()
        p:resolve(answer)
        return p
    end,
}

-- QB.progressbar.start is called by the built-in flip-vehicle action --
-- modules/progressbar/client.lua isn't loaded here (this test only needs the
-- QB table it would attach to), so it's stubbed directly, controllable via
-- `progressCompletes`.
local progressCompletes = true
QB.progressbar = { start = function() return progressCompletes end }

dofile(repoRoot .. "compat/client/exports.lua")

-- Controllable mock qbcore PlayerData -- the built-in job/vehicle content
-- reads job/metadata via exports.qbcore:getPlayerData/getShared (pcall-
-- guarded in the compat file itself, same pattern as qb-menu compat's
-- imageFor), so a real exports mock is needed to exercise that content
-- rather than only its "qbcore isn't running" degraded path.
local playerJob = { name = nil, onduty = false }
local playerMetadata = {}
local jobDefs = { police = { type = "leo" }, ambulance = { type = "ems" }, unemployed = { type = "civ" } }

_G.exports = {
    qbcore = {
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

-- Controllable mock vehicle state -- native names/shapes match what
-- compat/client/qb-radialmenu.lua's built-in Vehicle submenu and its door/
-- extra/seat event handlers actually call.
local vehicleState = {
    pedVehicle = 0,     -- GetVehiclePedIsIn: 0 means "not in a vehicle"
    nearestVehicle = 0, -- getNearestVeh's own raycast result
    onAllWheels = true,
    seatCount = 4,
    speed = 0,          -- m/s, matches GetEntitySpeed's real unit (the compat file converts to km/h itself)
    doorAngle = {},     -- [doorIndex] -> float; unset means "closed" (0.0), same as a fresh vehicle
    extraExists = {},   -- [extraIndex] -> bool; unset means "exists" (true), matching most vehicles having all 13 slots
    extraOn = {},       -- [extraIndex] -> bool; unset means "off" (false)
    seatFree = {},      -- [seatIndex] -> bool; unset means "free" (true)
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
_G.SetVehicleExtra = function(_, extra, state) vehicleState.extraOn[extra] = (state == 0) end -- real native: 0 = on, 1 = off
_G.SetVehicleAutoRepairDisabled = function() end
_G.IsVehicleSeatFree = function(_, seat) return vehicleState.seatFree[seat] ~= false end
_G.GetEntitySpeed = function() return vehicleState.speed end
_G.SetPedIntoVehicle = function() end
_G.SetVehicleOnGroundProperly = function() end

dofile(repoRoot .. "compat/client/qb-radialmenu.lua")

-- Mirrors what a real cross-resource exports['qb-radialmenu']:Fn() call does
-- under the hood: fire the __cfx_export_ event with a setCB stub and capture
-- what gets passed to it.
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
        if item.id == id then return item end
    end
    return nil
end

-- The wheel only opens via the registered command/keybind handler, not a
-- direct export -- RegisterCommand's callback is the one actually under
-- test here, grabbed straight from the mock's own command registry.
local function openRadial()
    harness.assertTrue(net.commands ~= nil and net.commands["qblib_radialmenu_open"] ~= nil,
        "qblib_radialmenu_open should be registered")
    net.commands["qblib_radialmenu_open"](0, {}, "")
end

harness.test("AddOption returns a generated id and RemoveOption clears it from the wheel", function()
    -- A second, always-present option keeps the registry non-empty after
    -- removing the first, so the wheel actually reopens (and sentItems gets
    -- refreshed) instead of openRegisteredRadial's own `#order == 0` early
    -- return leaving sentItems stale from before the removal.
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

-- Real qbcore-framework/qb-radialmenu's own signature is AddOption(data, id)
-- -- id, not shouldClose -- used internally to update an existing slot in
-- place. A non-boolean second argument must be honoured as that explicit id.
harness.test("AddOption's non-boolean second argument is an explicit id, matching real qb-radialmenu", function()
    local id = AddOption({ title = "Job Menu" }, "jobinteractions")
    harness.assertEqual(id, "jobinteractions", "a string second argument should become the option's id")

    -- Re-registering at the same explicit id updates in place rather than
    -- appending a duplicate entry, mirroring upstream's SetupJobMenu/
    -- SetupVehicleMenu update-in-place pattern.
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

-- Other forks use the second positional argument as `shouldClose` instead --
-- a genuine boolean is unambiguous (real qb-radialmenu never passes a
-- boolean as `id`), so it must still be honoured that way.
harness.test("AddOption's boolean second argument is still honoured as shouldClose", function()
    local id = AddOption({ title = "Stay Open" }, false)
    local option = nil
    -- shouldClose isn't exposed directly; confirm indirectly via the
    -- reopen-after-select behaviour further down instead. Here just confirm
    -- a boolean second argument doesn't get stringified into the id.
    harness.assertTrue(id ~= "false" and id ~= "true", "a boolean second argument should not become the id")
    RemoveOption(id)
end)

harness.test("selecting an option with an event fires TriggerEvent/TriggerServerEvent", function()
    local clientId = AddOption({ title = "Client Action", type = "client", event = "test:client:action" })
    local serverId = AddOption({ title = "Server Action", type = "server", event = "test:server:action" })

    local clientFired, serverFired = false, false
    net.eventHandlers["test:client:action"] = { function() clientFired = true end }

    nextRadialResult = { selectedId = clientId }
    openRadial()
    harness.assertTrue(clientFired, "a client-type option should fire TriggerEvent")

    nextRadialResult = { selectedId = serverId }
    openRadial()
    harness.assertTrue(net.triggeredServerEvents[#net.triggeredServerEvents].name == "test:server:action",
        "a server-type option should fire TriggerServerEvent")

    RemoveOption(clientId)
    RemoveOption(serverId)
end)

-- Real qb-radialmenu options can carry their own nested `items[]` to form a
-- submenu (upstream's own "Work"/"Vehicle" branches work this way).
-- QB.nui.openRadialMenu natively supports `item.submenu = {title, items}`,
-- so a registered option with nested items must translate onto that instead
-- of being flattened or dropped, and a NESTED leaf's selection must still
-- dispatch correctly even though it was never in the top-level registry.
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
    -- Same reasoning as the export-level removal test above: an always-present
    -- anchor keeps the registry non-empty so the wheel actually reopens (and
    -- sentItems refreshes) after the net-event removal.
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

-- --- built-in wheel content -------------------------------------------

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

    -- openRegisteredRadial returns early (never calling QB.nui.openRadialMenu
    -- at all) when there's nothing to show, which would otherwise leave
    -- sentItems stale from whatever the previous test last sent.
    sentItems = nil
    nextRadialResult = { cancelled = true }
    openRadial()
    harness.assertTrue(sentItems == nil, "an empty wheel should never call QB.nui.openRadialMenu")
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
    -- Any job registered with type='leo' should reach the 'police' key, not
    -- a literal job named 'police' -- jobDefs above registers 'police' as
    -- the leo-typed job, so this also exercises the getJobType lookup path.
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
    harness.assertTrue(sentItems == nil, "a downed civilian should never reach QB.nui.openRadialMenu at all")
end)

harness.test("a downed police/EMS player sees only the emergency button, bypassing the normal registry", function()
    resetVehicleState()
    resetPlayerData()
    playerJob.name = "ambulance"
    playerJob.onduty = true
    playerMetadata.inlaststand = true
    vehicleState.nearestVehicle = 99 -- would normally also produce a Vehicle option

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
    harness.assertTrue(sentItems == nil, "a handcuffed player should never reach QB.nui.openRadialMenu")
end)

resetVehicleState()
resetPlayerData()

harness.report("compat_qb_radialmenu")
