local bindings = {}
local nativeRegistrations = {}
local commandBindings = {}
local ownership

local commandEvents = {
    add = 'kora_lib:commands:keybind:add',
    remove = 'kora_lib:commands:keybind:remove',
    sync = 'kora_lib:commands:keybind:sync',
    execute = 'kora_lib:commands:keybind:execute',
}

local isCallable = Kora.compat.isCallable

local function assertOptions(options)
    assert(type(options) == 'table', 'Kora.keybind.add requires an options table.')
    assert(type(options.name) == 'string' and options.name:match('^[%w_:%.%-]+$'),
        'Keybind name must be a non-empty command name without whitespace.')
    assert(type(options.description) == 'string' and options.description ~= '',
        'Keybind description must be a non-empty string.')
    assert(options.defaultKey == nil or type(options.defaultKey) == 'string',
        'Keybind defaultKey must be a string.')
    assert(options.defaultMapper == nil or (type(options.defaultMapper) == 'string' and options.defaultMapper ~= ''),
        'Keybind defaultMapper must be a non-empty string.')
    assert(options.secondaryKey == nil or type(options.secondaryKey) == 'string',
        'Keybind secondaryKey must be a string.')
    assert(options.secondaryMapper == nil or (type(options.secondaryMapper) == 'string' and options.secondaryMapper ~= ''),
        'Keybind secondaryMapper must be a non-empty string.')
    assert(options.disabled == nil or type(options.disabled) == 'boolean',
        'Keybind disabled must be a boolean.')
    assert(options.onPressed == nil or isCallable(options.onPressed), 'Keybind onPressed must be callable.')
    assert(options.onReleased == nil or isCallable(options.onReleased), 'Keybind onReleased must be callable.')
    assert(options.onPressed ~= nil or options.onReleased ~= nil,
        'Keybind requires onPressed, onReleased, or both.')
end

local function safeCall(definition, phase)
    local handler = phase == 'pressed' and definition.onPressed or definition.onReleased
    if not handler then return end

    local ok, err = pcall(handler, definition.handle)
    if not ok then
        Kora.logging.error('lib.client.diagnostic', ("^3[kora_lib:keybind]^7 '%s' %s callback errored: %s")
            :format(definition.name, phase, tostring(err)))
    end
end

local function removeDefinition(name, expected)
    local definition = bindings[name]
    if not definition or (expected and definition ~= expected) then return false end

    definition.pressed = false
    bindings[name] = nil
    ownership.untrack(name)
    return true
end

ownership = Kora.resources.registry(function(name)
    local definition = bindings[name]
    if definition then
        definition.pressed = false
        bindings[name] = nil
    end
end)

local function createHandle(definition)
    local handle = {
        name = definition.name,
        description = definition.description,
        defaultKey = definition.defaultKey,
        defaultMapper = definition.defaultMapper,
        secondaryKey = definition.secondaryKey,
        secondaryMapper = definition.secondaryMapper,
        resource = definition.resource,
    }

    handle.disable = function(toggle)
        assert(type(toggle) == 'boolean', 'Keybind disabled state must be a boolean.')
        if bindings[definition.name] ~= definition then return false end
        definition.disabled = toggle
        if toggle then definition.pressed = false end
        return true
    end

    handle.isDisabled = function()
        return bindings[definition.name] == definition and definition.disabled or false
    end

    handle.isPressed = function()
        return bindings[definition.name] == definition and definition.pressed or false
    end

    handle.getCurrentBinding = function()
        if bindings[definition.name] ~= definition then return nil end
        local ok, value = pcall(GetControlInstructionalButton, 0, definition.hash, true)
        if not ok or type(value) ~= 'string' or value == '' then return nil end
        return (value:gsub('^[bt]_', '', 1))
    end

    handle.remove = function()
        return removeDefinition(definition.name, definition)
    end

    definition.handle = handle
    return handle
end

