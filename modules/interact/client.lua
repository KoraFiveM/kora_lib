---@class QBInteractOption
---@field label string
---@field action? fun()
---@field event? string
---@field args? any[]
---@field type? "client"|"server"
---@field canInteract? fun(): boolean
---@field job? string|string[]
---@field gang? string|string[]
---@field item? string
---@field icon? string UI consumers may use this; qblib's compact selector currently renders labels only.

local active
local callbackRegistered = false
local zonesByName = {}
local reopenFns = {}
local targetRegistry = QB.resources.registry(function(handle)
    if handle.kind == 'entity' then
        exports.qbtarget:removeEntity(handle.value, handle.id)
    else
        exports.qbtarget:removeModel(handle.value, handle.id)
    end
end)

local isCallable = QB.compat.isCallable

local function isEnabled()
    local state = LocalPlayer and LocalPlayer.state
    -- Character/scene selection is a camera preview, not gameplay. Do not let
    -- a nearby world target open a qblib selector over that NUI.
    if state and state['qbmultichar:mode'] and state['qbmultichar:mode'] ~= false then return false end
    return Config.ui and Config.ui.interact == true
end

local function matchesRestriction(actual, required)
    if required == nil then return true end
    if type(required) == "string" then return actual == required end
    if type(required) ~= "table" then return false end

    for _, value in ipairs(required) do
        if actual == value then return true end
    end

    return false
end

local function playerData()
    local ok, data = pcall(function()
        return exports["qb-core"]:GetPlayerData()
    end)

    return ok and type(data) == "table" and data or nil
end

local function hasItem(item)
    local ok, result = pcall(function()
        return exports["qb-inventory"]:HasItem(item)
    end)

    return ok and result == true
end

local function isAvailable(option, data, ...)
    if type(option) ~= "table" or type(option.label) ~= "string" or #option.label == 0 then return false end

    if option.canInteract then
        if not isCallable(option.canInteract) then return false end
        local ok, allowed = pcall(option.canInteract, ...)
        if not ok or allowed ~= true then return false end
    end

    if option.job and (not data or not matchesRestriction(data.job and data.job.name, option.job)) then return false end
    if option.gang and (not data or not matchesRestriction(data.gang and data.gang.name, option.gang)) then return false end
    if option.citizenid and (not data or not matchesRestriction(data.citizenid, option.citizenid)) then return false end
    if option.item and not hasItem(option.item) then return false end

    return true
end

