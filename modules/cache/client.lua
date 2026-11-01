local cache = {}
local listeners = {}
local SERVER_ID_RETRY_INTERVAL = 250
local refreshInterval = Config.cache.tickInterval

assert(Kora.util.isInteger(refreshInterval) and refreshInterval > 0,
    'Config.cache.tickInterval must be a positive finite integer.')

-- Built-in keys this module owns. Kora.cache.set rejects writes to them outright,
-- so no consumer can observe even a transient poisoned value.
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

-- listenersById[id] = { key, entry }: lets the registry's onDispose (which only knows
-- an id) find one listener without scanning. A key can have several listeners from
-- several resources, so each onChange registration gets its own synthetic id.
local listenersById = {}
local nextListenerId = 0

-- Forward-declared: Kora.cache.onChange references it as an upvalue before it is created.
local listenerRegistry

local function assertKey(key)
    assert(type(key) == "string" and #key > 0 and #key <= 256,
        "Cache key must be a non-empty string up to 256 bytes.")
end

-- The private bootstrap helper normalizes native functions and every Cfx
-- cross-resource funcref proxy shape consistently across kora_lib modules.
local isCallable = Kora.compat.isCallable

-- No-op when the value hasn't actually changed, so setting the same vehicle/
-- weapon/etc. every tick doesn't spam onChange handlers.
local function setValue(key, value)
    local old = cache[key]
    if old == value then return end
    cache[key] = value

    local handlers = listeners[key]
    if not handlers then return end

    -- A handler may remove itself (or its resource may stop) while it runs.
    -- Walk the original range by identity so a shifted next entry is neither
    -- skipped nor called through a stale slot.
    local entryIndex = 1
    local lastEntryIndex = #handlers
    while entryIndex <= lastEntryIndex do
        local entry = handlers[entryIndex]
        if entry then
            local ok, err = pcall(entry.handler, value, old)
            if not ok then
                print(("[kora_lib:cache] onChange handler for '%s' errored: %s"):format(key, tostring(err)))
            end

            if handlers[entryIndex] == entry then entryIndex = entryIndex + 1 end
        else
            entryIndex = entryIndex + 1
        end
    end
end

-- No single native answers "what seat am I in": scan seats (-1 = driver, 0+ = passenger).
local function computeSeat(vehicle, ped, cachedSeat)
    if not vehicle then return false end

    -- Check the previous seat first; only scan the vehicle when the ped has left it.
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

-- Player indices are session constants, resolved outside refresh(). GetPlayerServerId
-- may still be -1 early in resource start; a short startup worker replaces it.
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
            -- Networking can stay unavailable through a long loading screen; don't poll every frame.
            Wait(SERVER_ID_RETRY_INTERVAL)
        end
    end)
end

local function refresh()
    local ped = PlayerPedId()
    setValue("ped", ped)
    setValue("health", GetEntityHealth(ped))
    setValue("armour", GetPedArmour(ped))
    -- Keyed off the PLAYER index (GetPlayerStamina takes a player). Cached here because it
    -- changes continuously while sprinting, so HUDs can use onChange instead of their own thread.
    setValue("stamina", GetPlayerStamina(playerId))

    -- Track the attempted-entry state alongside the actual vehicle so consumers can follow
    -- Entering -> Entered/Aborted without a second polling loop.
    -- Native guard keeps this smoke-testable under minimal mocks.
    local enteringVehicle = GetVehiclePedIsTryingToEnter and GetVehiclePedIsTryingToEnter(ped) or 0
    if enteringVehicle == 0 then enteringVehicle = false end
    local enteringSeat = enteringVehicle and GetSeatPedIsTryingToEnter and GetSeatPedIsTryingToEnter(ped) or false

    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then vehicle = false end
    local seat = computeSeat(vehicle, ped, cache.seat)

    -- Order matters to onChange consumers: an entering attempt is reported
    -- before an actual entry, while the current seat is updated before the
    -- vehicle change so an "Entered" handler sees the correct seat directly.
    setValue("enteringSeat", enteringSeat)
    setValue("enteringVehicle", enteringVehicle)
    setValue("seat", seat)
    setValue("vehicle", vehicle)
    setValue("weapon", GetSelectedPedWeapon(ped))
    local coords = GetEntityCoords(ped)
    local oldCoords = cache.coords
    if not oldCoords or oldCoords.x ~= coords.x or oldCoords.y ~= coords.y or oldCoords.z ~= coords.z then
        setValue('coords', coords)
    end
    -- Engine death predicate, not a health threshold. Set after coords so an isDead
    -- observer gets this refresh's location on the alive -> dead edge.
    setValue("isDead", IsPedFatallyInjured and IsPedFatallyInjured(ped) or false)
end

refresh()

