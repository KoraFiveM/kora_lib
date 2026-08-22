-- QB.logging (server realm) -- a lightweight ring-buffered event log with an
-- optional Discord webhook, plus aggregate counters other tooling can read.
-- Framework-agnostic: any resource can call QB.logging.event(...), and
-- webhook messages are attributed to whichever resource actually logged the
-- event rather than to a hardcoded name.

local RING = 500
local ring = {}
local head = 0
local counts = {}   -- category -> count

---Log a gameplay/admin event. category groups them (e.g. 'money', 'job',
---'admin'). data is any table; src is the acting player (0 for system).
---@param category string
---@param src integer
---@param data table|nil
function QB.logging.event(category, src, data)
    local entry = {
        category = category, source = src, data = data,
        at = os.time(),
    }
    if #ring < RING then ring[#ring + 1] = entry else ring[head + 1] = entry; head = (head + 1) % RING end
    counts[category] = (counts[category] or 0) + 1

    -- 'qbcore_log_webhook' is a legacy fallback for servers that already set
    -- it before this module lived in qblib.
    local url = GetConvar('qblib_log_webhook', GetConvar('qbcore_log_webhook', ''))
    if url ~= '' then
        local resource = GetInvokingResource() or GetCurrentResourceName()
        -- Fire-and-forget webhook; never blocks the caller.
        PerformHttpRequest(url, function() end, 'POST', json.encode({
            username = resource,
            content = ('[%s] src=%s %s'):format(category, tostring(src), json.encode(data or {})),
        }), { ['Content-Type'] = 'application/json' })
    end
end

---@return table  -- { counts = {category=n}, ringSize = n }
function QB.logging.getStats()
    return { counts = counts, ringSize = #ring }
end