local function visibleOptions(options)
    assert(type(options) == "table" and #options > 0, "interact options must be a non-empty array.")

    local needsPlayerData = false
    for _, option in ipairs(options) do
        if type(option) == "table" and (option.job or option.gang or option.citizenid) then
            needsPlayerData = true
            break
        end
    end

    local data = needsPlayerData and playerData() or nil
    local visible = {}

    for _, option in ipairs(options) do
        if isAvailable(option, data) then
            -- Keep the original option for selection, but construct a compact
            -- NUI payload so no action/event data leaks into the browser.
            visible[#visible + 1] = option
        end
    end

    return visible
end

local function hide(session)
    if session and active ~= session then return false end
    if not active then return false end

    local controlLease = active.controlLease
    active = nil
    if controlLease then QB.controls.release(controlLease) end
    QB.nui.send("hideInteract")
    return true
end

local function dispatch(option)
    if isCallable(option.action) then
        option.action()
        return
    end

    if type(option.event) ~= "string" or #option.event == 0 then return end

    local args = option.args or {}
    assert(type(args) == "table", "interact option args must be an array.")

    if option.type == "server" then
        TriggerServerEvent(option.event, table.unpack(args))
    else
        TriggerEvent(option.event, table.unpack(args))
    end
end

-- Selecting an option only hides the compact selector -- it never resets the
-- zone's isInside state, and onEnter (the only thing that calls open()) fires
-- solely on a false->true transition. Without this, a player who never left
-- the zone's radius has no way to see the prompt again after picking an
-- option: onExit/onEnter can't refire while they're still standing inside.
-- Polls IsNuiFocused() rather than requiring the dispatched action to report
-- back, so this works for any option (an external menu, a server roundtrip,
-- or nothing at all) without qbinventory/other resources needing to know
-- interact exists. The grace period before the first check gives an
-- externally-opened menu (e.g. a shop, which grabs focus only after a server
-- roundtrip) time to actually take focus, so the prompt doesn't flash back on
-- screen in that gap.
local function watchForReopen(name)
    local zone = zonesByName[name]
    if not zone then return end

    CreateThread(function()
        Wait(500)

        while zonesByName[name] == zone and zone.isInside() and not active do
            if not IsNuiFocused() then
                local reopen = reopenFns[name]
                if reopen then reopen() end
                return
            end

            Wait(250)
        end
    end)
end

-- interact loads before nui under the manifest's alphabetical module glob,
-- so callbacks register lazily once a zone opens at runtime.
local function ensureCallbacks()
    if callbackRegistered then return end
    callbackRegistered = true

    QB.nui.registerCallback("selectOption", function(choice)
        local session = active
        if type(choice) ~= "number" or choice % 1 ~= 0 or not session then return {} end

        local option = session.options[choice]
        if not option then return {} end

        local zoneName = session.source
        hide(session)
        dispatch(option)
        if zoneName then watchForReopen(zoneName) end
        return {}
    end)

    QB.nui.registerCallback("closeInteract", function()
        hide()
        return {}
    end)
end

local function isPressed(controls)
    for _, control in ipairs(controls) do
        if IsDisabledControlJustPressed(0, control) then return true end
    end
    return false
end

local function controls(session)
    while active == session do
        if isPressed(Config.interact.previousControls) then
            QB.nui.send("scroll", -1)
        elseif isPressed(Config.interact.nextControls) then
            QB.nui.send("scroll", 1)
        elseif isPressed(Config.interact.selectControls) then
            QB.nui.send("select")
        elseif isPressed(Config.interact.cancelControls) then
            hide(session)
        end

        Wait(0)
    end
end

local function interactionControls()
    local controls, seen = {}, {}

    for _, list in ipairs({
        Config.interact.previousControls,
        Config.interact.nextControls,
        Config.interact.selectControls,
        Config.interact.cancelControls,
    }) do
        for _, control in ipairs(list) do
            if not seen[control] then
                seen[control] = true
                controls[#controls + 1] = control
            end
        end
    end

    return controls
end

local function open(options, source, owner)
    if not isEnabled() then return false end

    local available = visibleOptions(options)
    if #available == 0 then return false end

    ensureCallbacks()

    if active then hide(active) end

    local session = {
        options = available,
        source = source,
        owner = owner or GetCurrentResourceName(),
        controlLease = QB.controls.acquire(interactionControls()),
    }
    active = session

    local labels = {}
    for index, option in ipairs(available) do
        labels[index] = { label = option.label }
    end

    QB.nui.send("openInteract", labels)
    CreateThread(function()
        local ok, err = pcall(controls, session)
        if not ok then
            print(("[qblib:interact] input loop stopped after an error: %s"):format(tostring(err)))
            hide(session)
        end
    end)
    return true
end

---Opens the compact, game-input-driven selector. No NUI focus is granted.
---@param options QBInteractOption[]
---@return boolean opened False when disabled or no option passes its restrictions.
function QB.interact.open(options)
    return open(options, nil, GetInvokingResource() or GetCurrentResourceName())
end

---Hides any active selector without invoking an option.
---@return boolean closed
function QB.interact.close()
    return hide()
end

---@return boolean active
function QB.interact.isActive()
    return active ~= nil
end

---Adds a qblib sphere zone using qb-target-compatible option arguments.
---@param name string
---@param coords any
---@param radius number
---@param debug boolean
---@param targetOptions table `{ options: QBInteractOption[] }`
---@return QBZoneHandle? zone
function QB.interact.addCircleZone(name, coords, radius, targetOptions, debug)
    if not isEnabled() then return nil end
    assert(type(name) == "string" and #name > 0, "interact zone name is required.")
    assert(type(targetOptions) == "table",
        "interact target options require an options array.")

    if zonesByName[name] then zonesByName[name].remove() end

    local owner = GetInvokingResource() or GetCurrentResourceName()
    local function enter() open(targetOptions, name, owner) end
    reopenFns[name] = enter

    local zone = QB.zones.sphere({
        coords = coords,
        radius = radius or 5.0,
        debug = debug,
        onEnter = enter,
        onExit = function()
            if active and active.source == name then hide(active) end
        end,
    })

    zonesByName[name] = zone
    return zone
end

---Adds a qblib box zone using qb-target-compatible length/width/minZ/maxZ arguments.
---@param name string
---@param coords any
---@param size vector4
---@param targetOptions table `{ options: QBInteractOption[] }`
---@param debug boolean
---@return QBZoneHandle? zone
function QB.interact.addBoxZone(name, coords, size, targetOptions, debug)
    if not isEnabled() then return nil end
    assert(type(name) == "string" and #name > 0, "interact zone name is required.")
    assert(type(coords) == "table" or type(coords) == "vector3", "interact box coordinates must be vector-like.")
    assert(type(coords.x) == "number" and type(coords.y) == "number" and type(coords.z) == "number",
        "interact box coordinates must be vector-like.")
    assert(type(targetOptions) == "table",
        "interact target options require an options array.")

    if zonesByName[name] then zonesByName[name].remove() end

    local owner = GetInvokingResource() or GetCurrentResourceName()
    local function enter() open(targetOptions, name, owner) end
    reopenFns[name] = enter

    local zone = QB.zones.box({
        coords = { x = coords.x, y = coords.y, z = coords.z },
        size = { x = size.x, y = size.y, z = size.z },
        rotation = size.w or 0.0,
        debug = debug,
        onEnter = enter,
        onExit = function()
            if active and active.source == name then hide(active) end
        end,
    })

    zonesByName[name] = zone
    return zone
end

---Removes a zone previously created by addCircleZone/addBoxZone.
---@param name string
---@return boolean removed
function QB.interact.removeZone(name)
    local zone = zonesByName[name]
    if not zone then return false end

    zonesByName[name] = nil
    reopenFns[name] = nil
    if active and active.source == name then hide(active) end
    zone.remove()
    return true
end

---Adds static object zones for every currently streamed object matching model(s).
---Dynamic entities are intentionally not followed; call addTargetEntity after
---the entity exists for a one-off target.
---@param models string|number|(string|number)[]
---@param size table `{ x: number, y: number, z: number, w: number }`
---@param targetOptions table 
---@param debug boolean
---@return QBZoneHandle[] zones
function QB.interact.addTargetModel(models, size, targetOptions, debug)
    if not isEnabled() then return {} end
    assert(type(targetOptions) == "table", "interact target options require an options array.")

    if type(models) ~= "table" then models = { models } end
    local wanted = {}
    for _, model in ipairs(models) do
        assert(type(model) == "string" or type(model) == "number", "interact target models must be strings or hashes.")
        wanted[type(model) == "number" and model or GetHashKey(model)] = true
    end

    local zones = {}
    for _, entity in ipairs(GetGamePool("CObject")) do
        if wanted[GetEntityModel(entity)] then
            local coords = GetEntityCoords(entity)
            local size = {x = size.x or 3.0, y = size.y or 3.0, z = size.z or 4.0, w = size.w or GetEntityHeading(entity)}
            assert(type(size.x) == "number" and type(size.y) == "number" and type(size.z) == "number" and type(size.w) == "number",
                "interact target model size must be vector-like.")

            zones[#zones + 1] = QB.interact.addBoxZone(("model:%s"):format(entity), coords, size, targetOptions, debug)
        end
    end

    return zones
end

---Adds a static box zone at an entity's current position.
---@param entity number
---@param size table `{ x: number, y: number, z: number, w: number }`
---@param targetOptions table `{ options: QBInteractOption[], size?: any, debugPoly?: boolean }`
---@param debug boolean
---@return QBZoneHandle? zone
function QB.interact.addTargetEntity(entity, size, targetOptions, debug)
    if not isEnabled() then return nil end
    assert(type(targetOptions) == "table",
        "interact target options require an options array.")
    size = {x = size.x or 3.0, y = size.y or 3.0, z = size.z or 4.0, w = size.w or GetEntityHeading(entity)}
    if not size.w then size.w = GetEntityHeading(entity) end
    assert(type(size.x) == "number" and type(size.y) == "number" and type(size.z) == "number" and type(size.w) == "number",
        "interact target entity size must be vector-like.")
    local coords = GetEntityCoords(entity)
    return QB.interact.addBoxZone(("entity:%s"):format(entity), coords, size, targetOptions, debug)
end

-- Registers an aim-targeted entity through qbtarget, while keeping qblib's
-- option vocabulary (`action`/`event`) and resource-stop ownership at this
-- public boundary. Unlike addTargetEntity this follows a moving entity.
---@param entity number|number[]
---@param options QBInteractOption[]
---@param distance? number
---@return integer id
function QB.interact.addEntity(entity, options, distance)
    assert(type(options) == 'table' and #options > 0, 'interact entity options must be a non-empty array.')
    local owner = GetInvokingResource() or GetCurrentResourceName()
    local translated = {}
    for i, option in ipairs(options) do
        translated[i] = {
            label = option.label,
            icon = option.icon,
            distance = option.distance,
            bones = option.bones,
            data = option.data,
            canInteract = function(target, targetDistance, data)
                return isAvailable(option, playerData(), target, targetDistance, data)
            end,
            onSelect = function() dispatch(option) end,
        }
    end
    local id = exports.qbtarget:addEntity(entity, translated, distance)
    -- qbtarget's removeEntity takes one entity even when registration covered
    -- several; removing by id tears down that whole registration.
    targetRegistry.track(owner, { kind = 'entity', value = type(entity) == 'table' and entity[1] or entity, id = id })
    return id
end

---@param entity number
---@param id? integer
---@return boolean
function QB.interact.removeEntity(entity, id)
    return exports.qbtarget:removeEntity(entity, id)
end

---@param model string|number|(string|number)[]
---@param options QBInteractOption[]
---@param distance? number
---@return integer id
function QB.interact.addModel(model, options, distance)
    assert(type(options) == 'table' and #options > 0, 'interact model options must be a non-empty array.')
    local owner = GetInvokingResource() or GetCurrentResourceName()
    local translated = {}
    for i, option in ipairs(options) do
        translated[i] = {
            label = option.label,
            icon = option.icon,
            distance = option.distance,
            bones = option.bones,
            canInteract = function(target, targetDistance, data)
                return isAvailable(option, playerData(), target, targetDistance, data)
            end,
            onSelect = function() dispatch(option) end,
        }
    end
    local id = exports.qbtarget:addModel(model, translated, distance)
    targetRegistry.track(owner, { kind = 'model', value = model, id = id })
    return id
end

---@param model string|number|(string|number)[]
---@param id? integer
---@return boolean
function QB.interact.removeModel(model, id)
    return exports.qbtarget:removeModel(model, id)
end

AddEventHandler("onClientResourceStop", function(resourceName)
    if active and (active.owner == resourceName or resourceName == GetCurrentResourceName()) then
        hide(active)
    end
end)
