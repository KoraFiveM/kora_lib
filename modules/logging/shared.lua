-- One implementation per realm. Internal helpers live in a table so finalise
-- does not expose them as cross-resource exports.
local L = {
    levels = { trace = 1, debug = 5, info = 9, warn = 13, error = 17, fatal = 21 },
    failures = 0,
    dropped = 0,
    emitted = 0,
}
Kora.logging._internal = L

function L.limit(name, default, minimum, maximum)
    local value = tonumber(GetConvar('kora_logging_' .. name, tostring(default)))
    if not value or value ~= value then
        return default
    end
    return math.floor(math.max(minimum, math.min(maximum, value)))
end

function L.text(value, limit)
    if type(value) ~= 'string' then
        return '[' .. type(value) .. ']'
    end
    local clipped = value:sub(1, limit or 1024)
    -- JSON requires valid UTF-8. Do not leave a partial multibyte character at
    -- the byte bound; malformed caller strings are represented safely too.
    local valid, bad = utf8.len(clipped)
    if not valid then
        clipped = clipped:sub(1, bad - 1) .. '[invalid/truncated UTF-8]'
    end
    clipped = clipped:gsub('\27%[[0-?]*[ -/]*[@-~]', '')
    repeat
        local previous = clipped
        clipped = clipped:gsub('%^%d', '')
        if clipped == previous then
            break
        end
    until false
    return clipped:gsub('\r', '\\r'):gsub('\n', '\\n'):gsub('[%z\1-\31\127]', '')
end

local function sensitive(key)
    key = key:lower():gsub('[^%w]', '')
    return key:find('password', 1, true)
        or key:find('secret', 1, true)
        or key:find('token', 1, true)
        or key:find('credential', 1, true)
        or key:find('authorization', 1, true)
        or key:find('webhook', 1, true)
        or key:find('connectionstring', 1, true)
        or key == 'license'
        or key == 'ip'
        or key == 'identifiers'
        or key == 'params'
        or key == 'parameters'
        or key == 'playerdata'
        or key == 'payload'
        or key == 'apikey'
end

function L.copy(value)
    local seen, remaining = {}, 128
    local function visit(item, depth)
        remaining = remaining - 1
        if remaining < 0 then
            return '[truncated]'
        end
        local kind = type(item)
        if kind == 'string' then
            return L.text(item)
        end
        if kind == 'boolean' or kind == 'nil' then
            return item
        end
        if kind == 'number' then
            return item == item and item ~= math.huge and item ~= -math.huge and item or '[non-finite]'
        end
        if kind ~= 'table' then
            return '[' .. kind .. ']'
        end
        if seen[item] then
            return '[cycle]'
        end
        if depth >= 4 then
            return '[depth limit]'
        end
        seen[item] = true
        local result, count = {}, 0
        -- next avoids user-controlled __pairs; never stringify arbitrary objects.
        for key, child in next, item do
            if remaining < 0 or count >= 32 then
                result._truncated = true
                break
            end
            if type(key) == 'string' or type(key) == 'number' then
                local name = L.text(tostring(key), 64)
                local targetKey = type(key) == 'number' and key or name
                result[targetKey] = sensitive(tostring(key)) and '[redacted]' or visit(child, depth + 1)
                count = count + 1
            end
        end
        seen[item] = nil
        return result
    end
    return visit(value, 0)
end

function L.owner()
    return GetInvokingResource() or GetCurrentResourceName()
end

function L.enabled(level, owner)
    local threshold = GetConvar('kora_logging_level_' .. owner, GetConvar('kora_logging_level', 'info'))
    return L.levels[level] ~= nil and L.levels[level] >= (L.levels[threshold] or 9)
end

function L.record(level, event, message, fields, owner, realm)
    assert(L.levels[level], 'Unknown logging severity.')
    assert(type(event) == 'string' and #event > 0 and #event <= 128, 'Log event must be 1-128 bytes.')
    assert(type(message) == 'string', 'Log message must be a string.')
    assert(fields == nil or type(fields) == 'table', 'Log fields must be a table or nil.')
    return {
        schemaVersion = 1,
        severity = level,
        severityNumber = L.levels[level],
        resource = L.text(owner, 128),
        realm = realm,
        event = L.text(event, 128),
        message = L.text(message),
        fields = L.copy(fields or {}),
    }
end

function L.encode(record)
    local encoded = json.encode(record)
    local max = L.limit('record_bytes', 4096, 1024, 4096)
    if #encoded > max then
        record.fields = { truncated = true }
        record.message = L.text(record.message, 256)
        encoded = json.encode(record)
    end
    assert(#encoded <= max, 'Log record exceeds byte limit.')
    return encoded
end

-- Until realm startup completes there is no ring/capture state. Shared module
-- diagnostics still render through the same sanitizer and formatter.
function L.write(level, eventName, message, fields, owner, realm)
    if L.writeRecord then
        return L.writeRecord(level, eventName, message, fields, owner, realm)
    end
    if not L.enabled(level, owner) then
        return false
    end
    local record = L.record(level, eventName, message, fields, owner, IsDuplicityVersion() and 'server' or 'client')
    L.render(record, L.encode(record))
    return true
end

local colors = { trace = '8', debug = '5', info = '2', warn = '3', error = '1', fatal = '1' }
function L.render(record, encoded)
    local mode = GetConvar('kora_logging_format', 'pretty')
    if mode == 'json' or mode == 'dual' then
        print('KORA_LOG ' .. encoded)
    end
    if mode ~= 'json' then
        local player = record.playerId and (' player=' .. record.playerId) or ''
        local fields = json.encode(record.fields)
        local capture = record.captureId and (' capture=' .. record.captureId) or ''
        local time = L.clock and record.observedAt and L.clock(record.observedAt) or 'client'
        print(
            ('%s ^%s%-5s^7 [%s/%s%s] %s — %s%s %s'):format(
                time,
                colors[record.severity],
                record.severity:upper(),
                record.resource,
                record.realm,
                player,
                record.event,
                record.message,
                capture,
                fields
            )
        )
    end
    L.emitted = L.emitted + 1
end

function L.safe(fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then
        L.failures = L.failures + 1
        -- Fixed text only: failures may contain the very secrets we were sanitizing.
        if L.failures == 1 or L.failures % 100 == 0 then
            pcall(print, '[kora_lib/logging] log sink/format failure; inspect logging stats')
        end
        return false
    end
    return result
end

---Both realms: check filtering before constructing expensive fields. Does not yield.
---@param level string
---@return boolean
function Kora.logging.isEnabled(level)
    return L.enabled(level, L.owner()) or (L.captureEnabled and L.captureEnabled(level, L.owner()) or false)
end

for level in pairs(L.levels) do
    ---Both realms: emit a diagnostic. Does not yield; fatal never terminates a resource.
    ---@param eventName string
    ---@param message string
    ---@param fields table|nil
    ---@return boolean emitted
    Kora.logging[level] = function(eventName, message, fields)
        local owner = L.owner()
        return L.safe(L.write, level, eventName, message, fields, owner)
    end
end
