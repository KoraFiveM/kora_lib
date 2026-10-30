-- Wire-protocol event names. Deliberately mirrored verbatim in
-- local/events/server.lua (separate Lua chunks can't share a local table) --
-- any change here must be made there too, or the two realms stop talking.
local events = {
    gateway = 'kora_lib:events:invoke',
    handshake = 'kora_lib:events:handshake',
    handshakeResponse = 'kora_lib:events:handshake:response',
    push = 'kora_lib:events:push',
}

local token = nil
local pushRegistry = {}

-- Ownership tracking (which resource registered a given push name, and bulk
-- cleanup when that resource stops) is delegated to the shared registry --
-- see local/resources/AGENTS.md.
local pushOwnership = QB.resources.registry(function(name)
    pushRegistry[name] = nil
end)

RegisterNetEvent(events.handshakeResponse, function(newToken)
    if type(newToken) == "string" then token = newToken end
end)

CreateThread(function()
    TriggerServerEvent(events.handshake)
end)

RegisterNetEvent(events.push, function(name, ...)
    if type(name) ~= "string" then return end
    local handler = pushRegistry[name]
    if handler == nil then return end

    local ok, err = pcall(handler, ...)
    if not ok then
        print(("[kora_lib:events] push handler for '%s' errored: %s"):format(name, tostring(err)))
    end
end)

local function awaitToken()
    if token ~= nil then return true end

    return QB.loops.controlled(function()
        return token ~= nil
    end, false) ~= false
end

-- The private bootstrap helper normalizes native functions and every Cfx
-- cross-resource funcref proxy shape consistently across kora_lib modules.
local isCallable = QB.compat.isCallable

---Triggers a registered server event through kora_lib's session-correlated gateway.
---Waits for the initial handshake token if it hasn't arrived yet.
---@param name string
---@param ... any
---@return boolean success
---@return string? error
function QB.events.trigger(name, ...)
    QB.events.assertName(name)

    if not awaitToken() then
        return false, "Event handshake did not complete in time."
    end

    TriggerServerEvent(events.gateway, token, name, ...)

    return true
end

---Registers a handler for a named push sent from the server via QB.events.push.
---The handler runs under pcall, so an error in it is isolated from the network dispatch.
---Automatically unregistered if the calling resource stops (see onClientResourceStop below) --
---most callers don't need to call QB.events.offPush themselves.
---@param name string
---@param handler fun(...: any)
function QB.events.onPush(name, handler)
    QB.events.assertName(name)
    assert(isCallable(handler), "Push handler must be a function.")

    local owner = GetInvokingResource() or GetCurrentResourceName()

    -- See local/events/server.lua's register for why a cross-resource
    -- overwrite is worth warning about rather than silently accepting.
    local previousOwner = pushOwnership.owner(name)
    if previousOwner and previousOwner ~= owner then
        print(("[kora_lib:events] push handler '%s' was registered by '%s' and is being overwritten by '%s' -- namespace your push names.")
            :format(name, previousOwner, owner))
    end

    pushRegistry[name] = handler
    pushOwnership.track(owner, name)
end

---Unregisters a push handler registered with QB.events.onPush.
---@param name string
---@return boolean removed
function QB.events.offPush(name)
    QB.events.assertName(name)
    local invoker = GetInvokingResource()
    if invoker and pushOwnership.owner(name) ~= invoker then return false end
    pushRegistry[name] = nil
    pushOwnership.untrack(name)
    return true
end
