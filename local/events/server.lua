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

-- Ownership tracking (which resource registered a given event name, and bulk
-- cleanup when that resource stops) is delegated to the shared registry --
-- see local/resources/AGENTS.md.
local eventOwnership = QB.resources.serverRegistry(function(name)
    registry[name] = nil
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
function QB.events.register(name, handler)
    QB.events.assertName(name)
    assert(isCallable(handler), "Event handler must be a function.")

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

    registry[name] = handler
    eventOwnership.track(owner, name)
end

---Unregisters an event handler registered with QB.events.register.
---@param name string
function QB.events.unregister(name)
    QB.events.assertName(name)
    registry[name] = nil
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

    local handler = registry[name]
    if handler == nil then return end

    -- pcall-and-log like every other dispatch site in the codebase: the
    -- payload is untrusted client input, and a handler that chokes on it
    -- shouldn't produce an unhandled server error a client can trigger at will.
    local ok, err = pcall(handler, src, ...)
    if not ok then
        print(("[qblib:events] handler for '%s' errored: %s"):format(name, tostring(err)))
    end
end)

AddEventHandler('playerDropped', function()
    tokens[source] = nil
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
