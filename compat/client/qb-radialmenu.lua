-- Compat bridge: translates exports['qb-radialmenu']:AddOption/RemoveOption, the matching net events and the
-- wheel keybind onto Kora.nui.openRadialMenu. Field mapping: see modules/nui/docs.md "Legacy compat".
--
-- SHAPE MISMATCH: upstream is a global, persistent wheel that scripts add to over time, while
-- Kora.nui.openRadialMenu is one-shot per call. This file keeps its own registry of options and only calls
-- openRadialMenu when the keybind fires, translating the registry to items at that moment.
--
-- Kora.nui.openRadialMenu always opens centered, as upstream does; `opts.radius` stays at Kora.nui's default.
--
-- Built-in content (job "Work" submenu, "Vehicle" submenu, police/EMS emergency button) is registered through
-- this file's own AddOption so it shares the third-party path. Not reproduced: most of upstream's
-- Config.JobInteractions (they fire companion-resource events or need a target player; see
-- Config.radialmenuCompat) and the stretcher/trunk/clothing submodules (owned by kora_ambulance/qbclothing).
-- Nested `items` translate recursively onto Kora.nui's `item.submenu = {title, items}` (see translateOption).

-- Warned once per resource run: Font Awesome `icon` classes don't map onto Kora.nui's lucide names, so icons are dropped.
local warnedIcon = false
local function warnIconOnce()
    if warnedIcon then return end
    warnedIcon = true
    print("[qb-radialmenu-bridge] WARNING: option 'icon' fields (Font Awesome classes) are not translated to "
        .. "Kora.nui's lucide icon names -- icons are dropped. Only shown once per session.")
end

-- `iconAnimation` has no equivalent on Kora.nui's item schema and is silently ignored.

-- Persistent registry standing in for upstream's internal state; `order` preserves registration order,
-- `byId` gives O(1) lookup for RemoveOption and dispatch.
local order = {}
local byId = {}

-- Auto-generated ids use a per-session counter; collisions with caller-supplied ids are not guarded against.
local nextGeneratedId = 0
local function generateId(leafById)
    repeat
        nextGeneratedId = nextGeneratedId + 1
        local key = tostring(nextGeneratedId)
    until not byId[key] and not (leafById and leafById[key])
    return nextGeneratedId
end

