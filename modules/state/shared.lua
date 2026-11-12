---Waits until a GlobalState key has a non-nil value or the bounded timeout expires. `false` is a valid value.
---@param key string
---@param timeoutMs? integer Defaults to 5000.
---@param pollIntervalMs? integer Defaults to 50.
---@return any value
---@return string|nil reason
function Kora.state.awaitGlobal(key, timeoutMs, pollIntervalMs)
    assert(type(key) == "string" and key ~= "", "Kora.state.awaitGlobal requires a state key.")
    if timeoutMs == nil then timeoutMs = 5000 end
    if pollIntervalMs == nil then pollIntervalMs = 50 end
    assert(Kora.util.isInteger(timeoutMs) and timeoutMs >= 0,
        "timeoutMs must be a non-negative integer.")
    assert(Kora.util.isInteger(pollIntervalMs) and pollIntervalMs >= 0,
        "pollIntervalMs must be a non-negative integer.")

    local startedAt = GetGameTimer()
    repeat
        local value = GlobalState[key]
        if value ~= nil then return value end
        if GetGameTimer() - startedAt >= timeoutMs then return nil, "timeout" end
        Wait(pollIntervalMs)
    until false
end
