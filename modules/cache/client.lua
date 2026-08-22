local cache = {}
local listeners = {}

-- Built-in keys the per-tick refresh() owns. QB.cache.set rejects writes to
-- any of these outright (see below) rather than merely letting refresh()
-- overwrite a bogus value back within one tick -- a resource (or a future
-- ambulance job reading `health` to gate treatment) must never observe even a
-- transient poisoned value for one of these.
local RESERVED_KEYS = {
    playerId = true,
    serverId = true,
    ped = true,
    vehicle = true,
    seat = true,
    weapon = true,
    health = true,
    armour = true,
}

-- listenersById[id] = { key = key, entry = entry } -- lets the shared
-- ownership registry's onDispose (which only knows an id) find and drop the
-- one listener entry that id refers to, without scanning every key. A cache
-- listener isn't a single owned handle like an entity/zone/blip -- one key
-- can have several listeners from several resources -- so each onChange
-- registration gets its own synthetic id to track, rather than tracking by
-- key or by resource directly.
local listenersById = {}
local nextListenerId = 0

-- Forward-declared: QB.cache.onChange (defined below, before the registry
-- itself is created) needs to reference it as an upvalue.
local listenerRegistry

local function assertKey(key)
    assert(type(key) == "string" and #key > 0, "Cache key must be a non-empty string.")
end

-- FXServer's exports boundary hands a cross-resource function argument back
-- as a table with a __call metamethod, not a plain Lua function -- so a bare
-- type(x) == "function" check rejects a perfectly callable handler registered
-- from another resource. Deliberately duplicated per-file (separate chunks,
-- no shared locals) -- see local/callback/{client,server}.lua, local/events/{client,server}.lua,
-- and modules/zones/client.lua for the other copies.
local function isCallable(x)
    if type(x) == "function" then return true end
    local mt = type(x) == "table" and getmetatable(x) or nil
    return mt ~= nil and mt.__call ~= nil
end

-- No-op when the value hasn't actually changed, so setting the same vehicle/
-- weapon/etc. every tick doesn't spam onChange handlers.
local function setValue(key, value)
    local old = cache[key]
    if old == value then return end
    cache[key] = value

    local handlers = listeners[key]
    if not handlers then return end

    for _, entry in ipairs(handlers) do
        local ok, err = pcall(entry.handler, value, old)
        if not ok then
            print(("[qblib:cache] onChange handler for '%s' errored: %s"):format(key, tostring(err)))
        end
    end
end

-- No single native answers "what seat am I in" -- scan every seat (-1 =
-- driver, 0+ = passenger) and find the one this ped occupies.
local function computeSeat(vehicle, ped)
    if not vehicle then return false end

    for seat = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        if GetPedInVehicleSeat(vehicle, seat) == ped then
            return seat
        end
    end

    return false
end

-- Every built-in key is re-asserted from its native each tick -- including
-- playerId/serverId, which never legitimately change mid-session. That's
-- deliberate: QB.cache.set is a public export any resource can call, and
-- refreshing ALL built-ins means a bogus write to any of them self-heals
-- within one tick instead of persisting for the rest of the session.
local function refresh()
    local playerId = PlayerId()
    setValue("playerId", playerId)
    setValue("serverId", GetPlayerServerId(playerId))

    local ped = PlayerPedId()
    setValue("ped", ped)
    setValue("health", GetEntityHealth(ped))
    setValue("armour", GetPedArmour(ped))

    local vehicle = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or false
    setValue("vehicle", vehicle)
    setValue("seat", computeSeat(vehicle, ped))
    setValue("weapon", GetSelectedPedWeapon(ped))
end

refresh()

CreateThread(function()
    while true do
        refresh()
        Wait(Config.cache.tickInterval)
    end
end)

---Returns the cached value for `key`, or nil if nothing has set it yet.
---@param key string
---@return any
function QB.cache.get(key)
    return cache[key]
end

---Sets a cached value directly, firing any QB.cache.onChange handlers
---registered for `key` if the value actually changed. Lets other modules (or
---other resources, via exports.qblib:cache_set) piggyback on the same cache +
---change-notification system for their own local state. Writing a built-in
---key (playerId/serverId/ped/vehicle/seat/weapon/health/armour) is rejected
---outright -- logged and ignored -- rather than merely self-healing on the
---next refresh tick, so no caller (this resource or another) can ever observe
---even a transient poisoned value for one of them.
---@param key string
---@param value any
function QB.cache.set(key, value)
    assertKey(key)

    if RESERVED_KEYS[key] then
        print(("[qblib:cache] Ignoring QB.cache.set('%s', ...) -- '%s' is a reserved built-in key."):format(key, key))
        return
    end

    setValue(key, value)
end

---Registers `handler(newValue, oldValue)` to run whenever `key`'s cached
---value changes, whether via QB.cache.set or the module's own per-tick
---refresh. Multiple handlers may be registered for the same key; a handler
---that errors is logged and doesn't stop the others. Automatically removed
---when the registering resource stops (see the sweep below) -- most callers
---don't need QB.cache.offChange themselves.
---@param key string
---@param handler fun(newValue: any, oldValue: any)
function QB.cache.onChange(key, handler)
    assertKey(key)
    assert(isCallable(handler), "onChange handler must be a function.")

    local owner = GetInvokingResource() or GetCurrentResourceName()

    nextListenerId = nextListenerId + 1
    local id = nextListenerId

    local entry = { handler = handler, owner = owner, id = id }
    listeners[key] = listeners[key] or {}
    table.insert(listeners[key], entry)
    listenersById[id] = { key = key, entry = entry }

    listenerRegistry.track(owner, id)
end

---Removes one listener entry, dropping it from `listeners[key]` and the
---ownership registry alike. Shared by QB.cache.offChange and the registry's
---own onDispose (a stopped resource's listeners), so there is exactly one
---place that keeps `listeners`/`listenersById` consistent.
---@param id number
local function removeListener(id)
    local record = listenersById[id]
    if not record then return end

    listenersById[id] = nil

    local handlers = listeners[record.key]
    if not handlers then return end

    for i = #handlers, 1, -1 do
        if handlers[i] == record.entry then table.remove(handlers, i) end
    end

    if #handlers == 0 then listeners[record.key] = nil end
end

-- Ownership tracking (which resource registered a given listener, and bulk
-- cleanup when that resource stops) is delegated to the shared registry --
-- see local/resources/AGENTS.md. A cache listener isn't a single owned
-- handle, so the id tracked here is the synthetic per-listener id above, not
-- the key or the resource itself.
listenerRegistry = QB.resources.registry(removeListener)

---Removes every onChange handler the calling resource registered for `key`.
---(Handler identity doesn't survive the exports boundary, so removal is
---per-resource-per-key rather than per-function.)
---@param key string
function QB.cache.offChange(key)
    assertKey(key)

    local handlers = listeners[key]
    if not handlers then return end

    local caller = GetInvokingResource() or GetCurrentResourceName()

    for i = #handlers, 1, -1 do
        if handlers[i].owner == caller then
            listenerRegistry.untrack(handlers[i].id)
            listenersById[handlers[i].id] = nil
            table.remove(handlers, i)
        end
    end

    if #handlers == 0 then listeners[key] = nil end
end

---The local player id (PlayerId()) -- stable for the whole session.
---@return integer
function QB.cache.playerId()
    return cache.playerId
end

---This player's server id (GetPlayerServerId(PlayerId())) -- stable for the whole session.
---@return integer
function QB.cache.serverId()
    return cache.serverId
end

---The local player's current ped handle. Refreshed every tick, so this stays
---correct across death/respawn without re-fetching PlayerPedId() yourself.
---@return integer
function QB.cache.ped()
    return cache.ped
end

---The vehicle the local player is currently in, or false if on foot.
---@return integer | false
function QB.cache.vehicle()
    return cache.vehicle
end

---The seat the local player currently occupies (-1 = driver, 0+ = passenger),
---or false if not in a vehicle.
---@return integer | false
function QB.cache.seat()
    return cache.seat
end

---The local player's currently selected weapon hash. Always a hash --
---GetSelectedPedWeapon reports `WEAPON_UNARMED`'s hash when holding nothing,
---never a false/nil sentinel.
---@return integer
function QB.cache.weapon()
    return cache.weapon
end

---The local player's current health (GetEntityHealth(ped)). Note GTA's death
---threshold is commonly 100, not 0 -- a ped dies once health drops to (or
---below) that engine-defined floor, not at a literal zero. A consumer
---checking for death (e.g. a future ambulance/EMS job) should compare against
---that threshold, or better, hook a death event, rather than assuming 0 is
---reachable.
---@return integer
function QB.cache.health()
    return cache.health
end

---The local player's current armour (GetPedArmour(ped)). 0 when no armour is
---equipped.
---@return integer
function QB.cache.armour()
    return cache.armour
end
