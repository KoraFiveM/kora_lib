-- Optional FFT development hooks (client). Loaded by fxmanifest.lua just before
-- build/finalise.lua and inert unless `setr fft_kora_hooks true`.
--
-- Every kora_lib surface (menus, dialogs, AppShell apps, the interact selector,
-- progress bars, notifications, text UI) reaches the browser through
-- Kora.nui.send, so one observer sees them all. Answers go back through the
-- same NUI callbacks the browser uses (request id + token), so the normal
-- handlers, ownership checks and focus leases run. This drives the Lua side of
-- the UI contract: it does not click DOM controls and proves nothing about
-- rendering or browser-side validation.
if GetConvar('fft_kora_hooks', 'false') ~= 'true' then return end

local RUNNER = 'fft'
local VERSION = 2
local MAX_LOG, MAX_NOTIFICATIONS = 200, 50

local function session()
    if GetResourceState(RUNNER) ~= 'started' then return nil end
    local id = LocalPlayer.state.fftSession
    return type(id) == 'string' and id or nil
end

local sequence = 0
local log, notifications = {}, {}
local requests = {}  -- [action] = newest pending request sent with that action
local interact, progress, textui

-- Bounded, JSON-safe copy: functions and deep or huge values never leave the VM.
local function summary(value, depth)
    depth = depth or 0
    local kind = type(value)
    if kind == 'string' then return #value > 300 and (value:sub(1, 300) .. '...') or value end
    if kind == 'number' or kind == 'boolean' or value == nil then return value end
    if kind ~= 'table' then return '<' .. kind .. '>' end
    if depth >= 5 then return '<table>' end
    local out, count = {}, 0
    for key, item in pairs(value) do
        count = count + 1
        if count > 40 then out['...'] = 'truncated' break end
        out[type(key) == 'number' and key or tostring(key)] = summary(item, depth + 1)
    end
    return out
end

