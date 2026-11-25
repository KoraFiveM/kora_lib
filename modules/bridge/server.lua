local function call(area, method, fallback, ...)
    return Kora.compat.bridgeCall(area, method, fallback, ...)
end

local function assertString(value, name)
    assert(type(value) == 'string' and value ~= '', ('%s must be a non-empty string.'):format(name))
end

local function assertFiniteNumber(value, name)
    assert(type(value) == 'number' and value == value and math.abs(value) < math.huge,
        ('%s must be a finite number.'):format(name))
end

local function assertTable(value, name)
    assert(type(value) == 'table', ('%s must be a table.'):format(name))
end

---Credits a named account.
---@param name string
---@param amount number
---@param reason? string
---@return boolean ok
function Kora.bridge.addSocietyMoney(name, amount, reason)
    assertString(name, 'name')
    assertFiniteNumber(amount, 'amount')
    assert(reason == nil or type(reason) == 'string', 'reason must be a string or nil.')
    return call('banking', 'addSocietyMoney', table.pack(false), name, amount, reason)
end

---Debits a named account.
---@param name string
---@param amount number
---@param reason? string
---@return boolean ok
function Kora.bridge.removeSocietyMoney(name, amount, reason)
    assertString(name, 'name')
    assertFiniteNumber(amount, 'amount')
    assert(reason == nil or type(reason) == 'string', 'reason must be a string or nil.')
    return call('banking', 'removeSocietyMoney', table.pack(false), name, amount, reason)
end

---Returns a named account's cached balance.
---@param name string
---@return number balance
function Kora.bridge.getSocietyAccountBalance(name)
    assertString(name, 'name')
    return call('banking', 'getSocietyAccountBalance', table.pack(0), name)
end

---Executes an idempotent multi-party transaction.
---@param key string
---@param request table
---@return any ...
function Kora.bridge.executeSocietyTransaction(key, request)
    assertString(key, 'key')
    assertTable(request, 'request')
    return call('banking', 'executeSocietyTransaction', table.pack(nil, 'unavailable'), key, request)
end

---Creates a bank statement entry.
---@param playerId integer
---@param account string
---@param amount number
---@param reason string
---@param kind 'deposit'|'withdraw'
---@param accountType? string
---@return any ...
function Kora.bridge.createSocietyBankStatement(playerId, account, amount, reason, kind, accountType)
    assert(type(playerId) == 'number' and playerId % 1 == 0, 'playerId must be an integer.')
    assertString(account, 'account')
    assertFiniteNumber(amount, 'amount')
    assert(type(reason) == 'string', 'reason must be a string.')
    assert(kind == 'deposit' or kind == 'withdraw', "kind must be 'deposit' or 'withdraw'.")
    assert(accountType == nil or type(accountType) == 'string', 'accountType must be a string or nil.')
    return call(
        'banking', 'createSocietyBankStatement', table.pack(false), playerId, account, amount, reason, kind, accountType
    )
end

---Credits a job business account.
---@param jobName string
---@param amount number
---@param reason? string
---@return boolean ok
---@return string|nil error
function Kora.bridge.addBusinessMoney(jobName, amount, reason)
    assertString(jobName, 'jobName')
    assertFiniteNumber(amount, 'amount')
    assert(reason == nil or type(reason) == 'string', 'reason must be a string or nil.')
    return call('bossmenu', 'addBusinessMoney', table.pack(false, 'unavailable'), jobName, amount, reason)
end

---Debits a job business account.
---@param jobName string
---@param amount number
---@param reason? string
---@return boolean ok
---@return string|nil error
function Kora.bridge.removeBusinessMoney(jobName, amount, reason)
    assertString(jobName, 'jobName')
    assertFiniteNumber(amount, 'amount')
    assert(reason == nil or type(reason) == 'string', 'reason must be a string or nil.')
    return call('bossmenu', 'removeBusinessMoney', table.pack(false, 'unavailable'), jobName, amount, reason)
end

---Returns a job business account balance.
---@param jobName string
---@return number|nil balance
---@return string|nil error
function Kora.bridge.getBusinessBalance(jobName)
    assertString(jobName, 'jobName')
    return call('bossmenu', 'getBusinessBalance', table.pack(nil, 'unavailable'), jobName)
end

---Credits a job account through the boss-menu compatibility export.
---@param jobName string
---@param amount number
---@return boolean ok
function Kora.bridge.bossmenuAddMoney(jobName, amount)
    assertString(jobName, 'jobName')
    assertFiniteNumber(amount, 'amount')
    return call('bossmenu', 'addMoney', table.pack(false), jobName, amount)
end

---Debits a job account through the boss-menu compatibility export.
---@param jobName string
---@param amount number
---@return boolean ok
function Kora.bridge.bossmenuRemoveMoney(jobName, amount)
    assertString(jobName, 'jobName')
    assertFiniteNumber(amount, 'amount')
    return call('bossmenu', 'removeMoney', table.pack(false), jobName, amount)
end

---Credits a gang account.
---@param gangName string
---@param amount number
---@return boolean ok
function Kora.bridge.addGangMoney(gangName, amount)
    assertString(gangName, 'gangName')
    assertFiniteNumber(amount, 'amount')
    return call('bossmenu', 'addGangMoney', table.pack(false), gangName, amount)
end

