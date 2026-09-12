-- QB.timers -- owner-tracked repeating/deferred callbacks, plus the two rate
-- shapers (debounce/throttle) every consumer otherwise hand-rolls.
--
-- Why this exists next to modules/loops: QB.loops.controlled polls until a
-- predicate goes truthy and then STOPS. It has no answer for "run this every
-- N ms until I say stop", which is what a heartbeat, a decay tick, or a
-- periodic refresh needs. Bare SetTimeout/CreateThread do that, but nothing
-- cancels them when the owning resource stops -- a stopped resource's
-- interval keeps ticking inside qblib's VM forever, calling a closure whose
-- upvalues belong to a dead script. Every timer here is tracked against
-- GetInvokingResource() and swept on stop, same contract as blips/zones.
--
-- One shared file rather than a client/server pair: the logic is byte-for-byte
-- realm-identical, and only the ownership registry differs (registry() vs
-- serverRegistry()).

-- The registry is created LAZILY, not at load time. fxmanifest.lua loads every
-- modules/**/shared.lua before ANY local/resources/{client,server}.lua, so
-- QB.resources.registry/serverRegistry do not exist yet while this chunk runs
-- -- calling either here would index a nil. By the time a consumer can reach
-- QB.timers.setInterval, both realms have finished loading.
local timerRegistry

local function registry()
    if not timerRegistry then
        local factory = IsDuplicityVersion() and QB.resources.serverRegistry or QB.resources.registry

        -- onDispose only flips the record's flag: the coroutine is parked in a
        -- Wait() and notices on its next wake. There is deliberately no attempt
        -- to kill the coroutine outright -- FiveM has no such native, and a
        -- flag check is both sufficient and cheap.
        timerRegistry = factory(function(id)
            local record = QB.timers._records[id]
            if record then
                record.cancelled = true
                QB.timers._records[id] = nil
            end
        end)
    end

    return timerRegistry
end

-- id -> { cancelled = boolean }. The record (not a bare boolean) is what the
-- running coroutine holds a reference to, so cancelling is a single field
-- write the loop observes on its next wake -- no shared-table lookup on the
-- hot path, and no risk of a recycled id cancelling a still-sleeping timer.
--
-- Underscore-prefixed so build/finalise.lua skips it (it only exports
-- functions, but keeping the naming convention makes the intent explicit:
-- this is module state, not API).
QB.timers._records = {}

local nextId = 0

---Cross-resource callables arrive as a table with a `__call` metamethod, not
---a function -- a bare `type(x) == "function"` guard rejects every handler
---that came through an exports boundary. Same helper every other qblib module
---that accepts a callback carries.
---@param value any
---@return boolean
local isCallable = QB.compat.isCallable

---@param interval any
---@param label string
---@return integer
local function assertInterval(interval, label)
    assert(type(interval) == "number" and interval >= 0 and interval == interval,
        ("%s requires a non-negative millisecond interval."):format(label))
    return math.floor(interval)
end

---@return integer
local function allocateId()
    nextId = nextId + 1
    return nextId
end

---Internal one-shot scheduler taking an explicit owner, so debounce() can
---attribute its pending run to the resource that created the debouncer rather
---than to qblib. GetInvokingResource() inside a deferred closure is always
---nil -- there is no in-progress exports() call at that point -- so the owner
---has to be captured at registration time and carried down.
---@param owner string
---@param fn fun()
---@param delay integer
---@return integer id
local function scheduleTimeout(owner, fn, delay)
    local id = allocateId()
    local record = { cancelled = false }
    QB.timers._records[id] = record
    registry().track(owner, id)

    CreateThread(function()
        Wait(delay)
        if record.cancelled then return end

        -- Untracked before running, not after: a one-shot has no further
        -- schedule, so leaving it tracked would leak one registry entry per
        -- timeout for the lifetime of the resource.
        QB.timers._records[id] = nil
        registry().untrack(id)

        local ok, err = pcall(fn)
        if not ok then
            print(("[qblib] QB.timers timeout %d (%s) errored: %s"):format(id, owner, err))
        end
    end)

    return id
end

---Runs `fn` every `interval` ms until cancelled or the owning resource stops.
---The first run happens one full interval from now, not immediately.
---
---`fn` is pcall'd: an error is printed and the interval KEEPS RUNNING. A
---heartbeat that dies permanently because one tick hit a transient nil is a
---worse failure than a noisy console, and it's the same containment
---QB.keybind and QB.state already apply to their handlers.
---@param fn fun() Callback invoked on each tick.
---@param interval number Milliseconds between ticks.
---@return integer id Pass to QB.timers.clearInterval.
function QB.timers.setInterval(fn, interval)
    local owner = GetInvokingResource() or GetCurrentResourceName()

    assert(isCallable(fn), "QB.timers.setInterval requires a callable.")
    interval = assertInterval(interval, "QB.timers.setInterval")

    local id = allocateId()
    local record = { cancelled = false }
    QB.timers._records[id] = record
    registry().track(owner, id)

    CreateThread(function()
        while not record.cancelled do
            Wait(interval)
            -- Re-check after the wait: cancellation almost always lands while
            -- this coroutine is parked, so checking only at the top of the
            -- loop would still fire one extra tick after clearInterval.
            if record.cancelled then return end

            local ok, err = pcall(fn)
            if not ok then
                print(("[qblib] QB.timers interval %d (%s) errored: %s"):format(id, owner, err))
            end
        end
    end)

    return id
end

