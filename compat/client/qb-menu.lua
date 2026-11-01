-- Compat bridge: translates exports['qb-menu']:openMenu/closeMenu and the 'qb-menu:client:*' net events
-- onto Kora.nui.openMenu. Field mapping and caveats: see modules/nui/docs.md "Legacy compat".

-- Registers the hidden CFX export event under the legacy `qb-menu` identity; `provide` alone only satisfies dependency checks.

-- Warned once per resource run: qb-menu's Font Awesome `icon` strings don't map onto the lucide names
-- Kora.nui.openMenu expects, so icons are dropped rather than guessed.
local function imageFor(item)
    if type(item.icon) ~= 'string' or item.icon == '' then return nil end
    if item.icon:find('://', 1, true) then return item.icon end
    -- Resolve at render time through the registry getter. Capturing the whole
    -- Items map here would miss definitions registered after this resource
    -- started (and getShared expects a lowercase registry plus a record key).
    local ok, definition = pcall(function() return exports.kora_core:getShared('items', item.icon) end)
    definition = ok and definition or nil
    if definition and type(definition.imageUrl) == 'string' and definition.imageUrl ~= '' then return definition.imageUrl end
    -- `definition.image` is the legacy local-file field served from qb-inventory's html/images/, which
    -- kora_inventory doesn't ship, so that URL would always 404. kora_core's seed already resolves
    -- `imageUrl` when real artwork exists; if it's missing, drop the image.
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


-- Upstream items have no stable `id`; MenuItem requires one, so the 1-based array position is used.
-- `isMenuHeader` rows (unselectable section labels) map onto `disabled = true`.
local function translateItems(menu, sort, skipFirst)
    -- Upstream no-ops on nil/empty data; translate a non-table menu to zero items instead of asserting.
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

-- Functions that crossed an exports boundary arrive as __call tables, so a bare `type(x) == 'function'`
-- would reject items/actions built by another resource.
local isCallable = Kora.compat.isCallable

-- Selecting an item fires `params.event` (server event if `params.isServer`) with `params.args` unpacked;
-- an item without params/event just closes the menu, as upstream.
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

-- Fire-and-forget like upstream (selection is event-driven). Through the compat export Kora.nui.openMenu
-- already awaits for the external caller (a second Await would turn the result into nil); the net-event
-- path has no external caller and must await the pending promise here.
local headerShown = false
local headerMenu
local openSerial, menuOpen = 0, false
local silenced = {}

local function openMenu(menu, sort, skipFirst)
    local items, byId = translateItems(menu, sort, skipFirst)
    if #items == 0 then return end
    if headerShown then Kora.nui.send('hideMenuHeader', {}); headerShown = false end

    -- Capture this before Kora.nui.openMenu can yield. Once the coroutine resumes,
    -- the original export runtime is no longer necessarily on FiveM's runtime
    -- stack, so querying GetInvokingResource afterwards is not reliable.
    local calledFromExport = GetInvokingResource() ~= nil
    if menuOpen then silenced[openSerial] = true end
    openSerial = openSerial + 1
    local mine = openSerial
    menuOpen = true
    local result = Kora.nui.openMenu(items)
    if not calledFromExport then result = Citizen.Await(result) end
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

-- Force-dismiss the open menu; the container answers its pending request as cancelled, same path as Escape.
-- The programmatic close is silenced: upstream fires menuClosed only for a user close.
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
    local items = select(1, translateItems(menu))
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