---Debits a gang account.
---@param gangName string
---@param amount number
---@return boolean ok
function Kora.bridge.removeGangMoney(gangName, amount)
    assertString(gangName, 'gangName')
    assertFiniteNumber(amount, 'amount')
    return call('bossmenu', 'removeGangMoney', table.pack(false), gangName, amount)
end

---Returns a gang account balance.
---@param gangName string
---@return number balance
function Kora.bridge.getGangBalance(gangName)
    assertString(gangName, 'gangName')
    return call('bossmenu', 'getGangBalance', table.pack(0), gangName)
end

---Creates a dispatch call.
---@param payload table
---@return integer|false id
---@return any ...
function Kora.bridge.createCall(payload)
    assertTable(payload, 'payload')
    return call('dispatch', 'createCall', table.pack(false, 'unavailable'), payload)
end

---Updates an open dispatch call.
---@param id integer
---@param patch table
---@return boolean ok
---@return string|nil error
function Kora.bridge.updateCall(id, patch)
    assert(type(id) == 'number' and id % 1 == 0, 'id must be an integer.')
    assertTable(patch, 'patch')
    return call('dispatch', 'updateCall', table.pack(false, 'unavailable'), id, patch)
end

---Closes a dispatch call.
---@param id integer
---@param reason? string
---@return boolean ok
---@return string|nil error
function Kora.bridge.closeCall(id, reason)
    assert(type(id) == 'number' and id % 1 == 0, 'id must be an integer.')
    assert(reason == nil or type(reason) == 'string', 'reason must be a string or nil.')
    return call('dispatch', 'closeCall', table.pack(false, 'unavailable'), id, reason)
end

---Returns dispatch calls matching an optional filter.
---@param filter? table
---@return table calls
function Kora.bridge.getCalls(filter)
    assert(filter == nil or type(filter) == 'table', 'filter must be a table or nil.')
    return call('dispatch', 'getCalls', table.pack({}), filter)
end

---Registers a resource-owned player alert.
---@param key string
---@param definition table
---@return boolean ok
---@return string|nil error
function Kora.bridge.registerPlayerAlert(key, definition)
    assertString(key, 'key')
    assertTable(definition, 'definition')
    return call('dispatch', 'registerPlayerAlert', table.pack(false, 'unavailable'), key, definition)
end

---Creates a dispatch call for a registered player alert.
---@param src integer
---@param key string
---@return integer|false callId
---@return any ...
function Kora.bridge.createPlayerCall(src, key)
    assert(type(src) == 'number' and src % 1 == 0, 'src must be an integer.')
    assertString(key, 'key')
    return call('dispatch', 'createPlayerCall', table.pack(false, 'unavailable'), src, key)
end

---Changes a door's lock state.
---@param id string
---@param state boolean|0|1
---@return boolean|nil changed
function Kora.bridge.setDoorState(id, state)
    assertString(id, 'id')
    assert(state == true or state == false or state == 0 or state == 1, 'state must be a boolean, 0, or 1.')
    return call('doorlock', 'setDoorState', table.pack(false), id, state)
end

---Creates a door definition.
---@param raw table
---@return string|false id
---@return string|nil error
function Kora.bridge.createDoor(raw)
    assertTable(raw, 'raw')
    return call('doorlock', 'createDoor', table.pack(false, 'unavailable'), raw)
end

---Registers an access policy for an existing door.
---@param id string
---@param callback fun(source:integer, id:string, context:table):boolean
---@return boolean|nil registered
function Kora.bridge.registerDoorPolicy(id, callback)
    assertString(id, 'id')
    assert(type(callback) == 'function', 'callback must be a function.')
    return call('doorlock', 'registerDoorPolicy', table.pack(false), id, callback)
end

---Grants a vehicle key to a player.
---@param src integer
---@param plate string
---@param allowWhenDisabled? boolean
---@return boolean granted
function Kora.bridge.giveKeys(src, plate, allowWhenDisabled)
    assert(type(src) == 'number' and src % 1 == 0, 'src must be an integer.')
    assertString(plate, 'plate')
    assert(allowWhenDisabled == nil or type(allowWhenDisabled) == 'boolean',
        'allowWhenDisabled must be a boolean or nil.')
    return call('vehiclekeys', 'giveKeys', table.pack(false), src, plate, allowWhenDisabled)
end

---Removes a vehicle key from a player.
---@param src integer
---@param plate string
---@return boolean removed
function Kora.bridge.removeKeys(src, plate)
    assert(type(src) == 'number' and src % 1 == 0, 'src must be an integer.')
    assertString(plate, 'plate')
    return call('vehiclekeys', 'removeKeys', table.pack(false), src, plate)
end

---Checks whether a player has access to a vehicle.
---@param src integer
---@param plate string
---@return boolean hasKeys
function Kora.bridge.hasKeys(src, plate)
    assert(type(src) == 'number' and src % 1 == 0, 'src must be an integer.')
    assertString(plate, 'plate')
    return call('vehiclekeys', 'hasKeys', table.pack(false), src, plate)
end

---Opens an admin clothing session for a player.
---@param targetSrc integer
---@param service 'clothing'|'barber'|'tattoo'|'creation'
---@return boolean opened
---@return string|nil error
function Kora.bridge.openAdminSession(targetSrc, service)
    assert(type(targetSrc) == 'number' and targetSrc % 1 == 0, 'targetSrc must be an integer.')
    assertString(service, 'service')
    return call('clothing', 'openAdminSession', table.pack(false, 'unavailable'), targetSrc, service)
end