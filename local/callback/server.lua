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
local isInteger = QB.util.isInteger
local MAX_RATE_LIMIT = 10000
local MAX_RATE_WINDOW = 86400000

local function normalizeRateLimit(opts)
    if opts == nil then return nil end
    assert(type(opts) == 'table', 'Callback registration options must be a table.')
    local limit = opts.rateLimit
    if limit == nil or limit == false then return nil end
    assert(type(limit) == 'table', 'Callback rateLimit must be a table or false.')
    assert(isInteger(limit.max) and limit.max >= 1 and limit.max <= MAX_RATE_LIMIT,
        ('Callback rateLimit.max must be a positive integer no greater than %d.'):format(MAX_RATE_LIMIT))
    assert(isInteger(limit.window) and limit.window > 0 and limit.window <= MAX_RATE_WINDOW,
        ('Callback rateLimit.window must be a positive integer no greater than %d milliseconds.'):format(MAX_RATE_WINDOW))
    return { max = limit.max, window = limit.window }
end

local function clearRateLimit(name)
    rateBuckets[name] = nil
end

local function pruneTimestamps(bucket, cutoff)
    while bucket.count > 0 and bucket.timestamps[bucket.head] <= cutoff do
        bucket.timestamps[bucket.head] = nil
        bucket.head = bucket.head % bucket.max + 1
        bucket.count = bucket.count - 1
    end
    return bucket.count
end

local function scheduleBucketCleanup(name, src, bucket, limit, delay)
    if bucket.cleanupScheduled then return end
    bucket.cleanupScheduled = true

    SetTimeout(delay, function()
        local bySource = rateBuckets[name]
        if not bySource or bySource[src] ~= bucket then return end

        local count = pruneTimestamps(bucket, GetGameTimer() - limit.window)
        if count == 0 then
            bySource[src] = nil
            if next(bySource) == nil then rateBuckets[name] = nil end
            return
        end

        bucket.cleanupScheduled = false
        scheduleBucketCleanup(name, src, bucket, limit,
            math.max(1, math.ceil(limit.window - (GetGameTimer() - bucket.timestamps[bucket.head]))))
    end)
end

local function consumeRateLimit(name, src, limit)
    if not limit then return true end
    local bySource = rateBuckets[name]
    if not bySource then bySource = {}; rateBuckets[name] = bySource end

    local bucket = bySource[src]
    if not bucket then
        bucket = { timestamps = {}, head = 1, tail = 0, count = 0, max = limit.max }
        bySource[src] = bucket
    end

    local now = GetGameTimer()
    local count = pruneTimestamps(bucket, now - limit.window)

    if count >= limit.max then
        return false, math.max(1, math.ceil(limit.window - (now - bucket.timestamps[bucket.head])))
    end
    bucket.tail = bucket.tail % bucket.max + 1
    bucket.timestamps[bucket.tail] = now
    bucket.count = count + 1
    scheduleBucketCleanup(name, src, bucket, limit, limit.window)
    return true
end

-- Ownership tracking (which resource registered a given callback name, and
-- bulk cleanup when that resource stops) is delegated to the shared registry
-- -- see local/resources/AGENTS.md.
local callbackOwnership = QB.resources.serverRegistry(function(name)
    registry[name] = nil
    clearRateLimit(name)
end)

local generateToken = QB.compat.generateToken

-- The private bootstrap helper normalizes native functions and every Cfx
-- cross-resource funcref proxy shape consistently across qblib modules.
local isCallable = QB.compat.isCallable

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
---@param opts? QBRegistrationOptions
function QB.callback.register(name, handler, opts)
    QB.callback.assertName(name)
    assert(isCallable(handler), "Callback handler must be a function.")
    local rateLimit = normalizeRateLimit(opts)
    -- Some compatibility resources intentionally replace a placeholder owned
    -- by another resource; make that handoff explicit without hiding accidents.
    local replace = opts and opts.replace == true

    local owner = GetInvokingResource() or GetCurrentResourceName()

    -- See local/events/server.lua's register for why a cross-resource
    -- overwrite is worth warning about rather than silently accepting.
    local previousOwner = callbackOwnership.owner(name)
    if previousOwner and previousOwner ~= owner and not replace then
        print(("[qblib:callback] '%s' was registered by '%s' and is being overwritten by '%s' -- namespace your callback names.")
            :format(name, previousOwner, owner))
    end

    registry[name] = { handler = handler, rateLimit = rateLimit }
    clearRateLimit(name)
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
    clearRateLimit(name)
    callbackOwnership.untrack(name)
    return true
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
    assert(isInteger(target) and target >= 1, "target must be a positive finite player server ID.")

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
    if type(src) ~= "number" or src < 1 or src % 1 ~= 0 or src ~= src
        or src == math.huge or src == -math.huge then
        return
    end
    local token = generateToken()

    tokens[src] = token

    TriggerClientEvent(events.handshakeResponse, src, token)
end)

RegisterNetEvent(events.invoke, function(token, requestId, name, ...)
    local src = source

    if type(src) ~= "number" or src < 1 or src % 1 ~= 0 or src ~= src
        or src == math.huge or src == -math.huge then
        return
    end
    if type(token) ~= "string" or type(requestId) ~= "number" or type(name) ~= "string" or #name > 128 then return end
    if requestId < 1 or requestId % 1 ~= 0 or requestId ~= requestId
        or requestId == math.huge or requestId == -math.huge then
        return
    end
    if tokens[src] == nil or tokens[src] ~= token then return end

    local definition = registry[name]
    if definition == nil then
        TriggerClientEvent(events.response, src, requestId, false,
            ("Callback '%s' is not registered on the server."):format(name))
        return
    end
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
    if type(requestId) ~= 'number' or requestId < 1 or requestId % 1 ~= 0 or requestId ~= requestId
        or requestId == math.huge or requestId == -math.huge then
        return
    end

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
    local src = source
    tokens[src] = nil
    for name, bySource in pairs(rateBuckets) do
        bySource[src] = nil
        if next(bySource) == nil then rateBuckets[name] = nil end
    end

    for requestId, pending in pairs(pendingClientCallbacks) do
        if pending.target == src then
            pendingClientCallbacks[requestId] = nil
            pending.promise:reject("Player disconnected before answering the callback.")
        end
    end
end)
