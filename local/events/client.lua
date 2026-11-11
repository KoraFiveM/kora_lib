local events = {
    gateway = 'kora_lib:events:invoke',
    handshake = 'kora_lib:events:handshake',
    handshakeResponse = 'kora_lib:events:handshake:response',
    push = 'kora_lib:events:push',
}

local token = nil
local TOKEN_POLL_INTERVAL = 50
local pushRegistry = {}

local pushOwnership = Kora.resources.registry(function(name)
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

    return Kora.loops.controlled(function()
        return token ~= nil
    end, false, nil, TOKEN_POLL_INTERVAL) ~= false
end

local isCallable = Kora.compat.isCallable

---Triggers a registered server event through kora_lib's session-correlated gateway.
---Waits for the initial handshake token if it hasn't arrived yet.
---@param name string
---@param ... any
---@return boolean success
---@return string? error
function Kora.events.trigger(name, ...)
    Kora.events.assertName(name)

    if not awaitToken() then
        return false, "Event handshake did not complete in time."
    end

    TriggerServerEvent(events.gateway, token, name, ...)

    return true
end

---Registers a handler for a named push sent from the server via Kora.events.push.
---The handler runs under pcall, so an error in it is isolated from the network dispatch.
---Automatically unregistered if the calling resource stops (see onClientResourceStop below) --
---most callers don't need to call Kora.events.offPush themselves.
---@param name string
---@param handler fun(...: any)
function Kora.events.onPush(name, handler)
    Kora.events.assertName(name)
    assert(isCallable(handler), "Push handler must be a function.")

    local owner = GetInvokingResource() or GetCurrentResourceName()

    local previousOwner = pushOwnership.owner(name)
    if previousOwner and previousOwner ~= owner then
        print(("[kora_lib:events] push handler '%s' was registered by '%s' and is being overwritten by '%s' -- namespace your push names.")
            :format(name, previousOwner, owner))
    end

    pushRegistry[name] = handler
    pushOwnership.track(owner, name)
end

---Unregisters a push handler registered with Kora.events.onPush.
---@param name string
---@return boolean removed
function Kora.events.offPush(name)
    Kora.events.assertName(name)
    local invoker = GetInvokingResource()
    if invoker and pushOwnership.owner(name) ~= invoker then return false end
    pushRegistry[name] = nil
    pushOwnership.untrack(name)
    return true
end
