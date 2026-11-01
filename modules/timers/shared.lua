-- Kora.timers -- owner-tracked repeating/deferred callbacks, plus debounce/throttle.
--
-- Unlike Kora.loops.controlled (which stops once a predicate goes truthy) this runs "every N ms until I
-- say stop". Bare SetTimeout/CreateThread would keep ticking in kora_lib's VM after the owner stops, so
-- every timer is tracked against GetInvokingResource() and swept on stop (same contract as blips/zones).
--
-- One shared file: the logic is realm-identical, only the ownership registry differs.

-- The registry is created lazily: fxmanifest.lua loads every modules/**/shared.lua before
-- local/resources/{client,server}.lua, so Kora.resources.registry/serverRegistry don't exist at load time.
local timerRegistry

local function registry()
    if not timerRegistry then
        local factory = IsDuplicityVersion() and Kora.resources.serverRegistry or Kora.resources.registry

        -- onDispose only flips the flag; the coroutine is parked in Wait() and notices on its next wake (no native kills it).
        timerRegistry = factory(function(id)
            local record = Kora.timers._records[id]
            if record then
                record.cancelled = true
                Kora.timers._records[id] = nil
            end
        end)
    end

    return timerRegistry
end

-- id -> { cancelled = boolean }. The running coroutine holds the record itself, so cancelling is one field
-- write and a recycled id can't cancel a still-sleeping timer. Underscore-prefixed: module state, not API.
Kora.timers._records = {}

local nextId = 0

---Cross-resource callables arrive as a table with `__call`, not a function, so a bare `type(x) == "function"` guard
---would reject every handler that crossed an exports boundary.
---@param value any
---@return boolean
local isCallable = Kora.compat.isCallable

---@param interval any
---@param label string
---@return integer
local function assertInterval(interval, label)
    assert(Kora.util.isInteger(interval) and interval >= 0,
        ("%s requires a non-negative integer millisecond interval."):format(label))
    return interval
end

