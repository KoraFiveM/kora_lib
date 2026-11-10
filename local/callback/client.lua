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

    return Kora.loops.controlled(function()
        return token ~= nil
    end, false, Config.callback.timeout, TOKEN_POLL_INTERVAL) ~= false
end

local isCallable = Kora.compat.isCallable

local function settleForExport(p, invoker)
    if invoker then
        Citizen.Await(p)
        local packed = p.koraLibCallbackResults
        if packed == nil then return p.value end
        return table.unpack(packed, 1, packed.n)
    end
    return p
end

-- Export return values travel as a msgpack'd `{ ... }`, which loses everything
-- after a leading nil (`return nil, "reason"` arrives as nothing at all). The
-- consumer proxy (init.lua) therefore calls triggerPacked and unpacks the
-- envelope itself, so every value, nils included, reaches the caller.
local function envelope(p)
    Citizen.Await(p)
    local packed = p.koraLibCallbackResults
    if packed == nil then return { n = 1, [1] = p.value } end
    local out = { n = packed.n }
    for index = 1, packed.n do out[index] = packed[index] end
    return out
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

local function request(name, ...)
    Kora.callback.assertName(name)

    local p = promise.new()

    if not awaitToken() then
        p:reject("Callback handshake did not complete in time.")
        return p
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

    return p
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
    -- Captured before any yield: the invoking resource is only known up front.
    local invoker = GetInvokingResource()
    return settleForExport(request(name, ...), invoker)
end

---Same request as Kora.callback.trigger, but always waits and returns one
---`{ n = count, [1] = ..., [2] = ... }` envelope instead of multiple values.
---Used by the consumer proxy in init.lua; call Kora.callback.trigger instead.
---@param name string
---@param ... any
---@return { n: integer, [integer]: any }
function Kora.callback.triggerPacked(name, ...)
    return envelope(request(name, ...))
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
        local packed = table.pack(...)
        p.koraLibCallbackResults = packed
        p:resolve(packed[1])
    else
        p:reject((...))
    end
end)

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

    local results = table.pack(pcall(handler, ...))
    local ok = results[1]

    TriggerServerEvent(events.clientResponse, requestId, ok, table.unpack(results, 2, results.n))
end)