-- Options may carry nested `items[]`, which translate directly onto Kora.nui's `item.submenu = {title, items}`.
-- Every leaf at any depth is indexed into `leafById`; ids are unique across the registry, so a flat lookup suffices.
local function translateOption(option, leafById)
    if option.icon then warnIconOnce() end

    if option.id == nil then option.id = generateId(leafById) end
    local id = tostring(option.id)

    local translated = { id = id, label = option.title or option.label or "" }

    if type(option.items) == "table" and #option.items > 0 then
        local children = {}
        for childIndex = 1, #option.items do
            children[#children + 1] = translateOption(option.items[childIndex], leafById)
        end
        translated.submenu = { title = option.title or option.label, items = children }
    else
        leafById[id] = option
    end

    return translated
end

-- Maps the registered top-level options onto an openMenu-shaped items list, recursing via translateOption.
-- `top = true` options move to the front (stable); that field is a compat addition upstream ignores.
local function translateItems(leafById)
    local topItems, restItems = {}, {}

    for idIndex = 1, #order do
        local id = order[idIndex]
        local option = byId[id]
        local translated = translateOption(option, leafById)

        if option.top then
            topItems[#topItems + 1] = translated
        else
            restItems[#restItems + 1] = translated
        end
    end

    table.move(restItems, 1, #restItems, #topItems + 1, topItems)
    return topItems
end

-- Selecting fires `option.onSelect(option)` if given, else `option.event` (server event when
-- `option.type == "server"`). The option table itself is passed as the event argument because upstream
-- handlers (e.g. openDoor reading `data.id`) depend on it. No handler just closes the wheel.
local function dispatch(option)
    if not option then return end

    if option.onSelect then
        local ok, err = pcall(option.onSelect, option)
        if not ok then
            print(("[qb-radialmenu-bridge] WARNING: onSelect for option %q errored: %s"):format(
                tostring(option.id), tostring(err)))
        end
        return
    end

    if not option.event then return end

    -- Types: client/server/command/qbcommand. Unlike upstream, any other (or missing) type falls through
    -- to client dispatch.
    if option.type == "server" then
        TriggerServerEvent(option.event, option)
    elseif option.type == "command" then
        ExecuteCommand(option.event)
    elseif option.type == "qbcommand" then
        TriggerServerEvent("QBCore:CallCommand", option.event, option)
    else
        TriggerEvent(option.event, option)
    end
end

-- Registers one option and returns its id (numeric when generated, as upstream; a caller-supplied id is returned unchanged). The second positional argument is overloaded across forks:
-- a boolean is `shouldClose` (an explicit `option.shouldClose` wins), anything else non-nil is the explicit
-- slot id, as in upstream's `AddOption(data, id)`. shouldClose defaults to true.
local function addOption(option, second)
    assert(type(option) == "table", "qb-radialmenu compat: AddOption requires an option table.")

    local id
    if type(second) == "boolean" then
        if option.shouldClose == nil then option.shouldClose = second end
        id = option.id
    else
        id = second
        if id == nil then id = option.id end
    end
    if id == nil then id = generateId() end
    if option.shouldClose == nil then option.shouldClose = true end

    option.id = id
    option.__koraLibOwner = GetInvokingResource() or GetCurrentResourceName()

    local key = tostring(id)
    if not byId[key] then
        order[#order + 1] = key
    end
    byId[key] = option

    return id
end

-- Removes a registered option by id; a no-op if absent, as upstream.
local function removeOption(id)
    id = tostring(id)
    if not byId[id] then return end

    byId[id] = nil
    for i = 1, #order do
        local existingId = order[i]
        if existingId == id then
            table.remove(order, i)
            break
        end
    end
end

-- Built-in wheel content: Vehicle submenu + per-job Work submenu.
-- Upstream recomputes these on every open and updates them at a stable slot through its own AddOption;
-- mirrored here via this file's local AddOption/RemoveOption so built-ins share the third-party path.

-- pcall-guarded and framework-agnostic: if kora_core isn't running this content simply doesn't appear.
local function getPlayerDataPath(path)
    local ok, value = pcall(function() return exports.kora_core:getPlayerData(path) end)
    if ok and type(value) == "table" then return value end
    return {}
end

-- PlayerData.job here lacks `type` ('leo'/'ems'/'civ'); it lives on the job's registry record,
-- fetched via exports.kora_core:getShared('jobs', jobName).
local function getJobType(jobName)
    if not jobName then return nil end
    local ok, def = pcall(function() return exports.kora_core:getShared("jobs", jobName) end)
    if ok and type(def) == "table" then return def.type end
    return nil
end

local function getNearestVeh()
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local ahead = GetOffsetFromEntityInWorldCoords(ped, 0.0, 20.0, 0.0)
    local rayHandle = CastRayPointToPoint(pos.x, pos.y, pos.z, ahead.x, ahead.y, ahead.z, 10, ped, 0)
    local _, _, _, _, vehicleHandle = GetRaycastResult(rayHandle)
    return vehicleHandle
end

local function getCurrentOrNearestVeh(ped)
    local current = GetVehiclePedIsIn(ped)
    if current and current ~= 0 then return current end
    return getNearestVeh()
end

-- Door/extra/seat items carry doorIndex/extraIndex/seatIndex fields directly instead of upstream's
-- packed id strings ("door0"); these ids are owned by this file so no string round-trip is needed.
local VEHICLE_DOOR_ITEMS = {
    { id = "door0", title = "Driver Door", doorIndex = 0 },
    { id = "door4", title = "Hood", doorIndex = 4 },
    { id = "door1", title = "Passenger Door", doorIndex = 1 },
    { id = "door3", title = "Right Rear", doorIndex = 3 },
    { id = "door5", title = "Trunk", doorIndex = 5 },
    { id = "door2", title = "Left Rear", doorIndex = 2 },
}
local VEHICLE_EXTRA_COUNT = 13
local VEHICLE_SEAT_LABELS = { [1] = "Driver Seat", [2] = "Passenger Seat", [3] = "Rear Left Seat", [4] = "Rear Right Seat" }

RegisterNetEvent("kora_lib:radialmenuCompat:client:openDoor", function(data)
    local ped = PlayerPedId()
    local vehicle = getCurrentOrNearestVeh(ped)
    if not vehicle or vehicle == 0 then return end

    local door = data.doorIndex
    if GetVehicleDoorAngleRatio(vehicle, door) > 0.0 then
        SetVehicleDoorShut(vehicle, door, false)
    else
        SetVehicleDoorOpen(vehicle, door, false, false)
    end
end)

-- Simplification: upstream round-trips doors through a server event (server/trunk.lua, not ported), so
-- changes made on a vehicle the player isn't in don't broadcast to other clients.
RegisterNetEvent("kora_lib:radialmenuCompat:client:setExtra", function(data)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then return end
    if not DoesExtraExist(vehicle, data.extraIndex) then return end

    SetVehicleAutoRepairDisabled(vehicle, true) -- forces auto-repair off when toggling an extra, same as upstream
    if IsVehicleExtraTurnedOn(vehicle, data.extraIndex) then
        SetVehicleExtra(vehicle, data.extraIndex, 1)
    else
        SetVehicleExtra(vehicle, data.extraIndex, 0)
    end
end)

RegisterNetEvent("kora_lib:radialmenuCompat:client:changeSeat", function(data)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped)
    if vehicle == 0 then return end
    if not IsVehicleSeatFree(vehicle, data.seatIndex) then return end
    local ok, harness = pcall(function() return exports['qb-smallresources']:HasHarness() end)
    if ok and harness then return end
    if (GetEntitySpeed(vehicle) * 3.6) > 100.0 then return end -- upstream's own too-fast-to-swap-seats guard

    SetPedIntoVehicle(ped, vehicle, data.seatIndex)
end)

RegisterNetEvent("kora_lib:radialmenuCompat:client:flipVehicle", function()
    local completed = Kora.progressbar.start({
        label = "Flipping vehicle...",
        duration = Config.radialmenuCompat.flipVehicleTime,
        disable = { move = true, car = true, combat = true },
        anim = { dict = "mini@repair", clip = "fixing_a_ped" },
    })
    if not completed then return end

    local ped = PlayerPedId()
    local vehicle = getCurrentOrNearestVeh(ped)
    if vehicle and vehicle ~= 0 then SetVehicleOnGroundProperly(vehicle) end
end)

local VEHICLE_SLOT_ID = "qblib_radialmenu_vehicle"
local vehicleMenuRegistered = false

-- Mirrors upstream's SetupVehicleMenu: doors/extras for any nearby or occupied vehicle, flip only when not
-- on all wheels, seats only while inside.
local function setupVehicleMenu()
    local ped = PlayerPedId()
    local vehicle = getCurrentOrNearestVeh(ped)

    if not vehicle or vehicle == 0 then
        if vehicleMenuRegistered then
            removeOption(VEHICLE_SLOT_ID)
            vehicleMenuRegistered = false
        end
        return
    end

    local doorItems = {}
    for doorIndex = 1, #VEHICLE_DOOR_ITEMS do
        local door = VEHICLE_DOOR_ITEMS[doorIndex]
        doorItems[#doorItems + 1] = {
            id = door.id, title = door.title, doorIndex = door.doorIndex,
            type = "client", event = "kora_lib:radialmenuCompat:client:openDoor", shouldClose = false,
        }
    end
    local items = { { id = "vehicledoors", title = "Vehicle Doors", items = doorItems } }

    if Config.radialmenuCompat.enableVehicleExtras then
        local extraItems = {}
        for i = 1, VEHICLE_EXTRA_COUNT do
            extraItems[#extraItems + 1] = {
                id = ("extra%d"):format(i), title = ("Extra %d"):format(i), extraIndex = i,
                type = "client", event = "kora_lib:radialmenuCompat:client:setExtra", shouldClose = false,
            }
        end
        items[#items + 1] = { id = "vehicleextras", title = "Vehicle Extras", items = extraItems }
    end

    if not IsVehicleOnAllWheels(vehicle) then
        items[#items + 1] = {
            id = "vehicle-flip", title = "Flip Vehicle",
            type = "client", event = "kora_lib:radialmenuCompat:client:flipVehicle", shouldClose = true,
        }
    end

    if IsPedInAnyVehicle(ped, false) then
        local seatItems = {}
        local seatCount = GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))
        for i = 1, seatCount do
            local seatIndex = i - 2 -- real GTA seat numbering: -1 = driver, 0 = front passenger, 1.. = rear
            seatItems[#seatItems + 1] = {
                id = tostring(seatIndex), title = VEHICLE_SEAT_LABELS[i] or "Other Seat", seatIndex = seatIndex,
                type = "client", event = "kora_lib:radialmenuCompat:client:changeSeat", shouldClose = false,
            }
        end
        if #seatItems > 0 then
            items[#items + 1] = { id = "vehicleseats", title = "Vehicle Seats", items = seatItems }
        end
    end

    addOption({ id = VEHICLE_SLOT_ID, title = "Vehicle", items = items }, VEHICLE_SLOT_ID)
    vehicleMenuRegistered = true
end

local JOB_SLOT_ID = "qblib_radialmenu_job"
local jobMenuRegistered = false

-- Mirrors upstream's SetupJobMenu: a "Work" submenu from Config.radialmenuCompat.jobInteractions[jobKey]
-- while on duty; any 'leo'-type job collapses onto the 'police' key.
local function setupJobMenu(job, jobType)
    local jobKey = jobType == "leo" and "police" or job.name
    local entries = jobKey and Config.radialmenuCompat.jobInteractions[jobKey]

    if not entries or #entries == 0 or job.onduty ~= true then
        if jobMenuRegistered then
            removeOption(JOB_SLOT_ID)
            jobMenuRegistered = false
        end
        return
    end

    addOption({ id = JOB_SLOT_ID, title = "Work", items = entries }, JOB_SLOT_ID)
    jobMenuRegistered = true
end

-- Guards against the keybind stacking a second Kora.nui.openRadialMenu request
-- on top of one that's already open and awaiting the player.
local isOpen = false

-- Opens the wheel from the current registry and dispatches the selection. If `shouldClose` is false it
-- reopens with a fresh request, approximating upstream's chained-selection wheel (openRadialMenu is one-shot).
local function openRegisteredRadial()
    if isOpen then return end

    -- Mirrors upstream's gate: a downed player may only reach the police/EMS emergency button;
    -- everyone else is blocked while downed, handcuffed, or in the pause menu.
    local metadata = getPlayerDataPath({ "metadata" })
    local downed = metadata.isdead == true or metadata.inlaststand == true
    local job = getPlayerDataPath({ "job" })
    local jobType = getJobType(job.name)
    local policeOrEms = jobType == "leo" or job.name == "ambulance"

    if downed and not policeOrEms then return end
    if metadata.ishandcuffed == true then return end
    if IsPauseMenuActive then
        local ok, active = pcall(IsPauseMenuActive)
        if ok and active then return end
    end

    local leafById, items

    if downed and policeOrEms then
        -- Real qb-radialmenu wholesale replaces the wheel with just this one
        -- option while downed -- calling for help takes priority over every
        -- other registered option, bypassing the normal registry entirely.
        local emergency = Config.radialmenuCompat.jobInteractions.police
            and Config.radialmenuCompat.jobInteractions.police[1]
        if not emergency then return end
        leafById = { [emergency.id] = emergency }
        items = { { id = emergency.id, label = emergency.title } }
    else
        setupJobMenu(job, jobType)
        setupVehicleMenu()

        if #order == 0 then return end

        leafById = {}
        items = translateItems(leafById)
    end

    if #items == 0 then return end

    -- This is invoked from kora_lib's own command/keybind, not from the resource
    -- that originally registered an option. Kora.nui.openRadialMenu therefore
    -- returns its pending same-resource promise and must be awaited here.
    isOpen = true
    TriggerEvent("qb-radialmenu:client:onRadialmenuOpen")
    local result = Citizen.Await(Kora.nui.openRadialMenu(items))
    isOpen = false
    TriggerEvent("qb-radialmenu:client:onRadialmenuClose")

    if not result or result.cancelled then return end

    local option = leafById[result.selectedId]
    dispatch(option)

    if option and option.shouldClose == false then
        openRegisteredRadial()
    end
end

Kora.compat.provideExport("qb-radialmenu", "AddOption", addOption)
Kora.compat.provideExport("qb-radialmenu", "RemoveOption", removeOption)

RegisterNetEvent("qb-radialmenu:client:AddOption", addOption)
RegisterNetEvent("qb-radialmenu:client:RemoveOption", removeOption)

AddEventHandler("onClientResourceStop", function(resource)
    local owned = {}
    for id, option in pairs(byId) do
        if option.__koraLibOwner == resource then owned[#owned + 1] = id end
    end
    for i = 1, #owned do removeOption(owned[i]) end
end)

-- Upstream opens on a fixed keybind; "F1" is its default. Players can rebind it in FiveM's Key Bindings.
Kora.keybind.add({
    name = 'qblib_radialmenu_open',
    description = 'Open Radial Menu',
    defaultMapper = 'keyboard',
    defaultKey = 'F1',
    onPressed = openRegisteredRadial,
})
