local contexts = {}
local menus = {}
local radialMenus = {}
local radialItems = {}
local radialItemOwners = {}
local radialBrowserIds = setmetatable({}, { __mode = 'k' })
local nextRadialBrowserId = 0
local isCallable = QB.compat.isCallable

local activeAlert
local activeContext
local activeInput
local activeMenu
local activeProgressOwner
local activeRadial
local activeSkillOwner
local activeSkillRequest
local activeText
local focusReleases = {}
local iconPrefixes = { fas = true, far = true, fal = true, fat = true, fad = true, fab = true, fak = true, fass = true }
local oxLocale = {
    cancel = 'Cancel',
    close = 'Close',
    confirm = 'Confirm',
    more = 'More...',
}

local function assertOwner(owner)
    assert(type(owner) == 'string' and owner ~= '', 'ox bridge owner must be a non-empty string.')
end

local function localeText(value, fallback)
    return type(value) == 'string' and value ~= '' and value or fallback
end

local function browserLocale(data)
    local ui = type(data) == 'table' and type(data.ui) == 'table' and data.ui or {}
    return {
        cancel = localeText(ui.cancel, 'Cancel'),
        close = localeText(ui.close, 'Close'),
        confirm = localeText(ui.confirm, 'Confirm'),
        more = localeText(ui.more, 'More...'),
    }
end

local function awaitPromise(value)
    return Citizen.Await(value)
end

local function iconName(icon)
    if type(icon) == 'table' then
        local prefix, name = icon[1], icon[2]
        if type(prefix) == 'string' and type(name) == 'string'
            and iconPrefixes[prefix] then
            return ('%s:%s'):format(prefix, name)
        end
        return name or prefix
    end
    return icon
end

local function denseArray(value)
    if type(value) ~= 'table' or #value == 0 then return false end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then return false end
        count = count + 1
    end
    return count == #value
end

local function sortedKeys(value)
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
    return keys
end

local function cancelSession(session, result, rejection)
    if not session or not session.request then return false end
    return QB.nui.cancelRequest(session.request, result, rejection)
end

local function request(action, payload, owner, timeout, onEvent)
    return QB.nui.requestAsync(action, payload, timeout, owner, true, onEvent)
end

local function menuPosition(position)
    if type(position) ~= 'string' then return nil end
    local vertical, horizontal = position:match('^(%a+)%-(%a+)$')
    if (vertical ~= 'top' and vertical ~= 'bottom') or (horizontal ~= 'left' and horizontal ~= 'right') then return nil end
    return { horizontal = horizontal, vertical = vertical }
end

local function contextMetadata(metadata)
    if type(metadata) == 'string' then return { metadata } end
    if type(metadata) ~= 'table' then return nil end

    local items = {}
    if denseArray(metadata) then
        for index = 1, #metadata do
            local value = metadata[index]
            if type(value) == 'table' then
                items[index] = {
                    label = tostring(value.label or value[1] or index),
                    value = value.value ~= nil and value.value or value[2],
                    progress = value.progress,
                    colorScheme = value.colorScheme,
                }
            else
                items[index] = tostring(value)
            end
        end
    else
        local keys = sortedKeys(metadata)
        for index = 1, #keys do
            local key = keys[index]
            items[index] = { label = tostring(key), value = metadata[key] }
        end
    end
    return items
end

local function copyOptions(options)
    if options == nil then return nil end
    assert(type(options) == 'table', 'ox input options must be a table.')
    assert(denseArray(options) or next(options) == nil, 'ox input options must be a dense array.')
    local out = {}
    for index = 1, #options do
        local option = options[index]
        assert(type(option) == 'table', 'ox input options must contain tables.')
        out[index] = {
            value = option.value,
            label = tostring(option.label or option.value),
            disabled = option.disabled == true,
        }
    end
    return out
end

local INPUT_TYPES = {
    input = 'text', number = 'number', checkbox = 'checkbox', select = 'select',
    slider = 'range', ['multi-select'] = 'multiselect', date = 'date',
    ['date-range'] = 'date-range', time = 'time', textarea = 'textarea', color = 'color',
}

