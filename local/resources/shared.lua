local function assertResourceName(resourceName, label)
    assert(type(resourceName) == 'string' and resourceName ~= '' and #resourceName <= 256,
        label .. ' requires a resource name up to 256 bytes.')
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
    assert(options == nil or type(options) == 'table', 'Kora.resources.awaitStarted options must be a table.')
    options = options or {}

    local timeout = options.timeout
    if timeout == nil then timeout = 10000 end
    local interval = options.interval
    if interval == nil then interval = 100 end
    assert(Kora.util.isFiniteNumber(timeout) and timeout >= 0,
        'Kora.resources.awaitStarted timeout must be a non-negative finite number.')
    assert(Kora.util.isFiniteNumber(interval) and interval >= 0,
        'Kora.resources.awaitStarted interval must be a non-negative finite number.')

    local startedAt = GetGameTimer()
    repeat
        local state = GetResourceState(resourceName)
        if state == 'started' then return true end
        if state == 'missing' then return false, 'missing' end
        if GetGameTimer() - startedAt >= timeout then return false, 'timeout' end
        Wait(interval)
    until false
end

-- onStart/onStop handlers: kind ('start'|'stop') -> watched resource name -> id -> entry.
-- One start and one stop event handler serve every registration. The realm (and so the
-- event names and ownership registry) is picked on first use: this shared chunk loads
-- before local/resources/{client,server}.lua define the registry factories.
local lifecycleHandlers = { start = {}, stop = {} }
local lifecycleEntries = {}
local lifecycleOwnership
local nextLifecycleId = 0

local function removeLifecycleHandler(id)
    local entry = lifecycleEntries[id]
    if not entry then return end
    lifecycleEntries[id] = nil
    entry.removed = true

    local byName = lifecycleHandlers[entry.kind]
    local entries = byName[entry.name]
    entries[id] = nil
    if next(entries) == nil then byName[entry.name] = nil end
end

local function runLifecycleHandler(entry, resourceName)
    local ok, err = pcall(entry.fn, resourceName)
    if not ok then
        print(('[kora_lib:resources] %s handler for %s (registered by %s) errored: %s')
            :format(entry.kind, resourceName, entry.owner, tostring(err)))
    end
end

local function dispatchLifecycle(kind, resourceName)
    local entries = lifecycleHandlers[kind][resourceName]
    if not entries then return end

    -- Snapshot first: a handler may register or remove handlers for this name while it runs.
    local snapshot = {}
    for _, entry in pairs(entries) do snapshot[#snapshot + 1] = entry end

    -- One thread each, so a handler that waits or errors cannot hold up the others.
    for _, entry in ipairs(snapshot) do
        -- A resource stopping is not told about itself; its own handlers are being swept.
        if entry.owner ~= resourceName then
            CreateThread(function()
                if not entry.removed then runLifecycleHandler(entry, resourceName) end
            end)
        end
    end
end

local function lifecycle()
    if lifecycleOwnership then return lifecycleOwnership end

    local isServer = IsDuplicityVersion()
    local factory = isServer and Kora.resources.serverRegistry or Kora.resources.registry
    lifecycleOwnership = factory(removeLifecycleHandler)

    AddEventHandler(isServer and 'onResourceStart' or 'onClientResourceStart', function(resourceName)
        dispatchLifecycle('start', resourceName)
    end)
    AddEventHandler(isServer and 'onResourceStop' or 'onClientResourceStop', function(resourceName)
        dispatchLifecycle('stop', resourceName)
    end)

    return lifecycleOwnership
end

local function addLifecycleHandler(kind, label, resourceName, fn)
    assertResourceName(resourceName, label)
    assert(Kora.compat.isCallable(fn), label .. ' requires a callable handler.')

    local owner = GetInvokingResource() or GetCurrentResourceName()
    local ownership = lifecycle()

    nextLifecycleId = nextLifecycleId + 1
    local id = nextLifecycleId
    local entry = { kind = kind, name = resourceName, fn = fn, owner = owner }

    local byName = lifecycleHandlers[kind]
    byName[resourceName] = byName[resourceName] or {}
    byName[resourceName][id] = entry
    lifecycleEntries[id] = entry
    ownership.track(owner, id)

    return id, entry
end

---Runs `fn(resourceName)` now if `resourceName` is started (unless `opts.runNow` is false),
---then again every time it starts. Removed automatically when the calling resource stops.
---@param resourceName string
---@param fn fun(resourceName: string)
---@param opts? { runNow?: boolean }
---@return integer id Pass to Kora.resources.off to remove the handler early.
function Kora.resources.onStart(resourceName, fn, opts)
    assert(opts == nil or type(opts) == 'table', 'Kora.resources.onStart options must be a table.')
    local runNow = opts and opts.runNow
    assert(runNow == nil or type(runNow) == 'boolean', 'Kora.resources.onStart runNow must be a boolean.')

    local id, entry = addLifecycleHandler('start', 'Kora.resources.onStart', resourceName, fn)
    if runNow ~= false and GetResourceState(resourceName) == 'started' then
        runLifecycleHandler(entry, resourceName)
    end
    return id
end

---Runs `fn(resourceName)` every time `resourceName` stops. Removed automatically when the
---calling resource stops.
---@param resourceName string
---@param fn fun(resourceName: string)
---@return integer id Pass to Kora.resources.off to remove the handler early.
function Kora.resources.onStop(resourceName, fn)
    return (addLifecycleHandler('stop', 'Kora.resources.onStop', resourceName, fn))
end

---Removes an onStart/onStop handler. Only the resource that registered it can remove it.
---@param id integer
---@return boolean removed
function Kora.resources.off(id)
    local entry = lifecycleEntries[id]
    if not entry then return false end
    local invoker = GetInvokingResource()
    if invoker and invoker ~= entry.owner then return false end

    removeLifecycleHandler(id)
    lifecycleOwnership.untrack(id)
    return true
end
