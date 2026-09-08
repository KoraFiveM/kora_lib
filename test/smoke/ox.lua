local harness = dofile('test/harness.lua')

QB = {
    ox = {}, nui = {}, notify = {}, progressbar = {}, minigames = {}, textui = {},
    locale = {}, stream = {}, controls = {}, compat = {},
}

function QB.compat.isCallable(value)
    if type(value) == 'function' then return true end
    local metatable = type(value) == 'table' and getmetatable(value)
    return type(metatable) == 'table' and type(metatable.__call) == 'function'
end

local requests = {}
local responses = {}
local cancellations = {}
local notifications = {}
local progressCalls = {}
local minigameCalls = {}
local textEntries = {}
local triggered = {}
local triggeredServer = {}
local focusKeep = {}
local commands = {}
local nuiCallbacks = {}
local nuiMessages = {}
local nextText = 0
local progressActive = false
local providerActiveDuringProgress = false
local locale = 'en'

local function queue(action, result)
    responses[action] = responses[action] or {}
    responses[action][#responses[action] + 1] = result
end

local function lastRequest(action)
    for index = #requests, 1, -1 do
        if requests[index].action == action then return requests[index] end
    end
end

function QB.nui.requestAsync(action, payload, timeout, owner, focused, onEvent)
    local pending = responses[action] or {}
    local result = table.remove(pending, 1)
    local request = {
        action = action,
        payload = payload,
        timeout = timeout,
        owner = owner,
        focused = focused,
        onEvent = onEvent,
        result = result,
    }
    if type(result) == 'function' then request.result = result(request) end
    requests[#requests + 1] = request
    return request
end

function QB.nui.send(action, payload)
    nuiMessages[#nuiMessages + 1] = { action = action, payload = payload }
    if action == 'notify' then notifications[#notifications + 1] = payload end
end

function QB.nui.registerCallback(name, callback)
    nuiCallbacks[name] = callback
end

function QB.nui.cancelRequest(request, result, rejection)
    cancellations[#cancellations + 1] = { request = request, result = result, rejection = rejection }
    return true
end

function QB.nui.updateRequest(request, action, payload)
    requests[#requests + 1] = { action = action, request = request, payload = payload }
    return true
end

function QB.nui.acquireFocus(mouse, cursor, keepInput, owner)
    local released = false
    requests[#requests + 1] = { action = 'focus', mouse = mouse, cursor = cursor, keepInput = keepInput, owner = owner }
    return function()
        released = true
        requests[#requests + 1] = { action = 'focusRelease', owner = owner }
    end
end

function QB.progressbar.isActive() return progressActive end
function QB.progressbar.start(payload, owner)
    progressCalls[#progressCalls + 1] = { payload = payload, owner = owner }
    providerActiveDuringProgress = QB.ox.progressActive(owner)
    progressActive = false
    return true
end
function QB.progressbar.cancel() progressActive = false return true end
function QB.minigames.playAsync(kind, options, authorization, owner)
    minigameCalls[#minigameCalls + 1] = { kind = kind, options = options, authorization = authorization, owner = owner }
    return { result = { success = true } }
end
function QB.minigames.cancel(owner) minigameCalls[#minigameCalls + 1] = { cancel = owner } return true end
function QB.textui.show(text, options, owner)
    nextText = nextText + 1
    textEntries[nextText] = { text = text, options = options, owner = owner }
    return nextText
end
function QB.textui.hide(id) textEntries[id] = nil return true end
function QB.controls.acquire(ids, options)
    requests[#requests + 1] = { action = 'controls', ids = ids, options = options }
    return #requests
end
function QB.controls.release(lease)
    requests[#requests + 1] = { action = 'controlsRelease', lease = lease }
    return true
end
function QB.locale.getLanguage() return locale end
function QB.locale.setLanguage(value) locale = value return true end
function QB.stream.loadAudioBank(_, callback) callback() return true end

Citizen = { Await = function(value)
    local scripted = value.result
    if value.onEvent and type(scripted) == 'table' and scripted.events then
        for index = 1, #scripted.events do
            local event = scripted.events[index]
            value.onEvent(event.name, event.data)
        end
    end
    if type(scripted) == 'table' and scripted.terminal ~= nil then return scripted.terminal end
    return scripted
end }
function CreateThread(callback) callback() end
function Wait() end
function SetTimeout() end
function RegisterCommand(name, callback) commands[name] = callback end
function RegisterKeyMapping() end
function GetConvarInt(name, default) return name == 'ox:progressPropLimit' and 2 or default end
function GetCurrentResourceName() return 'qblib' end
function GetLocalTime() return 2026, 9, 8, 12, 0, 0 end
function IsNuiFocused() return false end
function IsPauseMenuActive() return false end
function SetCursorLocation() end
function TriggerEvent(name, ...) triggered[#triggered + 1] = { name = name, ... } end
function TriggerServerEvent(name, ...) triggeredServer[#triggeredServer + 1] = { name = name, ... } end

exports = setmetatable({}, {
    __index = function(_, resource)
        return setmetatable({}, {
            __index = function(_, name)
                return function(_, ...)
                    triggered[#triggered + 1] = { name = ('export:%s:%s'):format(resource, name), ... }
                end
            end,
        })
    end,
})

dofile('modules/ox/shared.lua')
dofile('modules/ox/client.lua')

harness.test('provider exposes every function forwarded by the ox_lib shim', function()
    local names = {
        'alertDialog', 'closeAlertDialog', 'setClipboard', 'showContext', 'registerContext',
        'getOpenContextMenu', 'hideContext', 'inputDialog', 'closeInputDialog', 'setNuiFocus',
        'resetNuiFocus', 'registerMenu', 'showMenu', 'hideMenu', 'setMenuOptions', 'getOpenMenu',
        'notify', 'defaultNotify', 'progressBar', 'progressCircle', 'cancelProgress', 'progressActive',
        'registerRadial', 'getCurrentRadialId', 'hideRadial', 'addRadialItem', 'removeRadialItem',
        'clearRadialItems', 'disableRadial', 'showRadialMenu', 'skillCheck', 'cancelSkillCheck',
        'skillCheckActive', 'showTextUI', 'hideTextUI', 'isTextUIOpen', 'setLocale', 'disposeOwner',
    }
    for index = 1, #names do
        harness.assertEqual(type(QB.ox[names[index]]), 'function', ('QB.ox.%s must exist'):format(names[index]))
    end
end)

harness.test('alert translates fields and returns ox confirmation vocabulary', function()
    queue('openAlert', { confirmed = true })
    local result = QB.ox.alertDialog({
        header = 'Delete?', content = 'This cannot be undone.', cancel = true,
        centered = true, size = 'lg', overflow = true,
        labels = { confirm = 'Delete', cancel = 'Keep' },
    }, 4000, 'shop')
    harness.assertEqual(result, 'confirm')
    local call = requests[#requests]
    harness.assertEqual(call.action, 'openAlert')
    harness.assertEqual(call.owner, 'shop')
    harness.assertEqual(call.timeout, false)
    harness.assertEqual(call.payload.title, 'Delete?')
    harness.assertEqual(call.payload.message, 'This cannot be undone.')
    harness.assertEqual(call.payload.confirmLabel, 'Delete')
    harness.assertTrue(call.payload.cancellable)
    harness.assertTrue(call.payload.showCancel)
    harness.assertFalse(call.payload.showClose)
    harness.assertFalse(call.payload.dismissOnBackdrop)
    harness.assertTrue(call.payload.centered)
    harness.assertEqual(call.payload.size, 'lg')
    harness.assertTrue(call.payload.overflow)
end)

harness.test('clipboard keeps the consumer owner and avoids focus', function()
    queue('copyToClipboard', true)
    QB.ox.setClipboard('hello', 'notes')
    local call = requests[#requests]
    harness.assertEqual(call.action, 'copyToClipboard')
    harness.assertEqual(call.payload.text, 'hello')
    harness.assertEqual(call.owner, 'notes')
    harness.assertFalse(call.focused)
    harness.assertEqual(QB.ox.setClipboard(false, 'notes'), nil)
    harness.assertEqual(requests[#requests], call)
end)

harness.test('context selection dispatches callbacks, local events, and server events', function()
    local selected
    QB.ox.registerContext({
        id = 'actions', title = 'Actions', options = {
            { title = 'Use', description = 'Use it', onSelect = function(args) selected = args.id end, args = { id = 7 } },
        },
    }, 'context_owner')
    queue('openMenu', { selectedId = '__ox_context_1' })
    QB.ox.showContext('actions', 'context_owner')
    harness.assertEqual(selected, 7)

    QB.ox.registerContext({ id = 'events', title = 'Events', options = {
        fire = { title = 'Fire', event = 'local:event', serverEvent = 'server:event', args = 9 },
    } }, 'context_owner')
    queue('openMenu', { selectedId = '__ox_context_1' })
    QB.ox.showContext('events', 'context_owner')
    harness.assertEqual(triggered[#triggered].name, 'local:event')
    harness.assertEqual(triggeredServer[#triggeredServer].name, 'server:event')
end)

harness.test('input maps the complete ox row set and returns a positional array', function()
    queue('openInputDialog', { values = {
        ['1'] = 'Ada', ['2'] = 42, ['3'] = true, ['4'] = 'a', ['5'] = 75,
        ['6'] = { 'a', 'b' }, ['7'] = 1704067200000, ['8'] = { 1704067200000, 1704153600000 },
        ['9'] = '12:30', ['10'] = 'notes', ['11'] = '#ffffff',
    } })
    local values = QB.ox.inputDialog('All inputs', {
        'Name',
        { type = 'number', label = 'Age', min = 1, max = 100, precision = 2 },
        { type = 'checkbox', label = 'Enabled', checked = true },
        { type = 'select', label = 'One', options = { { value = 'a', label = 'A' } } },
        { type = 'slider', label = 'Level', min = 0, max = 100 },
        { type = 'multi-select', label = 'Many', options = { { value = 'a', label = 'A' } } },
        { type = 'date', label = 'Date', format = 'DD/MM/YYYY', returnString = true, default = true, min = '01/01/2000' },
        { type = 'date-range', label = 'Range' },
        { type = 'time', label = 'Time', format = '12', clearable = true },
        { type = 'textarea', label = 'Notes', autosize = true, min = 2, max = 5, icon = { 'far', 'note-sticky' } },
        { type = 'color', label = 'Colour', format = 'rgba' },
    }, { size = 'xl' }, 'forms')
    harness.assertEqual(values[1], 'Ada')
    harness.assertEqual(values[11], '#ffffff')
    local call = requests[#requests]
    harness.assertEqual(call.payload.fields[1].type, 'text')
    harness.assertEqual(call.payload.fields[5].type, 'range')
    harness.assertEqual(call.payload.fields[6].type, 'multiselect')
    harness.assertEqual(call.payload.fields[8].type, 'date-range')
    harness.assertTrue(call.payload.fields[7].returnString)
    harness.assertFalse(call.payload.fields[8].returnString)
    harness.assertEqual(call.payload.fields[7].dateFormat, 'DD/MM/YYYY')
    harness.assertEqual(call.payload.fields[7].default, true)
    harness.assertEqual(call.payload.fields[7].dateMin, '01/01/2000')
    harness.assertEqual(call.payload.fields[2].precision, 2)
    harness.assertEqual(call.payload.fields[9].timeFormat, '12')
    harness.assertTrue(call.payload.fields[10].autosize)
    harness.assertEqual(call.payload.fields[10].minRows, 2)
    harness.assertEqual(call.payload.fields[10].maxRows, 5)
    harness.assertEqual(call.payload.fields[10].icon, 'far:note-sticky')
    harness.assertEqual(call.payload.fields[11].colorFormat, 'rgba')
    harness.assertEqual(call.payload.size, 'xl')
    harness.assertFalse(call.payload.dismissOnBackdrop)
end)

harness.test('actionless context rows stay open instead of dismissing the surface', function()
    QB.ox.registerContext({ id = 'information', title = 'Information', options = {
        {
            title = 'Read only detail',
            metadata = { status = 'Ready' },
            readOnly = true,
            arrow = false,
            icon = { 'fal', 'coffee' },
        },
    } }, 'context_owner')
    queue('openMenu', { cancelled = true })
    QB.ox.showContext('information', 'context_owner')
    local call = lastRequest('openMenu')
    harness.assertFalse(call.payload.items[1].close)
    harness.assertEqual(call.payload.position.horizontal, 'right')
    harness.assertEqual(call.payload.position.vertical, 'top')
    harness.assertEqual(call.payload.presentation, 'panel')
    harness.assertTrue(call.payload.items[1].readOnly)
    harness.assertFalse(call.payload.items[1].arrow)
    harness.assertEqual(call.payload.items[1].icon, 'fal:coffee')
    harness.assertEqual(call.payload.items[1].metadata[1].label, 'status')
    harness.assertEqual(call.payload.items[1].metadata[1].value, 'Ready')
end)

harness.test('context submenu and back navigation update one mounted panel in place', function()
    local backed = 0
    QB.ox.registerContext({
        {
            id = 'context_parent',
            title = 'Parent',
            options = { { title = 'Open child', menu = 'context_child' } },
        },
        { id = 'context_child', title = 'Child', menu = 'context_parent', onBack = function() backed = backed + 1 end,
            options = { { title = 'Child action' } } },
    }, 'context_owner')
    local previousRequests = #requests
    queue('openMenu', {
        events = {
            { name = 'confirmed', data = { selectedId = '__ox_context_1' } },
            { name = 'back', data = {} },
        },
        terminal = { cancelled = true },
    })
    QB.ox.showContext('context_parent', 'context_owner')
    harness.assertEqual(backed, 1)
    local opened, updated = 0, 0
    for index = previousRequests + 1, #requests do
        local call = requests[index]
        if call.action == 'openMenu' then opened = opened + 1 end
        if call.action == 'updateMenu' then updated = updated + 1 end
    end
    harness.assertEqual(opened, 1)
    harness.assertEqual(updated, 2)
    local parent = lastRequest('updateMenu')
    harness.assertEqual(parent.payload.title, 'Parent')
    harness.assertFalse(parent.payload.back == true)
    harness.assertEqual(#parent.payload.items, 1)
    harness.assertEqual(parent.payload.items[1].label, 'Open child')
    harness.assertFalse(parent.payload.items[1].close)
end)

harness.test('explicit focus uses an owner lease with composed keep-input state', function()
    QB.ox.setNuiFocus(true, true, 'focus_owner')
    local call = requests[#requests]
    harness.assertEqual(call.action, 'focus')
    harness.assertTrue(call.mouse)
    harness.assertFalse(call.cursor)
    harness.assertTrue(call.keepInput)
    harness.assertEqual(call.owner, 'focus_owner')
    QB.ox.resetNuiFocus('focus_owner')
    harness.assertEqual(requests[#requests].action, 'focusRelease')
end)

harness.test('registered menu invokes the exact positional callback contract', function()
    local callbackArgs
    local live = {}
    QB.ox.registerMenu({
        id = 'shop', title = 'Shop', position = 'top-right', options = {
            { label = 'Buy', values = { 'One', 'Two' }, defaultIndex = 2, args = { item = 'water' }, close = false },
        },
        onSelected = function(...) live.selected = { ... } end,
        onSideScroll = function(...) live.sideScroll = { ... } end,
    }, function(...) callbackArgs = { ... } end, 'menu_owner')
    queue('openMenu', {
        events = {
            { name = 'selected', data = { selectedId = '__ox_menu_1', valueIndex = 2 } },
            { name = 'sideScroll', data = { selectedId = '__ox_menu_1', valueIndex = 1 } },
            { name = 'confirmed', data = { selectedId = '__ox_menu_1', valueIndex = 1 } },
        },
        terminal = { cancelled = true, keyPressed = 'Escape' },
    })
    QB.ox.showMenu('shop', 1, 'menu_owner')
    harness.assertEqual(callbackArgs[1], 1)
    harness.assertEqual(callbackArgs[2], 1)
    harness.assertEqual(callbackArgs[3].item, 'water')
    harness.assertEqual(live.selected[2], 2)
    harness.assertTrue(live.selected[3].isScroll)
    harness.assertEqual(live.sideScroll[2], 1)
    local call = lastRequest('openMenu')
    harness.assertEqual(call.payload.position.horizontal, 'right')
    harness.assertEqual(call.payload.position.vertical, 'top')
    harness.assertEqual(call.payload.items[1].defaultIndex, 2)
    harness.assertFalse(call.payload.items[1].close)
    harness.assertEqual(call.payload.presentation, 'panel')
    harness.assertTrue(lastRequest('focus').keepInput)

    QB.ox.registerMenu({ id = 'default_position', title = 'Default', options = { { label = 'Close' } } }, nil, 'menu_owner')
    queue('openMenu', { cancelled = true })
    QB.ox.showMenu('default_position', nil, 'menu_owner')
    local defaultCall = lastRequest('openMenu')
    harness.assertEqual(defaultCall.payload.position.horizontal, 'left')
    harness.assertEqual(defaultCall.payload.position.vertical, 'top')

    local uncheckedSelection
    QB.ox.registerMenu({
        id = 'unchecked', title = 'Unchecked', options = { { label = 'Toggle', checked = false } },
        onSelected = function(...) uncheckedSelection = { ... } end,
    }, nil, 'menu_owner')
    queue('openMenu', {
        events = { { name = 'selected', data = { selectedId = '__ox_menu_1', checked = false } } },
        terminal = { cancelled = true },
    })
    QB.ox.showMenu('unchecked', nil, 'menu_owner')
    harness.assertEqual(uncheckedSelection[1], 1)
    harness.assertEqual(uncheckedSelection[2], nil)
    harness.assertEqual(uncheckedSelection[3].isCheck, nil)
end)

harness.test('notifications normalize ox fields without mutating the source', function()
    local source = {
        id = 42,
        title = 'Saved',
        description = 'Done',
        type = 'inform',
        position = 'top',
        icon = { 'fas', 'check' },
        iconAnimation = 'beat',
        alignIcon = 'top',
        style = { color = 'red', ['& .description'] = { color = 'blue' } },
    }
    QB.ox.notify(source, 'notify_owner')
    local payload = notifications[#notifications]
    harness.assertEqual(payload.message, 'Done')
    harness.assertEqual(payload.type, 'info')
    harness.assertEqual(payload.position, 'top')
    harness.assertEqual(payload.icon, 'fas:check')
    harness.assertEqual(payload.id, '42')
    harness.assertEqual(payload.duration, 3000)
    harness.assertEqual(payload.iconAnimation, 'beat')
    harness.assertEqual(payload.alignIcon, 'top')
    harness.assertEqual(payload.style['& .description'].color, 'blue')
    harness.assertEqual(source.type, 'inform')
end)

harness.test('progress translates props, scenarios, controls, and owner', function()
    local completed = QB.ox.progressCircle({
        label = 'Working', duration = 1000, position = 'bottom', canCancel = true,
        anim = { scenario = 'WORLD_HUMAN_HAMMERING' },
        prop = { model = 'prop_tool_hammer', bone = 60309, pos = { x = 1, y = 2, z = 3 }, rot = { x = 4, y = 5, z = 6 } },
        disable = { move = true, sprint = true, mouse = true },
        allowRagdoll = true,
    }, 'progress_owner')
    harness.assertTrue(completed)
    harness.assertTrue(providerActiveDuringProgress)
    local call = progressCalls[#progressCalls]
    harness.assertEqual(call.owner, 'progress_owner')
    harness.assertEqual(call.payload.presentation, 'circle')
    harness.assertEqual(call.payload.maxProps, false)
    harness.assertEqual(call.payload.maxDuration, false)
    harness.assertFalse(call.payload.cancelControls)
    harness.assertTrue(call.payload.strictAnim == false)
    harness.assertEqual(call.payload.disable.moveMode, 'controls')
    harness.assertEqual(call.payload.disable.controlProfile, 'ox')
    harness.assertEqual(call.payload.scenario.name, 'WORLD_HUMAN_HAMMERING')
    harness.assertEqual(call.payload.props[1].offset.y, 2)
    harness.assertTrue(call.payload.disable.sprint)

    QB.ox.progressBar({
        label = 'Animating', duration = 500,
        anim = { dict = 'anim@amb@business@weed@weed_inspecting_lo_med_hi@', clip = 'weed_spraybottle_crouch_base_inspector' },
    }, 'progress_owner')
    local animCall = progressCalls[#progressCalls]
    harness.assertTrue(animCall.payload.strictAnim)
    harness.assertEqual(animCall.payload.anim.flag, 49)
    harness.assertEqual(animCall.payload.anim.blendIn, 3.0)
    harness.assertEqual(animCall.payload.anim.blendOut, 1.0)
    harness.assertEqual(animCall.payload.anim.stopBlendOut, 1.0)

    QB.ox.progressBar({
        label = 'Limited props',
        duration = 500,
        prop = {
            { model = 'prop_one' },
            { model = 'prop_two' },
            { model = 'prop_three' },
        },
    }, 'progress_owner')
    local propCall = progressCalls[#progressCalls]
    harness.assertEqual(#propCall.payload.props, 2)
    harness.assertEqual(propCall.payload.props[1].model, 'prop_one')
    harness.assertEqual(propCall.payload.props[2].model, 'prop_two')

    progressActive = true
    harness.assertFalse(QB.ox.progressActive('progress_owner'))
    harness.assertThrows(function() QB.ox.cancelProgress('progress_owner') end)
    progressActive = false
end)

harness.test('radial resolves registered submenus and invokes selection callback', function()
    local selection, openedFrom
    QB.ox.registerRadial({ id = 'doors', items = {
        { label = 'Lock', onSelect = function(menu, index) selection = { menu, index } end },
    } }, 'radial_owner')
    QB.ox.registerRadial({ id = 'vehicle', items = {
        { label = 'Doors', menu = 'doors', onSelect = function(menu, index)
            openedFrom = { menu, index, QB.ox.getCurrentRadialId('radial_owner') }
        end },
    } }, 'radial_owner')
    queue('openRadialMenu', function(request)
        local parent = request.payload.items[1]
        return {
            events = {
                { name = 'radialLevel', data = { path = { parent.id } } },
            },
            terminal = { selectedId = parent.submenu.items[1].id },
        }
    end)
    QB.ox.showRadialMenu('vehicle', 'radial_owner')
    harness.assertEqual(openedFrom[1], 'vehicle')
    harness.assertEqual(openedFrom[2], 1)
    harness.assertEqual(openedFrom[3], 'doors')
    harness.assertEqual(selection[1], 'doors')
    harness.assertEqual(selection[2], 1)
end)

harness.test('keep-open radial choices stay mounted and live registry changes refresh in place', function()
    local selected = 0
    QB.ox.registerRadial({ id = 'live_radial', items = {
        { label = 'Refresh', keepOpen = true, onSelect = function()
            selected = selected + 1
            QB.ox.addRadialItem({ id = 'added', label = 'Added' }, 'live_radial', 'radial_owner')
        end },
    } }, 'radial_owner')
    queue('openRadialMenu', function(request)
        local id = request.payload.items[1].id
        return {
            events = {
                { name = 'confirmed', data = { selectedId = id, path = { id } } },
            },
            terminal = { cancelled = true },
        }
    end)
    QB.ox.showRadialMenu('live_radial', 'radial_owner')
    harness.assertEqual(selected, 1)
    local refresh = lastRequest('updateRadialMenu')
    harness.assertEqual(#refresh.payload.items, 2)
    harness.assertFalse(refresh.payload.items[1].close)
end)

harness.test('owner disposal removes radial items nested under another consumer without mutating inputs', function()
    local transient = { id = 'transient', label = 'Transient' }
    QB.ox.registerRadial({ id = 'shared_radial', items = {
        { id = 'base', label = 'Base' },
    } }, 'base_owner')
    QB.ox.addRadialItem(transient, 'shared_radial', 'temporary_owner')
    harness.assertEqual(transient.__oxOwner, nil)
    QB.ox.disposeOwner('temporary_owner')

    queue('openRadialMenu', { cancelled = true })
    QB.ox.showRadialMenu('shared_radial', 'base_owner')
    local request = lastRequest('openRadialMenu')
    harness.assertEqual(#request.payload.items, 1)
    harness.assertEqual(request.payload.items[1].label, 'Base')
end)

harness.test('registered radial string callbacks execute against the menu resource', function()
    QB.ox.registerRadial({ id = 'owned_submenu', items = {
        { id = 'base_callback', label = 'Base' },
    } }, 'menu_resource')
    QB.ox.addRadialItem({ id = 'foreign_callback', label = 'Foreign', onSelect = 'selectForeign' }, 'owned_submenu', 'adding_resource')
    queue('openRadialMenu', function(request)
        return { selectedId = request.payload.items[2].id }
    end)
    QB.ox.showRadialMenu('owned_submenu', 'opening_resource')
    harness.assertEqual(triggered[#triggered].name, 'export:menu_resource:selectForeign')
end)

harness.test('skillCheck sends the complete stage sequence to one local NUI session', function()
    queue('oxSkillCheck', true)
    local success = QB.ox.skillCheck({ 'easy', { areaSize = 36, speedMultiplier = 2 } }, { 'e', 'q' }, 'skill_owner')
    harness.assertTrue(success)
    local call = lastRequest('oxSkillCheck')
    harness.assertEqual(call.owner, 'skill_owner')
    harness.assertEqual(call.payload.difficulty[1], 'easy')
    harness.assertEqual(call.payload.difficulty[2].areaSize, 36)
    harness.assertEqual(call.payload.inputs[2], 'q')
    harness.assertFalse(call.focused)
end)

harness.test('TextUI preserves the original ox text and extracts a qblib key chip', function()
    QB.ox.showTextUI('[E] - Open door', {
        position = 'left-center', icon = { 'fas', 'door-open' }, iconColor = '#fff',
        iconAnimation = 'pulse', alignIcon = 'top', style = { color = 'red' },
    }, 'door')
    local open, text = QB.ox.isTextUIOpen('door')
    harness.assertTrue(open)
    harness.assertEqual(text, '[E] - Open door')
    local entry = textEntries[nextText]
    harness.assertEqual(entry.text, 'Open door')
    harness.assertEqual(entry.options.key, 'E')
    harness.assertEqual(entry.options.icon, 'fas:door-open')
    harness.assertEqual(entry.options.iconColor, '#fff')
    harness.assertEqual(entry.options.iconAnimation, 'pulse')
    harness.assertEqual(entry.options.alignIcon, 'top')
    harness.assertEqual(entry.options.style.color, 'red')
    harness.assertEqual(entry.owner, 'door')
    QB.ox.hideTextUI('another_resource')
    harness.assertFalse(QB.ox.isTextUIOpen('door'))
    local messagesBeforeInactiveHide = #nuiMessages
    QB.ox.hideTextUI('door')
    harness.assertEqual(#nuiMessages, messagesBeforeInactiveHide)
    QB.ox.showTextUI('String style', { style = 'color: red' }, 'door')
    harness.assertEqual(textEntries[nextText].options.style, 'color: red')
end)

harness.test('locale and owner disposal are explicit contracts', function()
    harness.assertEqual(QB.ox.getLocaleKey('locale_owner'), 'en')
    harness.assertTrue(QB.ox.setLocale('de', 'locale_owner'))
    harness.assertEqual(locale, 'en')
    harness.assertTrue(QB.ox.setLocale('de', {
        ui = { cancel = 'Abbrechen', close = 'Schliessen', confirm = 'Bestaetigen', more = 'Mehr...' },
    }, 'locale_owner'))
    local message = nuiMessages[#nuiMessages]
    harness.assertEqual(message.action, 'oxLocale')
    harness.assertEqual(message.payload.cancel, 'Abbrechen')
    harness.assertEqual(message.payload.confirm, 'Bestaetigen')
    harness.assertEqual(nuiCallbacks['qblib:oxLocale']().more, 'Mehr...')

    QB.ox.registerContext({ id = 'temporary', title = 'Temporary', options = {} }, 'temporary_owner')
    QB.ox.disposeOwner('temporary_owner')
    harness.assertThrows(function() QB.ox.showContext('temporary', 'temporary_owner') end)
end)

harness.test('FiveM callable proxies survive menu and radial registration', function()
    local menuCalls, radialCalls = 0, 0
    local menuCallback = setmetatable({}, { __call = function() menuCalls = menuCalls + 1 end })
    local radialCallback = setmetatable({}, { __call = function() radialCalls = radialCalls + 1 end })

    QB.ox.registerMenu({ id = 'proxy_menu', title = 'Proxy', options = { { label = 'Run' } } }, menuCallback, 'proxy_owner')
    queue('openMenu', { selectedId = '__ox_menu_1', path = { '__ox_menu_1' } })
    QB.ox.showMenu('proxy_menu', nil, 'proxy_owner')
    harness.assertEqual(menuCalls, 1)

    QB.ox.registerRadial({ id = 'proxy_radial', items = { { label = 'Run', onSelect = radialCallback } } }, 'proxy_owner')
    queue('openRadialMenu', function(request)
        local id = request.payload.items[1].id
        return { selectedId = id, path = { id } }
    end)
    QB.ox.showRadialMenu('proxy_radial', 'proxy_owner')
    harness.assertEqual(radialCalls, 1)
end)

harness.test('invalid owners and unsupported input types fail fast', function()
    harness.assertThrows(function() QB.ox.notify({}, '') end)
    harness.assertThrows(function()
        QB.ox.inputDialog('Bad', { { type = 'file', label = 'Upload' } }, {}, 'forms')
    end)
end)

harness.test('an unknown radial root is an upstream-compatible no-op', function()
    local previous = #requests
    harness.assertEqual(QB.ox.showRadialMenu('missing_radial', 'radial_owner'), nil)
    harness.assertEqual(#requests, previous)
end)

harness.report('ox provider')
