---Repeatedly invokes `call` until it returns a truthy value, or until the try
---count / timeout is exhausted.
---
---`call` signals "not ready yet" by returning `false` or `nil`, and "done" by
---returning any truthy value, which becomes the first return value below.
---@param call fun(): any Predicate to poll. Truthy return ends the loop.
---@param tries? integer | false Max attempts, or false to disable. Defaults to 10.
---@param timeout? integer | false Max milliseconds, or false to disable. Defaults to 10000.
---@param backoff? boolean | integer How long to wait between attempts: `true` backs off exponentially (25ms -> 1s), a number waits that many ms every attempt, and `false`/omitted waits a single frame.
---@return any | false result The truthy value from `call`, or false on failure.
---@return string? error Reason the loop gave up.
function QB.loops.controlled(call, tries, timeout, backoff)

    if timeout ~= false then
        timeout = timeout or 10000
    end

    if tries ~= false then
        tries = tries or 10
    end

    local isExponential = backoff == true
    local fixedInterval = type(backoff) == "number" and backoff or nil

    assert(fixedInterval == nil or fixedInterval >= 0, "A fixed backoff interval must not be negative.")

    local timer = GetGameTimer()

    local attempt = 0

    while true do
        local value = call()

        attempt = attempt + 1

        if value then
            return value
        end

        if timeout then
            local currentTime = GetGameTimer()
            if (currentTime - timer) > timeout then
                return false, "Loop timed out."
            end
        end

        if tries then
            if attempt >= tries then
                return false, "Loop failed due to exceeding try count."
            end
        end

        if isExponential or fixedInterval then
            -- math.pow was removed in Lua 5.3; the ^ operator is version-agnostic.
            -- min() runs before floor() so an overflowed 2^n (inf) clamps to 1000
            -- rather than blowing up on the float-to-integer conversion.
            local delay = isExponential
                and math.floor(math.min(1000, 2 ^ (attempt - 1) * 25))
                or fixedInterval or 0

            -- Never sleep past the deadline: without this a long interval could
            -- overshoot `timeout` by most of its own duration before the check
            -- at the top of the next iteration even runs.
            if timeout then
                local remaining = timeout - (GetGameTimer() - timer)
                if remaining <= 0 then
                    return false, "Loop timed out."
                end
                delay = math.min(delay, remaining)
            end

            Wait(delay)
        else
            Wait(0)
        end
    end
end
