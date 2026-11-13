-- Consumer-local NUI transport. Include as a client_script after @kora_lib/init.lua.
-- NUI callbacks must live in the page-owning resource, not the library's frame.
local budget, at = 40, GetGameTimer()
local function allowed()
    local now = GetGameTimer()
    budget = math.min(40, budget + math.max(0, now - at) * 0.02)
    at = now
    if budget < 1 then
        return false
    end
    budget = budget - 1
    return true
end
local function state()
    local ok, value = pcall(function()
        return Kora.logging.getCapture()
    end)
    return ok and value or { enabled = false, localLevel = 'info' }
end
RegisterNUICallback('kora_logging', function(data, cb)
    if not allowed() or type(data) ~= 'table' then
        cb({ ok = false })
        return
    end
    if data.action == 'ready' then
        cb(state())
        return
    end
    -- Serialize only a bounded shape; browser data is not trusted.
    if
        type(data.level) ~= 'string'
        or type(data.event) ~= 'string'
        or #data.event > 128
        or type(data.message) ~= 'string'
        or #data.message > 2048
    then
        cb({ ok = false })
        return
    end
    local ok, result = pcall(function()
        return Kora.logging.nui(data.level, data.event, data.message, data.fields)
    end)
    cb({ ok = ok and result == true })
end)
local function sendState()
    SendNUIMessage({ action = 'kora_logging:state', data = state() })
end
AddEventHandler('kora_lib:logging:state', sendState)
AddEventHandler('kora_lib:client:updated', sendState)
AddEventHandler('onClientResourceStop', function(name)
    if name == 'kora_lib' then
        SendNUIMessage({ action = 'kora_logging:state', data = { enabled = false } })
    end
end)
