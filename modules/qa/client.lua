-- Client half of Kora.qa. While the local player has an active kora_qa run,
-- marks and passive observations (notifications, AppShell/menu opens) are
-- forwarded to the server, which attaches them to the run. Inactive: every
-- wrapper below costs one boolean test.

local internal = Kora.compat.qa
local FORWARD_EVENT = 'kora_lib:qa:client'
local MAX_PER_SECOND = 20

local active = false
local activeOwner = nil
local windowStart, windowCount = 0, 0

local function emit(eventType, name, data)
    if not active then return end
    local now = GetGameTimer()
    if now - windowStart >= 1000 then
        windowStart, windowCount = now, 0
    end
    if windowCount >= MAX_PER_SECOND then return end
    windowCount = windowCount + 1

    local event = {
        type = eventType,
        name = type(name) == 'string' and name:sub(1, 128) or nil,
        data = internal.sanitize(data),
        side = 'client',
    }
    internal.dispatch(event)
    TriggerServerEvent(FORWARD_EVENT, event)
end
internal.emit = emit

---Records a named point in the local player's active test run (no-op otherwise).
---@param name string e.g. 'fishing:caught'
---@param data? table small, JSON-safe context
function Kora.qa.mark(name, data)
    if not active then return end
    assert(internal.validName(name), 'Kora.qa.mark name must be 1-64 characters of [A-Za-z0-9_:.-/ ].')
    emit('mark', name, data)
end

---Whether the local player currently has an active kora_qa run.
---@return boolean
function Kora.qa.active()
    return active
end

---Turns forwarding on/off for the local player. Only kora_qa (or kora_lib) may call it.
---@param state boolean
---@return boolean active
function Kora.qa.setActive(state)
    local invoker = GetInvokingResource()
    assert(internal.isRunner(invoker), 'Only kora_qa may change the QA run state.')
    active = state == true
    activeOwner = active and (invoker or GetCurrentResourceName()) or nil
    return active
end

-- --- passive observers --------------------------------------------------------
-- These wrap table entries that were defined by modules loaded before this
-- file (fxmanifest globs modules/**/client.lua alphabetically, and build/
-- finalise.lua exports whatever the table holds at the end), so both internal
-- and cross-resource callers go through them.

local function wrap(module, name, before)
    local original = module and module[name]
    if type(original) ~= 'function' then return end
    module[name] = function(...)
        if active then
            local ok, err = pcall(before, ...)
            if not ok then print(('[kora_lib:qa] observer %s failed: %s'):format(name, tostring(err))) end
        end
        return original(...)
    end
end

-- Every kora_lib notification ends in Kora.nui.send('notify', payload)
-- (server pushes included), so one wrapper sees them all.
-- Progress bars (modules/progressbar) and the text UI (modules/textui) also
-- render through Kora.nui.send, so the same wrapper reports them.
wrap(Kora.nui, 'send', function(action, data)
    if action == 'notify' then
        if type(data) ~= 'table' then return end
        emit('notify', nil, { title = data.title, message = data.message, type = data.type })
    elseif action == 'progressStart' then
        emit('progress', 'start', type(data) == 'table' and { label = data.label, duration = data.duration } or nil)
    elseif action == 'progressCancel' then
        emit('progress', 'cancel', nil)
    elseif action == 'textui:set' and type(data) == 'table' then
        emit('textui', nil, { text = data.text, key = data.key })
    end
end)

wrap(Kora.nui, 'openApp', function(id)
    emit('nui', type(id) == 'string' and id or nil, { kind = 'app' })
end)

wrap(Kora.nui, 'openMenu', function(_, title)
    emit('nui', type(title) == 'string' and title or nil, { kind = 'menu' })
end)

wrap(Kora.nui, 'openContextMenu', function()
    emit('nui', nil, { kind = 'context' })
end)

wrap(Kora.nui, 'openRadialMenu', function()
    emit('nui', nil, { kind = 'radial' })
end)

wrap(Kora.nui, 'openInputDialog', function(_, title)
    emit('nui', type(title) == 'string' and title or nil, { kind = 'input' })
end)

-- Config.third_party_notify hands notifications to another resource through
-- this event instead of Kora.nui.send.
AddEventHandler('kora_lib:notify:send', function(payload)
    if not active or type(payload) ~= 'table' then return end
    emit('notify', nil, { title = payload.title, message = payload.message, type = payload.type })
end)

AddEventHandler('onClientResourceStop', function(resource)
    internal.dropOwner(resource)
    if activeOwner and resource == activeOwner then
        active = false
        activeOwner = nil
    end
end)
