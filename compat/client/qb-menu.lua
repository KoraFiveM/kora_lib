-- Drop-in compatibility bridge: translates the real, public qb-menu API
-- (exports['qb-menu']:openMenu/closeMenu, the 'qb-menu:client:openMenu' /
-- 'qb-menu:client:closeMenu' net events) onto QB.nui.openMenu, qblib's own
-- native replacement. qb-menu itself is being deprecated in favour of
-- QB.nui.openMenu/openContextMenu/openRadialMenu -- this file exists so a
-- script written against exports['qb-menu']:... keeps working unmodified
-- while it migrates, exactly the same shape of shim as
-- qbtarget/client/compat/ox-target.lua and qbcore/compat/*.
--
-- See modules/nui/docs.md's "Legacy compat" section for the field-by-field
-- mapping table and the caveats flagged below.

-- `provide 'qb-menu'` in fxmanifest.lua alone only satisfies another
-- resource's `dependency 'qb-menu'` check -- it does NOT make
-- exports['qb-menu']:Fn() resolve here. That resolution is itself just an
-- event under the hood: exports('name', fn) is sugar for
-- AddEventHandler(('__cfx_export_%s_%s'):format(GetCurrentResourceName(), name), function(setCB) setCB(fn) end).
-- This registers that exact event under the STRING 'qb-menu' instead of this
-- resource's real name ('qblib'), which is what actually makes
-- exports['qb-menu']:openMenu(...), called from any other resource, reach
-- the function below. Deliberately duplicated per compat file rather than
-- shared -- separate Lua chunks can't share a local.
local function provideExport(providedResource, exportName, func)
    AddEventHandler(('__cfx_export_%s_%s'):format(providedResource, exportName), function(setCB)
        setCB(func)
    end)
end

-- Warned once per resource run (not per menu/item) -- real qb-menu items
-- carry a Font Awesome class string (e.g. "fas fa-car"); QB.nui.openMenu's
-- `icon` expects a lucide-react name (web/src/lib/icon.ts) instead, and the
-- two vocabularies don't overlap. Rather than guess a translation that could
-- render the wrong glyph (or none), the icon is simply dropped -- one loud
-- warning is enough to point whoever's porting the script at the gap without
-- spamming the console for every item of every menu.
-- Real qb-menu items have no stable `id` field at all (`{header, txt, icon,
-- isMenuHeader, disabled, params}`) -- QB.nui's MenuItem requires one, so the
-- 1-based position in the array is used. `isMenuHeader` rows (real qb-menu's
-- unselectable section labels) map onto `disabled = true`, the closest thing
-- the new menu has to a non-interactive row.
local function imageFor(item)
    if type(item.icon) ~= 'string' or item.icon == '' then return nil end
    if item.icon:find('://', 1, true) or item.icon:sub(1, 6) == 'nui://' then return item.icon end
    local ok, shared = pcall(function() return exports.qbcore:getShared('Items') end)
    shared = ok and shared or {}
    local definition = shared[item.icon]
    if definition and type(definition.imageUrl) == 'string' and definition.imageUrl ~= '' then return definition.imageUrl end
    -- `definition.image` (e.g. "bread.png") is the LEGACY local-file field --
    -- real qb-inventory served it from its own html/images/ folder, but
    -- qbinventory (the resource that actually `provide`s the 'qb-inventory'
    -- identity in this codebase) ships no such files: its fxmanifest.lua
    -- `files{}` block only exposes web/build/**, nothing under
    -- html/images/. A `nui://qb-inventory/html/images/%s` URL therefore
    -- always 404s in the NUI -- it used to be built here as a fallback, which
    -- is dead weight, not a fallback.
    --
    -- qbcore's own seed data (shared/items.lua) already does the real
    -- resolution: every seeded item gets `imageUrl = QBCoreSeed.imageUrl(name)`
    -- at load time, which looks the item name up in `itemImagePaths` and
    -- returns a real, fetchable itemImageBaseUrl+path URL when one exists, or
    -- nil otherwise. So by the time `definition.imageUrl` is missing/empty
    -- here, qbcore has already told us there is no real artwork for this
    -- item -- re-deriving through itemImagePaths ourselves would just
    -- reproduce that same nil. Match this function's own "the icon is simply
    -- dropped" philosophy (see the Font-Awesome-vs-lucide comment above) and
    -- drop it here too instead of returning a URL known to 404.
    return nil
end

local function sorted(menu, sort, skipFirst)
    local copy = {}
    for i, item in ipairs(menu) do copy[i] = item end
    if not sort then return copy end
    local first = skipFirst and table.remove(copy, 1) or nil
    table.sort(copy, function(a, b) return tostring(a.header or '') < tostring(b.header or '') end)
    if first then table.insert(copy, 1, first) end
    return copy
end

local function translateItems(menu, sort, skipFirst)
    -- Real qb-menu's openMenu/showHeader silently no-op on `if not data or
    -- not next(data) then return end` -- a caller passing nil (or building an
    -- empty menu conditionally) gets nothing shown, not an error. Match that:
    -- a non-table menu translates to zero items instead of asserting, so
    -- openMenu/showHeader's own `#items == 0` guard below does the no-op.
    if type(menu) ~= "table" then return {}, {} end

    local items, byId = {}, {}

    for _, item in ipairs(sorted(menu, sort, skipFirst)) do
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

-- FXServer hands a function that crossed an exports boundary back as a TABLE
-- with a __call metamethod, not a real function -- a bare `type(x) ==
-- 'function'` guard rejects every item/action built by another resource and
-- handed to this one via exports['qb-menu']:openMenu(...). Same fix, same
-- reasoning, as qblib's own isCallable (local/events, local/callback,
-- modules/cache, modules/status, modules/zones, modules/interact) and
-- qbcore/qbinventory/qbtarget's copies -- duplicated per-file rather than
-- shared, like all of those. See the qbinventory funcref bug in
-- qbcore-compat-parity/inventory-compat-identities memory for the live crash
-- this pattern was discovered from.
local function isCallable(value)
    if type(value) == 'function' then return true end
    if type(value) == 'table' and type(rawget(value, '__cfx_functionReference')) == 'string' then return true end
    local mt = type(value) == 'table' and getmetatable(value) or nil
    return mt ~= nil and mt.__call ~= nil
end

-- Selecting an item in real qb-menu fires `params.event` (TriggerServerEvent
-- if `params.isServer`, TriggerEvent otherwise) with `params.args` unpacked
-- as positional arguments -- an item with no `params`/`params.event` just
-- closes the menu, same as here. Matches qb-menu's own
-- `RegisterNUICallback('selectMenuItem', ...)` handler.
local function dispatch(item)
    if isCallable(item.action) then
        item.action()
        return
    end
    local params = item and item.params
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

-- Real qb-menu's openMenu is fire-and-forget from the caller's point of view
-- (nothing reads its return value; selection is entirely event-driven) -- so
-- this doesn't return anything either, matching that shape. It still has to
-- consume QB.nui.openMenu's result itself to know which event to fire. When
-- reached through this compatibility export, QB.nui.openMenu already awaits
-- its promise for the external caller; a second Citizen.Await would turn that
-- plain result table into nil. The legacy net-event path has no external
-- caller, so it receives the pending promise and must await it here instead.
local headerShown = false

local function openMenu(menu, sort, skipFirst)
    local items, byId = translateItems(menu, sort, skipFirst)
    if #items == 0 then return end
    if headerShown then QB.nui.send('hideMenuHeader', {}); headerShown = false end

    -- Capture this before QB.nui.openMenu can yield. Once the coroutine resumes,
    -- the original export runtime is no longer necessarily on FiveM's runtime
    -- stack, so querying GetInvokingResource afterwards is not reliable.
    local calledFromExport = GetInvokingResource() ~= nil
    local result = QB.nui.openMenu(items)
    if not calledFromExport then result = Citizen.Await(result) end
    if not result or result.cancelled then
        TriggerEvent('qb-menu:client:menuClosed')
        return
    end
    dispatch(byId[result.selectedId])
end

-- Force-dismiss the currently open list menu. The menu container answers its
-- pending request with the normal cancelled result, so focus and the awaiting
-- Lua call are settled through the same path as Escape/backdrop dismissal.
local function closeMenu()
    if headerShown then
        QB.nui.send('hideMenuHeader', {})
        headerShown = false
    end
    QB.nui.send("closeMenu", {})
end

local function showHeader(menu)
    local items = select(1, translateItems(menu))
    if #items == 0 then return end
    headerShown = true
    QB.nui.send('showMenuHeader', items)
end

if RegisterCommand then
    RegisterCommand('playerfocus', function()
        if headerShown then QB.nui.setFocus(true, true) end
    end, false)
end
if RegisterKeyMapping then RegisterKeyMapping('playerfocus', 'Give Menu Focus', 'keyboard', 'LMENU') end

provideExport("qb-menu", "openMenu", openMenu)
provideExport("qb-menu", "closeMenu", closeMenu)
provideExport("qb-menu", "showHeader", showHeader)

RegisterNetEvent("qb-menu:client:openMenu", openMenu)
RegisterNetEvent("qb-menu:client:closeMenu", closeMenu)
