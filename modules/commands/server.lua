-- QB.commands (server realm) -- a registration wrapper over RegisterCommand
-- with pluggable permission gating and chat-suggestion support.
-- OWNER-TRACKED via QB.resources.serverRegistry, keyed by command name, so a
-- resource that restarts doesn't leave dead command handlers behind.

-- name -> { help, args, argsRequired, handler, permission, resource, checkPermission, notify }
local commands = {}

local MAX_SUGGESTIONS = 20
local keybindEvents = {
    add = 'qblib:commands:keybind:add',
    remove = 'qblib:commands:keybind:remove',
    sync = 'qblib:commands:keybind:sync',
    execute = 'qblib:commands:keybind:execute',
}

local function isCallable(value)
    if type(value) == 'function' then return true end
    local mt = type(value) == 'table' and getmetatable(value) or nil
    return mt ~= nil and mt.__call ~= nil
end

local function isAllowed(source, definition)
    if source == 0 or definition.permission == 'user' then return true end
    if not isCallable(definition.checkPermission) then
        return false, ('permission %q has no callable checkPermission (got %s)')
            :format(definition.permission, type(definition.checkPermission))
    end
    local ok, allowed = pcall(definition.checkPermission, source, definition.permission)
    if not ok then
        return false, ('checkPermission errored: %s'):format(tostring(allowed))
    end
    return allowed == true
end

-- Functions cannot be serialized into chat:addSuggestion. Publish only the
-- descriptive shape and a marker telling richer chat UIs that values exist.
local function publicArgs(args)
    if type(args) ~= 'table' then return args end

    local result = {}
    for index, arg in ipairs(args) do
        result[index] = {
            name = arg.name,
            help = arg.help,
            hasSuggestions = type(arg.values) == 'table' or isCallable(arg.provider),
        }
    end
    return result
end

local function normalizeKeybind(keybind, description, owner)
    if keybind == nil then return nil end
    assert(type(keybind) == 'table', 'Command keybind must be a table.')
    assert(keybind.description == nil or (type(keybind.description) == 'string' and keybind.description ~= ''),
        'Command keybind description must be a non-empty string.')
    assert(keybind.defaultKey == nil or type(keybind.defaultKey) == 'string',
        'Command keybind defaultKey must be a string.')
    assert(keybind.defaultMapper == nil or (type(keybind.defaultMapper) == 'string' and keybind.defaultMapper ~= ''),
        'Command keybind defaultMapper must be a non-empty string.')
    assert(keybind.secondaryKey == nil or type(keybind.secondaryKey) == 'string',
        'Command keybind secondaryKey must be a string.')
    assert(keybind.secondaryMapper == nil or (type(keybind.secondaryMapper) == 'string' and keybind.secondaryMapper ~= ''),
        'Command keybind secondaryMapper must be a non-empty string.')

    return {
        description = keybind.description or description,
        defaultKey = keybind.defaultKey or '',
        defaultMapper = keybind.defaultMapper or 'keyboard',
        secondaryKey = keybind.secondaryKey,
        secondaryMapper = keybind.secondaryMapper or keybind.defaultMapper or 'keyboard',
        resource = owner,
    }
end

local function dispatch(name, definition, source, rawArgs, raw)
    -- No checkPermission with a non-'user' permission fails closed: a caller
    -- that declares a gated command without wiring a check must not get it for
    -- free. Key mappings use this exact same dispatcher. A denial caused by a
    -- broken check (missing/erroring checkPermission) is logged here -- only
    -- on dispatch, not per-keystroke suggestion filtering -- because it is
    -- otherwise indistinguishable from the player genuinely lacking the
    -- permission.
    local allowed, denyReason = isAllowed(source, definition)
    if not allowed then
        if denyReason then
            print(("^3[qblib:commands]^7 /%s denied for %s: %s"):format(name, tostring(source), denyReason))
        end
        definition.notify(source, 'You do not have permission for this command.', 'error')
        return
    end
    if definition.argsRequired and definition.args and #rawArgs < #definition.args then
        definition.notify(source, ('Missing arguments for /%s'):format(name), 'error')
        return
    end
    local ok, err = pcall(definition.handler, source, rawArgs, raw)
    if not ok then print(("^3[qblib:commands]^7 /%s errored: %s"):format(name, tostring(err))) end
end

local function removeCommand(name)
    local definition = commands[name]
    if not definition then return end
    commands[name] = nil
    TriggerClientEvent('chat:removeSuggestion', -1, '/' .. name)
    if definition.keybind then TriggerClientEvent(keybindEvents.remove, -1, name) end
end

-- Registry id == command name (a name-keyed registry, per QB.resources'
-- own documented use case): re-registering an existing name just transfers
-- ownership, and a resource stop disposes exactly the names it still owns.
local cmdRegistry = QB.resources.serverRegistry(removeCommand)

local function defaultNotify(src, message, type_)
    QB.notify.send(src, { message = message, type = type_ })
end

