-- Kora.logging (server): ring-buffered event log with an optional Discord webhook and aggregate counters.
-- Webhook messages are attributed to the resource that logged the event.

local L = Kora.logging._internal
L.clock = function(timestamp)
    return os.date('!%H:%M:%S', timestamp)
end
local RING = 500
local ring = {}
local head = 0
local counts = {} -- category -> count

local function retain(entry)
    if #ring < RING then
        ring[#ring + 1] = entry
    else
        ring[head + 1] = entry
        head = (head + 1) % RING
    end
end

local function writeRecord(level, eventName, message, fields, owner)
    if not L.enabled(level, owner) then
        return false
    end
    local record = L.record(level, eventName, message, fields, owner, 'server')
    record.observedAt = os.time()
    local encoded = L.encode(record)
    retain(record)
    L.render(record, encoded)
    return true
end

L.writeRecord = writeRecord

local function assertEvent(category, src, data)
    assert(
        type(category) == 'string' and category ~= '' and #category <= 64,
        'Log category must be a non-empty string of at most 64 bytes.'
    )
    assert(Kora.util.isInteger(src) and src >= 0, 'Log source must be zero or a positive integer player ID.')
    assert(data == nil or type(data) == 'table', 'Log data must be a table or nil.')
end

---Log a gameplay/admin event; category groups them, src is the acting player (0 for system).
---@param category string
---@param src integer
---@param data table|nil
function Kora.logging.event(category, src, data)
    assertEvent(category, src, data)
    local entry = {
        category = category,
        source = src,
        data = L.copy(data),
        at = os.time(),
    }
    retain(entry)
    L.safe(function()
        local record =
            L.record('info', category, 'Gameplay event', { source = src, data = entry.data }, L.owner(), 'server')
        record.observedAt = entry.at
        if L.enabled('info', record.resource) then
            L.render(record, L.encode(record))
        end
    end)
    counts[category] = (counts[category] or 0) + 1

    -- 'qblib_log_webhook' and 'qbcore_log_webhook' are legacy fallbacks.
    local url = GetConvar('kora_lib_log_webhook', '')
    if url == '' then
        url = GetConvar('kora_core_log_webhook', GetConvar('qblib_log_webhook', GetConvar('qbcore_log_webhook', '')))
    end
    if url ~= '' then
        local resource = GetInvokingResource() or GetCurrentResourceName()
        local encoded, encodedData = pcall(json.encode, entry.data or {})
        if not encoded then
            L.failures = L.failures + 1
            return
        end
        local content = ('[%s] src=%s %s'):format(L.text(category, 64), tostring(src), encodedData)
        if #content > 2000 then
            content = content:sub(1, 1997) .. '...'
        end
        local payloadEncoded, payload = pcall(json.encode, {
            username = resource,
            content = content,
            -- Log data contains player-supplied text; this stops a crafted "@everyone" pinging the channel.
            allowed_mentions = { parse = {} },
        })
        if not payloadEncoded then
            L.failures = L.failures + 1
            return
        end
        -- Fire-and-forget; never blocks the caller.
        local submitted = pcall(PerformHttpRequest, url, function(status)
            if type(status) ~= 'number' or status < 200 or status >= 300 then
                L.failures = L.failures + 1
            end
        end, 'POST', payload, { ['Content-Type'] = 'application/json' })
        if not submitted then
            L.failures = L.failures + 1
        end
    end
end

---@return table  -- { counts = {category=n}, ringSize = n }
function Kora.logging.getStats()
    local snapshot = {}
    for category, count in pairs(counts) do
        snapshot[category] = count
    end
    return { counts = snapshot, ringSize = #ring, failures = L.failures, dropped = L.dropped, emitted = L.emitted }
end

-- The network accepts encoded, bounded batches only. Player identity and capture
-- generation come from this realm, never from a submitted record.
local captures, buckets, helloTimes = {}, {}, {}
local generation = ('%s:%s:%s'):format(os.time(), GetGameTimer(), math.random(1, 2147483647))
local lastDropReport, reportedDrops = -10000, 0
local serial, aggregate = 0, { tokens = 200, at = GetGameTimer() }
local function take(bucket, rate, burst, amount)
    local now = GetGameTimer()
    bucket.tokens = math.min(burst, bucket.tokens + math.max(0, now - bucket.at) * rate / 1000)
    bucket.at = now
    if bucket.tokens < amount then
        return false
    end
    bucket.tokens = bucket.tokens - amount
    return true
end

local function stopCapture(player)
    captures[player], buckets[player] = nil, nil
    TriggerClientEvent('kora_lib:logging:capture', player, false)
end

local function startCapture(player, resource, level, seconds)
    serial = serial + 1
    local capture = {
        id = generation .. ':' .. serial,
        resource = resource,
        level = level,
        expires = os.time() + seconds,
        duration = seconds,
        recordBytes = L.limit('record_bytes', 4096, 1024, 4096),
        batchBytes = L.limit('batch_bytes', 16384, 4096, 16384),
        queueBytes = L.limit('queue_bytes', 65536, 4096, 65536),
        flushMs = L.limit('flush_ms', 1000, 100, 10000),
    }
    captures[player] = capture
    buckets[player] = { tokens = L.limit('client_burst', 40, 1, 200), at = GetGameTimer() }
    TriggerClientEvent('kora_lib:logging:capture', player, capture)
    SetTimeout(seconds * 1000, function()
        if captures[player] == capture then
            stopCapture(player)
        end
    end)
    return capture
end

-- Explicit command replies remain visible even when diagnostic info is filtered.
local function reportStatus(fields)
    L.safe(function()
        local record = L.record(
            'info',
            'logging.capture_status',
            'Client diagnostic capture status',
            fields,
            GetCurrentResourceName(),
            'server'
        )
        record.observedAt = os.time()
        L.render(record, L.encode(record))
    end)
end

RegisterCommand('kora_log_capture', function(actor, args)
    if actor ~= 0 and not IsPlayerAceAllowed(actor, 'kora.logging.capture') then
        return
    end
    local action, player = args[1], tonumber(args[2])
    if action == 'status' then
        if next(captures) == nil then
            reportStatus({ active = 0 })
        end
        for id, capture in pairs(captures) do
            reportStatus({
                playerId = id,
                captureId = capture.id,
                resource = capture.resource,
                expires = capture.expires,
            })
        end
        return
    end
    if not player or player % 1 ~= 0 or player <= 0 then
        return
    end
    if action == 'stop' then
        stopCapture(player)
        Kora.logging.info(
            'logging.capture_stopped',
            'Client diagnostic capture stopped',
            { actor = actor, playerId = player }
        )
        return
    end
    local resource, level, seconds = args[3] or '*', args[4] or 'debug', tonumber(args[5] or '600')
    if
        action ~= 'start'
        or not GetPlayerName(player)
        or not L.levels[level]
        or not seconds
        or seconds % 1 ~= 0
        or seconds < 1
        or seconds > 3600
        or #resource > 128
        or not resource:match('^[%w_%-*]+$')
    then
        return
    end
    local capture = startCapture(player, resource, level, seconds)
    Kora.logging.info('logging.capture_started', 'Client diagnostic capture started', {
        actor = actor,
        playerId = player,
        captureId = capture.id,
        resource = resource,
        duration = seconds,
    })
end, false)

-- Only configured development capture installs a client-ready network handler.
if GetConvar('kora_logging_capture_all', 'false') == 'true' then
    RegisterNetEvent('kora_lib:logging:ready', function()
        local player, now = source, os.time()
        if not GetPlayerName(player) or (helloTimes[player] and now - helloTimes[player] < 10) then
            return
        end
        helloTimes[player] = now
        local level = GetConvar('kora_logging_capture_level', 'debug')
        startCapture(player, '*', L.levels[level] and level or 'debug', 3600)
    end)
end

RegisterNetEvent('kora_lib:logging:batch', function(id, raw)
    local player = source
    local capture = captures[player]
    if not capture or capture.id ~= id or capture.expires <= os.time() or not GetPlayerName(player) then
        return
    end
    local function reject()
        L.dropped = L.dropped + 1
        local now = GetGameTimer()
        if now - lastDropReport >= 10000 then
            local count = L.dropped - reportedDrops
            lastDropReport, reportedDrops = now, L.dropped
            L.safe(
                L.write,
                'warn',
                'logging.records_dropped',
                'Client diagnostics rejected or rate limited',
                { count = count },
                GetCurrentResourceName()
            )
        end
    end
    if type(raw) ~= 'string' or #raw > capture.batchBytes then
        reject()
        return
    end
    -- Charge before decoding, then charge each record; invalid batches cannot
    -- evade per-player/global CPU budgets.
    local bucket = buckets[player]
    local rate, burst = L.limit('client_rate', 20, 1, 200), L.limit('client_burst', 40, 1, 200)
    local globalRate = L.limit('aggregate_rate', 200, 1, 2000)
    if not take(bucket, rate, burst, 1) or not take(aggregate, globalRate, globalRate, 1) then
        reject()
        return
    end
    local decoded, batch = pcall(json.decode, raw)
    if not decoded or type(batch) ~= 'table' then
        reject()
        return
    end
    local size = 0
    for key in pairs(batch) do
        size = size + 1
        if type(key) ~= 'number' or key % 1 ~= 0 or key < 1 or key > 40 or size > 40 then
            reject()
            return
        end
    end
    if size ~= #batch then
        reject()
        return
    end
    for index, item in ipairs(batch) do
        if index > 1 and (not take(bucket, rate, burst, 1) or not take(aggregate, globalRate, globalRate, 1)) then
            L.dropped = L.dropped + size - index + 1
            break
        end
        local ok = L.safe(function()
            if
                type(item) ~= 'table'
                or type(item.resource) ~= 'string'
                or #item.resource > 128
                or (item.realm ~= 'client' and item.realm ~= 'nui')
                or not L.levels[item.severity]
                or L.levels[item.severity] < (L.levels[capture.level] or 5)
                or (capture.resource ~= '*' and capture.resource ~= item.resource)
                or #json.encode(item) > capture.recordBytes
            then
                return false
            end
            local record = L.record(item.severity, item.event, item.message, item.fields, item.resource, item.realm)
            record.observedAt, record.playerId, record.captureId = os.time(), player, capture.id
            record.clientReported, record.sessionId = true, capture.id
            if
                type(item.clientTime) == 'number'
                and item.clientTime == item.clientTime
                and math.abs(item.clientTime) < 1e15
            then
                record.clientTime = item.clientTime
            end
            local encoded = L.encode(record)
            retain(record)
            L.render(record, encoded)
            return true
        end)
        if not ok then
            reject()
        end
    end
end)

AddEventHandler('playerDropped', function()
    captures[source], buckets[source], helloTimes[source] = nil, nil, nil
end)
AddEventHandler('onResourceStop', function(resource)
    for player, capture in pairs(captures) do
        if resource == GetCurrentResourceName() or capture.resource == resource then
            stopCapture(player)
        end
    end
end)
