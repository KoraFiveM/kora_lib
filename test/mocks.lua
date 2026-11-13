---Minimal stand-ins for the FiveM/CFX globals kora_lib's modules call directly
---(RegisterNetEvent, TriggerServerEvent, CreateThread, promise, ...), so module
---files can be `dofile`'d and smoke-tested under plain Lua. Native functions
---specific to a single module (e.g. CreatePed, glm.vec3) are mocked in that
---module's own smoke test instead of here.
local M = {}

M.SOURCE = 1

---Scans a recorded event list (triggeredServerEvents/triggeredClientEvents)
---backwards for the most recent entry with `name` -- the lookup several smoke
---tests need after driving a request through the mock network.
---@param entries table[]
---@param name string
---@return table | nil entry
function M.lastEntry(entries, name)
    for i = #entries, 1, -1 do
        if entries[i].name == name then return entries[i] end
    end
    return nil
end

---Installs the mocked globals into _G. Returns handles into the mock network
---state so tests can inspect what was sent/registered or fire an event directly.
function M.install()
    local mockClock = 0
    local FRAME_MS = 16

    local netHandlers = {}
    local eventHandlers = {}
    local eventHandlerIds = {}
    local nextEventHandlerId = 0
    local triggeredServerEvents = {}
    local triggeredClientEvents = {}
    local threads = {}
    local commands = {}

    _G.source = nil

    function _G.RegisterNetEvent(name, cb)
        netHandlers[name] = netHandlers[name] or {}
        table.insert(netHandlers[name], cb)
    end

    function _G.AddEventHandler(name, cb)
        eventHandlers[name] = eventHandlers[name] or {}
        table.insert(eventHandlers[name], cb)
        nextEventHandlerId = nextEventHandlerId + 1
        eventHandlerIds[nextEventHandlerId] = { name = name, callback = cb }
        return nextEventHandlerId
    end

    function _G.RemoveEventHandler(id)
        local handler = eventHandlerIds[id]
        if not handler then return end
        eventHandlerIds[id] = nil
        local handlers = eventHandlers[handler.name]
        for index = 1, #handlers do
            if handlers[index] == handler.callback then
                table.remove(handlers, index)
                return
            end
        end
    end

    function _G.RegisterCommand(name, cb, restricted)
        commands[name] = cb
    end

    function _G.RegisterKeyMapping(_, _, _, _) end

    local executedCommands = {}
    function _G.ExecuteCommand(command)
        table.insert(executedCommands, command)
        local args = {}
        for word in tostring(command):gmatch("%S+") do args[#args + 1] = word end
        local handler = commands[args[1]]
        if handler then handler(_G.source or 0, { table.unpack(args, 2) }, command) end
    end

    function _G.TriggerEvent(name, ...)
        for _, fn in ipairs(eventHandlers[name] or {}) do fn(...) end
        for _, fn in ipairs(netHandlers[name] or {}) do fn(...) end
    end

    function _G.TriggerServerEvent(name, ...)
        table.insert(triggeredServerEvents, { name = name, ... })

        local previousSource = _G.source
        _G.source = M.SOURCE

        for _, fn in ipairs(netHandlers[name] or {}) do fn(...) end

        _G.source = previousSource
    end

    function _G.TriggerLatentServerEvent(name, _, ...)
        _G.TriggerServerEvent(name, ...)
    end

    function _G.TriggerClientEvent(name, target, ...)
        table.insert(triggeredClientEvents, { name = name, target = target, ... })

        for _, fn in ipairs(netHandlers[name] or {}) do fn(...) end
    end

    function _G.CreateThread(fn)
        local co = coroutine.create(fn)
        table.insert(threads, co)

        local ok, err = coroutine.resume(co)
        if not ok then
            error(("CreateThread body errored: %s"):format(tostring(err)), 0)
        end
    end

    function _G.Wait(ms)
        mockClock = mockClock + math.max(ms or 0, FRAME_MS)
        if coroutine.isyieldable() then
            coroutine.yield()
        end
    end

    function _G.GetGameTimer()
        return mockClock
    end

    function _G.SetTimeout(_, _) end

    function _G.GetInvokingResource()
        return nil
    end

    function _G.GetCurrentResourceName()
        return "kora_lib_test"
    end

    function _G.GetConvar(_, default) return default end
    function _G.IsDuplicityVersion() return false end
    _G.json = { encode = function() return '{}' end }

    function _G.GetConvarInt(_, default)
        return default
    end

    function _G.joaat(str)
        local hash = 0
        for i = 1, #str do
            hash = (hash * 31 + str:byte(i)) % 4294967296
        end
        return hash
    end

    local promiseMt = {}
    promiseMt.__index = promiseMt

    function promiseMt:resolve(value)
        if self.state ~= "pending" then return end
        self.state = "resolved"
        self.value = value
        for _, cb in ipairs(self.onResolved) do cb(value) end
    end

    function promiseMt:reject(err)
        if self.state ~= "pending" then return end
        self.state = "rejected"
        self.value = err
        for _, cb in ipairs(self.onRejected) do cb(err) end
    end

    function promiseMt:next(onResolved, onRejected)
        if self.state == "resolved" then
            if onResolved then onResolved(self.value) end
        elseif self.state == "rejected" then
            if onRejected then onRejected(self.value) end
        else
            if onResolved then table.insert(self.onResolved, onResolved) end
            if onRejected then table.insert(self.onRejected, onRejected) end
        end

        return self
    end

    function promiseMt:catch(fn)
        return self:next(nil, fn)
    end

    _G.promise = {
        new = function()
            return setmetatable({ state = "pending", onResolved = {}, onRejected = {} }, promiseMt)
        end,
    }

    for _, name in ipairs({ 'IsPedFalling', 'IsPedJumping', 'IsPedRagdoll', 'IsEntityInAir', 'IsPedInParachuteFreeFall' }) do
        _G[name] = _G[name] or function() return false end
    end

    _G.Citizen = {
        Await = function(p)
            if p.state == "resolved" then return p.value end
            if p.state == "rejected" then error(p.value, 0) end
            error("mock Citizen.Await: promise never settled synchronously", 0)
        end,
        -- Runs the function now, up to its first yield, like the real scheduler.
        CreateThreadNow = function(fn)
            local co = coroutine.create(fn)
            local ok, err = coroutine.resume(co)
            if not ok then error(err, 0) end
        end,
    }

    return {
        netHandlers = netHandlers,
        eventHandlers = eventHandlers,
        triggeredServerEvents = triggeredServerEvents,
        triggeredClientEvents = triggeredClientEvents,
        commands = commands,
        executedCommands = executedCommands,
        fire = function(name, ...)
            _G.TriggerEvent(name, ...)
        end,
        step = function()
            for _, co in ipairs(threads) do
                if coroutine.status(co) == "suspended" then
                    local ok, err = coroutine.resume(co)
                    if not ok then
                        error(("stepped thread errored: %s"):format(tostring(err)), 0)
                    end
                end
            end
        end,
    }
end

return M
