-- Drop-in compatibility bridge: translates the real, public qb-radialmenu API
-- (exports['qb-radialmenu']:AddOption/RemoveOption, the
-- 'qb-radialmenu:client:AddOption'/'qb-radialmenu:client:RemoveOption' net
-- events, and the fixed keybind that opens the wheel) onto
-- QB.nui.openRadialMenu, kora_lib's own native replacement. qb-radialmenu itself
-- is being deprecated in favour of QB.nui.openMenu/openContextMenu/
-- openRadialMenu -- this file exists so a script written against
-- exports['qb-radialmenu']:... keeps working unmodified while it migrates,
-- exactly the same shape of shim as compat/client/qb-menu.lua and
-- compat/client/qb-input.lua.
--
-- SHAPE MISMATCH, read before touching this file: real qb-radialmenu is a
-- GLOBAL, PERSISTENT menu -- other resources register/unregister options
-- into one shared wheel over time via AddOption/RemoveOption, and the player
-- opens it whenever they want via a fixed keybind. QB.nui.openRadialMenu is a
-- ONE-SHOT, per-call menu -- a caller builds an items list and awaits a
-- single result. There is no primitive on QB.nui for "a menu that's already
-- open and waiting, built from whatever's currently registered" -- so this
-- file keeps its own registry of currently-registered options and only
-- actually calls QB.nui.openRadialMenu when the keybind fires, translating
-- the registry to an items list at that moment. See modules/nui/docs.md's
-- "Legacy compat" section for the field-by-field mapping table and this
-- caveat spelled out again.
--
-- Also note: QB.nui.openRadialMenu never takes x/y (it always opens
-- centered) -- real qb-radialmenu has no notion of screen position either
-- (it always opens centered on the player's cursor/screen), so nothing is
-- lost there. `opts.radius` is left at QB.nui's default; nothing in
-- qb-radialmenu's public surface configures it.
--
-- BUILT-IN CONTENT: real qb-radialmenu's own main.lua also injects a set of
-- default options into the wheel every time it opens -- a job-specific
-- "Work" submenu (Config.JobInteractions), a "Vehicle" submenu (doors/
-- extras/seats/flip), and a police/EMS-only "Emergency Button" replacing the
-- whole wheel while downed. All three are reproduced below (see "built-in
-- wheel content" further down), registered through this file's OWN AddOption
-- so they share the exact same registry/translation/dispatch path a
-- third-party script's AddOption call would. Two things are deliberately
-- NOT reproduced:
--   * Most of real qb-radialmenu's default Config.JobInteractions content
--     (tow/taxi/mechanic/hotdog jobs, and most of the police entries) --
--     those fire events owned by companion job resources this environment
--     doesn't run, or need an aimed-at/nearby TARGET player the wheel's own
--     event payload never carries. See config.lua's Config.radialmenuCompat
--     comment for exactly what's wired up instead and why.
--   * qb-radialmenu's own stretcher.lua/trunk.lua/clothing.lua submodules --
--     these are ambulance/police/character-creation FEATURES bundled into
--     the real resource, not part of the generic AddOption/RemoveOption API
--     surface, and this environment's kora_ambulance/qbclothing already own
--     equivalent functionality through their own (differently-shaped)
--     mechanisms.
--
-- Nested submenus are what makes the built-in content possible at all: a
-- registered option's own `items` (array of the same option shape --
-- exactly how upstream's "Work"/"Vehicle" branches are built) translates
-- recursively onto QB.nui's native `item.submenu = {title, items}` -- see
-- translateOption below.

-- QB.compat.provideExport registers the hidden CFX export event under the
-- legacy `qb-radialmenu` identity; `provide 'qb-radialmenu'` alone only
-- satisfies dependency checks.

-- Warned once per resource run -- same reasoning as qb-menu compat's
-- warnIconOnce: real qb-radialmenu options carry a Font Awesome `icon` class
-- string; QB.nui.openMenu-shaped items' `icon` expects a lucide-react name
-- (web/src/lib/icon.ts), and the two vocabularies don't overlap. Dropped
-- rather than mistranslated.
local warnedIcon = false
local function warnIconOnce()
    if warnedIcon then return end
    warnedIcon = true
    print("[qb-radialmenu-bridge] WARNING: option 'icon' fields (Font Awesome classes) are not translated to "
        .. "QB.nui's lucide icon names -- icons are dropped. Only shown once per session.")
end

-- `iconAnimation` (a CSS/animate.css-style spin/pulse class in real
-- qb-radialmenu) has no equivalent at all on QB.nui's item schema -- it's
-- purely decorative on top of the already-dropped icon, so it's silently
-- ignored rather than given its own warning on top of warnIconOnce.

-- The persistent registry this file stands in for the real resource's own
-- internal state. `order` keeps registration order (also used for `top`
-- promotion below); `byId` is keyed by the same stringified id for O(1)
-- lookup on both RemoveOption and dispatch.
local order = {}
local byId = {}

-- Real qb-radialmenu options are usually given their own `id` by the caller
-- (so a later RemoveOption(id) can find them again); when one isn't
-- supplied, forks generally generate one and hand it back from AddOption.
-- Mirrored here with a simple per-session counter -- collisions with a
-- caller-supplied id are not guarded against, same as most real forks.
local nextGeneratedId = 0
local function generateId()
    nextGeneratedId = nextGeneratedId + 1
    return ("radial_%d"):format(nextGeneratedId)
end

-- Real qb-radialmenu options can carry their OWN nested `items[]` (an array
-- of the same option shape) to form a submenu -- e.g. upstream's own
-- main.lua builds a "Work"/"Vehicle" branch this way, and third-party
-- scripts do the same for any grouped set of actions. QB.nui's radial menu
-- natively supports arbitrary submenu depth via `item.submenu = {title,
-- items}` (web/src/components/menu/RadialMenu.tsx), so nesting translates
-- directly instead of needing its own emulation the way the persistent
-- top-level registry does (see this file's header comment). Every LEAF
-- option encountered at any depth -- one with no `items` of its own -- is
-- indexed into `leafById` so dispatch can resolve the selection result
-- purely by id regardless of how deep it was nested; ids are unique across
-- this whole registry (auto-generated and persisted back onto the option the
-- same way AddOption does for top-level ones), so a flat lookup is enough
-- even though QB.nui's result also carries the full root-to-leaf `path`.
local function translateOption(option, leafById)
    if option.icon then warnIconOnce() end

    local id = option.id ~= nil and tostring(option.id) or generateId()
    option.id = id

    local translated = { id = id, label = option.title or option.label or "" }

    if type(option.items) == "table" and #option.items > 0 then
        local children = {}
        for childIndex = 1, #option.items do
            local child = option.items[childIndex]
            children[#children + 1] = translateOption(child, leafById)
        end
        translated.submenu = { title = option.title or option.label, items = children }
    else
        leafById[id] = option
    end

    return translated
end

-- Maps the currently-registered top-level options onto one
-- QB.nui.openMenu-shaped items list (openRadialMenu takes the same item
-- schema), recursing into any nested `items` via translateOption above.
-- `top = true` options are moved to the front, stable within each group --
-- the closest flat-list equivalent of "pin near the top of the wheel"; note
-- this is NOT a real qb-radialmenu field (upstream has no such concept at
-- all) -- it's an additive convenience this compat layer accepts, which real
-- qb-radialmenu would simply ignore since it never reads `.top`.
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

    local items = {}
    for i = 1, #topItems do items[#items + 1] = topItems[i] end
    for i = 1, #restItems do items[#items + 1] = restItems[i] end
    return items
end

-- Selecting an option fires `option.onSelect(option)` if given, otherwise
-- `option.event` -- TriggerServerEvent if `option.type == "server"`,
-- TriggerEvent otherwise (mirrors qb-menu compat's dispatch and real
-- qb-radialmenu's own client/server event split). An option with neither
-- just closes the wheel, same as an item with no `params.event` in qb-menu.
-- The option's own table is passed as the event's argument -- real
-- qb-radialmenu's selectItem NUI callback always does `TriggerEvent(data.
-- event, data)` / `TriggerServerEvent(data.event, data)`, and its own
-- handlers (e.g. qb-radialmenu:client:openDoor reading `data.id`) depend on
-- getting that table back, not just a bare event with no payload.
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

    -- Real qb-radialmenu's selectItem callback supports four `type` values
    -- (client/server/command/qbcommand, exactly mirroring qb-menu compat's
    -- own params.isServer/isCommand/isQBCommand dispatch) -- command/
    -- qbcommand were previously missing here entirely. Unlike upstream
    -- (which does nothing for any OTHER type, including a missing one),
    -- anything not "server"/"command"/"qbcommand" still falls through to
    -- client dispatch -- a harmless, more forgiving default for options that
    -- never set `type` at all, kept from before this fix.
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

-- Real qb-radialmenu's AddOption registers one item into the global wheel
-- and returns its id so the caller can RemoveOption it later. Two DIFFERENT
-- conventions share this same second positional argument slot across the
-- ecosystem, so both are honoured:
--   * qbcore-framework/qb-radialmenu's own `main.lua` signature is
--     `AddOption(data, id)` -- `id`, when given, is an explicit slot to
--     register/update at (`local menuID = id ~= nil and id or
--     (#DynamicMenuItems + 1)`), used internally by its own SetupJobMenu/
--     SetupVehicleMenu to update an existing entry in place rather than
--     appending a duplicate one every time the wheel opens.
--   * Other forks instead use the second argument as `shouldClose`, a plain
--     boolean.
-- A boolean second argument is unambiguous (real qb-radialmenu never passes
-- one as `id`), so that's the discriminator: boolean -> shouldClose (unless
-- `option.shouldClose` is already set, which wins as the more explicit of
-- the two), anything else non-nil -> the explicit id, exactly like upstream.
-- Defaults to true (select -> wheel closes) same as real qb-radialmenu.
local function addOption(option, second)
    assert(type(option) == "table", "qb-radialmenu compat: AddOption requires an option table.")

    local id
    if type(second) == "boolean" then
        if option.shouldClose == nil then option.shouldClose = second end
        id = option.id ~= nil and tostring(option.id) or generateId()
    else
        id = second ~= nil and tostring(second) or (option.id ~= nil and tostring(option.id) or generateId())
    end
    if option.shouldClose == nil then
        option.shouldClose = true
    end

    option.id = id
    option.__koraLibOwner = GetInvokingResource() or GetCurrentResourceName()

    if not byId[id] then
        order[#order + 1] = id
    end
    byId[id] = option

    return id
end

-- Removes a previously-registered option by id. A no-op if the id isn't
-- currently registered (real qb-radialmenu doesn't error on this either).
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

-- --- built-in wheel content: Vehicle submenu + per-job Work submenu -------
--
-- Real qb-radialmenu's own main.lua recomputes these two branches fresh
-- every time the wheel is about to open (SetupSubItems, called from
-- SetupRadialMenu, called right before the NUI push) and registers/updates
-- them through its OWN AddOption at a stable slot (jobIndex/vehicleIndex) so
-- repeated opens update the same entry instead of appending duplicates.
-- Mirrored the same way below, using THIS file's own AddOption/RemoveOption
-- (the locals above, not the exported wrappers) so third-party-registered
-- options and these built-ins share exactly one registry/translation/
-- dispatch path -- see openRegisteredRadial further down for where these
-- run, and modules/nui/docs.md's "Legacy compat" section for what's
-- deliberately NOT ported (most job-specific content -- see config.lua's
-- Config.radialmenuCompat comment for exactly why).

-- pcall-guarded and framework-agnostic, same reasoning as qb-menu compat's
-- imageFor: kora_lib itself has no player-data concept of its own, so if
-- kora_core isn't running (or a different framework is), this content simply
-- doesn't appear -- the same way real qb-radialmenu would show nothing here
-- without QBCore.Functions.GetPlayerData() ever resolving.
local function getPlayerDataPath(path)
    local ok, value = pcall(function() return exports.kora_core:getPlayerData(path) end)
    if ok and type(value) == "table" then return value end
    return {}
end

-- PlayerData.job in THIS environment's kora_core only carries name/label/
-- payment/onduty/isboss/grade (see kora_core's shared/jobs.lua) -- `type`
-- ('leo'/'ems'/'civ', what real qb-core's own PlayerData.job carries and
-- what upstream qb-radialmenu's IsPoliceOrEMS/JobInteractionCheck key off)
-- only lives on the job's REGISTRY record, fetched separately exactly the
-- way that file's own header comment says to: `exports.kora_core:getShared(
-- 'jobs', jobName)`, not PlayerData.job.
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

-- Door/extra/seat items below carry their own doorIndex/extraIndex/
-- seatIndex field directly, read by the handlers below, rather than real
-- qb-radialmenu's own convention of packing the index into the id string
-- ("door0".."door5") and gsub-parsing it back out in the event handler --
-- these ids are entirely owned by this file (never caller-supplied), so
-- there's no reason to round-trip through string parsing for something a
-- plain integer field already carries safely.
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
    local vehicle = GetVehiclePedIsIn(ped) ~= 0 and GetVehiclePedIsIn(ped) or getNearestVeh()
    if not vehicle or vehicle == 0 then return end

    local door = data.doorIndex
    if GetVehicleDoorAngleRatio(vehicle, door) > 0.0 then
        SetVehicleDoorShut(vehicle, door, false)
    else
        SetVehicleDoorOpen(vehicle, door, false, false)
    end
end)

-- Simplification vs. real qb-radialmenu's own openDoor handler: upstream
-- round-trips through a server event (qb-radialmenu:trunk:server:Door) to
-- authoritatively open/close another vehicle's doors when the player isn't
-- its occupant, so every client sees the same state. That path depends on
-- upstream's own server/trunk.lua, which isn't ported here (see this file's
-- header comment) -- the natives above still work fine locally either way,
-- they just don't broadcast to other clients when used on a vehicle the
-- player isn't in.
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
    if (GetEntitySpeed(vehicle) * 3.6) > 100.0 then return end -- upstream's own too-fast-to-swap-seats guard

    SetPedIntoVehicle(ped, vehicle, data.seatIndex)
end)

-- Simplification vs. upstream: real qb-radialmenu also gates this on
-- exports['qb-smallresources']:HasHarness() (racing-harness check) -- no
-- resource in this environment exposes that export, and calling a
-- cross-resource export that doesn't exist errors rather than returning
-- nil/false, so it's omitted entirely rather than guarded with a pcall that
-- would just always fall back the same way.
RegisterNetEvent("kora_lib:radialmenuCompat:client:flipVehicle", function()
    local completed = QB.progressbar.start({
        label = "Flipping vehicle...",
        duration = Config.radialmenuCompat.flipVehicleTime,
        disable = { move = true, car = true, combat = true },
        anim = { dict = "mini@repair", clip = "fixing_a_ped" },
    })
    if not completed then return end

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped) ~= 0 and GetVehiclePedIsIn(ped) or getNearestVeh()
    if vehicle and vehicle ~= 0 then SetVehicleOnGroundProperly(vehicle) end
end)

local VEHICLE_SLOT_ID = "qblib_radialmenu_vehicle"
local vehicleMenuRegistered = false

-- Mirrors real qb-radialmenu's own SetupVehicleMenu: doors + (optionally)
-- extras always show for any nearby/occupied vehicle; a flip option only
-- while it's not sitting on all its wheels; a seats submenu only while the
-- player is actually inside it (switching from outside makes no sense).
local function setupVehicleMenu()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped) ~= 0 and GetVehiclePedIsIn(ped) or getNearestVeh()

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

-- Mirrors real qb-radialmenu's own SetupJobMenu: shows a "Work" submenu
-- built from Config.radialmenuCompat.jobInteractions[jobKey] only while
-- on duty in a job that has entries configured -- exactly upstream's
-- Config.JobInteractions[JobInteractionCheck] behaviour (JobInteractionCheck
-- itself being the job name, except any 'leo'-type job collapses onto the
-- 'police' key, same override upstream applies).
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

-- Guards against the keybind stacking a second QB.nui.openRadialMenu request
-- on top of one that's already open and awaiting the player.
local isOpen = false

-- Opens the wheel from whatever's currently registered, dispatches the
-- selection, and -- if the selected option's `shouldClose` is false --
-- reopens immediately to approximate real qb-radialmenu's "wheel stays open
-- for chained selections" behaviour. QB.nui.openRadialMenu has no concept of
-- staying open across a selection (it's one-shot), so this is a best-effort
-- emulation via a fresh request rather than a truly persistent NUI state.
local function openRegisteredRadial()
    if isOpen then return end

    -- Matches real qb-radialmenu's own RegisterCommand('radialmenu', ...)
    -- gate: a downed player can only reach the wheel at all to get to the
    -- emergency button below (police/EMS only) -- everyone else is blocked
    -- outright while downed, handcuffed, or the pause menu is open.
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
    -- that originally registered an option. QB.nui.openRadialMenu therefore
    -- returns its pending same-resource promise and must be awaited here.
    isOpen = true
    local result = Citizen.Await(QB.nui.openRadialMenu(items))
    isOpen = false

    if not result or result.cancelled then return end

    local option = leafById[result.selectedId]
    dispatch(option)

    if option and option.shouldClose == false then
        openRegisteredRadial()
    end
end

QB.compat.provideExport("qb-radialmenu", "AddOption", addOption)
QB.compat.provideExport("qb-radialmenu", "RemoveOption", removeOption)

RegisterNetEvent("qb-radialmenu:client:AddOption", addOption)
RegisterNetEvent("qb-radialmenu:client:RemoveOption", removeOption)

AddEventHandler("onClientResourceStop", function(resource)
    local owned = {}
    for id, option in pairs(byId) do
        if option.__koraLibOwner == resource then owned[#owned + 1] = id end
    end
    for i = 1, #owned do removeOption(owned[i]) end
end)

-- Real qb-radialmenu opens on a fixed keybind rather than a script-triggered
-- call -- there's no QB.nui hook for "open whatever's registered", so this
-- owns one QB.keybind definition. "F1" matches
-- qbcore-framework/qb-radialmenu's own config.lua default (`Config.Keybind =
-- 'F1'`) -- some forks differ, and it's always rebindable by the player from
-- FiveM's own Settings > Key Bindings regardless of what's set here, so this
-- is a best-effort default rather than a guarantee every fork matches it.
QB.keybind.add({
    name = 'qblib_radialmenu_open',
    description = 'Open Radial Menu',
    defaultMapper = 'keyboard',
    defaultKey = 'F1',
    onPressed = openRegisteredRadial,
})
