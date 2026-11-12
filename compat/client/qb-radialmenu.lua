local warnedIcon = false
local function warnIconOnce()
    if warnedIcon then return end
    warnedIcon = true
    print("[qb-radialmenu-bridge] WARNING: option 'icon' fields (Font Awesome classes) are not translated to "
        .. "Kora.nui's lucide icon names -- icons are dropped. Only shown once per session.")
end

local order = {}
local byId = {}

local nextGeneratedId = 0
local function generateId(leafById)
    repeat
        nextGeneratedId = nextGeneratedId + 1
        local key = tostring(nextGeneratedId)
    until not byId[key] and not (leafById and leafById[key])
    return nextGeneratedId
end

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

local function getPlayerDataPath(path)
    local ok, value = pcall(function() return exports.kora_core:getPlayerData(path) end)
    if ok and type(value) == "table" then return value end
    return {}
end

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

RegisterNetEvent("kora_lib:radialmenuCompat:client:setExtra", function(data)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then return end
    if not DoesExtraExist(vehicle, data.extraIndex) then return end

    SetVehicleAutoRepairDisabled(vehicle, true)
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
    if (GetEntitySpeed(vehicle) * 3.6) > 100.0 then return end

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

local VEHICLE_SLOT_ID = "kora_lib_radialmenu_vehicle"
local vehicleMenuRegistered = false

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
            local seatIndex = i - 2
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

local JOB_SLOT_ID = "kora_lib_radialmenu_job"
local jobMenuRegistered = false

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

local isOpen = false

local function openRegisteredRadial()
    if isOpen then return end

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

Kora.keybind.add({
    name = 'kora_lib_radialmenu_open',
    description = 'Open Radial Menu',
    defaultMapper = 'keyboard',
    defaultKey = 'F1',
    onPressed = openRegisteredRadial,
})