local function inputFields(rows, owner)
    assert(type(rows) == 'table', 'ox inputDialog rows must be a table.')
    assert(denseArray(rows) or next(rows) == nil, 'ox inputDialog rows must be a dense array.')
    local fields = {}
    for index = 1, #rows do
        local source = rows[index]
        local row = type(source) == 'string' and { type = 'input', label = source } or source
        assert(type(row) == 'table', ('ox inputDialog row %d must be a table or string.'):format(index))
        local inputType = INPUT_TYPES[row.type or 'input']
        assert(inputType, ('ox inputDialog row %d has unsupported type %s.'):format(index, tostring(row.type)))
        if row.password and inputType == 'text' then inputType = 'password' end
        local field = {
            id = tostring(index),
            type = inputType,
            label = tostring(row.label or ('Input %d'):format(index)),
            description = row.description,
            placeholder = row.placeholder,
            default = row.type == 'checkbox' and (row.checked == true or row.default == true) or row.default,
            disabled = row.disabled,
            required = row.required,
            min = (inputType == 'number' or inputType == 'range') and row.min or nil,
            max = (inputType == 'number' or inputType == 'range') and row.max or nil,
            dateMin = (inputType == 'date' or inputType == 'date-range') and row.min or nil,
            dateMax = (inputType == 'date' or inputType == 'date-range') and row.max or nil,
            step = row.step,
            minLength = (inputType == 'text' or inputType == 'password') and row.min or row.minLength,
            maxLength = (inputType == 'text' or inputType == 'password') and row.max or row.maxLength,
            rows = inputType == 'textarea' and row.min or nil,
            options = copyOptions(row.options),
            precision = inputType == 'number' and row.precision or nil,
            dateFormat = (inputType == 'date' or inputType == 'date-range') and row.format or nil,
            colorFormat = inputType == 'color' and row.format or nil,
            timeFormat = inputType == 'time' and row.format and tostring(row.format) or nil,
            clearable = row.clearable,
            searchable = row.searchable,
            maxSelectedValues = inputType == 'multiselect' and row.maxSelectedValues or nil,
            autosize = inputType == 'textarea' and row.autosize or nil,
            minRows = inputType == 'textarea' and row.min or nil,
            maxRows = inputType == 'textarea' and row.max or nil,
            icon = iconName(row.icon),
            iconColor = row.iconColor,
        }
        if inputType == 'date' or inputType == 'date-range' then field.returnString = row.returnString == true end
        fields[index] = field
    end
    return fields
end

local function orderedInputValues(fields, result)
    if not result or result.cancelled then return nil end
    local values = {}
    for index = 1, #fields do values[index] = result.values[tostring(index)] end
    return values
end

local function notify(data, owner, legacy)
    assert(type(data) == 'table', 'ox notify requires a data table.')

    local kind = legacy and data.status or data.type
    if kind == 'inform' then kind = 'info' end
    QB.nui.send('notify', {
        title = data.title,
        message = data.description,
        duration = QB.util.isFiniteNumber(data.duration) and data.duration > 0 and data.duration or 3000,
        position = data.position,
        type = kind,
        icon = iconName(data.icon),
        id = data.id ~= nil and tostring(data.id) or nil,
        iconColor = data.iconColor,
        iconAnimation = data.iconAnimation,
        alignIcon = data.alignIcon,
        style = data.style,
        showDuration = data.showDuration,
    })

    local sound = data.sound
    if type(sound) == 'table' and type(sound.name) == 'string' and type(sound.set) == 'string' then
        local function play()
            local soundId = GetSoundId()
            PlaySoundFrontend(soundId, sound.name, sound.set, true)
            ReleaseSoundId(soundId)
        end
        if sound.bank then QB.stream.loadAudioBank(sound.bank, play) else play() end
    end
end

