local active
local callbackRegistered = false
local zonesByName = {}
local reopenFns = {}
local zoneOwners = {}
local targetHandles = { entity = {}, model = {} }
local targetRegistry = Kora.resources.registry(function(handle)
    targetHandles[handle.kind][handle.id] = nil
    if handle.kind == 'entity' then
        exports.kora_target:removeEntity(handle.value, handle.id)
    else
        exports.kora_target:removeModel(handle.value, handle.id)
    end
end)

local isCallable = Kora.compat.isCallable

local function isEnabled()
    local state = LocalPlayer and LocalPlayer.state
    if state and state['kora_multichar:mode'] and state['kora_multichar:mode'] ~= false then return false end
    return Config.ui and Config.ui.interact == true
end

local function matchesRestriction(actual, grade, required)
    if required == nil then return true end
    if type(required) == "string" then return actual == required end
    if type(required) ~= "table" then return false end

    for valueIndex = 1, #required do
        local value = required[valueIndex]
        if actual == value then return true end
    end

    if actual == nil then return false end
    local minimum = required[actual]
    if type(minimum) == 'boolean' then return minimum end
    return type(minimum) == 'number' and type(grade) == 'number' and grade >= minimum
end

local function groupGrade(group)
    local grade = type(group) == 'table' and group.grade or nil
    if type(grade) == 'table' then grade = grade.level end
    return Kora.util.isFiniteNumber(grade) and grade or nil
end

local function playerData()
    local ok, data = pcall(function()
        return exports.kora_core:getPlayerData()
    end)

    return ok and type(data) == "table" and data or nil
end

local function hasItem(item)
    local ok, result = pcall(function()
        return exports["qb-inventory"]:HasItem(item)
    end)

    return ok and result == true
end

local function isAvailable(option, data, itemAvailability, ...)
    if type(option) ~= "table" or type(option.label) ~= "string" or #option.label == 0 then return false end

    if option.canInteract then
        if not isCallable(option.canInteract) then return false end
        local ok, allowed = pcall(option.canInteract, ...)
        if not ok or allowed ~= true then return false end
    end

    if option.job and (not data or not matchesRestriction(data.job and data.job.name, groupGrade(data.job), option.job)) then return false end
    if option.gang and (not data or not matchesRestriction(data.gang and data.gang.name, groupGrade(data.gang), option.gang)) then return false end
    if option.citizenid and (not data or not matchesRestriction(data.citizenid, nil, option.citizenid)) then return false end
    if option.item then
        local allowed = itemAvailability and itemAvailability[option.item]
        if allowed == nil then
            allowed = hasItem(option.item)
            if itemAvailability then itemAvailability[option.item] = allowed end
        end
        if not allowed then return false end
    end

    return true
end

