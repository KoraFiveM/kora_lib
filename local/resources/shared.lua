local function assertResourceName(resourceName, label)
    assert(type(resourceName) == 'string' and resourceName ~= '' and #resourceName <= 256,
        label .. ' requires a resource name up to 256 bytes.')
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
    assert(options == nil or type(options) == 'table', 'QB.resources.awaitStarted options must be a table.')
    options = options or {}

    local timeout = options.timeout
    if timeout == nil then timeout = 10000 end
    local interval = options.interval
    if interval == nil then interval = 100 end
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
