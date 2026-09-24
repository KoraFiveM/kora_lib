-- Wire-protocol event names. Deliberately mirrored verbatim in
-- local/events/client.lua (separate Lua chunks can't share a local table) --
-- any change here must be made there too, or the two realms stop talking.
local events = {
    gateway = 'qblib:events:invoke',
    handshake = 'qblib:events:handshake',
    handshakeResponse = 'qblib:events:handshake:response',
    push = 'qblib:events:push',
}

local tokens = {}
local registry = {}
local rateBuckets = {}
local isInteger = QB.util.isInteger
local MAX_RATE_LIMIT = 10000
local MAX_RATE_WINDOW = 86400000

local function normalizeRateLimit(opts)
    if opts == nil then return nil end
    assert(type(opts) == 'table', 'Event registration options must be a table.')
    local limit = opts.rateLimit
    if limit == nil or limit == false then return nil end
    assert(type(limit) == 'table', 'Event rateLimit must be a table or false.')
    assert(isInteger(limit.max) and limit.max >= 1 and limit.max <= MAX_RATE_LIMIT,
        ('Event rateLimit.max must be a positive integer no greater than %d.'):format(MAX_RATE_LIMIT))
    assert(isInteger(limit.window) and limit.window > 0 and limit.window <= MAX_RATE_WINDOW,
        ('Event rateLimit.window must be a positive integer no greater than %d milliseconds.'):format(MAX_RATE_WINDOW))
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

-- Ownership tracking (which resource registered a given event name, and bulk
-- cleanup when that resource stops) is delegated to the shared registry --
-- see local/resources/AGENTS.md.
local eventOwnership = QB.resources.serverRegistry(function(name)
    registry[name] = nil
    clearRateLimit(name)
end)

local generateToken = QB.compat.generateToken

-- The private bootstrap helper normalizes native functions and every Cfx
-- cross-resource funcref proxy shape consistently across qblib modules.
local isCallable = QB.compat.isCallable

---Registers a handler callable from the client via QB.events.trigger.
---Requests carrying a missing or invalid per-player token are dropped silently.
---Automatically unregistered if the calling resource stops (see onResourceStop below) --
---most callers don't need to call QB.events.unregister themselves.
---@param name string
---@param handler fun(src: integer, ...: any)
---@param opts? QBRegistrationOptions
function QB.events.register(name, handler, opts)
    QB.events.assertName(name)
    assert(isCallable(handler), "Event handler must be a function.")
    local rateLimit = normalizeRateLimit(opts)

    local owner = GetInvokingResource() or GetCurrentResourceName()

    -- One name, one handler: a second registration silently replaces the
    -- first, and QB.resources.serverRegistry's track() moves ownership to
    -- match. Cross-resource collisions are almost always a namespacing
    -- mistake, so say so loudly rather than failing mysteriously later.
    -- (Re-registering your own name -- a resource restart -- is normal.)
    local previousOwner = eventOwnership.owner(name)
    if previousOwner and previousOwner ~= owner then
        print(("[qblib:events] '%s' was registered by '%s' and is being overwritten by '%s' -- namespace your event names.")
            :format(name, previousOwner, owner))
    end

    registry[name] = { handler = handler, rateLimit = rateLimit }
    clearRateLimit(name)
    eventOwnership.track(owner, name)
end

---Unregisters an event handler registered with QB.events.register.
---@param name string
---@return boolean removed
function QB.events.unregister(name)
    QB.events.assertName(name)
    local invoker = GetInvokingResource()
    if invoker and eventOwnership.owner(name) ~= invoker then return false end
    registry[name] = nil
    clearRateLimit(name)
    eventOwnership.untrack(name)
    return true
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

RegisterNetEvent(events.gateway, function(token, name, ...)
    local src = source

    if type(src) ~= "number" or src < 1 or src % 1 ~= 0 or src ~= src
        or src == math.huge or src == -math.huge then
        return
    end
    if type(token) ~= "string" or type(name) ~= "string" or #name > 128 then return end
    if tokens[src] == nil or tokens[src] ~= token then return end

    local definition = registry[name]
    if definition == nil then return end
    if not consumeRateLimit(name, src, definition.rateLimit) then return end

    -- pcall-and-log like every other dispatch site in the codebase: the
    -- payload is untrusted client input, and a handler that chokes on it
    -- shouldn't produce an unhandled server error a client can trigger at will.
    local ok, err = pcall(definition.handler, src, ...)
    if not ok then
        print(("[qblib:events] handler for '%s' errored: %s"):format(name, tostring(err)))
    end
end)

AddEventHandler('playerDropped', function()
    tokens[source] = nil
    for name, bySource in pairs(rateBuckets) do
        bySource[source] = nil
        if next(bySource) == nil then rateBuckets[name] = nil end
    end
end)

---Pushes a named action to a client's QB.events.onPush handler.
---Server-authoritative, like any other TriggerClientEvent — there's no client to
---authenticate against, since the server is always the trusted party here.
---@param target integer Server ID of the target player, or -1 for every connected player.
---@param name string
---@param ... any
function QB.events.push(target, name, ...)
    QB.events.assertName(name)
    assert(target == -1 or (isInteger(target) and target >= 1),
        'target must be -1 or a positive finite player server ID.')

    TriggerClientEvent(events.push, target, name, ...)
end
