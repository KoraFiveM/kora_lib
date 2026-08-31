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
local rateBuckets = {}
local pendingClientCallbacks = {}
local requestCounter = 0

local function normalizeRateLimit(opts)
    if opts == nil then return nil end
    assert(type(opts) == 'table', 'Callback registration options must be a table.')
    local limit = opts.rateLimit
    if limit == nil or limit == false then return nil end
    assert(type(limit) == 'table', 'Callback rateLimit must be a table or false.')
    assert(type(limit.max) == 'number' and limit.max >= 1 and limit.max % 1 == 0,
        'Callback rateLimit.max must be a positive integer.')
    assert(type(limit.window) == 'number' and limit.window > 0 and limit.window % 1 == 0,
        'Callback rateLimit.window must be a positive integer in milliseconds.')
    return { max = limit.max, window = limit.window }
end

local function clearRateLimit(name)
    rateBuckets[name] = nil
end

local function consumeRateLimit(name, src, limit)
    if not limit then return true end
    local bySource = rateBuckets[name]
    if not bySource then bySource = {}; rateBuckets[name] = bySource end

    local bucket = bySource[src]
    if not bucket then
        bucket = { timestamps = {} }
        bySource[src] = bucket
    end

    local timestamps = bucket.timestamps
    local now = GetGameTimer()
    local cutoff = now - limit.window
    local retained = {}
    for i = 1, #timestamps do
        if timestamps[i] > cutoff then retained[#retained + 1] = timestamps[i] end
    end
    timestamps = retained
    bucket.timestamps = timestamps

    if #timestamps >= limit.max then
        return false, math.max(1, math.ceil(limit.window - (now - timestamps[1])))
    end
    timestamps[#timestamps + 1] = now

    SetTimeout(limit.window, function()
        local currentBySource = rateBuckets[name]
        local currentBucket = currentBySource and currentBySource[src]
        -- A replacement/cleanup/reconnect may have created a new bucket for
        -- the same name and source. An old timer must never prune that quota.
        if currentBucket ~= bucket then return end

        local expiryCutoff = GetGameTimer() - limit.window
        local live = {}
        for i = 1, #currentBucket.timestamps do
            if currentBucket.timestamps[i] > expiryCutoff then live[#live + 1] = currentBucket.timestamps[i] end
        end

        if #live > 0 then
            currentBucket.timestamps = live
        else
            currentBySource[src] = nil
            if next(currentBySource) == nil then rateBuckets[name] = nil end
        end
    end)
    return true
end

-- Ownership tracking (which resource registered a given callback name, and
-- bulk cleanup when that resource stops) is delegated to the shared registry
-- -- see local/resources/AGENTS.md.
local callbackOwnership = QB.resources.serverRegistry(function(name)
    registry[name] = nil
    clearRateLimit(name)
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
--
-- UNLIKE every other module's identical copy of this helper (see
-- local/callback/client.lua, local/events/{client,server}.lua, and
-- modules/{cache,zones,nui}/client.lua), this copy also forwards every extra
-- return value a callback handler produced (e.g.
-- `return false, "you didn't have a proper item"`), not just the first --
-- see p.qblibCallbackResults on the events.clientResponse handler below. The
-- promise itself still resolves with ONLY the handler's first return value,
-- deliberately unchanged from before this existed, so every EXISTING
-- same-VM caller inside qblib keeps working exactly as it did -- only a
-- genuine cross-resource caller, reached here, gets the extra values, by
-- reading the side-channel field Citizen.Await(p) itself can't carry (a
-- promise only ever resolves with ONE value).
local function settleForExport(p)
    if GetInvokingResource() then
        Citizen.Await(p) -- suspends until settled; its own return value is deliberately unused, see above
        local packed = p.qblibCallbackResults
        if packed == nil then return p.value end -- not a QB.callback.trigger promise (or nothing to unpack) -- fall back to the bare resolved value
        return table.unpack(packed, 1, packed.n)
    end
    return p
end

---Registers a handler for a callback invoked from the client via QB.callback.trigger(name, ...).
---Requests carrying a missing or invalid per-player token are dropped silently.
---Automatically unregistered if the calling resource stops (see onResourceStop below) --
---most callers don't need to call QB.callback.unregister themselves.
---@param name string
---@param handler fun(src: integer, ...: any): any
---@param opts? {rateLimit?: {max: integer, window: integer}|false}
function QB.callback.register(name, handler, opts)
    QB.callback.assertName(name)
    assert(isCallable(handler), "Callback handler must be a function.")
    local rateLimit = normalizeRateLimit(opts)

    local owner = GetInvokingResource() or GetCurrentResourceName()

    -- See local/events/server.lua's register for why a cross-resource
    -- overwrite is worth warning about rather than silently accepting.
    local previousOwner = callbackOwnership.owner(name)
    if previousOwner and previousOwner ~= owner then
        print(("[qblib:callback] '%s' was registered by '%s' and is being overwritten by '%s' -- namespace your callback names.")
            :format(name, previousOwner, owner))
    end

    registry[name] = { handler = handler, rateLimit = rateLimit }
    clearRateLimit(name)
    callbackOwnership.track(owner, name)
end

---Unregisters a callback handler registered with QB.callback.register.
---@param name string
function QB.callback.unregister(name)
    QB.callback.assertName(name)
    registry[name] = nil
    clearRateLimit(name)
    callbackOwnership.untrack(name)
end

---Triggers a callback registered on a specific client via QB.callback.register(name, handler).
---Not token-gated on the way out — the server is always the trusted party for its own
---TriggerClientEvent calls — but the client's response is only accepted from the same
---player it was addressed to.
---@param target integer Server ID of the player to ask.
---@param name string
---@param ... any
---@return promise|any ... A promise for a same-VM caller (unchanged, awaitable as before -- it resolves
---with a `table.pack`'d `{n=, ...}` envelope, since the handler can return more than one value; unpack it
---yourself). For a genuine cross-resource caller, the handler's own return values themselves, unpacked --
---e.g. a handler doing `return false, "reason"` comes back as two real return values here, not one (see
---settleForExport above).
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

    local definition = registry[name]
    if definition == nil then return end
    local allowed, retryAfter = consumeRateLimit(name, src, definition.rateLimit)
    if not allowed then
        TriggerClientEvent(events.response, src, requestId, false,
            ('Callback rate limit exceeded; retry in %dms.'):format(retryAfter))
        return
    end

    -- table.pack, not `local ok, result = pcall(...)` -- a handler is free
    -- to return more than one value (e.g.
    -- `return false, "you didn't have a proper item"`), and the old
    -- two-variable capture silently dropped everything past the first.
    -- `results[1]` is pcall's OWN success flag (did the handler raise a Lua
    -- error) -- a different thing from whatever the handler itself chose to
    -- return as its first value.
    local results = table.pack(pcall(definition.handler, src, ...))
    local ok = results[1]

    TriggerClientEvent(events.response, src, requestId, ok, table.unpack(results, 2, results.n))
end)

RegisterNetEvent(events.clientResponse, function(requestId, ok, ...)
    local src = source
    local pending = pendingClientCallbacks[requestId]

    if pending == nil then return end
    if pending.target ~= src then return end

    pendingClientCallbacks[requestId] = nil

    if ok then
        -- The FULL result is stashed as a plain field on the promise table
        -- (not part of its own resolve/reject state machine) before
        -- resolving -- settleForExport above reads it back out for a
        -- cross-resource caller. The promise itself still resolves with only
        -- the handler's FIRST return value, unchanged from before this
        -- existed, so a same-VM `Citizen.Await(QB.callback.trigger(...))`
        -- caller sees no behavior change at all.
        local packed = table.pack(...)
        pending.promise.qblibCallbackResults = packed
        pending.promise:resolve(packed[1])
    else
        -- The error path only ever carries a single value (client.lua's
        -- events.clientInvoke handler sends just the pcall error message
        -- here, not a packed envelope), so no unpacking is needed on
        -- rejection.
        pending.promise:reject((...))
    end
end)

AddEventHandler('playerDropped', function()
    tokens[source] = nil
    for name, bySource in pairs(rateBuckets) do
        bySource[source] = nil
        if next(bySource) == nil then rateBuckets[name] = nil end
    end
end)