local function contextItems(context)
    local items, choices = {}, {}
    local keys
    if not denseArray(context.options) then keys = sortedKeys(context.options) end
    local count = keys and #keys or #context.options
    for index = 1, count do
        local key = keys and keys[index] or index
        local option = context.options[key]
        local id = ('__ox_context_%d'):format(index)
        local translated = {
            id = id,
            label = tostring(option.title or key),
            description = option.description,
            icon = iconName(option.icon),
            image = option.image,
            disabled = option.disabled == true,
            readOnly = option.readOnly == true,
            progress = option.progress,
            colorScheme = option.colorScheme,
            iconColor = option.iconColor,
            iconAnimation = option.iconAnimation,
            arrow = option.menu ~= nil and option.arrow ~= false or option.arrow,
            metadata = contextMetadata(option.metadata),
        }
        if option.menu ~= nil then translated.close = false end
        if option.menu == nil and not isCallable(option.onSelect)
            and option.event == nil and option.serverEvent == nil then
            translated.close = false
            translated.readOnly = true
        end
        items[#items + 1] = translated
        choices[id] = option
    end
    return items, choices
end

local function contextPayload(session)
    local definition = session.registration.data
    local items, choices = contextItems(definition)
    session.choices = choices
    return {
        title = definition.title,
        items = items,
        canClose = definition.canClose,
        position = { horizontal = 'right', vertical = 'top' },
        presentation = 'panel',
        back = definition.menu ~= nil,
    }
end

local function transitionContext(session, id)
    local registration = contexts[id]
    if not registration then error('No context menu of such id found.', 2) end
    session.id = id
    session.registration = registration
    return QB.nui.updateRequest(session.request, 'updateMenu', contextPayload(session))
end

local function refreshContext(session)
    if activeContext ~= session or not session.request then return end
    QB.nui.updateRequest(session.request, 'updateMenu', contextPayload(session))
end

local function contextEvent(session, event, data)
    if activeContext ~= session then return end
    local definition = session.registration.data
    if event == 'back' then
        if definition.menu == nil then return end
        if isCallable(definition.onBack) then definition.onBack() end
        transitionContext(session, definition.menu)
        return
    end
    if event ~= 'confirmed' or type(data) ~= 'table' then return end
    local option = session.choices and session.choices[data.selectedId]
    if option and option.menu then transitionContext(session, option.menu) end
end

local function runContext(session)
    session.request = request('openMenu', contextPayload(session), session.owner, false,
        function(event, data) contextEvent(session, event, data) end)
    local ok, result = pcall(awaitPromise, session.request)
    session.request = nil
    if activeContext ~= session then return end
    if not ok then
        activeContext = nil
        print(('[kora_lib:ox] context menu failed: %s'):format(tostring(result)))
        return
    end

    local definition = session.registration.data
    activeContext = nil
    if not result or result.cancelled then
        if isCallable(definition.onExit) then definition.onExit() end
        return
    end

    local option = session.choices and session.choices[result.selectedId]
    if not option then return end
    if isCallable(option.onSelect) then option.onSelect(option.args) end
    if option.event then TriggerEvent(option.event, option.args) end
    if option.serverEvent then TriggerServerEvent(option.serverEvent, option.args) end
end

local function showContext(id, owner)
    assertOwner(owner)
    local registration = contexts[id]
    if not registration then error('No context menu of such id found.', 2) end
    if activeContext then
        local previous = activeContext
        activeContext = nil
        cancelSession(previous, { cancelled = true })
    end
    local session = { id = id, owner = owner, registration = registration }
    activeContext = session
    CreateThread(function() runContext(session) end)
end

local function menuItems(definition)
    local items, choices = {}, {}
    for index = 1, #definition.options do
        local option = definition.options[index]
        local id = ('__ox_menu_%d'):format(index)
        items[index] = {
            id = id,
            label = tostring(option.label),
            description = option.description,
            icon = iconName(option.icon),
            disabled = option.disabled == true,
            values = option.values,
            defaultIndex = option.defaultIndex,
            checked = option.checked,
            progress = option.progress,
            colorScheme = option.colorScheme,
            iconColor = option.iconColor,
            close = option.close,
        }
        choices[id] = { option = option, index = index }
    end
    return items, choices
end

local function menuArgs(choice, secondary, marker)
    local args = choice.option.args
    if args ~= nil and type(args) ~= 'table' then error('Menu args must be passed as a table', 2) end
    args = args or {}
    if marker then args[marker] = true end
    return choice.index, secondary, args
end

local function menuEvent(session, event, data)
    if activeMenu ~= session or type(data) ~= 'table' then return end
    local choice = session.choices[data.selectedId]
    if not choice then return end
    local definition = session.registration.data
    if event == 'selected' and isCallable(definition.onSelected) then
        local secondary, marker
        if choice.option.values then
            secondary, marker = data.valueIndex, 'isScroll'
        elseif choice.option.checked == true then
            secondary = data.checked
            if secondary then marker = 'isCheck' end
        end
        definition.onSelected(menuArgs(choice, secondary, marker))
    elseif event == 'sideScroll' and isCallable(definition.onSideScroll) then
        definition.onSideScroll(choice.index, data.valueIndex, choice.option.args)
    elseif event == 'checked' and isCallable(definition.onCheck) then
        definition.onCheck(choice.index, data.checked, choice.option.args)
    elseif event == 'confirmed' and isCallable(session.registration.callback) then
        session.registration.callback(choice.index, data.valueIndex, choice.option.args, data.checked)
    end
end

local function menuPayload(session)
    local definition = session.registration.data
    local items, choices = menuItems(definition)
    session.choices = choices
    return {
        title = definition.title,
        items = items,
        position = menuPosition(definition.position or 'top-left'),
        canClose = definition.canClose,
        startIndex = session.startIndex,
        presentation = 'panel',
    }
end

local function refreshMenu(session)
    if activeMenu ~= session or not session.request then return end
    QB.nui.updateRequest(session.request, 'updateMenu', menuPayload(session))
end

local function runMenu(session)
    local definition = session.registration.data
    while activeMenu == session do
        session.releaseFocus = QB.nui.acquireFocus(true, false, definition.disableInput ~= true, session.owner)
        if definition.disableInput == nil or definition.disableInput == true then
            session.controlLease = QB.compat.acquireControls({ 140 }, {
                disablePlayerFiring = true,
                ignoreWeaponWheel = true,
            }, session.owner)
        end
        session.request = QB.nui.requestAsync('openMenu', menuPayload(session), false, session.owner, false,
            function(event, data) menuEvent(session, event, data) end)
        local ok, result = pcall(awaitPromise, session.request)
        session.request = nil
        if session.releaseFocus then session.releaseFocus() session.releaseFocus = nil end
        if session.controlLease then QB.compat.releaseControlLease(session.controlLease, session.owner) session.controlLease = nil end
        if activeMenu ~= session then return end
        if not ok then
            activeMenu = nil
            print(('[kora_lib:ox] menu failed: %s'):format(tostring(result)))
            return
        end
        if not result or result.cancelled then
            activeMenu = nil
            if isCallable(definition.onClose) then definition.onClose(result and result.keyPressed or nil) end
            return
        else
            local choice = session.choices[result.selectedId]
            if not choice then return end
            if choice.option.close ~= false then activeMenu = nil end
            if isCallable(session.registration.callback) then
                session.registration.callback(choice.index, result.valueIndex, choice.option.args, result.checked)
            end
            if choice.option.close ~= false then return end
        end
    end
end

local function radialTree(items, menuId, mapped, seen, menuOwner)
    local out = {}
    seen = seen or {}
    assert(not seen[items], 'ox radial menus must not contain a cycle.')
    seen[items] = true
    for index = 1, #items do
        local item = items[index]
        local id = radialBrowserIds[item]
        if not id then
            nextRadialBrowserId = nextRadialBrowserId + 1
            id = ('__ox_radial_%d'):format(nextRadialBrowserId)
            radialBrowserIds[item] = id
        end
        local node = {
            id = id,
            label = tostring(item.label),
            description = item.description,
            icon = iconName(item.icon),
            iconColor = item.iconColor,
            iconAnimation = item.iconAnimation,
            iconWidth = item.iconWidth,
            iconHeight = item.iconHeight,
            disabled = item.disabled == true,
        }
        if item.keepOpen then node.close = false end
        mapped[#mapped + 1] = {
            id = id,
            item = item,
            menuId = menuId,
            index = index,
            owner = menuId and menuOwner or radialItemOwners[item] or menuOwner,
        }
        if item.menu then
            local submenu = radialMenus[item.menu]
            assert(submenu, ('No radial menu with id %s found.'):format(tostring(item.menu)))
            node.submenu = { title = submenu.data.label, items = radialTree(submenu.data.items, submenu.data.id, mapped, seen, submenu.owner) }
        end
        out[index] = node
    end
    seen[items] = nil
    return out
end

local function mappedRadialChoice(mapped, selectedId)
    for index = 1, #mapped do
        if mapped[index].id == selectedId then return mapped[index] end
    end
end

local function invokeRadialChoice(session, choice)
    local onSelect = choice.item.onSelect
    if type(onSelect) == 'string' then
        local callbackOwner = choice.owner or session.owner
        exports[callbackOwner][onSelect](0, choice.menuId, choice.index)
    elseif isCallable(onSelect) then
        onSelect(choice.menuId, choice.index)
    end
end

local function buildRadial(session)
    local source = session.rootId and radialMenus[session.rootId]
    local items = source and source.data.items or radialItems
    local mapped = {}
    local tree = radialTree(items, source and source.data.id or nil, mapped, nil, source and source.owner or session.owner)
    return tree, mapped
end

local function radialEvent(session, event, data)
    if activeRadial ~= session or type(data) ~= 'table' then return end
    if event == 'confirmed' then
        local choice = mappedRadialChoice(session.mapped, data.selectedId)
        if choice then invokeRadialChoice(session, choice) end
        return
    end
    if event ~= 'radialLevel' or type(data.path) ~= 'table' then return end
    local previousPath = session.path or {}
    local selectedId = data.path[#data.path]
    local choice = selectedId and mappedRadialChoice(session.mapped, selectedId) or nil
    session.path = {}
    for index = 1, #data.path do session.path[index] = data.path[index] end
    session.currentId = choice and choice.item.menu or session.rootId
    if #data.path > #previousPath and choice then invokeRadialChoice(session, choice) end
end

local function refreshRadial(session)
    if activeRadial ~= session or not session.request then return end
    local tree, mapped = buildRadial(session)
    session.mapped = mapped
    QB.nui.updateRequest(session.request, 'updateRadialMenu', { items = tree })
end

local function releaseRadialLeases(session)
    if session.releaseFocus then session.releaseFocus() session.releaseFocus = nil end
    if session.controls then QB.compat.releaseControlLease(session.controls, session.owner) session.controls = nil end
    if session.pauseControls then QB.compat.releaseControlLease(session.pauseControls, session.owner) session.pauseControls = nil end
end

local function runRadial(session)
    session.releaseFocus = QB.nui.acquireFocus(true, true, true, session.owner)
    session.controls = QB.compat.acquireControls({ 1, 2, 142 }, { disablePlayerFiring = true }, session.owner)
    session.pauseControls = QB.compat.acquireControls({ 199, 200 }, { inputGroup = 2 }, session.owner)
    SetCursorLocation(0.5, 0.5)

    local ok, err = pcall(function()
        local tree, mapped = buildRadial(session)
        if #tree == 0 then activeRadial = nil return end
        session.mapped = mapped
        session.request = QB.nui.requestAsync('openRadialMenu', { items = tree }, false, session.owner, false,
            function(event, data) radialEvent(session, event, data) end)
        local result = awaitPromise(session.request)
        session.request = nil
        if activeRadial ~= session then return end
        if not result or result.cancelled then activeRadial = nil return end
        local choice = mappedRadialChoice(session.mapped, result.selectedId)
        activeRadial = nil
        if choice then invokeRadialChoice(session, choice) end
    end)

    releaseRadialLeases(session)
    if not ok then
        if activeRadial == session then activeRadial = nil end
        print(('[kora_lib:ox] radial menu failed: %s'):format(tostring(err)))
    end
end

local function openRadial(id, owner)
    if not activeRadial and (IsNuiFocused() or IsPauseMenuActive()) then return end
    if activeRadial and activeRadial.rootId == id then
        local previous = activeRadial
        activeRadial = nil
        cancelSession(previous, { cancelled = true })
        return
    end
    if activeRadial then
        local previous = activeRadial
        activeRadial = nil
        cancelSession(previous, { cancelled = true })
    end
    local session = { rootId = id, currentId = id, owner = owner, path = {} }
    activeRadial = session
    CreateThread(function() runRadial(session) end)
end

local function difficultyOptions(difficulty)
    local areaSize, multiplier
    if difficulty == 'easy' then areaSize, multiplier = 50, 1.0
    elseif difficulty == 'medium' then areaSize, multiplier = 40, 1.5
    elseif difficulty == 'hard' then areaSize, multiplier = 25, 1.75
    elseif type(difficulty) == 'table' then
        areaSize, multiplier = difficulty.areaSize, difficulty.speedMultiplier
        assert(QB.util.isFiniteNumber(areaSize) and QB.util.isFiniteNumber(multiplier),
            'custom skillCheck difficulty requires finite areaSize and speedMultiplier.')
    else
        error(('invalid skillCheck difficulty: %s'):format(tostring(difficulty)), 2)
    end
    return {
        attempts = 1,
        zoneSize = areaSize / 360,
        speed = math.max(0.3, multiplier / 4),
        timeLimit = math.floor(2000 / math.max(multiplier, 0.0001)),
    }
end

local function progressPayload(data, style, owner)
    assert(type(data) == 'table', 'ox progress requires a data table.')
    local props = data.prop
    local propCount
    if props then
        if denseArray(props) then
            propCount = math.min(#props, math.max(0, GetConvarInt('ox:progressPropLimit', 2)))
        elseif next(props) == nil then
            propCount = 0
        else
            props, propCount = { props }, 1
        end
    end
    local translatedProps
    if props then
        translatedProps = {}
        for index = 1, propCount do
            local prop = props[index]
            translatedProps[index] = {
                model = prop.model,
                bone = prop.bone,
                offset = prop.pos or { x = 0, y = 0, z = 0 },
                rotation = prop.rot or { x = 0, y = 0, z = 0 },
                rotationOrder = prop.rotOrder,
            }
        end
    end
    local anim, scenario
    if data.anim then
        if data.anim.dict then
            anim = {
                dict = data.anim.dict, clip = data.anim.clip, flag = data.anim.flag or 49,
                blendIn = data.anim.blendIn or 3.0, blendOut = data.anim.blendOut or 1.0,
                stopBlendOut = 1.0,
                duration = data.anim.duration, playbackRate = data.anim.playbackRate,
                lockX = data.anim.lockX, lockY = data.anim.lockY, lockZ = data.anim.lockZ,
            }
        elseif data.anim.scenario then
            scenario = { name = data.anim.scenario, playEnter = data.anim.playEnter }
        end
    end
    local disable
    if data.disable then
        disable = {
            move = data.disable.move,
            sprint = data.disable.sprint,
            car = data.disable.car,
            combat = data.disable.combat,
            mouse = data.disable.mouse,
            controlProfile = 'ox',
        }
        if disable.move then disable.moveMode = 'controls' end
    end
    return {
        label = type(data.label) == 'string' and data.label ~= '' and data.label or ' ',
        duration = data.duration,
        canCancel = data.canCancel,
        disable = disable,
        anim = anim,
        scenario = scenario,
        props = translatedProps,
        strictAnim = anim ~= nil,
        maxProps = false,
        maxDuration = false,
        cancelControls = false,
        useWhileDead = data.useWhileDead,
        allowRagdoll = data.allowRagdoll,
        allowCuffed = data.allowCuffed,
        allowFalling = data.allowFalling,
        allowSwimming = data.allowSwimming,
        presentation = style,
        position = data.position,
    }
end

local function startProgress(data, style, owner)
    assertOwner(owner)
    while QB.progressbar.isActive() do Wait(0) end
    activeProgressOwner = owner
    local ok, completed, err = pcall(QB.progressbar.start, progressPayload(data, style, owner), owner)
    if activeProgressOwner == owner then activeProgressOwner = nil end
    if not ok then error(completed, 2) end
    if err then error(err, 2) end
    return completed
end

function QB.ox.alertDialog(data, timeout, owner)
    assertOwner(owner)
    assert(type(data) == 'table' and type(data.content) == 'string', 'ox alertDialog requires content.')
    assert(timeout == nil or timeout == false or (QB.util.isInteger(timeout) and timeout >= 0),
        'ox alertDialog timeout must be a non-negative finite integer or false.')
    if activeAlert then return nil end
    local session = { owner = owner }
    activeAlert = session
    session.request = request('openAlert', {
        title = data.header,
        message = data.content,
        cancellable = true,
        showCancel = data.cancel == true,
        showClose = false,
        dismissOnBackdrop = false,
        confirmLabel = data.labels and data.labels.confirm,
        cancelLabel = data.labels and data.labels.cancel,
        centered = data.centered == true,
        size = data.size,
        overflow = data.overflow,
    }, owner, false)
    if timeout ~= nil and timeout ~= false then
        SetTimeout(timeout, function()
            if activeAlert == session then cancelSession(session, nil, 'timeout') end
        end)
    end
    local ok, result = pcall(awaitPromise, session.request)
    if activeAlert == session then activeAlert = nil end
    if not ok then error(result, 2) end
    if result == nil then return nil end
    return result.confirmed and 'confirm' or 'cancel'
end

function QB.ox.closeAlertDialog(reason, owner)
    assertOwner(owner)
    local session = activeAlert
    if not session then return end
    activeAlert = nil
    cancelSession(session, nil, reason)
end

function QB.ox.setClipboard(value, owner)
    assertOwner(owner)
    if type(value) ~= 'string' then return end
    QB.nui.requestAsync('copyToClipboard', { text = value }, nil, owner, false)
end

function QB.ox.registerContext(context, owner)
    assertOwner(owner)
    assert(type(context) == 'table', 'ox registerContext requires a table.')
    assert(context.id or denseArray(context) or next(context) == nil,
        'ox context definitions must be a dense array or a single definition.')
    local list = context.id and { context } or context
    for index = 1, #list do
        local definition = list[index]
        assert(type(definition.id) == 'string' and definition.id ~= '', 'No context menu id was provided.')
        assert(type(definition.title) == 'string' and definition.title ~= '', 'No context menu title was provided.')
        assert(type(definition.options) == 'table', 'No context menu options were provided.')
        for _, option in pairs(definition.options) do
            assert(type(option) == 'table', 'ox context options must be tables.')
        end
        contexts[definition.id] = { data = definition, owner = owner }
        if activeContext and activeContext.id == definition.id then
            activeContext.registration = contexts[definition.id]
            refreshContext(activeContext)
        end
    end
end

function QB.ox.showContext(id, owner) return showContext(id, owner) end

function QB.ox.getOpenContextMenu(owner)
    assertOwner(owner)
    return activeContext and activeContext.id or nil
end

function QB.ox.hideContext(onExit, owner)
    assertOwner(owner)
    local session = activeContext
    if not session then return end
    activeContext = nil
    cancelSession(session, { cancelled = true })
    if onExit and isCallable(session.registration.data.onExit) then session.registration.data.onExit() end
end

function QB.ox.inputDialog(heading, rows, options, owner)
    assertOwner(owner)
    assert(type(heading) == 'string', 'ox inputDialog heading must be a string.')
    assert(options == nil or type(options) == 'table', 'ox inputDialog options must be a table.')
    if activeInput then return nil end
    if options == nil then options = {} end
    local fields = inputFields(rows, owner)
    local session = { owner = owner }
    activeInput = session
    session.request = request('openInputDialog', {
        title = heading,
        fields = fields,
        allowCancel = options.allowCancel,
        dismissOnBackdrop = false,
        size = options.size,
    }, owner, false)
    local ok, result = pcall(awaitPromise, session.request)
    session.request = nil
    if activeInput ~= session then return nil end
    activeInput = nil
    if not ok then error(result, 2) end
    return orderedInputValues(fields, result)
end

function QB.ox.closeInputDialog(owner)
    assertOwner(owner)
    local session = activeInput
    if not session then return end
    activeInput = nil
    cancelSession(session, { cancelled = true })
end

function QB.ox.setNuiFocus(allowInput, disableCursor, owner)
    assertOwner(owner)
    assert(allowInput == nil or type(allowInput) == 'boolean', 'ox setNuiFocus allowInput must be a boolean.')
    assert(disableCursor == nil or type(disableCursor) == 'boolean', 'ox setNuiFocus disableCursor must be a boolean.')
    if focusReleases[owner] then focusReleases[owner]() end
    focusReleases[owner] = QB.nui.acquireFocus(true, not disableCursor, allowInput == true, owner)
end

function QB.ox.resetNuiFocus(owner)
    assertOwner(owner)
    local release = focusReleases[owner]
    if release then
        focusReleases[owner] = nil
        release()
    end
end

function QB.ox.registerMenu(data, callback, owner)
    assertOwner(owner)
    assert(type(data) == 'table', 'ox registerMenu requires a table.')
    if not data.id then error('No menu id was provided.', 2) end
    if not data.title then error('No menu title was provided.', 2) end
    if type(data.options) ~= 'table' then error('No menu options were provided.', 2) end
    assert(denseArray(data.options) or next(data.options) == nil, 'ox menu options must be a dense array.')
    for index = 1, #data.options do
        assert(type(data.options[index]) == 'table', 'ox menu options must be tables.')
    end
    assert(callback == nil or isCallable(callback), 'ox menu callback must be callable.')
    menus[data.id] = { data = data, callback = callback, owner = owner }
    if activeMenu and activeMenu.id == data.id then
        activeMenu.registration = menus[data.id]
        refreshMenu(activeMenu)
    end
end

function QB.ox.showMenu(id, startIndex, owner)
    assertOwner(owner)
    local registration = menus[id]
    if not registration then error(('No menu with id %s was found'):format(id), 2) end
    if #registration.data.options == 0 then error(('Can\'t open empty menu with id %s'):format(id), 2) end
    if activeMenu then
        local previous = activeMenu
        activeMenu = nil
        cancelSession(previous, { cancelled = true })
    end
    local session = { id = id, owner = owner, registration = registration, startIndex = startIndex }
    activeMenu = session
    CreateThread(function() runMenu(session) end)
end

function QB.ox.hideMenu(onExit, owner)
    assertOwner(owner)
    local session = activeMenu
    if not session then return end
    activeMenu = nil
    cancelSession(session, { cancelled = true })
    if onExit and session.registration.data.onClose then session.registration.data.onClose() end
end

function QB.ox.setMenuOptions(id, options, index, owner)
    assertOwner(owner)
    local registration = menus[id]
    assert(registration, ('No menu with id %s was found'):format(tostring(id)))
    if index ~= nil then
        assert(QB.util.isInteger(index) and index >= 1, 'ox menu option index must be a positive integer.')
        assert(index <= #registration.data.options, 'ox menu option index must refer to an existing option.')
        assert(type(options) == 'table', 'ox menu option must be a table.')
        registration.data.options[index] = options
    else
        assert(type(options) == 'table' and (denseArray(options) or next(options) == nil),
            'Invalid override format used, expected a dense table of options.')
        for optionIndex = 1, #options do
            assert(type(options[optionIndex]) == 'table', 'ox menu options must be tables.')
        end
        registration.data.options = options
    end
    if activeMenu and activeMenu.id == id then refreshMenu(activeMenu) end
end

function QB.ox.getOpenMenu(owner)
    assertOwner(owner)
    return activeMenu and activeMenu.id or nil
end

function QB.ox.notify(data, owner) assertOwner(owner) return notify(data, owner, false) end
function QB.ox.defaultNotify(data, owner) assertOwner(owner) return notify(data, owner, true) end
function QB.ox.progressBar(data, owner) return startProgress(data, 'bar', owner) end
function QB.ox.progressCircle(data, owner) return startProgress(data, 'circle', owner) end

function QB.ox.cancelProgress(owner)
    assertOwner(owner)
    if not activeProgressOwner then error('No progress bar is active', 2) end
    QB.progressbar.cancel(owner)
end

function QB.ox.progressActive(owner)
    assertOwner(owner)
    return activeProgressOwner ~= nil
end

function QB.ox.registerRadial(radial, owner)
    assertOwner(owner)
    assert(type(radial) == 'table' and type(radial.id) == 'string' and radial.id ~= '' and type(radial.items) == 'table',
        'ox registerRadial requires a non-empty id and items.')
    assert(denseArray(radial.items) or next(radial.items) == nil, 'ox radial items must be a dense array.')
    local previous = radialMenus[radial.id]
    if previous then
        for index = 1, #previous.data.items do
            radialItemOwners[previous.data.items[index]] = nil
            radialBrowserIds[previous.data.items[index]] = nil
        end
    end
    radialMenus[radial.id] = { data = radial, owner = owner }
    if activeRadial then refreshRadial(activeRadial) end
end

function QB.ox.getCurrentRadialId(owner)
    assertOwner(owner)
    return activeRadial and activeRadial.currentId or nil
end

function QB.ox.hideRadial(owner)
    assertOwner(owner)
    local session = activeRadial
    if not session then return end
    activeRadial = nil
    cancelSession(session, { cancelled = true })
end

function QB.ox.addRadialItem(items, parentMenuId, owner)
    assertOwner(owner)
    local target
    if parentMenuId then
        local parent = radialMenus[parentMenuId]
        if not parent then error('No radial submenu with such parent id found.', 2) end
        target = parent.data.items
    else
        target = radialItems
    end
    local list = denseArray(items) and items or { items }
    for index = 1, #list do
        local item = list[index]
        assert(type(item) == 'table' and type(item.id) == 'string' and item.id ~= '', 'ox radial item requires a non-empty id.')
        local replacement
        for targetIndex = 1, #target do
            if target[targetIndex].id == item.id then replacement = targetIndex break end
        end
        if replacement then
            radialItemOwners[target[replacement]] = nil
            radialBrowserIds[target[replacement]] = nil
        end
        radialItemOwners[item] = owner
        target[replacement or (#target + 1)] = item
    end
    if activeRadial then refreshRadial(activeRadial) end
end

function QB.ox.removeRadialItem(id, parentMenuId, owner)
    assertOwner(owner)
    local target
    if parentMenuId then
        local parent = radialMenus[parentMenuId]
        if not parent then error('No radial sub menu with such parent id found.', 2) end
        target = parent.data.items
    else
        target = radialItems
    end
    for index = 1, #target do
        if target[index].id == id then
            radialItemOwners[target[index]] = nil
            radialBrowserIds[target[index]] = nil
            table.remove(target, index)
            break
        end
    end
    if activeRadial then refreshRadial(activeRadial) end
end

function QB.ox.clearRadialItems(owner)
    assertOwner(owner)
    for index = #radialItems, 1, -1 do
        radialItemOwners[radialItems[index]] = nil
        radialBrowserIds[radialItems[index]] = nil
        table.remove(radialItems, index)
    end
    if activeRadial then refreshRadial(activeRadial) end
end

function QB.ox.disableRadial(state, owner)
    assertOwner(owner)
    assert(type(state) == 'boolean', 'ox disableRadial state must be a boolean.')
    QB.ox._radialDisabled = state
    if state then QB.ox.hideRadial(owner) end
end

function QB.ox.showRadialMenu(id, owner)
    assertOwner(owner)
    if QB.ox._radialDisabled then return end
    local registration = radialMenus[id]
    if not registration or #registration.data.items == 0 then return end
    openRadial(id, owner)
end

function QB.ox.skillCheck(difficulty, inputs, owner)
    assertOwner(owner)
    if activeSkillOwner then return nil end
    if inputs ~= nil then
        assert(type(inputs) == 'table' and denseArray(inputs), 'ox skillCheck inputs must be a non-empty dense array.')
    end
    local stages = denseArray(difficulty) and difficulty or { difficulty }
    for index = 1, #stages do difficultyOptions(stages[index]) end

    activeSkillOwner = owner
    local releaseFocus = QB.nui.acquireFocus(true, false, false, owner)
    local pending = QB.nui.requestAsync('oxSkillCheck', {
        difficulty = difficulty,
        inputs = inputs,
    }, false, owner, false)
    activeSkillRequest = pending

    local ok, result = pcall(awaitPromise, pending)
    releaseFocus()
    if activeSkillRequest == pending then
        activeSkillRequest = nil
        activeSkillOwner = nil
    end
    if not ok then error(result, 2) end
    return result == true
end

function QB.ox.cancelSkillCheck(owner)
    assertOwner(owner)
    if not activeSkillRequest then error('No skillCheck is active', 2) end
    QB.nui.cancelRequest(activeSkillRequest, false)
end

function QB.ox.skillCheckActive(owner)
    assertOwner(owner)
    return activeSkillOwner ~= nil
end

function QB.ox.showTextUI(text, options, owner)
    assertOwner(owner)
    assert(type(text) == 'string' and text ~= '', 'ox showTextUI requires text.')
    assert(options == nil or type(options) == 'table', 'ox TextUI options must be a table.')
    if options == nil then options = {} end
    assert(options.style == nil or type(options.style) == 'table' or type(options.style) == 'string',
        'ox TextUI style must be a table or CSS declaration string.')
    if activeText and activeText.text == text then return end
    if activeText then QB.textui.hide(activeText.handle) end
    local key, body = text:match('^%[([^%]]+)%]%s*%-?%s*(.+)$')
    local handle = QB.textui.show(body or text, {
        key = key,
        icon = iconName(options.icon),
        iconColor = options.iconColor,
        iconAnimation = options.iconAnimation,
        alignIcon = options.alignIcon,
        style = options.style,
        position = options.position,
    }, owner)
    activeText = { owner = owner, handle = handle, text = text }
end

function QB.ox.hideTextUI(owner)
    assertOwner(owner)
    if not activeText then return end
    QB.textui.hide(activeText.handle)
    activeText = nil
end

function QB.ox.isTextUIOpen(owner)
    assertOwner(owner)
    return activeText ~= nil, activeText and activeText.text or nil
end

---@param key string
---@param data? table|string Locale JSON data, or the legacy owner argument.
---@param owner? string
function QB.ox.setLocale(key, data, owner)
    if owner == nil and type(data) == 'string' then
        owner = data
        data = nil
    end
    assertOwner(owner)
    assert(type(key) == 'string' and key ~= '', 'ox locale key must be a non-empty string.')
    assert(data == nil or type(data) == 'table', 'ox locale data must be a table.')
    if data then oxLocale = browserLocale(data) end
    QB.nui.send('oxLocale', oxLocale)
    return true
end


QB.nui.registerCallback('kora_lib:oxLocale', function()
    return oxLocale
end)

function QB.ox.disposeOwner(owner)
    assertOwner(owner)
    for id, registration in pairs(contexts) do if registration.owner == owner then contexts[id] = nil end end
    for id, registration in pairs(menus) do if registration.owner == owner then menus[id] = nil end end
    local radialChanged = false
    for id, registration in pairs(radialMenus) do
        if registration.owner == owner then
            for index = 1, #registration.data.items do
                radialItemOwners[registration.data.items[index]] = nil
                radialBrowserIds[registration.data.items[index]] = nil
            end
            radialMenus[id] = nil
            radialChanged = true
        end
    end
    for index = #radialItems, 1, -1 do
        local item = radialItems[index]
        if radialItemOwners[item] == owner then
            radialItemOwners[item] = nil
            table.remove(radialItems, index)
            radialChanged = true
        end
    end
    for _, registration in pairs(radialMenus) do
        local items = registration.data.items
        for index = #items, 1, -1 do
            local item = items[index]
            if radialItemOwners[item] == owner then
                radialItemOwners[item] = nil
                radialBrowserIds[item] = nil
                table.remove(items, index)
                radialChanged = true
            end
        end
    end
    if activeAlert and activeAlert.owner == owner then QB.ox.closeAlertDialog('resource stopped', owner) end
    if activeContext and (activeContext.owner == owner or activeContext.registration.owner == owner) then QB.ox.hideContext(false, owner) end
    if activeInput and activeInput.owner == owner then QB.ox.closeInputDialog(owner) end
    if activeMenu and (activeMenu.owner == owner or activeMenu.registration.owner == owner) then QB.ox.hideMenu(false, owner) end
    if activeRadial and (activeRadial.owner == owner or radialChanged) then
        QB.ox.hideRadial(owner)
    end
    if activeProgressOwner == owner and QB.progressbar.isActive() then QB.progressbar.cancel(owner) end
    if activeSkillOwner == owner and activeSkillRequest then pcall(QB.nui.cancelRequest, activeSkillRequest, false) end
    if activeText and activeText.owner == owner then QB.ox.hideTextUI(owner) end
    if focusReleases[owner] then QB.ox.resetNuiFocus(owner) end
end

RegisterCommand('ox_lib-radial', function()
    if QB.ox._radialDisabled or #radialItems == 0 then return end
    openRadial(nil, GetCurrentResourceName())
end, false)
RegisterKeyMapping('ox_lib-radial', 'Open radial menu', 'keyboard', 'z')
