-- QB.state (server realm) -- server-side twin of client.lua. Kept separate so
-- the listener registry and lifecycle event match the realm that owns them.

local listeners = {}

local isCallable = QB.compat.isCallable

local function removeListener(id)
    local listener = listeners[id]
    if not listener then return false end
    listeners[id] = nil
    pcall(RemoveStateBagChangeHandler, listener.cookie)
    return true
end

local ownership = QB.resources.serverRegistry(removeListener)

---Subscribe to state-bag changes in the server realm.
---@param keyFilter? string
---@param bagFilter? string
---@param handler fun(context: QBStateChange)
---@return integer listenerId
function QB.state.onChange(keyFilter, bagFilter, handler)
    assert(keyFilter == nil or type(keyFilter) == 'string', 'State keyFilter must be a string or nil.')
    assert(bagFilter == nil or type(bagFilter) == 'string', 'State bagFilter must be a string or nil.')
    assert(isCallable(handler), 'State change handler must be callable.')

    local owner = GetInvokingResource() or GetCurrentResourceName()
    local cookie
    cookie = AddStateBagChangeHandler(keyFilter, bagFilter, function(bagName, key, value, reserved, replicated)
        if not listeners[cookie] then return end

        local entity = 0
        if type(bagName) == 'string' and bagName:sub(1, 7) == 'entity:' then
            local okEntity, resolved = pcall(GetEntityFromStateBagName, bagName)
            if okEntity and type(resolved) == 'number' then entity = resolved end
        end

        local ok, err = pcall(handler, {
            entity = entity,
            bagName = bagName,
            key = key,
            value = value,
            reserved = reserved,
            replicated = replicated,
        })
        if not ok then
            print(("^3[qblib:state]^7 listener %s errored: %s"):format(tostring(cookie), tostring(err)))
        end
    end)

    assert(type(cookie) == 'number', 'AddStateBagChangeHandler did not return a listener id.')
    listeners[cookie] = { cookie = cookie, resource = owner }
    ownership.track(owner, cookie)
    return cookie
end

---@param listenerId integer
---@return boolean removed
function QB.state.offChange(listenerId)
    assert(QB.util.isInteger(listenerId) and listenerId > 0, 'State listenerId must be a positive integer.')
    local invoker = GetInvokingResource()
    if invoker and ownership.owner(listenerId) ~= invoker then return false end

    ownership.untrack(listenerId)
    return removeListener(listenerId)
end
