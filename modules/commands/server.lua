-- Registration wrapper over RegisterCommand with pluggable permission gating and chat
-- suggestions. Owner-tracked via Kora.resources.serverRegistry (keyed by command name).

-- name -> { help, args, argsRequired, handler, permission, resource, checkPermission, notify }
local commands = {}

local MAX_SUGGESTIONS = 20
local MAX_PARSED_ARGS = 16
local keybindEvents = {
    add = 'kora_lib:commands:keybind:add',
    remove = 'kora_lib:commands:keybind:remove',
    sync = 'kora_lib:commands:keybind:sync',
    execute = 'kora_lib:commands:keybind:execute',
}

local isCallable = Kora.compat.isCallable
local isInteger = Kora.util.isInteger

local function isPlayerSource(src)
    return isInteger(src) and src >= 1
end

local function normalizeParsedArgs(parsedArgs)
    if parsedArgs == nil then return {} end
    if type(parsedArgs) ~= 'table' or #parsedArgs > MAX_PARSED_ARGS then return nil end

    local normalized, count = {}, 0
    for key in pairs(parsedArgs) do
        if not isInteger(key) or key < 1 or key > #parsedArgs then return nil end
        count = count + 1
    end
    if count ~= #parsedArgs then return nil end

    for index = 1, #parsedArgs do
        local value = parsedArgs[index]
        if type(value) ~= 'string' or #value > 128 then return nil end
        normalized[index] = value
    end
    return normalized
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
    for index = 1, #args do
        local arg = args[index]
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
    -- No checkPermission with a non-'user' permission fails closed. A denial from a broken
    -- check is logged here (dispatch only, not suggestion filtering) since it is otherwise
    -- indistinguishable from the player lacking the permission.
    local allowed, denyReason = isAllowed(source, definition)
    if not allowed then
        if denyReason then
            print(("^3[kora_lib:commands]^7 /%s denied for %s: %s"):format(name, tostring(source), denyReason))
        end
        definition.notify(source, 'You do not have permission for this command.', 'error')
        return
    end
    if definition.argsRequired and definition.args and #rawArgs < #definition.args then
        definition.notify(source, ('Missing arguments for /%s'):format(name), 'error')
        return
    end
    local ok, err = pcall(definition.handler, source, rawArgs, raw)
    if not ok then print(("^3[kora_lib:commands]^7 /%s errored: %s"):format(name, tostring(err))) end
end

local function sendKeybind(src, name, definition)
    if definition.keybind and isAllowed(src, definition) then
        TriggerClientEvent(keybindEvents.add, src, name, definition.keybind)
    end
end

local function publishKeybind(name, definition)
    if not definition.keybind then return end
    if definition.permission == 'user' then
        TriggerClientEvent(keybindEvents.add, -1, name, definition.keybind)
        return
    end

    for _, playerId in ipairs(GetPlayers()) do
        sendKeybind(tonumber(playerId), name, definition)
    end
end

local function removeCommand(name)
    local definition = commands[name]
    if not definition then return end
    commands[name] = nil
    TriggerClientEvent('chat:removeSuggestion', -1, '/' .. name)
    if definition.keybind then TriggerClientEvent(keybindEvents.remove, -1, name) end
end

-- Registry id == command name: re-registering transfers ownership; a resource stop
-- disposes exactly the names it still owns.
local cmdRegistry = Kora.resources.serverRegistry(removeCommand)

