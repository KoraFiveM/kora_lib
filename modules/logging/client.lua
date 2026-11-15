local L = Kora.logging._internal
---@class KoraLogCapture
---@field id string
---@field resource string
---@field level string
---@field duration number
---@field deadline number
---@field flushMs number
---@field batchBytes number
---@field recordBytes number
---@field queueBytes number
---@type KoraLogCapture|nil
local capture
local queue, bytes = {}, 2
local dropped = 0

local function matches(level, resource)
    return capture ~= nil
        and GetGameTimer() < capture.deadline
        and (capture.resource == '*' or capture.resource == resource)
        and L.levels[level] ~= nil
        and L.levels[level] >= (L.levels[capture.level] or 5)
end
L.captureEnabled = matches

local function clear()
    capture, queue, bytes = nil, {}, 2
    TriggerEvent('kora_lib:logging:state', false)
end

---@param expected KoraLogCapture
local function flush(expected)
    if not capture or capture ~= expected then
        return
    end
    if GetGameTimer() >= capture.deadline then
        clear()
        return
    end
    local batch, size = {}, 2
    while #queue > 0 and #batch < 40 do
        local nextRecord = queue[1].encoded
        if size + #nextRecord + 1 > capture.batchBytes then
            break
        end
        table.remove(queue, 1)
        batch[#batch + 1] = nextRecord
        size = size + #nextRecord + 1
        bytes = bytes - #nextRecord - 1
    end
    if #batch > 0 then
        TriggerServerEvent('kora_lib:logging:batch', capture.id, '[' .. table.concat(batch, ',') .. ']')
    end
    if dropped > 0 then
        L.safe(function()
            local record = L.record(
                'warn',
                'logging.records_dropped',
                'Client log queue overflow',
                { count = dropped },
                GetCurrentResourceName(),
                'client'
            )
            L.render(record, L.encode(record))
        end)
        dropped = 0
    end
    SetTimeout(capture.flushMs, function()
        flush(expected)
    end)
end

RegisterNetEvent('kora_lib:logging:capture', function(value)
    -- A server-origin event has source 65535 on the client. Local scripts cannot
    -- grant collection authority (and the server validates independently).
    if source ~= 65535 then
        return
    end
    clear()
    if type(value) ~= 'table' or type(value.id) ~= 'string' or not L.levels[value.level] then
        return
    end
    capture = value
    capture.deadline = GetGameTimer() + value.duration * 1000
    local expected = capture
    TriggerEvent('kora_lib:logging:state', true)
    SetTimeout(capture.flushMs, function()
        flush(expected)
    end)
end)

local function writeRecord(level, eventName, message, fields, owner, realm)
    local localEnabled, forward = L.enabled(level, owner), matches(level, owner)
    if not localEnabled and not forward then
        return false
    end
    local record = L.record(level, eventName, message, fields, owner, realm or 'client')
    record.clientTime = GetGameTimer()
    local encoded = L.encode(record)
    if localEnabled then
        L.render(record, encoded)
    end
    if forward and capture then
        if
            #encoded > capture.recordBytes
            or #encoded + 3 > capture.batchBytes
            or bytes + #encoded + 1 > capture.queueBytes
        then
            L.dropped, dropped = L.dropped + 1, dropped + 1
            return false
        end
        queue[#queue + 1] = { encoded = encoded, resource = owner }
        bytes = bytes + #encoded + 1
    end
    return true
end

L.writeRecord = writeRecord

---Client: NUI bridge entry point. Resource identity is obtained from the export caller.
---@param level string
---@param eventName string
---@param message string
---@param fields table|nil
---@return boolean
function Kora.logging.nui(level, eventName, message, fields)
    return L.safe(L.write, level, eventName, message, fields, L.owner(), 'nui')
end

---Client: snapshot used by consumer-local NUI bridges; contains no credentials.
---@return table
function Kora.logging.getCapture()
    local owner = L.owner()
    return {
        enabled = capture ~= nil
            and GetGameTimer() < capture.deadline
            and (capture.resource == '*' or capture.resource == owner),
        level = capture and capture.level or 'info',
        localLevel = GetConvar('kora_logging_level_' .. owner, GetConvar('kora_logging_level', 'info')),
    }
end

---Client: local delivery counters, never authoritative server statistics.
---@return table
function Kora.logging.getStats()
    return { dropped = L.dropped, failures = L.failures, emitted = L.emitted, queuedBytes = bytes - 2 }
end

AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() or (capture and capture.resource == resource) then
        clear()
    else
        for index = #queue, 1, -1 do
            if queue[index].resource == resource then
                bytes = bytes - #queue[index].encoded - 1
                table.remove(queue, index)
            end
        end
    end
end)
-- No handshake, periodic work, or network traffic in the default disabled mode.
if GetConvar('kora_logging_capture_all', 'false') == 'true' then
    CreateThread(function()
        local deadline = GetGameTimer() + 10000
        while not NetworkIsSessionStarted() or GetPlayerServerId(PlayerId()) <= 0 do
            if GetGameTimer() >= deadline then
                return
            end
            Wait(100)
        end
        TriggerServerEvent('kora_lib:logging:ready')
    end)
end
