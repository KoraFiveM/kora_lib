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

local function normalizeRateLimit(opts)
    if opts == nil then return nil end
    assert(type(opts) == 'table', 'Event registration options must be a table.')
    local limit = opts.rateLimit
    if limit == nil or limit == false then return nil end
    assert(type(limit) == 'table', 'Event rateLimit must be a table or false.')
    assert(type(limit.max) == 'number' and limit.max >= 1 and limit.max % 1 == 0,
        'Event rateLimit.max must be a positive integer.')
    assert(type(limit.window) == 'number' and limit.window > 0 and limit.window % 1 == 0,
        'Event rateLimit.window must be a positive integer in milliseconds.')
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

    -- Remove idle buckets even when the player never calls this handler
    -- again. The lazy prune above remains necessary for timers that run late.
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

-- Ownership tracking (which resource registered a given event name, and bulk
-- cleanup when that resource stops) is delegated to the shared registry --
-- see local/resources/AGENTS.md.
local eventOwnership = QB.resources.serverRegistry(function(name)
    registry[name] = nil
    clearRateLimit(name)
end)

-- Seeded ONCE at load, not per token: reseeding from a time-derived value on
-- every call would hand two same-millisecond calls identical RNG state --
-- and therefore identical tokens.
math.randomseed(GetGameTimer() + math.floor(os.clock() * 1000000))

-- Deliberately duplicated in local/callback/server.lua and modules/nui/client.lua
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
-- no shared locals) -- see local/callback/{client,server}.lua, local/events/client.lua,
-- modules/cache/client.lua, and modules/zones/client.lua for the other copies.
local function isCallable(x)
    if type(x) == "function" then return true end
    local mt = type(x) == "table" and getmetatable(x) or nil
    return mt ~= nil and mt.__call ~= nil
end

---Registers a handler for a secure event, callable from the client via QB.events.trigger.
---Requests carrying a missing or invalid per-player token are dropped silently.
---Automatically unregistered if the calling resource stops (see onResourceStop below) --
---most callers don't need to call QB.events.unregister themselves.
---@param name string
---@param handler fun(src: integer, ...: any)
---@param opts? {rateLimit?: {max: integer, window: integer}|false}
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
function QB.events.unregister(name)
    QB.events.assertName(name)
    registry[name] = nil
    clearRateLimit(name)
    eventOwnership.untrack(name)
end

RegisterNetEvent(events.handshake, function()
    local src = source
    local token = generateToken()

    tokens[src] = token

    TriggerClientEvent(events.handshakeResponse, src, token)
end)

RegisterNetEvent(events.gateway, function(token, name, ...)
    local src = source

    if type(token) ~= "string" or type(name) ~= "string" then return end
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

    TriggerClientEvent(events.push, target, name, ...)
end
