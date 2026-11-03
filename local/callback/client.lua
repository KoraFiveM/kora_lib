-- Wire-protocol event names. Deliberately mirrored verbatim in
-- local/callback/server.lua (separate Lua chunks can't share a local table) --
-- any change here must be made there too, or the two realms stop talking.
local events = {
    handshake = 'kora_lib:callback:handshake',
    handshakeResponse = 'kora_lib:callback:handshake:response',
    invoke = 'kora_lib:callback:invoke',
    response = 'kora_lib:callback:response',
    clientInvoke = 'kora_lib:callback:clientInvoke',
    clientResponse = 'kora_lib:callback:clientResponse',
}

local token = nil
local TOKEN_POLL_INTERVAL = 50
local registry = {}
local pending = {}
local requestCounter = 0

-- Ownership tracking is delegated to the shared registry (see local/resources/AGENTS.md).
local callbackOwnership = Kora.resources.registry(function(name)
    registry[name] = nil
end)

RegisterNetEvent(events.handshakeResponse, function(newToken)
    if type(newToken) == "string" then token = newToken end
end)

CreateThread(function()
    TriggerServerEvent(events.handshake)
end)

local function awaitToken()
    if token ~= nil then return true end

    -- Explicitly Config.callback.timeout, not Kora.loops.controlled's own 10s
    -- default: the handshake is the FIRST thing a consumer waits on, on the
    -- coldest a client will ever be, so it must get the same budget as the
    -- request it is gating rather than a shorter hidden one.
    -- Polled every 50ms rather than every frame (see local/events/client.lua).
    return Kora.loops.controlled(function()
        return token ~= nil
    end, false, Config.callback.timeout, TOKEN_POLL_INTERVAL) ~= false
end

-- The private bootstrap helper normalizes native functions and every Cfx
-- cross-resource funcref proxy shape consistently across kora_lib modules.
local isCallable = Kora.compat.isCallable

-- A promise doesn't survive an exports() crossing: only method calls reach the real promise, so the caller's
-- Citizen.Await would silently resolve nil. GetInvokingResource() is nil for same-VM calls and the caller's
-- name for cross-resource ones; same-VM callers get the promise, cross-resource callers get the awaited value
-- (or no values at all on rejection/timeout: the reason is printed here, never raised in the caller).
--
-- Callers MUST capture GetInvokingResource() before anything can yield and pass it as `invoker`; it only
-- reflects the cross-resource caller within the synchronous native-call frame.
--
-- Unlike other modules' copies, this one also forwards every extra handler return value (e.g.
-- `return false, "reason"`) via the p.koraLibCallbackResults side channel, since a promise resolves with one
-- value. The promise itself still resolves with only the first return value.
local function settleForExport(p, invoker, name)
    if invoker then
        -- suspends until settled; its own return value is deliberately unused, see above
        local settled, reason = pcall(Citizen.Await, p)
        if not settled then
            print(("[kora_lib:callback] '%s' requested by '%s' failed: %s"):format(name, invoker, tostring(reason)))
            return
        end
        local packed = p.koraLibCallbackResults
        if packed == nil then return p.value end -- not a Kora.callback.trigger promise (or nothing to unpack) -- fall back to the bare resolved value
        return table.unpack(packed, 1, packed.n)
    end
    return p
end

---Registers a handler for a callback invoked from the server via Kora.callback.trigger(target, name, ...).
---Automatically unregistered if the calling resource stops (see onClientResourceStop below) --
---most callers don't need to call Kora.callback.unregister themselves.
---@param name string
---@param handler fun(...: any): any
function Kora.callback.register(name, handler)
    Kora.callback.assertName(name)
    assert(isCallable(handler), "Callback handler must be a function.")

    local owner = GetInvokingResource() or GetCurrentResourceName()

    -- Warn on cross-resource overwrite; see local/events/server.lua register.
    local previousOwner = callbackOwnership.owner(name)
    if previousOwner and previousOwner ~= owner then
        print(("[kora_lib:callback] '%s' was registered by '%s' and is being overwritten by '%s' -- namespace your callback names.")
            :format(name, previousOwner, owner))
    end

    registry[name] = handler
    callbackOwnership.track(owner, name)
end

---Unregisters a callback handler registered with Kora.callback.register.
---@param name string
---@return boolean removed
function Kora.callback.unregister(name)
    Kora.callback.assertName(name)
    local invoker = GetInvokingResource()
    if invoker and callbackOwnership.owner(name) ~= invoker then return false end
    registry[name] = nil
    callbackOwnership.untrack(name)
    return true
end

---Triggers a callback registered on the server via Kora.callback.register(name, handler).
---Waits for the initial handshake token if it hasn't arrived yet.
---@param name string
---@param ... any
---@return promise|any ... A promise for a same-VM caller (unchanged, awaitable as before -- its resolved
---value is the handler's first return value, while additional values remain available to kora_lib's internal
---cross-resource settlement path). For a genuine cross-resource caller, the handler's return values are unpacked --
---e.g. a handler doing `return false, "reason"` comes back as two real return values here, not one (see
---settleForExport above).
function Kora.callback.trigger(name, ...)
    Kora.callback.assertName(name)

    -- Captured first: calling it after awaitToken() yields would lose the cross-resource caller's identity.
    local invoker = GetInvokingResource()

    local p = promise.new()

    if not awaitToken() then
        p:reject("Callback handshake did not complete in time.")
        return settleForExport(p, invoker, name)
    end

    requestCounter = requestCounter + 1
    local requestId = requestCounter

    pending[requestId] = p

    SetTimeout(Config.callback.timeout, function()
        if pending[requestId] == nil then return end

        pending[requestId] = nil
        p:reject("Callback timed out.")
    end)

    TriggerServerEvent(events.invoke, token, requestId, name, ...)

    return settleForExport(p, invoker, name)
end

RegisterNetEvent(events.response, function(requestId, ok, ...)
    if type(requestId) ~= "number" or requestId < 1 or requestId % 1 ~= 0 or requestId ~= requestId
        or requestId == math.huge or requestId == -math.huge then
        return
    end

    local p = pending[requestId]
    if p == nil then return end

    pending[requestId] = nil

    if ok then
        -- Stash the full result on the promise table for settleForExport; the promise still resolves with only the first value.
        local packed = table.pack(...)
        p.koraLibCallbackResults = packed
        p:resolve(packed[1])
    else
        -- Error path carries a single value (the pcall message); nothing to pack.
        p:reject((...))
    end
end)

-- No token check here: the server is always the trusted party for its own
-- TriggerClientEvent calls, same reasoning as Kora.events.push/onPush.
RegisterNetEvent(events.clientInvoke, function(requestId, name, ...)
    if type(requestId) ~= "number" or requestId < 1 or requestId % 1 ~= 0 or requestId ~= requestId
        or requestId == math.huge or requestId == -math.huge or type(name) ~= "string" or #name > 128 then
        return
    end

    local handler = registry[name]
    if handler == nil then
        TriggerServerEvent(events.clientResponse, requestId, false,
            ("Callback '%s' is not registered on the client."):format(tostring(name)))
        return
    end

    -- table.pack: a handler may return multiple values; `local ok, result = pcall(...)` would drop the rest.
    local results = table.pack(pcall(handler, ...))
    local ok = results[1]

    TriggerServerEvent(events.clientResponse, requestId, ok, table.unpack(results, 2, results.n))
end)
