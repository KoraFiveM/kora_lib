-- Wire-protocol event names. Deliberately mirrored verbatim in
-- local/callback/server.lua (separate Lua chunks can't share a local table) --
-- any change here must be made there too, or the two realms stop talking.
local events = {
    handshake = 'qblib:callback:handshake',
    handshakeResponse = 'qblib:callback:handshake:response',
    invoke = 'qblib:callback:invoke',
    response = 'qblib:callback:response',
    clientInvoke = 'qblib:callback:clientInvoke',
    clientResponse = 'qblib:callback:clientResponse',
}

local token = nil
local registry = {}
local pending = {}
local requestCounter = 0

-- Ownership tracking (which resource registered a given callback name, and
-- bulk cleanup when that resource stops) is delegated to the shared registry
-- -- see local/resources/AGENTS.md.
local callbackOwnership = QB.resources.registry(function(name)
    registry[name] = nil
end)

RegisterNetEvent(events.handshakeResponse, function(newToken)
    token = newToken
end)

CreateThread(function()
    TriggerServerEvent(events.handshake)
end)

local function awaitToken()
    if token ~= nil then return true end

    return QB.loops.controlled(function()
        return token ~= nil
    end, false) ~= false
end

-- FXServer's exports boundary hands a cross-resource function argument back
-- as a table with a __call metamethod, not a plain Lua function -- so a bare
-- type(x) == "function" check rejects a perfectly callable handler registered
-- from another resource. Deliberately duplicated per-file (separate chunks,
-- no shared locals) -- see local/callback/server.lua, local/events/{client,server}.lua,
-- modules/cache/client.lua, and modules/zones/client.lua for the other copies.
local function isCallable(x)
    if type(x) == "function" then return true end
    local mt = type(x) == "table" and getmetatable(x) or nil
    return mt ~= nil and mt.__call ~= nil
end

-- A promise object doesn't survive crossing a real cross-resource exports()
-- call back to the caller: only METHOD CALLS on it reach the real promise
-- inside qblib, while plain field reads (.state, .value -- what Citizen.Await
-- itself checks) on the crossed reference never reflect the real remote
-- promise's settlement, so the caller's own Citizen.Await silently resolves
-- nil regardless of the real outcome. GetInvokingResource() is nil for a
-- same-VM call (qblib's own modules, every dofile()'d smoke test) and the
-- real calling resource's name for a genuine cross-resource exports() call
-- (same signal modules/zones already relies on for ownership tracking -- see
-- its AGENTS.md's "Resource ownership" note) -- exactly the distinction that
-- matters here. Same-VM callers get the real promise back unchanged. A
-- genuine cross-resource caller gets the already-awaited plain value (or a
-- raised error on rejection/timeout, which -- like every other qblib error --
-- surfaces to that caller as a printed export-call error and a nil return,
-- not a catchable Lua error) instead of a promise it can't usefully await.
-- Deliberately duplicated per-file -- see local/callback/server.lua,
-- local/events/{client,server}.lua, and modules/{cache,zones,nui}/client.lua
-- for the other copies.
local function settleForExport(p)
    if GetInvokingResource() then
        return Citizen.Await(p)
    end
    return p
end

---Registers a handler for a callback invoked from the server via QB.callback.trigger(target, name, ...).
---Automatically unregistered if the calling resource stops (see onClientResourceStop below) --
---most callers don't need to call QB.callback.unregister themselves.
---@param name string
---@param handler fun(...: any): any
function QB.callback.register(name, handler)
    QB.callback.assertName(name)
    assert(isCallable(handler), "Callback handler must be a function.")

    local owner = GetInvokingResource() or GetCurrentResourceName()

    -- See local/events/server.lua's register for why a cross-resource
    -- overwrite is worth warning about rather than silently accepting.
    local previousOwner = callbackOwnership.owner(name)
    if previousOwner and previousOwner ~= owner then
        print(("[qblib:callback] '%s' was registered by '%s' and is being overwritten by '%s' -- namespace your callback names.")
            :format(name, previousOwner, owner))
    end

    registry[name] = handler
    callbackOwnership.track(owner, name)
end

---Unregisters a callback handler registered with QB.callback.register.
---@param name string
function QB.callback.unregister(name)
    QB.callback.assertName(name)
    registry[name] = nil
    callbackOwnership.untrack(name)
end

---Triggers a callback registered on the server via QB.callback.register(name, handler).
---Waits for the initial handshake token if it hasn't arrived yet.
---@param name string
---@param ... any
---@return promise|any result A promise for a same-VM caller (unchanged, awaitable as before); the
---already-settled result value directly for a genuine cross-resource caller (see settleForExport above).
function QB.callback.trigger(name, ...)
    QB.callback.assertName(name)

    local p = promise.new()

    if not awaitToken() then
        p:reject("Callback handshake did not complete in time.")
        return settleForExport(p)
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

    return settleForExport(p)
end

RegisterNetEvent(events.response, function(requestId, ok, result)
    local p = pending[requestId]
    if p == nil then return end

    pending[requestId] = nil

    if ok then
        p:resolve(result)
    else
        p:reject(result)
    end
end)

-- No token check here: the server is always the trusted party for its own
-- TriggerClientEvent calls, same reasoning as QB.events.push/onPush.
RegisterNetEvent(events.clientInvoke, function(requestId, name, ...)
    local handler = registry[name]
    if handler == nil then return end

    local ok, result = pcall(handler, ...)

    TriggerServerEvent(events.clientResponse, requestId, ok, result)
end)

