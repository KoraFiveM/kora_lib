-- Wire-protocol event names. Deliberately mirrored verbatim in
-- local/callback/client.lua (separate Lua chunks can't share a local table) --
-- any change here must be made there too, or the two realms stop talking.
local events = {
    handshake = 'qblib:callback:handshake',
    handshakeResponse = 'qblib:callback:handshake:response',
    invoke = 'qblib:callback:invoke',
    response = 'qblib:callback:response',
    clientInvoke = 'qblib:callback:clientInvoke',
    clientResponse = 'qblib:callback:clientResponse',
}

local tokens = {}
local registry = {}
local pendingClientCallbacks = {}
local requestCounter = 0

-- Ownership tracking (which resource registered a given callback name, and
-- bulk cleanup when that resource stops) is delegated to the shared registry
-- -- see local/resources/AGENTS.md.
local callbackOwnership = QB.resources.serverRegistry(function(name)
    registry[name] = nil
end)

-- Seeded ONCE at load, not per token: reseeding from a time-derived value on
-- every call would hand two same-millisecond calls identical RNG state --
-- and therefore identical tokens.
math.randomseed(GetGameTimer() + math.floor(os.clock() * 1000000))

-- Deliberately duplicated in local/events/server.lua and modules/nui/client.lua
-- (separate chunks; a shared private helper is impossible and QB.* attachments
-- become public exports) -- keep the three copies in sync.
local function generateToken()
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    local parts = {}

    for i = 1, 32 do
        local index = math.random(1, #chars)
        parts[i] = chars:sub(index, index)
    end

    return table.concat(parts)
end

-- FXServer's exports boundary hands a cross-resource function argument back
-- as a table with a __call metamethod, not a plain Lua function -- so a bare
-- type(x) == "function" check rejects a perfectly callable handler registered
-- from another resource. Deliberately duplicated per-file (separate chunks,
-- no shared locals) -- see local/events/{client,server}.lua and
-- modules/cache/client.lua and modules/zones/client.lua for the other copies.
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
-- Deliberately duplicated per-file -- see local/callback/client.lua,
-- local/events/{client,server}.lua, and modules/{cache,zones,nui}/client.lua
-- for the other copies.
local function settleForExport(p)
    if GetInvokingResource() then
        return Citizen.Await(p)
    end
    return p
end

---Registers a handler for a callback invoked from the client via QB.callback.trigger(name, ...).
---Requests carrying a missing or invalid per-player token are dropped silently.
---Automatically unregistered if the calling resource stops (see onResourceStop below) --
---most callers don't need to call QB.callback.unregister themselves.
---@param name string
---@param handler fun(src: integer, ...: any): any
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

---Triggers a callback registered on a specific client via QB.callback.register(name, handler).
---Not token-gated on the way out — the server is always the trusted party for its own
---TriggerClientEvent calls — but the client's response is only accepted from the same
---player it was addressed to.
---@param target integer Server ID of the player to ask.
---@param name string
---@param ... any
---@return promise|any result A promise for a same-VM caller (unchanged, awaitable as before); the
---already-settled result value directly for a genuine cross-resource caller (see settleForExport above).
function QB.callback.trigger(target, name, ...)
    QB.callback.assertName(name)
    assert(type(target) == "number", "target must be a player server ID.")

    local p = promise.new()

    requestCounter = requestCounter + 1
    local requestId = requestCounter

    pendingClientCallbacks[requestId] = { promise = p, target = target }

    SetTimeout(Config.callback.timeout, function()
        local pending = pendingClientCallbacks[requestId]
        if pending == nil then return end

        pendingClientCallbacks[requestId] = nil
        pending.promise:reject("Callback timed out.")
    end)

    TriggerClientEvent(events.clientInvoke, target, requestId, name, ...)

    return settleForExport(p)
end

RegisterNetEvent(events.handshake, function()
    local src = source
    local token = generateToken()

    tokens[src] = token

    TriggerClientEvent(events.handshakeResponse, src, token)
end)

RegisterNetEvent(events.invoke, function(token, requestId, name, ...)
    local src = source

    if type(token) ~= "string" or type(requestId) ~= "number" or type(name) ~= "string" then return end
    if tokens[src] == nil or tokens[src] ~= token then return end

    local handler = registry[name]
    if handler == nil then return end

    local ok, result = pcall(handler, src, ...)

    TriggerClientEvent(events.response, src, requestId, ok, result)
end)

RegisterNetEvent(events.clientResponse, function(requestId, ok, result)
    local src = source
    local pending = pendingClientCallbacks[requestId]

    if pending == nil then return end
    if pending.target ~= src then return end

    pendingClientCallbacks[requestId] = nil

    if ok then
        pending.promise:resolve(result)
    else
        pending.promise:reject(result)
    end
end)

AddEventHandler('playerDropped', function()
    tokens[source] = nil
end)

