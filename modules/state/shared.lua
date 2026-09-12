---Waits until a GlobalState key has a non-nil value, or until the bounded
---timeout expires. `false` is a valid resolved value.
---@param key string
---@param timeoutMs? integer Defaults to 5000.
---@param pollIntervalMs? integer Defaults to 50.
---@return any value
---@return string|nil reason
function QB.state.awaitGlobal(key, timeoutMs, pollIntervalMs)
    assert(type(key) == "string" and key ~= "", "QB.state.awaitGlobal requires a state key.")
    timeoutMs = timeoutMs or 5000
    pollIntervalMs = pollIntervalMs or 50
    assert(type(timeoutMs) == "number" and timeoutMs >= 0 and timeoutMs % 1 == 0,
        "timeoutMs must be a non-negative integer.")
    assert(type(pollIntervalMs) == "number" and pollIntervalMs >= 0 and pollIntervalMs % 1 == 0,
        "pollIntervalMs must be a non-negative integer.")

    local startedAt = GetGameTimer()
    repeat
        local value = GlobalState[key]
        if value ~= nil then return value end
        if GetGameTimer() - startedAt >= timeoutMs then return nil, "timeout" end
        Wait(pollIntervalMs)
    until false
end
