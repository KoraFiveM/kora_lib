local function assertResourceName(resourceName, label)
    assert(type(resourceName) == 'string' and resourceName ~= '' and #resourceName <= 256,
        KoraLang('Local.Resources.function_requires_resource_name', label))
end

---Returns whether a resource is currently started.
---@param resourceName string
---@return boolean
function Kora.resources.isStarted(resourceName)
    assertResourceName(resourceName, 'Kora.resources.isStarted')
    return GetResourceState(resourceName) == 'started'
end

---Waits until a resource starts or the timeout expires.
---@param resourceName string
---@param options? { timeout?: number, interval?: number }
---@return boolean started
---@return string? reason
function Kora.resources.awaitStarted(resourceName, options)
    assertResourceName(resourceName, 'Kora.resources.awaitStarted')
    assert(options == nil or type(options) == 'table', KoraLang('Local.Resources.await_started_options_must_be_table'))
    options = options or {}

    local timeout = options.timeout
    if timeout == nil then timeout = 10000 end
    local interval = options.interval
    if interval == nil then interval = 100 end
    assert(Kora.util.isFiniteNumber(timeout) and timeout >= 0,
        KoraLang('Local.Resources.await_started_timeout_invalid'))
    assert(Kora.util.isFiniteNumber(interval) and interval >= 0,
        KoraLang('Local.Resources.await_started_interval_invalid'))

    local startedAt = GetGameTimer()
    repeat
        local state = GetResourceState(resourceName)
        if state == 'started' then return true end
        if state == 'missing' then return false, 'missing' end
        if GetGameTimer() - startedAt >= timeout then return false, 'timeout' end
        Wait(interval)
    until false
end
