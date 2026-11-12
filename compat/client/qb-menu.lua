local function imageFor(item)
    if type(item.icon) ~= 'string' or item.icon == '' then return nil end
    if item.icon:find('://', 1, true) then return item.icon end
    local ok, definition = pcall(function() return exports.kora_core:getShared('items', item.icon) end)
    definition = ok and definition or nil
    if definition and type(definition.imageUrl) == 'string' and definition.imageUrl ~= '' then return definition.imageUrl end
    return nil
end

local function sorted(menu, sort, skipFirst)
    local copy = {}
    for i = 1, #menu do copy[i] = menu[i] end
    if not sort then return copy end
    local first = skipFirst and table.remove(copy, 1) or nil
    table.sort(copy, function(a, b) return tostring(a.header or '') < tostring(b.header or '') end)
    if first then table.insert(copy, 1, first) end
    return copy
end

local function translateItems(menu, sort, skipFirst)
    if type(menu) ~= "table" then return {}, {} end

    local items, byId = {}, {}

    local sortedItems = sorted(menu, sort, skipFirst)
    for itemIndex = 1, #sortedItems do
        local item = sortedItems[itemIndex]
        if not item.hidden then
            local index = #items + 1
            local id = tostring(index)
            items[index] = {
                id = id,
                label = item.header or "",
                description = item.txt,
                image = imageFor(item),
                disabled = item.disabled or item.isMenuHeader or false,
            }
            byId[id] = item
        end
    end

    return items, byId
end

local isCallable = Kora.compat.isCallable

local function dispatch(item)
    if isCallable(item.action) then
        item.action()
        return
    end
    local params = item.params
    if not params or not params.event then return end

    if params.isServer then
        TriggerServerEvent(params.event, params.args)
    elseif params.isCommand then
        ExecuteCommand(params.event)
    elseif params.isQBCommand then
        TriggerServerEvent('QBCore:CallCommand', params.event, params.args)
    elseif params.isAction and isCallable(params.event) then
        params.event(params.args)
    else
        TriggerEvent(params.event, params.args)
    end
end

local headerShown = false
local headerMenu
local openSerial, menuOpen = 0, false
local silenced = {}

local function openMenu(menu, sort, skipFirst)
    local items, byId = translateItems(menu, sort, skipFirst)
    if #items == 0 then return end
    if headerShown then Kora.nui.send('hideMenuHeader', {}); headerShown = false end

    local calledFromExport = GetInvokingResource() ~= nil
    if menuOpen then silenced[openSerial] = true end
    openSerial = openSerial + 1
    local mine = openSerial
    menuOpen = true
    local result = Kora.nui.openMenu(items)
    if not calledFromExport then
        local ok, value = pcall(Citizen.Await, result)
        result = ok and value or nil
    end
    if mine == openSerial then menuOpen = false end
    if not result or result.cancelled then
        if silenced[mine] then
            silenced[mine] = nil
        else
            TriggerEvent('qb-menu:client:menuClosed')
        end
        return
    end
    dispatch(byId[result.selectedId])
end

local function closeMenu()
    if headerShown then
        Kora.nui.send('hideMenuHeader', {})
        headerShown = false
    end
    headerMenu = nil
    if menuOpen then silenced[openSerial] = true end
    Kora.nui.send("closeMenu", {})
end

local function showHeader(menu)
    local items = translateItems(menu)
    if #items == 0 then return end
    headerShown = true
    headerMenu = menu
    Kora.nui.send('showMenuHeader', items)
end

Kora.keybind.add({
    name = 'playerfocus',
    description = 'Give Menu Focus',
    defaultMapper = 'keyboard',
    defaultKey = 'LMENU',
    onPressed = function()
        if not headerShown then return end

        local menu = headerMenu
        headerMenu = nil
        openMenu(menu)
    end,
})

Kora.compat.provideExport("qb-menu", "openMenu", openMenu)
Kora.compat.provideExport("qb-menu", "closeMenu", closeMenu)
Kora.compat.provideExport("qb-menu", "showHeader", showHeader)

RegisterNetEvent("qb-menu:client:openMenu", openMenu)
RegisterNetEvent("qb-menu:client:closeMenu", closeMenu)
