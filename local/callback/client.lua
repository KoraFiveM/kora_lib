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
--
-- UNLIKE every other module's identical copy of this helper (see
-- local/callback/server.lua, local/events/{client,server}.lua, and
-- modules/{cache,zones,nui}/client.lua), this copy also forwards every
-- extra return value a callback handler produced (e.g.
-- `return false, "you didn't have a proper item"`), not just the first --
-- see p.qblibCallbackResults on the events.response handler below. The
-- promise itself still resolves with ONLY the handler's first return value,
-- deliberately unchanged from before this existed, so every EXISTING
-- same-VM caller inside qblib (e.g. modules/minigames/client.lua's own
-- `Citizen.Await(QB.callback.trigger(...))`) keeps working exactly as it did
-- -- only a genuine cross-resource caller, reached here, gets the extra
-- values, by reading the side-channel field Citizen.Await(p) itself can't
-- carry (a promise only ever resolves with ONE value).
local function settleForExport(p)
    if GetInvokingResource() then
        Citizen.Await(p) -- suspends until settled; its own return value is deliberately unused, see above
        local packed = p.qblibCallbackResults
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
---@return promise|any ... A promise for a same-VM caller (unchanged, awaitable as before -- it resolves
---with a `table.pack`'d `{n=, ...}` envelope, since the handler can return more than one value; unpack it
---yourself). For a genuine cross-resource caller, the handler's own return values themselves, unpacked --
---e.g. a handler doing `return false, "reason"` comes back as two real return values here, not one (see
---settleForExport above).
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

RegisterNetEvent(events.response, function(requestId, ok, ...)
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
        p.qblibCallbackResults = packed
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
    local handler = registry[name]
    if handler == nil then return end

    -- table.pack, not `local ok, result = pcall(...)` -- see the identical
    -- comment on server.lua's events.invoke handler for why a two-variable
    -- capture would silently drop everything past a handler's first return
    -- value.
    local results = table.pack(pcall(handler, ...))
    local ok = results[1]

    TriggerServerEvent(events.clientResponse, requestId, ok, table.unpack(results, 2, results.n))
end)