---Register a command. handler(source, args, rawCommand).
---@param name string
---@param help string
---@param args table|nil    -- { {name=, help=}, ... } for chat suggestions
---@param argsRequired boolean|nil
---@param handler fun(source:integer, args:string[], raw:string)
---@param opts table|nil
---  - permission: string|nil -- default 'user'; anything else requires checkPermission to pass
---  - checkPermission: fun(source:integer, permission:string):boolean|nil
---  - notify: fun(source:integer, message:string, type:string)|nil -- defaults to QB.notify.send
---  - resource: string|nil -- owning resource; defaults to the invoking resource
function QB.commands.add(name, help, args, argsRequired, handler, opts)
    opts = opts or {}
    local permission = opts.permission or 'user'
    local owner = opts.resource or GetInvokingResource() or GetCurrentResourceName()
    local notify = opts.notify or defaultNotify
    local keybindDescription = type(help) == 'string' and help ~= '' and help or name
    local keybind = normalizeKeybind(opts.keybind, keybindDescription, owner)
    local previous = commands[name]

    commands[name] = {
        help = help, args = args, argsRequired = argsRequired,
        handler = handler, permission = permission, resource = owner,
        checkPermission = opts.checkPermission, notify = notify, keybind = keybind,
    }
    if owner then cmdRegistry.track(owner, name) end

    RegisterCommand(name, function(source, rawArgs, raw)
        local def = commands[name]
        if not def then return end
        dispatch(name, def, source, rawArgs, raw)
    end, false)

    -- Chat suggestion.
    TriggerClientEvent('chat:addSuggestion', -1, '/' .. name, help or '', publicArgs(args) or {})
    if previous and previous.keybind and not keybind then TriggerClientEvent(keybindEvents.remove, -1, name) end
    if keybind then TriggerClientEvent(keybindEvents.add, -1, name, keybind) end
end

---@param name string
function QB.commands.remove(name)
    cmdRegistry.untrack(name)
    removeCommand(name)
end

---Re-send all chat suggestions to one source (on (re)connect).
---@param src integer
function QB.commands.refresh(src)
    for name, def in pairs(commands) do
        TriggerClientEvent('chat:addSuggestion', src, '/' .. name, def.help or '', publicArgs(def.args) or {})
    end
end

---@return table[]  -- {name, help, permission, keybind?} for each command
function QB.commands.list()
    local out = {}
    for name, def in pairs(commands) do
        local keybind
        if def.keybind then
            keybind = {
                description = def.keybind.description,
                defaultKey = def.keybind.defaultKey,
                defaultMapper = def.keybind.defaultMapper,
                secondaryKey = def.keybind.secondaryKey,
                secondaryMapper = def.keybind.secondaryMapper,
            }
        end
        out[#out + 1] = { name = name, help = def.help, permission = def.permission, keybind = keybind }
    end
    return out
end

RegisterNetEvent(keybindEvents.sync, function()
    local src = source
    if type(src) ~= 'number' or src <= 0 then return end
    for name, definition in pairs(commands) do
        if definition.keybind then TriggerClientEvent(keybindEvents.add, src, name, definition.keybind) end
    end
end)

RegisterNetEvent(keybindEvents.execute, function(name)
    local src = source
    if type(src) ~= 'number' or src <= 0 or type(name) ~= 'string' then return end
    local definition = commands[name]
    if not definition or not definition.keybind then return end
    dispatch(name, definition, src, {}, name)
end)

---Resolve static or provider-backed values for one command argument.
---@param src integer
---@param name string Command name without a leading slash.
---@param argumentIndex integer One-based argument index.
---@param query string|nil Current value prefix.
---@param parsedArgs string[]|nil Current parsed argument values.
---@return table[] suggestions Normalized {value,label?,help?} entries.
function QB.commands.suggest(src, name, argumentIndex, query, parsedArgs)
    if type(src) ~= 'number' or type(name) ~= 'string' or type(argumentIndex) ~= 'number' then return {} end
    local definition = commands[name:gsub('^/', '')]
    if not definition or not isAllowed(src, definition) then return {} end

    argumentIndex = math.floor(argumentIndex)
    local argument = type(definition.args) == 'table' and definition.args[argumentIndex] or nil
    if type(argument) ~= 'table' then return {} end

    query = type(query) == 'string' and query:sub(1, 128) or ''
    parsedArgs = type(parsedArgs) == 'table' and parsedArgs or {}

    local candidates = {}
    if type(argument.values) == 'table' then
        for _, value in ipairs(argument.values) do candidates[#candidates + 1] = value end
    end

    if isCallable(argument.provider) then
        local ok, provided = pcall(argument.provider, src, {
            command = name:gsub('^/', ''),
            argumentIndex = argumentIndex,
            query = query,
            args = parsedArgs,
        })
        if not ok then
            print(("^3[qblib:commands]^7 suggestion provider for /%s argument %d errored: %s")
                :format(name, argumentIndex, tostring(provided)))
        elseif type(provided) == 'table' then
            for _, value in ipairs(provided) do candidates[#candidates + 1] = value end
        end
    end

    local loweredQuery = query:lower()
    local seen, result = {}, {}
    for _, candidate in ipairs(candidates) do
        local value, label, help
        if type(candidate) == 'table' then
            value, label, help = candidate.value, candidate.label, candidate.help
        elseif type(candidate) == 'string' or type(candidate) == 'number' then
            value = tostring(candidate)
        end

        if type(value) == 'string' and value ~= '' and #value <= 128 then
            label = type(label) == 'string' and label:sub(1, 128) or nil
            help = type(help) == 'string' and help:sub(1, 256) or nil
            local matches = loweredQuery == ''
                or value:lower():find(loweredQuery, 1, true) ~= nil
                or (label and label:lower():find(loweredQuery, 1, true) ~= nil)

            if matches and not seen[value] then
                seen[value] = true
                result[#result + 1] = { value = value, label = label, help = help }
                if #result >= MAX_SUGGESTIONS then break end
            end
        end
    end

    return result
end