local function defaultNotify(src, message, type_)
    Kora.notify.send(src, { message = message, type = type_ })
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
---  - notify: fun(source:integer, message:string, type:string)|nil -- defaults to Kora.notify.send
---  - resource: string|nil -- owning resource; defaults to the invoking resource
function Kora.commands.add(name, help, args, argsRequired, handler, opts)
    assert(type(name) == 'string' and name:match('^[%w_:%.%-]+$'),
        'Command name must be a non-empty command name without whitespace.')
    assert(help == nil or type(help) == 'string', 'Command help must be a string or nil.')
    assert(args == nil or type(args) == 'table', 'Command args must be a table or nil.')
    if args then
        local argumentCount = 0
        for index, argument in pairs(args) do
            assert(isInteger(index) and index >= 1 and type(argument) == 'table',
                'Command args must be a dense array of tables.')
            assert(type(argument.name) == 'string' and argument.name ~= '',
                'Command argument names must be non-empty strings.')
            assert(argument.help == nil or type(argument.help) == 'string',
                'Command argument help must be a string or nil.')
            argumentCount = argumentCount + 1
        end
        assert(argumentCount == #args, 'Command args must be a dense array of tables.')
    end
    assert(argsRequired == nil or type(argsRequired) == 'boolean', 'Command argsRequired must be a boolean or nil.')
    assert(isCallable(handler), 'Command handler must be callable.')
    if opts == nil then opts = {} end
    assert(type(opts) == 'table', 'Command options must be a table.')

    local permission = opts.permission
    if permission == nil then permission = 'user' end
    local owner = opts.resource
    if owner == nil then owner = GetInvokingResource() or GetCurrentResourceName() end
    local notify = opts.notify
    if notify == nil then notify = defaultNotify end
    assert(type(permission) == 'string' and permission ~= '', 'Command permission must be a non-empty string.')
    assert(owner == nil or (type(owner) == 'string' and owner ~= ''), 'Command resource must be a non-empty string.')
    assert(opts.checkPermission == nil or isCallable(opts.checkPermission), 'Command checkPermission must be callable.')
    assert(isCallable(notify), 'Command notify must be callable.')
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

    TriggerClientEvent('chat:addSuggestion', -1, '/' .. name, help or '', publicArgs(args) or {})
    if previous and previous.keybind and not keybind then TriggerClientEvent(keybindEvents.remove, -1, name) end
    publishKeybind(name, commands[name])
end

---@param name string
---@return boolean removed
function Kora.commands.remove(name)
    if cmdRegistry.owner(name) ~= (GetInvokingResource() or GetCurrentResourceName()) then return false end
    cmdRegistry.untrack(name)
    removeCommand(name)
    return true
end

local function sortedCommandNames()
    local names = {}
    for name in pairs(commands) do names[#names + 1] = name end
    table.sort(names)
    return names
end

---Re-send all chat suggestions to one source (on (re)connect).
---@param src integer
function Kora.commands.refresh(src)
    assert(isPlayerSource(src), 'Command refresh source must be a positive integer player ID.')
    for _, name in ipairs(sortedCommandNames()) do
        local def = commands[name]
        TriggerClientEvent('chat:addSuggestion', src, '/' .. name, def.help or '', publicArgs(def.args) or {})
    end
end

---@return table[]  -- {name, help, permission, keybind?} for each command
function Kora.commands.list()
    local out = {}
    for _, name in ipairs(sortedCommandNames()) do
        local def = commands[name]
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

-- Per-source sliding-window limits for the keybind net events (F#188). Created on first use so the
-- timers module is loaded; clearOnDrop forgets a player's bucket when they disconnect.
local keybindLimits = { sync = { 3, 10000 }, execute = { 20, 1000 } }
local function keybindAllowed(kind, src)
    local limit = keybindLimits[kind]
    if not limit.handle then
        limit.handle = Kora.timers.limiter(limit[1], limit[2], { clearOnDrop = true })
    end
    return (limit.handle.hit(src))
end

RegisterNetEvent(keybindEvents.sync, function()
    local src = source
    if not isPlayerSource(src) then return end
    if not keybindAllowed('sync', src) then return end
    for name, definition in pairs(commands) do
        sendKeybind(src, name, definition)
    end
end)

RegisterNetEvent(keybindEvents.execute, function(name)
    local src = source
    if not isPlayerSource(src) or type(name) ~= 'string' then return end
    if not keybindAllowed('execute', src) then return end
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
function Kora.commands.suggest(src, name, argumentIndex, query, parsedArgs)
    if not isPlayerSource(src) or type(name) ~= 'string'
        or not isInteger(argumentIndex) or argumentIndex < 1 then
        return {}
    end
    local definition = commands[name:gsub('^/', '')]
    if not definition or not isAllowed(src, definition) then return {} end

    argumentIndex = math.floor(argumentIndex)
    local argument = type(definition.args) == 'table' and definition.args[argumentIndex] or nil
    if type(argument) ~= 'table' then return {} end

    query = type(query) == 'string' and query:sub(1, 128) or ''
    parsedArgs = normalizeParsedArgs(parsedArgs)
    if parsedArgs == nil then return {} end

    local candidates = {}
    if type(argument.values) == 'table' then
        for i = 1, #argument.values do candidates[#candidates + 1] = argument.values[i] end
    end

    if isCallable(argument.provider) then
        local ok, provided = pcall(argument.provider, src, {
            command = name:gsub('^/', ''),
            argumentIndex = argumentIndex,
            query = query,
            args = parsedArgs,
        })
        if not ok then
            print(("^3[kora_lib:commands]^7 suggestion provider for /%s argument %d errored: %s")
                :format(name, argumentIndex, tostring(provided)))
        elseif type(provided) == 'table' then
            for i = 1, #provided do candidates[#candidates + 1] = provided[i] end
        end
    end

    local loweredQuery = query:lower()
    local seen, result = {}, {}
    for candidateIndex = 1, #candidates do
        local candidate = candidates[candidateIndex]
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
