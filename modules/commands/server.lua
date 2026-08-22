-- QB.commands (server realm) -- a registration wrapper over RegisterCommand
-- with pluggable permission gating and chat-suggestion support.
-- OWNER-TRACKED via QB.resources.serverRegistry, keyed by command name, so a
-- resource that restarts doesn't leave dead command handlers behind.

-- name -> { help, args, argsRequired, handler, permission, resource, checkPermission, notify }
local commands = {}

local function removeCommand(name)
    if not commands[name] then return end
    commands[name] = nil
    TriggerClientEvent('chat:removeSuggestion', -1, '/' .. name)
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

    commands[name] = {
        help = help, args = args, argsRequired = argsRequired,
        handler = handler, permission = permission, resource = owner,
        checkPermission = opts.checkPermission, notify = notify,
    }
    if owner then cmdRegistry.track(owner, name) end

    RegisterCommand(name, function(source, rawArgs, raw)
        local def = commands[name]
        if not def then return end

        -- No checkPermission with a non-'user' permission fails closed: a
        -- caller that declares a gated command without wiring a way to check
        -- it should not get it for free.
        local allowed = def.permission == 'user' or (def.checkPermission and def.checkPermission(source, def.permission))
        if source ~= 0 and not allowed then
            def.notify(source, 'You do not have permission for this command.', 'error')
            return
        end
        if def.argsRequired and def.args and #rawArgs < #def.args then
            def.notify(source, ('Missing arguments for /%s'):format(name), 'error')
            return
        end
        local ok, err = pcall(def.handler, source, rawArgs, raw)
        if not ok then print(("^3[qblib:commands]^7 /%s errored: %s"):format(name, tostring(err))) end
    end, false)

    -- Chat suggestion.
    TriggerClientEvent('chat:addSuggestion', -1, '/' .. name, help or '', args or {})
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
        TriggerClientEvent('chat:addSuggestion', src, '/' .. name, def.help or '', def.args or {})
    end
end

---@return table[]  -- {name, help, permission} for each command
function QB.commands.list()
    local out = {}
    for name, def in pairs(commands) do
        out[#out + 1] = { name = name, help = def.help, permission = def.permission }
    end
    return out
end
