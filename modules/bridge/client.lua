local function call(area, method, fallback, ...)
    return Kora.compat.bridgeCall(area, method, fallback, ...)
end

local function assertString(value, name)
    assert(type(value) == 'string' and value ~= '', ('%s must be a non-empty string.'):format(name))
end

local function assertTable(value, name)
    assert(type(value) == 'table', ('%s must be a table.'):format(name))
end

local function assertFiniteNumber(value, name)
    assert(type(value) == 'number' and value == value and math.abs(value) < math.huge,
        ('%s must be a finite number.'):format(name))
end

---Opens the job or gang boss menu.
---@param roleType? string
function Kora.bridge.openBossMenu(roleType)
    assert(roleType == nil or type(roleType) == 'string', 'roleType must be a string or nil.')
    return call('bossmenu', 'openBossMenu', table.pack(nil), roleType)
end

---Opens an organization application form.
---@param jobName string
---@param roleType? string
function Kora.bridge.openApplication(jobName, roleType)
    assertString(jobName, 'jobName')
    assert(roleType == nil or type(roleType) == 'string', 'roleType must be a string or nil.')
    return call('bossmenu', 'openApplication', table.pack(nil), jobName, roleType)
end

---Adds an item to the job boss menu and returns its key.
---@param data table
---@param id? string|integer
---@return string|integer|nil itemId
function Kora.bridge.addBossMenuItem(data, id)
    assertTable(data, 'data')
    assert(id == nil or type(id) == 'string' or (type(id) == 'number' and id % 1 == 0),
        'id must be a string, integer, or nil.')
    return call('bossmenu', 'addBossMenuItem', table.pack(nil), data, id)
end

---Removes an item from the job boss menu.
---@param id string|integer
function Kora.bridge.removeBossMenuItem(id)
    assert(type(id) == 'string' or (type(id) == 'number' and id % 1 == 0), 'id must be a string or integer.')
    return call('bossmenu', 'removeBossMenuItem', table.pack(nil), id)
end

---Adds an item to the gang boss menu and returns its key.
---@param data table
---@param id? string|integer
---@return string|integer|nil itemId
function Kora.bridge.addGangMenuItem(data, id)
    assertTable(data, 'data')
    assert(id == nil or type(id) == 'string' or (type(id) == 'number' and id % 1 == 0),
        'id must be a string, integer, or nil.')
    return call('bossmenu', 'addGangMenuItem', table.pack(nil), data, id)
end

---Removes an item from the gang boss menu.
---@param id string|integer
function Kora.bridge.removeGangMenuItem(id)
    assert(type(id) == 'string' or (type(id) == 'number' and id % 1 == 0), 'id must be a string or integer.')
    return call('bossmenu', 'removeGangMenuItem', table.pack(nil), id)
end

---Opens a player's wardrobe.
function Kora.bridge.openWardrobe()
    return call('clothing', 'openWardrobe', table.pack(nil))
end

---Opens a clothing room.
---@param options? table|number|string
function Kora.bridge.openClothingRoom(options)
    assert(options == nil or type(options) == 'table' or type(options) == 'number' or type(options) == 'string',
        'options must be a table, number, string, or nil.')
    return call('clothing', 'openClothingRoom', table.pack(nil), options)
end

---Applies a saved appearance to a ped.
---@param ped integer
---@param model string
---@param skin table
---@return boolean applied
---@return string|nil error
function Kora.bridge.applyAppearanceToPed(ped, model, skin)
    assert(type(ped) == 'number' and ped % 1 == 0, 'ped must be an integer entity handle.')
    assertString(model, 'model')
    assertTable(skin, 'skin')
    return call('clothing', 'applyAppearanceToPed', table.pack(false, 'unavailable'), ped, model, skin)
end

---Applies the configured starter appearance.
---@return boolean applied
function Kora.bridge.applyStarterAppearance()
    return call('clothing', 'applyStarterAppearance', table.pack(false))
end

---Reloads the saved appearance.
function Kora.bridge.reloadSkin()
    return call('clothing', 'reloadSkin', table.pack(nil))
end

---Returns the closest door object, if one is nearby.
---@return table|nil door
function Kora.bridge.getClosestDoor()
    return call('doorlock', 'getClosestDoor', table.pack(nil))
end

---Returns a door's current lock state.
---@param id string
---@return boolean|nil state
function Kora.bridge.getDoorState(id)
    assertString(id, 'id')
    return call('doorlock', 'getDoorState', table.pack(nil), id)
end

---Starts the lockpick action for the closest door.
---@return boolean|nil started
function Kora.bridge.pickClosestDoor()
    return call('doorlock', 'pickClosestDoor', table.pack(false))
end

---Returns a vehicle's fuel level.
---@param vehicle integer
---@return number level
function Kora.bridge.getFuel(vehicle)
    assert(type(vehicle) == 'number' and vehicle % 1 == 0, 'vehicle must be an integer entity handle.')
    return call('fuel', 'getFuel', table.pack(0), vehicle)
end

---Sets a vehicle's fuel level.
---@param vehicle integer
---@param level number
---@return boolean changed
function Kora.bridge.setFuel(vehicle, level)
    assert(type(vehicle) == 'number' and vehicle % 1 == 0, 'vehicle must be an integer entity handle.')
    assertFiniteNumber(level, 'level')
    return call('fuel', 'setFuel', table.pack(false), vehicle, level)
end

---Reports whether a vehicle model is electric.
---@param vehicle integer
---@return boolean electric
function Kora.bridge.isElectricVehicle(vehicle)
    assert(type(vehicle) == 'number' and vehicle % 1 == 0, 'vehicle must be an integer entity handle.')
    return call('fuel', 'isElectricVehicle', table.pack(false), vehicle)
end

---Displays a help prompt and returns the prompt handle.
---@param text string
---@param options? KoraTextUIOptions
---@return integer|nil id
function Kora.bridge.showHelpText(text, options)
    assertString(text, 'text')
    assert(options == nil or type(options) == 'table', 'options must be a table or nil.')
    return call('helptext', 'show', table.pack(nil), text, options)
end

---Updates a live help prompt.
---@param id integer
---@param text string
---@param options? KoraTextUIOptions
---@return boolean updated
function Kora.bridge.updateHelpText(id, text, options)
    assert(type(id) == 'number' and id % 1 == 0, 'id must be an integer.')
    assertString(text, 'text')
    assert(options == nil or type(options) == 'table', 'options must be a table or nil.')
    return call('helptext', 'update', table.pack(false), id, text, options)
end

---Hides a live help prompt.
---@param id integer
---@return boolean hidden
function Kora.bridge.hideHelpText(id)
    assert(type(id) == 'number' and id % 1 == 0, 'id must be an integer.')
    return call('helptext', 'hide', table.pack(false), id)
end

---Sends a notification through Kora Notify or the configured third-party notify path.
---@param payload KoraNotifyPayload
function Kora.bridge.sendNotification(payload)
    assertTable(payload, 'payload')
    return call('notify', 'send', table.pack(nil), payload)
end