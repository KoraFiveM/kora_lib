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

local function isCallable(value)
    if type(value) == "function" then return true end
    local mt = type(value) == "table" and getmetatable(value) or nil
    return mt ~= nil and mt.__call ~= nil
end

local function isEnabled()
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

local function isAvailable(option, data)
    if type(option) ~= "table" or type(option.label) ~= "string" or #option.label == 0 then return false end

    if option.canInteract then
        if not isCallable(option.canInteract) then return false end
        local ok, allowed = pcall(option.canInteract)
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

    active = nil
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

        hide(session)
        dispatch(option)
        return {}
    end)

    QB.nui.registerCallback("closeInteract", function()
        hide()
        return {}
    end)
end

local function disableControls(controls)
    for _, control in ipairs(controls) do
        DisableControlAction(0, control, true)
    end
end

local function isPressed(controls)
    for _, control in ipairs(controls) do
        if IsDisabledControlJustPressed(0, control) then return true end
    end
    return false
end

local function controls(session)
    while active == session do
        disableControls(Config.interact.previousControls)
        disableControls(Config.interact.nextControls)
        disableControls(Config.interact.selectControls)
        disableControls(Config.interact.cancelControls)

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

local function open(options, source)
    if not isEnabled() then return false end

    local available = visibleOptions(options)
    if #available == 0 then return false end

    ensureCallbacks()

    local session = { options = available, source = source }
    active = session

    local labels = {}
    for index, option in ipairs(available) do
        labels[index] = { label = option.label }
    end

    QB.nui.send("openInteract", labels)
    CreateThread(function() controls(session) end)
    return true
end

---Opens the compact, game-input-driven selector. No NUI focus is granted.
---@param options QBInteractOption[]
---@return boolean opened False when disabled or no option passes its restrictions.
function QB.interact.open(options)
    return open(options)
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
    local zone = QB.zones.sphere({
        coords = coords,
        radius = radius or 5.0,
        debug = debug,
        onEnter = function() open(targetOptions, name) end,
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

    local zone = QB.zones.box({
        coords = { x = coords.x, y = coords.y, z = coords.z },
        size = { x = size.x, y = size.y, z = size.z },
        rotation = size.w or 0.0,
        debug = debug,
        onEnter = function() open(targetOptions, name) end,
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
            local size = size or  { x = 3.0, y = 3.0, z = 4.0, w = GetEntityHeading(entity) }
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

    size = size or { x = 3.0, y = 3.0, z = 4.0, w = GetEntityHeading(entity) }
    assert(type(size.x) == "number" and type(size.y) == "number" and type(size.z) == "number" and type(size.w) == "number",
        "interact target entity size must be vector-like.")
    local coords = GetEntityCoords(entity)
    return QB.interact.addBoxZone(("entity:%s"):format(entity), coords, size, targetOptions, debug)
end
