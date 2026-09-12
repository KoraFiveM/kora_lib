local function assertResourceName(resourceName, label)
    assert(type(resourceName) == 'string' and resourceName ~= '', label .. ' requires a resource name.')
end

---Returns whether a resource is currently started.
---@param resourceName string
---@return boolean
function QB.resources.isStarted(resourceName)
    assertResourceName(resourceName, 'QB.resources.isStarted')
    return GetResourceState(resourceName) == 'started'
end

---Waits until a resource starts or the timeout expires.
---@param resourceName string
---@param options? { timeout?: number, interval?: number }
---@return boolean started
---@return string? reason
function QB.resources.awaitStarted(resourceName, options)
    assertResourceName(resourceName, 'QB.resources.awaitStarted')
    options = options or {}
    assert(type(options) == 'table', 'QB.resources.awaitStarted options must be a table.')

    local timeout = options.timeout or 10000
    local interval = options.interval or 100
    assert(QB.util.isFiniteNumber(timeout) and timeout >= 0,
        'QB.resources.awaitStarted timeout must be a non-negative finite number.')
    assert(QB.util.isFiniteNumber(interval) and interval >= 0,
        'QB.resources.awaitStarted interval must be a non-negative finite number.')

    local startedAt = GetGameTimer()
    repeat
        local state = GetResourceState(resourceName)
        if state == 'started' then return true end
        if state == 'missing' then return false, 'missing' end
        if GetGameTimer() - startedAt >= timeout then return false, 'timeout' end
        Wait(interval)
    until false
end
