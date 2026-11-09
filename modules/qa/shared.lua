-- Kora.qa: hooks for the kora_qa in-game test runner (see docs.md).
--
-- Everything here is a no-op until kora_qa registers a handler with
-- Kora.qa.onEvent (server) or marks the local player active (client). The
-- wrappers installed by client.lua/server.lua check one boolean before doing
-- anything else, so a server without kora_qa pays a single upvalue test per
-- wrapped call.
--
-- Internal state is shared between this file and the realm file through
-- Kora.compat.qa: build/finalise.lua never exports Kora.compat, so these
-- helpers stay private to kora_lib.

local internal = {
    -- The only resource allowed to toggle run state. Handlers may be added by
    -- any resource (tests), but kora_qa is the intended consumer.
    runner = 'kora_qa',
    handlers = {},
    handlerCount = 0,
    nextHandlerId = 0,
}
Kora.compat.qa = internal

local MAX_DEPTH = 4
local MAX_KEYS = 32
local MAX_STRING = 512

internal.EVENT_TYPES = { mark = true, notify = true, nui = true, callback = true, command = true, error = true, progress = true, textui = true }

---Returns a JSON-safe, bounded copy of `value`: no functions/userdata/cycles,
---vectors become {x,y,z[,w]}, strings are cut at 512 bytes, tables keep at most
---32 keys and 4 levels.
---@param value any
---@param depth? integer
---@return any
function internal.sanitize(value, depth)
    depth = depth or 0
    local kind = type(value)
    if kind == 'nil' or kind == 'boolean' then return value end
    if kind == 'number' then
        if value ~= value or value == math.huge or value == -math.huge then return nil end
        return value
    end
    if kind == 'string' then
        if #value > MAX_STRING then return value:sub(1, MAX_STRING) end
        return value
    end
    if kind == 'vector2' or kind == 'vector3' or kind == 'vector4' then
        return { x = value.x, y = value.y, z = value.z, w = kind == 'vector4' and value.w or nil }
    end
    if kind ~= 'table' or depth >= MAX_DEPTH then return nil end
    if rawget(value, '__cfx_functionReference') then return nil end

    local out, count = {}, 0
    for key, item in pairs(value) do
        if count >= MAX_KEYS then break end
        local keyKind = type(key)
        if keyKind == 'string' or keyKind == 'number' then
            local copy = internal.sanitize(item, depth + 1)
            if copy ~= nil then
                out[keyKind == 'string' and key:sub(1, 64) or key] = copy
                count = count + 1
            end
        end
    end
    return out
end

---@param name any
---@return boolean
function internal.validName(name)
    return type(name) == 'string' and #name >= 1 and #name <= 64 and name:match('^[%w_:%.%-/ ]+$') ~= nil
end

---Calls every registered handler; one failing handler never blocks the others.
function internal.dispatch(...)
    if internal.handlerCount == 0 then return end
    for id, handler in pairs(internal.handlers) do
        local ok, err = pcall(handler.fn, ...)
        if not ok then
            print(('[kora_lib:qa] event handler %d (%s) failed: %s'):format(id, handler.owner, tostring(err)))
        end
    end
end

---Registers a function that receives every QA event in this realm.
---Server handlers are called as `fn(src|nil, event)`, client handlers as `fn(event)`.
---`event = { type = 'mark'|'notify'|'nui'|'callback'|'command'|'error'|'progress'|'textui', name?, data?, side }`.
---The handler is removed automatically when its resource stops.
---@param fn function
---@return integer id
function Kora.qa.onEvent(fn)
    assert(Kora.compat.isCallable(fn), 'Kora.qa.onEvent handler must be a function.')
    local owner = GetInvokingResource() or GetCurrentResourceName()
    internal.nextHandlerId = internal.nextHandlerId + 1
    local id = internal.nextHandlerId
    internal.handlers[id] = { fn = fn, owner = owner }
    internal.handlerCount = internal.handlerCount + 1
    return id
end

---Removes a handler registered with Kora.qa.onEvent.
---@param id integer
---@return boolean removed
function Kora.qa.offEvent(id)
    if internal.handlers[id] == nil then return false end
    internal.handlers[id] = nil
    internal.handlerCount = internal.handlerCount - 1
    return true
end

---Drops every handler owned by `resource` (called on resource stop).
function internal.dropOwner(resource)
    for id, handler in pairs(internal.handlers) do
        if handler.owner == resource then Kora.qa.offEvent(id) end
    end
end

---May `invoker` change run state? kora_lib itself (nil invoker) and the runner may.
function internal.isRunner(invoker)
    return invoker == nil or invoker == internal.runner or invoker == GetCurrentResourceName()
end