---Runs `fn` once, `delay` ms from now, unless cancelled first. Unlike bare
---SetTimeout this is cancellable and dies with its owning resource.
---@param fn fun()
---@param delay number Milliseconds to wait.
---@return integer id Pass to QB.timers.clearTimeout.
function QB.timers.setTimeout(fn, delay)
    local owner = GetInvokingResource() or GetCurrentResourceName()

    assert(isCallable(fn), "QB.timers.setTimeout requires a callable.")

    return scheduleTimeout(owner, fn, assertInterval(delay, "QB.timers.setTimeout"))
end

---Cancels a timer created by setInterval or setTimeout. Returns false for an
---id that was never live, already cancelled, or already fired.
---@param id integer
---@return boolean cancelled
function QB.timers.clearInterval(id)
    local record = QB.timers._records[id]
    if not record then return false end

    record.cancelled = true
    QB.timers._records[id] = nil
    registry().untrack(id)

    return true
end

---Alias of clearInterval -- both timer kinds share one id space, but calling
---`clearTimeout` on a `setTimeout` id reads better at the call site.
---@param id integer
---@return boolean cancelled
function QB.timers.clearTimeout(id)
    return QB.timers.clearInterval(id)
end

---Wraps `fn` so it only runs once calls have stopped arriving for `wait` ms.
---Each call restarts the clock; the LAST call's arguments are the ones used.
---Trailing-edge only (the common "user stopped typing / entity stopped
---moving" shape).
---
---Returns a CALLABLE TABLE, not a bare function -- Lua functions can't carry
---fields, and `.cancel()` needs somewhere to live. It satisfies the same
---`__call` shape every cross-resource callable already has, so it can be
---passed anywhere a handler is accepted.
---@param fn fun(...) Callback.
---@param wait number Milliseconds of quiet required before firing.
---@return table debounced In-resource, call it like a function; from another resource use `.run(...)`. `.cancel()` drops a pending run.
function QB.timers.debounce(fn, wait)
    local owner = GetInvokingResource() or GetCurrentResourceName()

    assert(isCallable(fn), "QB.timers.debounce requires a callable.")
    wait = assertInterval(wait, "QB.timers.debounce")

    local pendingId
    local pendingArgs

    local debounced = {}

    ---Drops any pending run without firing it.
    ---@return boolean cancelled
    function debounced.cancel()
        if not pendingId then return false end
        QB.timers.clearInterval(pendingId)
        pendingId = nil
        pendingArgs = nil
        return true
    end

    ---@return boolean pending
    function debounced.isPending()
        return pendingId ~= nil
    end

    ---Schedules a run, exactly as calling the handle does.
    ---
    ---`.run()` exists because the `__call` metamethod below does NOT survive
    ---the export boundary: a resource reaching this through the `QB` proxy
    ---(init.lua -> exports.qblib:timers_debounce) receives the table's fields
    ---but not its metatable, so `debounced(...)` there raises "attempt to call
    ---a table value". Plain function fields cross as funcrefs and keep
    ---working, so `.run(...)` is the form every consumer outside qblib must
    ---use. Same reasoning as QB.timers.throttle's `.run`.
    function debounced.run(...)
        pendingArgs = table.pack(...)

        if pendingId then QB.timers.clearInterval(pendingId) end

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

---Wraps `fn` so it runs at most once per `interval` ms. Leading-edge: the
---first call passes through immediately, and calls inside the cooldown are
---DROPPED, not queued for a trailing run -- which is the semantics an alert
---detector or a rate-limited network send actually wants. A queued trailing
---call would fire an alert about a moment that has already passed.
---
---Returns a callable table, same rationale as debounce.
---@param fn fun(...) Callback.
---@param interval number Minimum milliseconds between runs.
---@return table throttled In-resource, call it like a function; from another resource use `.run(...)`. Either returns whether it ran. `.reset()` clears the cooldown.
function QB.timers.throttle(fn, interval)
    assert(isCallable(fn), "QB.timers.throttle requires a callable.")
    interval = assertInterval(interval, "QB.timers.throttle")

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
    ---
    ---`.run()` exists because the `__call` metamethod below does NOT survive
    ---the export boundary: a resource reaching this through the `QB` proxy
    ---(init.lua -> exports.qblib:timers_throttle) receives the table's fields
    ---but not its metatable, so `throttled(...)` there raises "attempt to call
    ---a table value" -- which is exactly how qbpolice's melee detector
    ---crashed. Plain function fields cross as funcrefs and keep working, so
    ---`.run(...)` is the form every consumer outside qblib must use.
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
function QB.timers.cooldown(interval)
    interval = assertInterval(interval, 'QB.timers.cooldown')
    local usedAt = {}
    local cooldown = {}

    function cooldown.use(key)
        assert(key ~= nil, 'QB.timers cooldown use requires a key.')
        local now = GetGameTimer()
        local previous = usedAt[key]
        if previous and now - previous < interval then return false end
        usedAt[key] = now
        return true
    end

    function cooldown.remaining(key)
        assert(key ~= nil, 'QB.timers cooldown remaining requires a key.')
        local previous = usedAt[key]
        if not previous then return 0 end
        return math.max(0, interval - (GetGameTimer() - previous))
    end

    function cooldown.reset(key)
        if key == nil then
            usedAt = {}
            return
        end
        usedAt[key] = nil
    end

    return cooldown
end

---Live timer count, for diagnostics and tests. Debounce/throttle wrappers are
---not timers themselves; a debouncer with a pending run contributes one.
---@return integer
function QB.timers.count()
    local n = 0
    for _ in pairs(QB.timers._records) do n = n + 1 end
    return n
end