CreateThread(function()
    while true do
        Wait(refreshInterval)
        refresh()
    end
end)

---Returns the cached value for `key`, or nil if nothing has set it yet.
---@param key string
---@return any
function Kora.cache.get(key)
    assertKey(key)
    return cache[key]
end

---Sets a cached value, firing onChange handlers for `key` if it changed. Reserved built-in keys
---(playerId/serverId/ped/vehicle/seat/weapon/health/armour/stamina/coords) are rejected and logged.
---@param key string
---@param value any
function Kora.cache.set(key, value)
    assertKey(key)

    if RESERVED_KEYS[key] then
        print(("[kora_lib:cache] Ignoring Kora.cache.set('%s', ...) -- '%s' is a reserved built-in key."):format(key, key))
        return
    end

    setValue(key, value)
end

---Registers `handler(newValue, oldValue)` for changes to `key` (via set or the per-tick refresh).
---A handler that errors is logged without stopping others; removed automatically when the resource stops.
---@param key string
---@param handler fun(newValue: any, oldValue: any)
function Kora.cache.onChange(key, handler)
    assertKey(key)
    assert(isCallable(handler), "onChange handler must be a function.")

    local owner = GetInvokingResource() or GetCurrentResourceName()

    nextListenerId = nextListenerId + 1
    local id = nextListenerId

    local entry = { handler = handler, owner = owner, id = id }
    listeners[key] = listeners[key] or {}
    listeners[key][#listeners[key] + 1] = entry
    listenersById[id] = { key = key, entry = entry }

    listenerRegistry.track(owner, id)
end

---Removes one listener entry from `listeners[key]` and the ownership registry (single place keeping both consistent).
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

-- Ownership/cleanup on resource stop is delegated to the shared registry
-- (local/resources/AGENTS.md); id = the synthetic per-listener id above.
listenerRegistry = Kora.resources.registry(removeListener)

---Removes every onChange handler the calling resource registered for `key`.
---(Handler identity doesn't survive the exports boundary, so removal is per-resource-per-key.)
---@param key string
function Kora.cache.offChange(key)
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
function Kora.cache.playerId()
    return cache.playerId
end

---This player's server id (GetPlayerServerId(PlayerId())) -- stable for the whole session.
---@return integer
function Kora.cache.serverId()
    return cache.serverId
end

---The local player's current ped handle. Refreshed every tick, so this stays
---correct across death/respawn without re-fetching PlayerPedId() yourself.
---@return integer
function Kora.cache.ped()
    return cache.ped
end

---The local player's last sampled world coordinates. Refreshed on the shared
---cache tick; use this for interval/event work, not frame-critical movement,
---aiming, or placement where a fresh native read is required.
---@return vector3|table
function Kora.cache.coords()
    return cache.coords
end

---The vehicle the local player is currently in, or false if on foot.
---@return integer | false
function Kora.cache.vehicle()
    return cache.vehicle
end

---The seat the local player currently occupies (-1 = driver, 0+ = passenger),
---or false if not in a vehicle.
---@return integer | false
function Kora.cache.seat()
    return cache.seat
end

---The vehicle the local player is trying to enter, or false when no entry
---animation is active. Use onChange rather than polling this value.
---@return integer | false
function Kora.cache.enteringVehicle()
    return cache.enteringVehicle
end

---The seat the local player is trying to enter, or false when no entry
---animation is active.
---@return integer | false
function Kora.cache.enteringSeat()
    return cache.enteringSeat
end

---The local player's currently selected weapon hash. Always a hash --
---GetSelectedPedWeapon reports `WEAPON_UNARMED`'s hash when holding nothing,
---never a false/nil sentinel.
---@return integer
function Kora.cache.weapon()
    return cache.weapon
end

---The local player's current health (GetEntityHealth(ped)). GTA's death threshold is commonly
---100, not 0; use `isDead` or a death event rather than assuming 0 is reachable.
---@return integer
function Kora.cache.health()
    return cache.health
end

---Whether the local player's ped is fatally injured according to FiveM's
---IsPedFatallyInjured native. Subscribe to onChange('isDead', ...) for the
---alive -> dead edge; this is not a health-threshold heuristic.
---@return boolean
function Kora.cache.isDead()
    return cache.isDead
end

---The local player's current armour (GetPedArmour(ped)). 0 when no armour is
---equipped.
---@return integer
function Kora.cache.armour()
    return cache.armour
end

---The local player's remaining sprint stamina (GetPlayerStamina(playerId)),
---0-100. Unlike health/armour this is keyed off the PLAYER index, not the ped.
---Falls while sprinting and regenerates back to 100 at rest, so onChange for
---this key fires on most ticks during a sprint and none at all standing still.
---@return number
function Kora.cache.stamina()
    return cache.stamina
end
