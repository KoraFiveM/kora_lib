local events = {
    handshake = 'kora_lib:callback:handshake',
    handshakeResponse = 'kora_lib:callback:handshake:response',
    invoke = 'kora_lib:callback:invoke',
    response = 'kora_lib:callback:response',
    clientInvoke = 'kora_lib:callback:clientInvoke',
    clientResponse = 'kora_lib:callback:clientResponse',
}

local tokens = {}
local registry = {}
local rateBuckets = {}
local pendingClientCallbacks = {}
local requestCounter = 0
local isInteger = Kora.util.isInteger
local MAX_RATE_LIMIT = 10000
local MAX_RATE_WINDOW = 86400000
local HANDSHAKE_LIMIT = { max = 5, window = 60000 }

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

local callbackOwnership = Kora.resources.serverRegistry(function(name)
    registry[name] = nil
    clearRateLimit(name)
end)

local generateToken = Kora.compat.generateToken

local isCallable = Kora.compat.isCallable

local function settleForExport(p)
    if GetInvokingResource() then
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

---Registers a handler for a callback invoked from the client via Kora.callback.trigger(name, ...).
---Requests carrying a missing or invalid per-player token are dropped silently.
---Automatically unregistered if the calling resource stops (see onResourceStop below) --
---most callers don't need to call Kora.callback.unregister themselves.
---@param name string
---@param handler fun(src: integer, ...: any): any
---@param opts? KoraRegistrationOptions
function Kora.callback.register(name, handler, opts)
    Kora.callback.assertName(name)
    assert(isCallable(handler), "Callback handler must be a function.")
    local rateLimit = normalizeRateLimit(opts)
    local replace = opts and opts.replace == true

    local owner = GetInvokingResource() or GetCurrentResourceName()

    local previousOwner = callbackOwnership.owner(name)
    if previousOwner and previousOwner ~= owner and not replace then
        print(("[kora_lib:callback] '%s' was registered by '%s' and is being overwritten by '%s' -- namespace your callback names.")
            :format(name, previousOwner, owner))
    end

    registry[name] = { handler = handler, rateLimit = rateLimit }
    clearRateLimit(name)
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
    clearRateLimit(name)
    callbackOwnership.untrack(name)
    return true
end

local function request(target, name, ...)
    Kora.callback.assertName(name)
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

    return p
end

---Triggers a callback registered on a specific client via Kora.callback.register(name, handler).
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
function Kora.callback.trigger(target, name, ...)
    return settleForExport(request(target, name, ...))
end

---Same request as Kora.callback.trigger, but always waits and returns one
---`{ n = count, [1] = ..., [2] = ... }` envelope instead of multiple values.
---Used by the consumer proxy in init.lua; call Kora.callback.trigger instead.
---@param target integer
---@param name string
---@param ... any
---@return { n: integer, [integer]: any }
function Kora.callback.triggerPacked(target, name, ...)
    return envelope(request(target, name, ...))
end

RegisterNetEvent(events.handshake, function()
    local src = source
    if type(src) ~= "number" or src < 1 or src % 1 ~= 0 or src ~= src
        or src == math.huge or src == -math.huge then
        return
    end
    if not consumeRateLimit(events.handshake, src, HANDSHAKE_LIMIT) then return end
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
    if tokens[src] ~= token then return end

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

    local results = KoraLibUnwrapCallbackResults(table.pack(pcall(definition.handler, src, ...)))
    local ok = results[1]

    if not ok then
        print(("[kora_lib:callback] handler for '%s' (player %d) errored: %s"):format(name, src, tostring(results[2])))
        if type(results[2]) == 'string' then
            results[2] = (results[2]:gsub('^[^%s:]+%.lua:%d+: ', '', 1))
        end
    end

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
        local packed = table.pack(...)
        pending.promise.koraLibCallbackResults = packed
        pending.promise:resolve(packed[1])
    else
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
