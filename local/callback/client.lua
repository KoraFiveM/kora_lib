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
    if type(newToken) == "string" then token = newToken end
end)

CreateThread(function()
    TriggerServerEvent(events.handshake)
end)

local function awaitToken()
    if token ~= nil then return true end

    -- Explicitly Config.callback.timeout, not QB.loops.controlled's own 10s
    -- default: the handshake is the FIRST thing a consumer waits on, on the
    -- coldest a client will ever be, so it must get the same budget as the
    -- request it is gating rather than a shorter hidden one.
    return QB.loops.controlled(function()
        return token ~= nil
    end, false, Config.callback.timeout) ~= false
end

-- The private bootstrap helper normalizes native functions and every Cfx
-- cross-resource funcref proxy shape consistently across kora_lib modules.
local isCallable = QB.compat.isCallable

-- A promise object doesn't survive crossing a real cross-resource exports()
-- call back to the caller: only METHOD CALLS on it reach the real promise
-- inside kora_lib, while plain field reads (.state, .value -- what Citizen.Await
-- itself checks) on the crossed reference never reflect the real remote
-- promise's settlement, so the caller's own Citizen.Await silently resolves
-- nil regardless of the real outcome. GetInvokingResource() is nil for a
-- same-VM call (kora_lib's own modules, every dofile()'d smoke test) and the
-- real calling resource's name for a genuine cross-resource exports() call
-- (same signal modules/zones already relies on for ownership tracking -- see
-- its AGENTS.md's "Resource ownership" note) -- exactly the distinction that
-- matters here. Same-VM callers get the real promise back unchanged. A
-- genuine cross-resource caller gets the already-awaited plain value (or a
-- raised error on rejection/timeout, which -- like every other kora_lib error --
-- surfaces to that caller as a printed export-call error and a nil return,
-- not a catchable Lua error) instead of a promise it can't usefully await.
--
-- Callers MUST capture GetInvokingResource() themselves, before doing
-- anything that can yield, and pass it in as `invoker` -- GetInvokingResource()
-- only reflects the real cross-resource caller within the SAME synchronous
-- native-call frame as the exports() invocation. QB.callback.trigger below
-- can yield inside awaitToken() (polling for the initial handshake token,
-- very much still in flight on a consumer resource's very first-ever
-- trigger() call), and by the time control comes back GetInvokingResource()
-- has already reverted to nil even though the original call was a genuine
-- cross-resource one -- calling it late here would silently misroute that
-- caller down the same-VM branch and hand it back a bare, unresolved promise.
--
-- UNLIKE every other module's identical copy of this helper (see
-- local/callback/server.lua, local/events/{client,server}.lua, and
-- modules/{cache,zones,nui}/client.lua), this copy also forwards every
-- extra return value a callback handler produced (e.g.
-- `return false, "you didn't have a proper item"`), not just the first --
-- see p.koraLibCallbackResults on the events.response handler below. The
-- promise itself still resolves with ONLY the handler's first return value,
-- deliberately unchanged from before this existed, so every EXISTING
-- same-VM caller inside kora_lib (e.g. modules/minigames/client.lua's own
-- `Citizen.Await(QB.callback.trigger(...))`) keeps working exactly as it did
-- -- only a genuine cross-resource caller, reached here, gets the extra
-- values, by reading the side-channel field Citizen.Await(p) itself can't
-- carry (a promise only ever resolves with ONE value).
local function settleForExport(p, invoker)
    if invoker then
        Citizen.Await(p) -- suspends until settled; its own return value is deliberately unused, see above
        local packed = p.koraLibCallbackResults
        if packed == nil then return p.value end -- not a QB.callback.trigger promise (or nothing to unpack) -- fall back to the bare resolved value
        return table.unpack(packed, 1, packed.n)
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
        print(("[kora_lib:callback] '%s' was registered by '%s' and is being overwritten by '%s' -- namespace your callback names.")
            :format(name, previousOwner, owner))
    end

    registry[name] = handler
    callbackOwnership.track(owner, name)
end

---Unregisters a callback handler registered with QB.callback.register.
---@param name string
---@return boolean removed
function QB.callback.unregister(name)
    QB.callback.assertName(name)
    local invoker = GetInvokingResource()
    if invoker and callbackOwnership.owner(name) ~= invoker then return false end
    registry[name] = nil
    callbackOwnership.untrack(name)
    return true
end

---Triggers a callback registered on the server via QB.callback.register(name, handler).
---Waits for the initial handshake token if it hasn't arrived yet.
---@param name string
---@param ... any
---@return promise|any ... A promise for a same-VM caller (unchanged, awaitable as before -- its resolved
---value is the handler's first return value, while additional values remain available to kora_lib's internal
---cross-resource settlement path). For a genuine cross-resource caller, the handler's return values are unpacked --
---e.g. a handler doing `return false, "reason"` comes back as two real return values here, not one (see
---settleForExport above).
function QB.callback.trigger(name, ...)
    QB.callback.assertName(name)

    -- Captured FIRST, before awaitToken() below gets any chance to yield --
    -- see the comment on settleForExport above for why calling this any
    -- later would silently drop a genuine cross-resource caller's identity.
    local invoker = GetInvokingResource()

    local p = promise.new()

    if not awaitToken() then
        p:reject("Callback handshake did not complete in time.")
        return settleForExport(p, invoker)
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

    return settleForExport(p, invoker)
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
        -- The FULL result is stashed as a plain field on the promise table
        -- (not part of its own resolve/reject state machine) before
        -- resolving -- settleForExport above reads it back out for a
        -- cross-resource caller. The promise itself still resolves with only
        -- the handler's FIRST return value, unchanged from before this
        -- existed, so a same-VM `Citizen.Await(QB.callback.trigger(...))`
        -- caller (e.g. modules/minigames/client.lua) sees no behavior change
        -- at all.
        local packed = table.pack(...)
        p.koraLibCallbackResults = packed
        p:resolve(packed[1])
    else
        -- The error path only ever carries a single value (server.lua's
        -- events.invoke handler sends just the pcall error message here), so
        -- there's nothing to pack -- a rejected promise's `.value` already
        -- is the one thing that matters.
        p:reject((...))
    end
end)

-- No token check here: the server is always the trusted party for its own
-- TriggerClientEvent calls, same reasoning as QB.events.push/onPush.
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

    -- table.pack, not `local ok, result = pcall(...)` -- see the identical
    -- comment on server.lua's events.invoke handler for why a two-variable
    -- capture would silently drop everything past a handler's first return
    -- value.
    local results = table.pack(pcall(handler, ...))
    local ok = results[1]

    TriggerServerEvent(events.clientResponse, requestId, ok, table.unpack(results, 2, results.n))
end)
