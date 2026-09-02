local cache = {}
local listeners = {}

-- Built-in keys this module owns. QB.cache.set rejects writes to
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
    enteringVehicle = true,
    enteringSeat = true,
    weapon = true,
    health = true,
    isDead = true,
    armour = true,
    stamina = true,
    coords = true,
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
local function computeSeat(vehicle, ped, cachedSeat)
    if not vehicle then return false end

    -- Most refreshes happen while the player remains in the same seat. Check
    -- that one slot first and only scan the vehicle when it no longer contains
    -- the ped (vehicle change, seat shuffle, or exit).
    if type(cachedSeat) == "number" and GetPedInVehicleSeat(vehicle, cachedSeat) == ped then
        return cachedSeat
    end

    for seat = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        if GetPedInVehicleSeat(vehicle, seat) == ped then
            return seat
        end
    end

    return false
end

-- Player indices are session constants. Resolve them outside refresh() so the
-- shared telemetry tick never pays for PlayerId/GetPlayerServerId. During an
-- early resource start GetPlayerServerId may still be -1; a short-lived startup
-- worker replaces that sentinel once networking assigns the real id.
local playerId = PlayerId()
setValue("playerId", playerId)

local serverId = GetPlayerServerId(playerId)
setValue("serverId", serverId)

if serverId == -1 and NetworkIsSessionStarted then
    CreateThread(function()
        while true do
            if NetworkIsSessionStarted() then
                serverId = GetPlayerServerId(playerId)
                if serverId ~= -1 then
                    setValue("serverId", serverId)
                    return
                end
            end
            Wait(0)
        end
    end)
end

local function refresh()
    local ped = PlayerPedId()
    setValue("ped", ped)
    setValue("health", GetEntityHealth(ped))
    setValue("armour", GetPedArmour(ped))
    -- Keyed off the PLAYER index, not the ped -- GetPlayerStamina takes a
    -- player, unlike the two above. Cached here rather than left to consumers
    -- because it changes CONTINUOUSLY while sprinting: a HUD that polls it on
    -- its own timer either lags visibly or runs a second always-on thread
    -- alongside this one. onChange off this shared tick gives it neither.
    setValue("stamina", GetPlayerStamina(playerId))

    -- Capture the attempted-entry state alongside the actual vehicle state so
    -- consumers can react to the full Entering -> Entered/Aborted lifecycle
    -- without running a second polling loop (the former separate vehicle
    -- lifecycle use case).
    -- The native is always present in FiveM; the guard keeps cache consumers
    -- independently smoke-testable under the deliberately minimal Lua mocks.
    local enteringVehicle = GetVehiclePedIsTryingToEnter and GetVehiclePedIsTryingToEnter(ped) or 0
    if enteringVehicle == 0 then enteringVehicle = false end
    local enteringSeat = enteringVehicle and GetSeatPedIsTryingToEnter and GetSeatPedIsTryingToEnter(ped) or false

    local vehicle = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or false
    local seat = computeSeat(vehicle, ped, cache.seat)

    -- Order matters to onChange consumers: an entering attempt is reported
    -- before an actual entry, while the current seat is updated before the
    -- vehicle change so an "Entered" handler sees the correct seat directly.
    setValue("enteringSeat", enteringSeat)
    setValue("enteringVehicle", enteringVehicle)
    setValue("seat", seat)
    setValue("vehicle", vehicle)
    setValue("weapon", GetSelectedPedWeapon(ped))
    setValue('coords', GetEntityCoords(ped))
    -- Use the engine's death predicate rather than inferring death from a
    -- health threshold. Set it after coords so an isDead observer receives
    -- this refresh's location when the alive -> dead edge occurs.
    -- The native is always available in FiveM; retain a false fallback so
    -- consumers can load the cache with intentionally minimal Lua mocks.
    setValue("isDead", IsPedFatallyInjured and IsPedFatallyInjured(ped) or false)
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
---key (playerId/serverId/ped/vehicle/seat/weapon/health/armour/stamina/coords) is rejected
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

---The local player's last sampled world coordinates. Refreshed on the shared
---cache tick; use this for interval/event work, not frame-critical movement,
---aiming, or placement where a fresh native read is required.
---@return vector3|table
function QB.cache.coords()
    return cache.coords
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

---The vehicle the local player is trying to enter, or false when no entry
---animation is active. Use onChange rather than polling this value.
---@return integer | false
function QB.cache.enteringVehicle()
    return cache.enteringVehicle
end

---The seat the local player is trying to enter, or false when no entry
---animation is active.
---@return integer | false
function QB.cache.enteringSeat()
    return cache.enteringSeat
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

---Whether the local player's ped is fatally injured according to FiveM's
---IsPedFatallyInjured native. Subscribe to onChange('isDead', ...) for the
---alive -> dead edge; this is not a health-threshold heuristic.
---@return boolean
function QB.cache.isDead()
    return cache.isDead
end

---The local player's current armour (GetPedArmour(ped)). 0 when no armour is
---equipped.
---@return integer
function QB.cache.armour()
    return cache.armour
end

---The local player's remaining sprint stamina (GetPlayerStamina(playerId)),
---0-100. Unlike health/armour this is keyed off the PLAYER index, not the ped.
---Falls while sprinting and regenerates back to 100 at rest, so onChange for
---this key fires on most ticks during a sprint and none at all standing still.
---@return number
function QB.cache.stamina()
    return cache.stamina
end
