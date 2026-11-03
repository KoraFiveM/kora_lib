-- Wire-protocol event names. Deliberately mirrored verbatim in
-- local/callback/client.lua (separate Lua chunks can't share a local table) --
-- any change here must be made there too, or the two realms stop talking.
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
-- A client handshakes once per session; anything faster is abuse of the
-- token issuer (each reply is a network event back to the sender).
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

-- Ownership tracking is delegated to the shared registry (see local/resources/AGENTS.md).
local callbackOwnership = Kora.resources.serverRegistry(function(name)
    registry[name] = nil
    clearRateLimit(name)
end)

local generateToken = Kora.compat.generateToken

-- The private bootstrap helper normalizes native functions and every Cfx
-- cross-resource funcref proxy shape consistently across kora_lib modules.
local isCallable = Kora.compat.isCallable

-- A promise doesn't survive an exports() crossing: only method calls reach the real promise, so the caller's
-- Citizen.Await would silently resolve nil. GetInvokingResource() is nil for same-VM calls and the caller's
-- name for cross-resource ones; same-VM callers get the promise, cross-resource callers get the awaited value
-- (or no values at all on rejection/timeout: the reason is printed here, never raised in the caller).
--
-- GetInvokingResource() only reflects the cross-resource caller within the synchronous native-call frame,
-- so it is read before Citizen.Await yields.
--
-- Unlike other modules' copies, this one also forwards every extra handler return value (e.g.
-- `return false, "reason"`) via the p.koraLibCallbackResults side channel, since a promise resolves with one
-- value. The promise itself still resolves with only the first return value.
local function settleForExport(p, target, name)
    local invoker = GetInvokingResource()
    if invoker then
        -- suspends until settled; its own return value is deliberately unused, see above
        local settled, reason = pcall(Citizen.Await, p)
        if not settled then
            print(("[kora_lib:callback] '%s' on player %d requested by '%s' failed: %s")
                :format(name, target, invoker, tostring(reason)))
            return
        end
        local packed = p.koraLibCallbackResults
        if packed == nil then return p.value end -- not a Kora.callback.trigger promise (or nothing to unpack) -- fall back to the bare resolved value
        return table.unpack(packed, 1, packed.n)
    end
    return p
end

---Registers a handler for a callback invoked from the client via Kora.callback.trigger(name, ...).
---Requests carrying a missing or invalid per-player token are dropped silently.
---Automatically unregistered if the calling resource stops (see onResourceStop below) --
---most callers don't need to call Kora.callback.unregister themselves.
---@param name string
---@param handler fun(src: integer, ...: any): any
---@param opts? QBRegistrationOptions
function Kora.callback.register(name, handler, opts)
    Kora.callback.assertName(name)
    assert(isCallable(handler), "Callback handler must be a function.")
    local rateLimit = normalizeRateLimit(opts)
    -- Some compatibility resources intentionally replace a placeholder owned
    -- by another resource; make that handoff explicit without hiding accidents.
    local replace = opts and opts.replace == true

    local owner = GetInvokingResource() or GetCurrentResourceName()

    -- Warn on cross-resource overwrite; see local/events/server.lua register.
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

    return settleForExport(p, target, name)
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

    -- table.pack: a handler may return multiple values; results[1] is pcall's own success flag.
    local results = table.pack(pcall(definition.handler, src, ...))
    local ok = results[1]

    if not ok then
        -- Handlers run on untrusted client input, so a raised error is logged
        -- for the server owner rather than vanishing. Only the message goes
        -- back to the client: the leading "path/file.lua:123: " position is
        -- dropped so internal paths and line numbers are not disclosed.
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
        -- Stash the full result on the promise table for settleForExport; the promise still resolves with only the first value.
        local packed = table.pack(...)
        pending.promise.koraLibCallbackResults = packed
        pending.promise:resolve(packed[1])
    else
        -- Error path carries a single value (the pcall message); nothing to unpack.
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