local function ensureNativeRegistration(definition)
    local registration = nativeRegistrations[definition.name]
    if not registration then
        registration = { secondary = false }
        nativeRegistrations[definition.name] = registration

        RegisterCommand('+' .. definition.name, function()
            local current = bindings[definition.name]
            if not current or current.disabled or current.pressed then return end
            if type(IsPauseMenuActive) == 'function' and IsPauseMenuActive() then return end
            current.pressed = true
            safeCall(current, 'pressed')
        end, false)

        RegisterCommand('-' .. definition.name, function()
            local current = bindings[definition.name]
            if not current then return end
            local wasPressed = current.pressed
            current.pressed = false
            if current.disabled or not wasPressed then return end
            safeCall(current, 'released')
        end, false)

        RegisterKeyMapping('+' .. definition.name, definition.description,
            definition.defaultMapper, definition.defaultKey)
    end

    if definition.secondaryKey ~= nil and not registration.secondary then
        registration.secondary = true
        RegisterKeyMapping('~!+' .. definition.name, definition.description,
            definition.secondaryMapper, definition.secondaryKey)
    end
end

local function add(options, resourceOverride)
    assertOptions(options)

    local name = options.name
    local owner = resourceOverride or GetInvokingResource() or GetCurrentResourceName()
    local previousOwner = ownership.owner(name)
    if previousOwner and previousOwner ~= owner then
        Kora.logging.warn('lib.client.diagnostic', ("^3[kora_lib:keybind]^7 '%s' was registered by '%s' and is being overwritten by '%s'.")
            :format(name, previousOwner, owner))
    end

    local definition = {
        name = name,
        description = options.description,
        defaultKey = options.defaultKey or '',
        defaultMapper = options.defaultMapper or 'keyboard',
        secondaryKey = options.secondaryKey,
        secondaryMapper = options.secondaryMapper or options.defaultMapper or 'keyboard',
        disabled = options.disabled == true,
        pressed = false,
        onPressed = options.onPressed,
        onReleased = options.onReleased,
        resource = owner,
        hash = joaat('+' .. name) | 0x80000000,
    }

    bindings[name] = definition
    ownership.track(owner, name)
    local handle = createHandle(definition)
    ensureNativeRegistration(definition)
    return handle
end

---Registers a rebindable press/release action.
---@param options KoraKeybindOptions
---@return KoraKeybindHandle handle
function Kora.keybind.add(options)
    return add(options)
end

---@param name string
---@return boolean removed
function Kora.keybind.remove(name)
    assert(type(name) == 'string' and name ~= '', 'Keybind name must be a non-empty string.')
    if ownership.owner(name) ~= (GetInvokingResource() or GetCurrentResourceName()) then return false end
    return removeDefinition(name)
end

---@return table[] bindings Shallow public metadata sorted by name.
function Kora.keybind.list()
    local result = {}
    for name, definition in pairs(bindings) do
        result[#result + 1] = {
            name = name,
            description = definition.description,
            defaultKey = definition.defaultKey,
            defaultMapper = definition.defaultMapper,
            secondaryKey = definition.secondaryKey,
            secondaryMapper = definition.secondaryMapper,
            disabled = definition.disabled,
            pressed = definition.pressed,
            resource = definition.resource,
        }
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

local function addCommandBinding(name, options)
    if type(name) ~= 'string' or type(options) ~= 'table' then return end
    local existing = commandBindings[name]
    if existing then existing.remove() end

    local ok, handle = pcall(add, {
        name = 'kora_lib_command:' .. name,
        description = options.description,
        defaultKey = options.defaultKey,
        defaultMapper = options.defaultMapper,
        secondaryKey = options.secondaryKey,
        secondaryMapper = options.secondaryMapper,
        onPressed = function()
            TriggerServerEvent(commandEvents.execute, name)
        end,
    }, options.resource or GetCurrentResourceName())

    if not ok then
        Kora.logging.warn('lib.client.could_not_register_key_mapping_for', ("^3[kora_lib:commands]^7 could not register key mapping for /%s: %s"):format(name, tostring(handle)))
        return
    end
    commandBindings[name] = handle
end

RegisterNetEvent(commandEvents.add, addCommandBinding)
RegisterNetEvent(commandEvents.remove, function(name)
    local handle = commandBindings[name]
    if not handle then return end
    commandBindings[name] = nil
    handle.remove()
end)

CreateThread(function()
    TriggerServerEvent(commandEvents.sync)
end)