local function assertCooldownKey(key)
    local keyType = type(key)
    if keyType == 'number' then
        assert(Kora.util.isFiniteNumber(key), 'Kora.timers cooldown keys must be finite scalars.')
    elseif keyType == 'string' then
        assert(#key <= 256, 'Kora.timers cooldown string keys must be at most 256 bytes.')
    else
        assert(keyType == 'boolean', 'Kora.timers cooldown keys must be finite scalars.')
    end
    return key
end

---@return integer
local function allocateId()
    nextId = nextId + 1
    return nextId
end

---Internal one-shot scheduler taking an explicit owner: GetInvokingResource() is always nil inside a deferred
---closure, so debounce() captures the owner at registration time and carries it down.
---@param owner string
---@param fn fun()
---@param delay integer
---@return integer id
local function scheduleTimeout(owner, fn, delay)
    local id = allocateId()
    local record = { cancelled = false }
    Kora.timers._records[id] = record
    registry().track(owner, id)

    CreateThread(function()
        Wait(delay)
        if record.cancelled then return end

        -- Untracked before running: a one-shot has no further schedule, so staying tracked would leak a registry entry.
        Kora.timers._records[id] = nil
        registry().untrack(id)

        local ok, err = pcall(fn)
        if not ok then
            print(("[kora_lib] Kora.timers timeout %d (%s) errored: %s"):format(id, owner, err))
        end
    end)

    return id
end

---Runs `fn` every `interval` ms until cancelled or the owning resource stops.
---The first run happens one full interval from now, not immediately.
---
---`fn` is pcall'd: an error is printed and the interval KEEPS RUNNING (same containment as Kora.keybind and Kora.state).
---@param fn fun() Callback invoked on each tick.
---@param interval number Milliseconds between ticks.
---@return integer id Pass to Kora.timers.clearInterval.
function Kora.timers.setInterval(fn, interval)
    local owner = GetInvokingResource() or GetCurrentResourceName()

    assert(isCallable(fn), "Kora.timers.setInterval requires a callable.")
    interval = assertInterval(interval, "Kora.timers.setInterval")

    local id = allocateId()
    local record = { cancelled = false }
    Kora.timers._records[id] = record
    registry().track(owner, id)

    CreateThread(function()
        while not record.cancelled do
            Wait(interval)
            -- Re-check after the wait: cancellation lands while parked, which would otherwise fire one extra tick.
            if record.cancelled then return end

            local ok, err = pcall(fn)
            if not ok then
                print(("[kora_lib] Kora.timers interval %d (%s) errored: %s"):format(id, owner, err))
            end
        end
    end)

    return id
end

---Runs `fn` once, `delay` ms from now, unless cancelled first. Unlike bare
---SetTimeout this is cancellable and dies with its owning resource.
---@param fn fun()
---@param delay number Milliseconds to wait.
---@return integer id Pass to Kora.timers.clearTimeout.
function Kora.timers.setTimeout(fn, delay)
    local owner = GetInvokingResource() or GetCurrentResourceName()

    assert(isCallable(fn), "Kora.timers.setTimeout requires a callable.")

    return scheduleTimeout(owner, fn, assertInterval(delay, "Kora.timers.setTimeout"))
end

local function clearTimer(id, owner)
    if not Kora.util.isInteger(id) then return false end
    local record = Kora.timers._records[id]
    if not record then return false end

    local caller = owner or GetInvokingResource()
    if caller and registry().owner(id) ~= caller then return false end

    record.cancelled = true
    Kora.timers._records[id] = nil
    registry().untrack(id)
    return true
end

---Cancels a timer created by setInterval or setTimeout. Returns false for an
---id that was never live, already cancelled, or already fired.
---@param id integer
---@return boolean cancelled
function Kora.timers.clearInterval(id)
    return clearTimer(id)
end

---Alias of clearInterval -- both timer kinds share one id space, but calling
---`clearTimeout` on a `setTimeout` id reads better at the call site.
---@param id integer
---@return boolean cancelled
function Kora.timers.clearTimeout(id)
    return Kora.timers.clearInterval(id)
end

---Wraps `fn` so it only runs once calls have stopped arriving for `wait` ms.
---Each call restarts the clock; the LAST call's arguments are the ones used.
---Trailing-edge only. Returns a CALLABLE TABLE (not a function) so `.cancel()` has somewhere to live.
---@param fn fun(...) Callback.
---@param wait number Milliseconds of quiet required before firing.
---@return table debounced In-resource, call it like a function; from another resource use `.run(...)`. `.cancel()` drops a pending run.
function Kora.timers.debounce(fn, wait)
    local owner = GetInvokingResource() or GetCurrentResourceName()

    assert(isCallable(fn), "Kora.timers.debounce requires a callable.")
    wait = assertInterval(wait, "Kora.timers.debounce")

    local pendingId
    local pendingArgs

    local debounced = {}

    ---Drops any pending run without firing it.
    ---@return boolean cancelled
    function debounced.cancel()
        if not pendingId then return false end
        clearTimer(pendingId, owner)
        pendingId = nil
        pendingArgs = nil
        return true
    end

    ---@return boolean pending
    function debounced.isPending()
        return pendingId ~= nil
    end

    ---Schedules a run, exactly as calling the handle does.
    ---`.run()` exists because the `__call` metamethod does NOT survive the export boundary: a consumer reaching this
    ---through the `Kora` proxy gets the fields but not the metatable, so `debounced(...)` raises "attempt to call a
    ---table value". Plain function fields cross as funcrefs, so consumers outside kora_lib must use `.run(...)`.
    function debounced.run(...)
        pendingArgs = table.pack(...)

        if pendingId then clearTimer(pendingId, owner) end

        pendingId = scheduleTimeout(owner, function()
            pendingId = nil
            local args = pendingArgs
            pendingArgs = nil
            fn(table.unpack(args, 1, args.n))
        end, wait)
    end

    return setmetatable(debounced, {
        __call = function(_, ...)
            return debounced.run(...)
        end
    })
end

---Wraps `fn` so it runs at most once per `interval` ms. Leading-edge: calls inside the cooldown are DROPPED, not
---queued (a trailing call would fire an alert about a moment that has passed). Returns a callable table.
---@param fn fun(...) Callback.
---@param interval number Minimum milliseconds between runs.
---@return table throttled In-resource, call it like a function; from another resource use `.run(...)`. Either returns whether it ran. `.reset()` clears the cooldown.
function Kora.timers.throttle(fn, interval)
    assert(isCallable(fn), "Kora.timers.throttle requires a callable.")
    interval = assertInterval(interval, "Kora.timers.throttle")

    local lastRun

    local throttled = {}

    ---Clears the cooldown so the next call passes through.
    function throttled.reset()
        lastRun = nil
    end

    ---Milliseconds until the next call would be allowed through; 0 when ready.
    ---@return integer
    function throttled.remaining()
        if not lastRun then return 0 end
        local elapsed = GetGameTimer() - lastRun
        return elapsed >= interval and 0 or (interval - elapsed)
    end

    ---Runs `fn` if the cooldown has elapsed, exactly as calling the handle does.
    ---`.run()` exists because `__call` does NOT survive the export boundary (see debounce): outside kora_lib
    ---`throttled(...)` raises "attempt to call a table value", so consumers must use `.run(...)`.
    ---@return boolean ran
    function throttled.run(...)
        local now = GetGameTimer()

        if lastRun and (now - lastRun) < interval then return false end

        lastRun = now
        fn(...)
        return true
    end

    return setmetatable(throttled, {
        __call = function(_, ...)
            return throttled.run(...)
        end
    })
end

---Creates independent leading-edge cooldowns keyed by player, action, or any
---other scalar identity. The handle contains no cleanup policy: callers reset
---player keys on disconnect when the handle is retained by long-lived code.
---@param interval number Minimum milliseconds between accepted uses.
---@return table cooldown `.use(key)`, `.remaining(key)`, and `.reset(key?)` survive the export boundary.
function Kora.timers.cooldown(interval)
    interval = assertInterval(interval, 'Kora.timers.cooldown')
    local usedAt = {}
    local cooldown = {}

    function cooldown.use(key)
        key = assertCooldownKey(key)
        local now = GetGameTimer()
        local previous = usedAt[key]
        if previous and now - previous < interval then return false end
        usedAt[key] = now
        return true
    end

    function cooldown.remaining(key)
        key = assertCooldownKey(key)
        local previous = usedAt[key]
        if not previous then return 0 end
        return math.max(0, interval - (GetGameTimer() - previous))
    end

    function cooldown.reset(key)
        if key == nil then
            usedAt = {}
            return
        end
        key = assertCooldownKey(key)
        usedAt[key] = nil
    end

    return cooldown
end

---Live timer count, for diagnostics and tests. Debounce/throttle wrappers are
---not timers themselves; a debouncer with a pending run contributes one.
---@return integer
function Kora.timers.count()
    local n = 0
    for _ in pairs(Kora.timers._records) do n = n + 1 end
    return n
end
