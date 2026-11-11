-- Server half of Kora.qa. kora_qa marks players active while they run a test
-- scenario; marks, callbacks and commands used by those players are handed to
-- kora_qa's Kora.qa.onEvent handler. Client events are accepted only from
-- active players and are rate limited and sanitised here.

local internal = Kora.compat.qa
local FORWARD_EVENT = 'kora_lib:qa:client'
local MAX_CLIENT_PER_SECOND = 25

local activePlayers = {}
local activeCount = 0
local activeOwner = nil
local buckets = {}

local function isPlayer(src)
    return type(src) == 'number' and src >= 1 and src % 1 == 0 and src < math.huge
end

local function emit(src, eventType, name, data, side)
    if internal.handlerCount == 0 then return end
    internal.dispatch(src, {
        type = eventType,
        name = type(name) == 'string' and name:sub(1, 128) or nil,
        data = internal.sanitize(data),
        side = side or 'server',
    })
end
internal.emit = emit

---Records a named point. With `target` (a player id) it goes to that player's
---active run; without it, to every active run. No-op when nobody is testing.
---@param name string
---@param data? table
---@param target? integer
function Kora.qa.mark(name, data, target)
    if activeCount == 0 or internal.handlerCount == 0 then return end
    assert(internal.validName(name), 'Kora.qa.mark name must be 1-64 characters of [A-Za-z0-9_:.-/ ].')
    if target ~= nil then
        if not activePlayers[target] then return end
        emit(target, 'mark', name, data)
        return
    end
    emit(nil, 'mark', name, data)
end

---Whether `src` (or, without an argument, anyone) has an active kora_qa run.
---@param src? integer
---@return boolean
function Kora.qa.active(src)
    if src == nil then return activeCount > 0 end
    return activePlayers[src] == true
end

---Marks a player's run active/inactive. Only kora_qa (or kora_lib) may call it.
---@param src integer
---@param state boolean
---@return boolean active
function Kora.qa.setActive(src, state)
    local invoker = GetInvokingResource()
    assert(internal.isRunner(invoker), 'Only kora_qa may change the QA run state.')
    assert(isPlayer(src), 'Kora.qa.setActive needs a player server id.')
    local was = activePlayers[src] == true
    local now = state == true
    if was ~= now then
        activePlayers[src] = now or nil
        activeCount = activeCount + (now and 1 or -1)
    end
    if now then activeOwner = invoker or GetCurrentResourceName() end
    if not now then buckets[src] = nil end
    return now
end

-- Client-forwarded events (see client.lua). Never trusted beyond "this player
-- said so": kora_qa records them in the timeline and as observer hints.
RegisterNetEvent(FORWARD_EVENT, function(event)
    local src = source
    if not isPlayer(src) or not activePlayers[src] or internal.handlerCount == 0 then return end
    if type(event) ~= 'table' or not internal.EVENT_TYPES[event.type] then return end

    local now = GetGameTimer()
    local bucket = buckets[src]
    if not bucket or now - bucket.start >= 1000 then
        bucket = { start = now, count = 0 }
        buckets[src] = bucket
    end
    if bucket.count >= MAX_CLIENT_PER_SECOND then return end
    bucket.count = bucket.count + 1

    local name = event.name
    if name ~= nil and type(name) ~= 'string' then return end
    if event.type == 'mark' and not internal.validName(name) then return end
    emit(src, event.type, name, event.data, 'client')
end)

-- --- passive observers --------------------------------------------------------

-- Server callbacks: what a tester's client asked for and what came back.
local originalCallbackRegister = Kora.callback.register
if type(originalCallbackRegister) == 'function' then
    Kora.callback.register = function(name, handler, ...)
        if type(name) ~= 'string' or not Kora.compat.isCallable(handler) then
            return originalCallbackRegister(name, handler, ...)
        end
        local wrapped = function(src, ...)
            if activeCount == 0 or not activePlayers[src] then return handler(src, ...) end
            local results = table.pack(pcall(handler, src, ...))
            if not results[1] then
                emit(src, 'callback', name, { ok = false, error = tostring(results[2]) })
                error(results[2], 0)
            end
            local first = results[2]
            local summary = { ok = true, returned = type(first) }
            if type(first) ~= 'table' then summary.value = first end
            if type(first) == 'table' then summary.okField = first.ok; summary.error = first.error or first.reason end
            if results.n > 2 and type(results[3]) ~= 'table' then summary.second = results[3] end
            emit(src, 'callback', name, summary)
            return table.unpack(results, 2, results.n)
        end
        return originalCallbackRegister(name, wrapped, ...)
    end
end

-- Kora.commands: which command a tester ran (handler reached = allowed and dispatched).
local originalCommandsAdd = Kora.commands.add
if type(originalCommandsAdd) == 'function' then
    Kora.commands.add = function(name, help, args, argsRequired, handler, opts)
        if type(name) ~= 'string' or not Kora.compat.isCallable(handler) then
            return originalCommandsAdd(name, help, args, argsRequired, handler, opts)
        end
        local wrapped = function(src, rawArgs, raw)
            if activeCount > 0 and activePlayers[src] then
                emit(src, 'command', name, { raw = type(raw) == 'string' and raw or nil })
            end
            return handler(src, rawArgs, raw)
        end
        return originalCommandsAdd(name, help, args, argsRequired, wrapped, opts)
    end
end

AddEventHandler('playerDropped', function()
    local src = source
    if activePlayers[src] then
        activePlayers[src] = nil
        activeCount = activeCount - 1
    end
    buckets[src] = nil
end)

AddEventHandler('onResourceStop', function(resource)
    internal.dropOwner(resource)
    if activeOwner and resource == activeOwner then
        activePlayers = {}
        activeCount = 0
        activeOwner = nil
        buckets = {}
    end
end)