local function observe(action, data)
    if not session() then return end
    sequence = sequence + 1
    local entry = { seq = sequence, t = GetGameTimer(), action = action, data = summary(data) }
    log[#log + 1] = entry
    if #log > MAX_LOG then table.remove(log, 1) end

    if type(data) == 'table' and data.requestId ~= nil and type(data.token) == 'string' then
        if action == 'cancelNuiRequest' then
            for name, request in pairs(requests) do
                if request.requestId == data.requestId then requests[name] = nil end
            end
        else
            requests[action] = { requestId = data.requestId, token = data.token, payload = data.payload, seq = sequence }
        end
    end
    if action == 'closeApp' then requests.openApp = nil end
    if action == 'openInteract' then interact = data
    elseif action == 'hideInteract' then interact = nil
    elseif action == 'progressStart' then progress = { label = data and data.label, duration = data and data.duration, t = entry.t }
    elseif action == 'progressCancel' then progress = nil
    elseif action == 'textui:set' then textui = data or nil
    elseif action == 'notify' and type(data) == 'table' then
        notifications[#notifications + 1] = { seq = sequence, title = data.title, message = data.message, type = data.type }
        if #notifications > MAX_NOTIFICATIONS then table.remove(notifications, 1) end
    end
end

local originalSend = Kora.nui.send
Kora.nui.send = function(action, data)
    local ok, err = pcall(observe, action, data)
    if not ok then print('[kora_lib:fft] observer failed: ' .. tostring(err)) end
    return originalSend(action, data)
end

-- Config.third_party_notify bypasses Kora.nui.send.
AddEventHandler('kora_lib:notify:send', function(payload)
    if type(payload) == 'table' then pcall(observe, 'notify', payload) end
end)

-- The browser (or a tester's own click) may settle a request first; forget it
-- so state() never reports a surface that has already closed.
AddEventHandler('__cfx_nui:kora_lib:nui:response', function(data)
    if type(data) ~= 'table' then return end
    for name, request in pairs(requests) do
        if request.requestId == data.requestId and request.token == data.token then requests[name] = nil end
    end
end)

-- Runs a registered NUI callback with the body the browser's fetch would send.
-- Callbacks registered through Kora.nui.registerCallback are called directly:
-- a script-fired `__cfx_nui:` event is not answered on current FiveM clients.
local function nui(name, body)
    local handler = Kora.compat and Kora.compat.nuiCallbacks and Kora.compat.nuiCallbacks[name]
    if handler then
        local ok, result = pcall(handler, body)
        if not ok then return false, ('NUI callback %s errored: %s'):format(name, tostring(result)) end
        return true, result == nil and {} or result
    end
    local answered, result = false, nil
    TriggerEvent('__cfx_nui:' .. name, body, function(value) answered, result = true, value end)
    local deadline = GetGameTimer() + 5000
    while not answered and GetGameTimer() < deadline do Wait(0) end
    if not answered then return false, 'NUI callback did not answer: ' .. name end
    return true, result
end

local function pending(action)
    local request = requests[action]
    if not request then return nil, 'No pending ' .. action .. ' request' end
    return request
end

-- Settles a pending request with the browser's own response message, then tells
-- the browser to drop its copy so the surface closes.
local function respond(action, result)
    local request, err = pending(action)
    if not request then return false, err end
    requests[action] = nil
    local ok, why = nui('kora_lib:nui:response', { requestId = request.requestId, token = request.token, ok = true, result = result })
    originalSend('cancelNuiRequest', { requestId = request.requestId, token = request.token })
    return ok, why
end

local MENUS = { 'openMenu', 'openContextMenu', 'openRadialMenu' }
local function openMenu()
    local newest, name
    for _, action in ipairs(MENUS) do
        local request = requests[action]
        if request and (not newest or request.seq > newest.seq) then newest, name = request, action end
    end
    return newest, name
end

local function findItem(items, wanted, path)
    for _, item in ipairs(type(items) == 'table' and items or {}) do
        local here = { table.unpack(path) }
        here[#here + 1] = item.id
        if item.id == wanted or item.label == wanted then return item, here end
        if item.submenu then
            local found, deeper = findItem(item.submenu.items, wanted, here)
            if found then return found, deeper end
        end
    end
end

local function menuItems(items, out, prefix)
    for _, item in ipairs(type(items) == 'table' and items or {}) do
        out[#out + 1] = { id = item.id, label = item.label, path = prefix .. item.label, disabled = item.disabled == true,
            description = item.description, submenu = item.submenu ~= nil }
        if item.submenu then menuItems(item.submenu.items, out, prefix .. item.label .. ' > ') end
    end
    return out
end

local actions = {}

function actions.state()
    local menu, menuAction = openMenu()
    local app = requests.openApp
    local input, alert = requests.openInputDialog, requests.openAlert
    return {
        interact = interact and summary(interact) or nil,
        interactActive = Kora.interact.isActive(),
        menu = menu and { kind = menuAction, title = menu.payload and menu.payload.title,
            items = menuItems(menu.payload and menu.payload.items, {}, '') } or nil,
        input = input and { title = input.payload.title, fields = summary(input.payload.fields) } or nil,
        alert = alert and summary(alert.payload) or nil,
        app = app and { id = app.payload.app and app.payload.app.id, viewId = app.payload.viewId, tabId = app.payload.tabId } or nil,
        progress = Kora.progressbar.isActive() and (progress or {}) or nil,
        textui = textui and summary(textui) or nil,
        minigame = requests['minigames:round'] and summary(requests['minigames:round'].payload) or nil,
        sequence = sequence,
    }
end

function actions.log(since)
    local out = {}
    for _, entry in ipairs(log) do if entry.seq > (tonumber(since) or 0) then out[#out + 1] = entry end end
    return out
end

function actions.notifications(since)
    local out = {}
    for _, entry in ipairs(notifications) do if entry.seq > (tonumber(since) or 0) then out[#out + 1] = entry end end
    return out
end

function actions.app()
    local app = requests.openApp
    if not app then return false, 'No app is open' end
    return summary(app.payload, -3)
end

actions['interact.select'] = function(label)
    if not interact or not Kora.interact.isActive() then return false, 'Interact selector is not open', 'not_open' end
    local matches = {}
    for index, option in ipairs(interact) do if option.label == label then matches[#matches + 1] = index end end
    if #matches ~= 1 then return false, ('Expected one interact option named %s; found %d'):format(tostring(label), #matches), 'not_visible' end
    return nui('selectOption', matches[1])
end

-- Nothing to close is a success: the callback is only registered once the
-- selector has been shown, and waiting for an unregistered one stalls cleanups.
actions['interact.close'] = function()
    if not Kora.interact.isActive() then return true end
    return nui('closeInteract', {})
end

actions['menu.select'] = function(wanted)
    local menu, action = openMenu()
    if not menu then return false, 'No menu is open', 'not_open' end
    local item, path = findItem(menu.payload.items, wanted, {})
    if not item then return false, 'Menu has no item ' .. tostring(wanted), 'not_visible' end
    if item.disabled then return false, 'Menu item is disabled: ' .. tostring(wanted), 'disabled' end
    if item.submenu then return false, 'Menu item opens a submenu; select one of its entries', 'submenu' end
    return respond(action, { selectedId = item.id, path = path })
end

actions['menu.cancel'] = function()
    local menu, action = openMenu()
    if not menu then return false, 'No menu is open', 'not_open' end
    if menu.payload.canClose == false then return false, 'Menu cannot be closed', 'locked' end
    return respond(action, { cancelled = true })
end

actions['alert.answer'] = function(confirmed)
    local alert = requests.openAlert
    if not alert then return false, 'No alert is open', 'not_open' end
    if confirmed ~= true and alert.payload.cancellable == false then return false, 'Alert cannot be cancelled', 'locked' end
    return respond('openAlert', { confirmed = confirmed == true })
end

actions['input.submit'] = function(values)
    local input = requests.openInputDialog
    if not input then return false, 'No input dialog is open', 'not_open' end
    if type(values) ~= 'table' then return false, 'Input values must be a table' end
    local known = {}
    for _, field in ipairs(input.payload.fields or {}) do
        if field.id then known[field.id] = field end
    end
    for key in pairs(values) do
        if not known[key] then return false, 'Input dialog has no field ' .. tostring(key), 'not_visible' end
    end
    for key, field in pairs(known) do
        if field.required and (values[key] == nil or values[key] == '') then
            return false, 'Required field is empty: ' .. tostring(key), 'invalid'
        end
    end
    return respond('openInputDialog', { values = values })
end

actions['input.cancel'] = function()
    if not requests.openInputDialog then return false, 'No input dialog is open', 'not_open' end
    return respond('openInputDialog', { cancelled = true })
end

actions['app.action'] = function(actionId, context)
    local app = requests.openApp
    if not app then return false, 'No app is open', 'not_open' end
    context = type(context) == 'table' and context or {}
    local ok, result = nui('kora_lib:app:action', { appId = app.payload.app.id, token = app.token, actionId = actionId,
        viewId = context.viewId or app.payload.viewId, tabId = context.tabId or app.payload.tabId,
        itemId = context.itemId, value = context.value })
    if not ok then return false, result end
    if type(result) == 'table' and result.ok == false then return false, result.error or 'App action rejected', 'rejected' end
    -- closeBeforeAction settles the request inside kora_lib; forget our copy.
    -- kora_lib answers { ok = true, result = <the app's own result> }; hand back
    -- the app's result so steps read notice/app/navigate directly.
    if type(result) == 'table' and result.ok == true and type(result.result) == 'table' then result = result.result end
    -- An action that answers `close = true` is closed by the browser
    -- (AppShell.tsx: `if (response.result?.close) close("action")`), which
    -- settles the openApp request. No browser reads this answer, so do the same.
    if type(result) == 'table' and result.close == true and requests.openApp == app then
        respond('openApp', { closed = true, reason = 'action', viewId = app.payload.viewId, tabId = app.payload.tabId })
    end
    return true, summary(result)
end

-- Cancels whatever progress bar is running, as its owner would. Used between
-- scenarios so a bar left by a timed-out step does not block the next one.
actions['progress.cancel'] = function()
    local owner = Kora.compat and Kora.compat.progressOwner and Kora.compat.progressOwner()
    if not owner then return true end
    return Kora.progressbar.cancel(owner)
end

actions['app.close'] = function()
    if not requests.openApp then return false, 'No app is open', 'not_open' end
    return respond('openApp', { closed = true, reason = 'close' })
end

local function action(name, ...)
    if GetInvokingResource() ~= RUNNER or not session() then
        return false, 'FFT hooks are disabled or session is not authorised'
    end
    local handler = actions[name]
    if not handler then return false, 'Unsupported kora_lib FFT action: ' .. tostring(name) end
    return handler(...)
end

-- Registered directly, not on a Kora module: build/finalise.lua must not turn
-- test hooks into part of the consumer-facing export surface.
exports('fftVersion', function() return VERSION end)
exports('fftAction', action)

AddStateBagChangeHandler('fftSession', nil, function(bag, _, value)
    if bag ~= ('player:%s'):format(GetPlayerServerId(PlayerId())) or type(value) == 'string' then return end
    log, notifications, requests, interact, progress, textui = {}, {}, {}, nil, nil, nil
end)