local function visibleOptions(options)
    assert(type(options) == "table" and #options > 0, "interact options must be a non-empty array.")

    local needsPlayerData = false
    for optionIndex = 1, #options do
        local option = options[optionIndex]
        if type(option) == "table" and (option.job or option.gang or option.citizenid) then
            needsPlayerData = true
            break
        end
    end

    local data = needsPlayerData and playerData() or nil
    local itemAvailability = {}
    local visible = {}

    for optionIndex = 1, #options do
        local option = options[optionIndex]
        if isAvailable(option, data, itemAvailability) then
            visible[#visible + 1] = option
        end
    end

    return visible
end

local function hide(session)
    if session and active ~= session then return false end
    if not active then return false end

    local controlLease, owner = active.controlLease, active.owner
    active = nil
    if controlLease then Kora.compat.releaseControlLease(controlLease, owner) end
    Kora.nui.send("hideInteract")
    return true
end

local function dispatch(option)
    if isCallable(option.action) then
        -- Runs synchronously up to its first yield, then detaches: an action
        -- that opens an app or awaits a callback must not hold the selectOption
        -- NUI callback (and its fetch) open until it finishes.
        Citizen.CreateThreadNow(function() option.action() end)
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

local function ensureCallbacks()
    if callbackRegistered then return end
    callbackRegistered = true

    Kora.nui.registerCallback("selectOption", function(choice)
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

    Kora.nui.registerCallback("closeInteract", function()
        hide()
        return {}
    end)
end

local function isPressed(controls)
    for controlIndex = 1, #controls do
        local control = controls[controlIndex]
        if IsDisabledControlJustPressed(0, control) then return true end
    end
    return false
end

local function controls(session)
    while active == session do
        if isPressed(Config.interact.previousControls) then
            Kora.nui.send("scroll", -1)
        elseif isPressed(Config.interact.nextControls) then
            Kora.nui.send("scroll", 1)
        elseif isPressed(Config.interact.selectControls) then
            Kora.nui.send("select")
        elseif isPressed(Config.interact.cancelControls) then
            hide(session)
        end

        Wait(0)
    end
end

local function interactionControls()
    local controls, seen = {}, {}
    local controlLists = {
        Config.interact.previousControls,
        Config.interact.nextControls,
        Config.interact.selectControls,
        Config.interact.cancelControls,
    }

    for listIndex = 1, #controlLists do
        local list = controlLists[listIndex]
        for controlIndex = 1, #list do
            local control = list[controlIndex]
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

    owner = owner or GetCurrentResourceName()
    local session = {
        options = available,
        source = source,
        owner = owner,
        controlLease = Kora.compat.acquireControls(interactionControls(), nil, owner),
    }
    active = session

    local labels = {}
    for index = 1, #available do
        local option = available[index]
        labels[index] = { label = option.label, icon = option.icon }
    end

    Kora.nui.send("openInteract", labels)
    CreateThread(function()
        local ok, err = pcall(controls, session)
        if not ok then
            print(("[kora_lib:interact] input loop stopped after an error: %s"):format(tostring(err)))
            hide(session)
        end
    end)
    return true
end

local function removeNamedZone(name)
    local zone = zonesByName[name]
    if not zone then return false end

    zonesByName[name] = nil
    reopenFns[name] = nil
    zoneOwners[name] = nil
    if active and active.source == name then hide(active) end
    zone.remove()
    return true
end

local function compatVector(vec)
    return vector3(vec.x, vec.y, vec.z)
end

---Opens the compact, game-input-driven selector. No NUI focus is granted.
---@param options KoraInteractOption[]
---@return boolean opened False when disabled or no option passes its restrictions.
function Kora.interact.open(options)
    return open(options, nil, GetInvokingResource() or GetCurrentResourceName())
end

---Hides any active selector without invoking an option.
---@return boolean closed
function Kora.interact.close()
    return hide()
end

---@return boolean active
function Kora.interact.isActive()
    return active ~= nil
end

local function assertCoords(coords, label)
    assert((type(coords) == 'table' or type(coords) == 'vector3')
        and Kora.util.isFiniteNumber(coords.x) and Kora.util.isFiniteNumber(coords.y) and Kora.util.isFiniteNumber(coords.z),
        ('%s must have finite x, y, and z coordinates.'):format(label))
end

local function assertBoxSize(size, label)
    assert((type(size) == 'table' or type(size) == 'vector3' or type(size) == 'vector4')
        and Kora.util.isFiniteNumber(size.x) and Kora.util.isFiniteNumber(size.y)
        and Kora.util.isFiniteNumber(size.z) and size.x > 0 and size.y > 0 and size.z > 0,
        ('%s must have positive finite x, y, and z dimensions.'):format(label))
    assert(size.w == nil or Kora.util.isFiniteNumber(size.w), ('%s rotation must be finite.'):format(label))
end

local function zoneOptionList(targetOptions)
    assert(type(targetOptions) == "table", "interact target options require an options array.")
    local options = targetOptions.options
    if options == nil then options = targetOptions end
    assert(type(options) == "table" and #options > 0,
        "interact target options require a non-empty options array.")
    return options
end

---Adds a kora_lib sphere zone using qb-target-compatible option arguments.
---@param name string
---@param coords any
---@param radius number
---@param debug boolean
---@param targetOptions KoraInteractTargetOptions|KoraInteractOption[]
---@return KoraZoneHandle? zone
function Kora.interact.addCircleZone(name, coords, radius, targetOptions, debug)
    if not isEnabled() then return nil end
    assert(type(name) == "string" and #name > 0, "interact zone name is required.")
    local options = zoneOptionList(targetOptions)
    assertCoords(coords, 'interact circle coordinates')
    if radius == nil then radius = 5.0 end
    assert(Kora.util.isFiniteNumber(radius) and radius > 0, 'interact circle radius must be positive and finite.')

    local owner = GetInvokingResource() or GetCurrentResourceName()
    if zonesByName[name] then
        if zoneOwners[name] ~= owner then return nil end
        removeNamedZone(name)
    end
    local function enter() open(options, name, owner) end
    local zone = Kora.zones.sphere({
        coords = compatVector(coords),
        radius = radius,
        debug = debug,
        onEnter = enter,
        onExit = function()
            if active and active.source == name then hide(active) end
        end,
    })

    zonesByName[name] = zone
    reopenFns[name] = enter
    zoneOwners[name] = owner
    return zone
end

---Adds a kora_lib box zone using qb-target-compatible length/width/minZ/maxZ arguments.
---@param name string
---@param coords any
---@param size vector4
---@param targetOptions KoraInteractTargetOptions|KoraInteractOption[]
---@param debug boolean
---@return KoraZoneHandle? zone
function Kora.interact.addBoxZone(name, coords, size, targetOptions, debug)
    if not isEnabled() then return nil end
    assert(type(name) == "string" and #name > 0, "interact zone name is required.")
    local options = zoneOptionList(targetOptions)
    assertCoords(coords, 'interact box coordinates')
    assertBoxSize(size, 'interact box size')

    local owner = GetInvokingResource() or GetCurrentResourceName()
    if zonesByName[name] then
        if zoneOwners[name] ~= owner then return nil end
        removeNamedZone(name)
    end
    local function enter() open(options, name, owner) end
    local zone = Kora.zones.box({
        coords = compatVector(coords),
        size = compatVector(size),
        rotation = size.w or 0.0,
        debug = debug,
        onEnter = enter,
        onExit = function()
            if active and active.source == name then hide(active) end
        end,
    })

    zonesByName[name] = zone
    reopenFns[name] = enter
    zoneOwners[name] = owner
    return zone
end

---Removes a zone previously created by addCircleZone/addBoxZone.
---@param name string
---@return boolean removed
function Kora.interact.removeZone(name)
    if zoneOwners[name] ~= (GetInvokingResource() or GetCurrentResourceName()) then return false end
    return removeNamedZone(name)
end

---Adds static object zones for every currently streamed object matching model(s).
---Dynamic entities are intentionally not followed; call addTargetEntity after
---the entity exists for a one-off target.
---@param models string|number|(string|number)[]
---@param size vector4
---@param targetOptions KoraInteractTargetOptions|KoraInteractOption[]
---@param debug boolean
---@return KoraZoneHandle[] zones
function Kora.interact.addTargetModel(models, size, targetOptions, debug)
    if not isEnabled() then return {} end
    assert(type(targetOptions) == "table", "interact target options require an options array.")

    if type(models) ~= "table" then models = { models } end
    local wanted = {}
    for modelIndex = 1, #models do
        local model = models[modelIndex]
        assert(type(model) == "string" or type(model) == "number", "interact target models must be strings or hashes.")
        wanted[type(model) == "number" and model or joaat(model)] = true
    end

    local zones = {}
    local objects = GetGamePool("CObject")
    for entityIndex = 1, #objects do
        local entity = objects[entityIndex]
        if wanted[GetEntityModel(entity)] then
            local coords = GetEntityCoords(entity)
            local size = {x = size.x or 3.0, y = size.y or 3.0, z = size.z or 4.0, w = size.w or GetEntityHeading(entity)}
            assert(type(size.x) == "number" and type(size.y) == "number" and type(size.z) == "number" and type(size.w) == "number",
                "interact target model size must be vector-like.")

            zones[#zones + 1] = Kora.interact.addBoxZone(("model:%s"):format(entity), coords, size, targetOptions, debug)
        end
    end

    return zones
end

---Adds a static box zone at an entity's current position.
---@param entity number
---@param size table `{ x: number, y: number, z: number, w: number }`
---@param targetOptions KoraInteractTargetOptions|KoraInteractOption[]
---@param debug boolean
---@return KoraZoneHandle? zone
function Kora.interact.addTargetEntity(entity, size, targetOptions, debug)
    if not isEnabled() then return nil end
    assert(type(targetOptions) == "table",
        "interact target options require an options array.")
    size = {x = size.x or 3.0, y = size.y or 3.0, z = size.z or 4.0, w = size.w or GetEntityHeading(entity)}
    assert(type(size.x) == "number" and type(size.y) == "number" and type(size.z) == "number" and type(size.w) == "number",
        "interact target entity size must be vector-like.")
    local coords = GetEntityCoords(entity)
    return Kora.interact.addBoxZone(("entity:%s"):format(entity), coords, size, targetOptions, debug)
end

local function assertTargetDistance(distance)
    assert(distance == nil or (Kora.util.isFiniteNumber(distance) and distance > 0),
        'interact target distance must be a positive finite number.')
end

---@param entity number|number[]
---@param options KoraInteractOption[]
---@param distance? number
---@return integer id
function Kora.interact.addEntity(entity, options, distance)
    assert(type(options) == 'table' and #options > 0, 'interact entity options must be a non-empty array.')
    assertTargetDistance(distance)
    local owner = GetInvokingResource() or GetCurrentResourceName()
    local translated = {}
    for i = 1, #options do
        local option = options[i]
        assertTargetDistance(option.distance)
        translated[i] = {
            label = option.label,
            icon = option.icon,
            distance = option.distance,
            bones = option.bones,
            data = option.data,
            canInteract = function(target, targetDistance, data)
                return isAvailable(option, playerData(), nil, target, targetDistance, data)
            end,
            onSelect = function() dispatch(option) end,
        }
    end
    local id = exports.kora_target:addEntity(entity, translated, distance)
    local handle = { kind = 'entity', value = type(entity) == 'table' and entity[1] or entity, id = id }
    targetHandles.entity[id] = handle
    targetRegistry.track(owner, handle)
    return id
end

---@param entity number
---@param id? integer
---@return boolean
function Kora.interact.removeEntity(entity, id)
    if id then
        local handle = targetHandles.entity[id]
        if not handle or targetRegistry.owner(handle) ~= (GetInvokingResource() or GetCurrentResourceName()) then
            return false
        end
        if exports.kora_target:removeEntity(handle.value, id) ~= true then return false end
        targetHandles.entity[id] = nil
        targetRegistry.untrack(handle)
        return true
    end

    local removed = false
    for targetId, handle in pairs(targetHandles.entity) do
        if handle.value == entity and targetRegistry.owner(handle) == (GetInvokingResource() or GetCurrentResourceName())
            and exports.kora_target:removeEntity(handle.value, targetId) == true then
            targetHandles.entity[targetId] = nil
            targetRegistry.untrack(handle)
            removed = true
        end
    end
    return removed
end

---@param model string|number|(string|number)[]
---@param options KoraInteractOption[]
---@param distance? number
---@return integer id
function Kora.interact.addModel(model, options, distance)
    assert(type(options) == 'table' and #options > 0, 'interact model options must be a non-empty array.')
    assertTargetDistance(distance)
    local owner = GetInvokingResource() or GetCurrentResourceName()
    local translated = {}
    for i = 1, #options do
        local option = options[i]
        assertTargetDistance(option.distance)
        translated[i] = {
            label = option.label,
            icon = option.icon,
            distance = option.distance,
            bones = option.bones,
            canInteract = function(target, targetDistance, data)
                return isAvailable(option, playerData(), nil, target, targetDistance, data)
            end,
            onSelect = function() dispatch(option) end,
        }
    end
    local id = exports.kora_target:addModel(model, translated, distance)
    local handle = { kind = 'model', value = model, id = id }
    targetHandles.model[id] = handle
    targetRegistry.track(owner, handle)
    return id
end

---@param model string|number|(string|number)[]
---@param id? integer
---@return boolean
function Kora.interact.removeModel(model, id)
    if id then
        local handle = targetHandles.model[id]
        if not handle or targetRegistry.owner(handle) ~= (GetInvokingResource() or GetCurrentResourceName()) then
            return false
        end
        if exports.kora_target:removeModel(handle.value, id) ~= true then return false end
        targetHandles.model[id] = nil
        targetRegistry.untrack(handle)
        return true
    end

    local removed = false
    for targetId, handle in pairs(targetHandles.model) do
        if handle.value == model and targetRegistry.owner(handle) == (GetInvokingResource() or GetCurrentResourceName())
            and exports.kora_target:removeModel(handle.value, targetId) == true then
            targetHandles.model[targetId] = nil
            targetRegistry.untrack(handle)
            removed = true
        end
    end
    return removed
end

AddEventHandler("onClientResourceStop", function(resourceName)
    if active and (active.owner == resourceName or resourceName == GetCurrentResourceName()) then
        hide(active)
    end

    local ownedNames = {}
    for name, owner in pairs(zoneOwners) do
        if owner == resourceName or resourceName == GetCurrentResourceName() then
            ownedNames[#ownedNames + 1] = name
        end
    end
    for i = 1, #ownedNames do removeNamedZone(ownedNames[i]) end
end)
