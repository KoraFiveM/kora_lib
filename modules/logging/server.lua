local RING = 500
local ring = {}
local head = 0
local counts = {}

local function assertEvent(category, src, data)
    assert(type(category) == 'string' and category ~= '' and #category <= 64,
        'Log category must be a non-empty string of at most 64 bytes.')
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
        category = category, source = src, data = data,
        at = os.time(),
    }
    if #ring < RING then ring[#ring + 1] = entry else ring[head + 1] = entry; head = (head + 1) % RING end
    counts[category] = (counts[category] or 0) + 1

    local url = GetConvar('kora_lib_log_webhook', '')
    if url == '' then url = GetConvar('kora_lib_log_webhook', GetConvar('kora_core_log_webhook', '')) end
    if url ~= '' then
        local resource = GetInvokingResource() or GetCurrentResourceName()
        local encoded, encodedData = pcall(json.encode, data or {})
        if not encoded then
            print(('[kora_lib:logging] webhook payload for %q could not be encoded: %s'):format(category, tostring(encodedData)))
            return
        end
        local content = ('[%s] src=%s %s'):format(category, tostring(src), encodedData)
        if #content > 2000 then content = content:sub(1, 1997) .. '...' end
        local payloadEncoded, payload = pcall(json.encode, {
            username = resource,
            content = content,
            allowed_mentions = { parse = {} },
        })
        if not payloadEncoded then
            print(('[kora_lib:logging] webhook envelope for %q could not be encoded: %s'):format(category, tostring(payload)))
            return
        end
        pcall(PerformHttpRequest, url, function() end, 'POST', payload, { ['Content-Type'] = 'application/json' })
    end
end

---@return table  -- { counts = {category=n}, ringSize = n }
function Kora.logging.getStats()
    local snapshot = {}
    for category, count in pairs(counts) do snapshot[category] = count end
    return { counts = snapshot, ringSize = #ring }
end
