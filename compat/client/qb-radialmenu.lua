-- Drop-in compatibility bridge: translates the real, public qb-radialmenu API
-- (exports['qb-radialmenu']:AddOption/RemoveOption, the
-- 'qb-radialmenu:client:AddOption'/'qb-radialmenu:client:RemoveOption' net
-- events, and the fixed keybind that opens the wheel) onto
-- QB.nui.openRadialMenu, qblib's own native replacement. qb-radialmenu itself
-- is being deprecated in favour of QB.nui.openMenu/openContextMenu/
-- openRadialMenu -- this file exists so a script written against
-- exports['qb-radialmenu']:... keeps working unmodified while it migrates,
-- exactly the same shape of shim as compat/client/qb-menu.lua and
-- compat/client/qb-input.lua.
--
-- SHAPE MISMATCH, read before touching this file: real qb-radialmenu is a
-- GLOBAL, PERSISTENT menu -- other resources register/unregister options
-- into one shared wheel over time via AddOption/RemoveOption, and the player
-- opens it whenever they want via a fixed keybind. QB.nui.openRadialMenu is a
-- ONE-SHOT, per-call menu -- a caller builds an items list and awaits a
-- single result. There is no primitive on QB.nui for "a menu that's already
-- open and waiting, built from whatever's currently registered" -- so this
-- file keeps its own registry of currently-registered options and only
-- actually calls QB.nui.openRadialMenu when the keybind fires, translating
-- the registry to an items list at that moment. See modules/nui/docs.md's
-- "Legacy compat" section for the field-by-field mapping table and this
-- caveat spelled out again.
--
-- Also note: QB.nui.openRadialMenu never takes x/y (it always opens
-- centered) -- real qb-radialmenu has no notion of screen position either
-- (it always opens centered on the player's cursor/screen), so nothing is
-- lost there. `opts.radius` is left at QB.nui's default; nothing in
-- qb-radialmenu's public surface configures it.

-- See compat/client/qb-menu.lua's identical copy of this helper for why it's
-- needed (`provide` in fxmanifest.lua alone doesn't make
-- exports['qb-radialmenu']:Fn() resolve here -- only registering the
-- underlying __cfx_export_qb-radialmenu_<name> event does). Duplicated
-- rather than shared -- separate Lua chunks can't share a local.
local function provideExport(providedResource, exportName, func)
    AddEventHandler(('__cfx_export_%s_%s'):format(providedResource, exportName), function(setCB)
        setCB(func)
    end)
end

-- Warned once per resource run -- same reasoning as qb-menu compat's
-- warnIconOnce: real qb-radialmenu options carry a Font Awesome `icon` class
-- string; QB.nui.openMenu-shaped items' `icon` expects a lucide-react name
-- (web/src/lib/icon.ts), and the two vocabularies don't overlap. Dropped
-- rather than mistranslated.
local warnedIcon = false
local function warnIconOnce()
    if warnedIcon then return end
    warnedIcon = true
    print("[qb-radialmenu-bridge] WARNING: option 'icon' fields (Font Awesome classes) are not translated to "
        .. "QB.nui's lucide icon names -- icons are dropped. Only shown once per session.")
end

-- `iconAnimation` (a CSS/animate.css-style spin/pulse class in real
-- qb-radialmenu) has no equivalent at all on QB.nui's item schema -- it's
-- purely decorative on top of the already-dropped icon, so it's silently
-- ignored rather than given its own warning on top of warnIconOnce.

-- The persistent registry this file stands in for the real resource's own
-- internal state. `order` keeps registration order (also used for `top`
-- promotion below); `byId` is keyed by the same stringified id for O(1)
-- lookup on both RemoveOption and dispatch.
local order = {}
local byId = {}

-- Real qb-radialmenu options are usually given their own `id` by the caller
-- (so a later RemoveOption(id) can find them again); when one isn't
-- supplied, forks generally generate one and hand it back from AddOption.
-- Mirrored here with a simple per-session counter -- collisions with a
-- caller-supplied id are not guarded against, same as most real forks.
local nextGeneratedId = 0
local function generateId()
    nextGeneratedId = nextGeneratedId + 1
    return ("radial_%d"):format(nextGeneratedId)
end

-- Maps the currently-registered options onto one QB.nui.openMenu-shaped
-- items list (openRadialMenu takes the same item schema). `top = true`
-- options are moved to the front, stable within each group -- the closest
-- flat-list equivalent of real qb-radialmenu's "pin near the top of the
-- wheel" behaviour; there's no ring-position concept to replicate here since
-- QB.nui's radial lays items out itself.
local function translateItems()
    local topItems, restItems = {}, {}

    for _, id in ipairs(order) do
        local option = byId[id]
        if option.icon then warnIconOnce() end

        local translated = {
            id = id,
            label = option.title or option.label or "",
        }

        if option.top then
            topItems[#topItems + 1] = translated
        else
            restItems[#restItems + 1] = translated
        end
    end

    local items = {}
    for _, item in ipairs(topItems) do items[#items + 1] = item end
    for _, item in ipairs(restItems) do items[#items + 1] = item end
    return items
end

-- Selecting an option fires `option.onSelect(option)` if given, otherwise
-- `option.event` -- TriggerServerEvent if `option.type == "server"`,
-- TriggerEvent otherwise (mirrors qb-menu compat's dispatch and real
-- qb-radialmenu's own client/server event split). An option with neither
-- just closes the wheel, same as an item with no `params.event` in qb-menu.
local function dispatch(option)
    if not option then return end

    if option.onSelect then
        local ok, err = pcall(option.onSelect, option)
        if not ok then
            print(("[qb-radialmenu-bridge] WARNING: onSelect for option %q errored: %s"):format(
                tostring(option.id), tostring(err)))
        end
        return
    end

    if not option.event then return end

    if option.type == "server" then
        TriggerServerEvent(option.event)
    else
        TriggerEvent(option.event)
    end
end

-- Real qb-radialmenu's AddOption registers one item into the global wheel
-- and returns its id (existing or freshly generated) so the caller can
-- RemoveOption it later. `shouldClose` is honoured from either
-- `option.shouldClose` (the field real forks increasingly use) or the
-- legacy second positional argument -- the field wins when both are given,
-- since it's the more explicit of the two. Defaults to true (select ->
-- wheel closes), same as real qb-radialmenu.
local function AddOption(option, shouldClose)
    assert(type(option) == "table", "qb-radialmenu compat: AddOption requires an option table.")

    local id = option.id and tostring(option.id) or generateId()

    if option.shouldClose == nil then
        option.shouldClose = shouldClose
    end
    if option.shouldClose == nil then
        option.shouldClose = true
    end

    option.id = id
    option.__qblibOwner = GetInvokingResource() or GetCurrentResourceName()

    if not byId[id] then
        order[#order + 1] = id
    end
    byId[id] = option

    return id
end

-- Removes a previously-registered option by id. A no-op if the id isn't
-- currently registered (real qb-radialmenu doesn't error on this either).
local function RemoveOption(id)
    id = tostring(id)
    if not byId[id] then return end

    byId[id] = nil
    for i, existingId in ipairs(order) do
        if existingId == id then
            table.remove(order, i)
            break
        end
    end
end

-- Guards against the keybind stacking a second QB.nui.openRadialMenu request
-- on top of one that's already open and awaiting the player.
local isOpen = false

-- Opens the wheel from whatever's currently registered, dispatches the
-- selection, and -- if the selected option's `shouldClose` is false --
-- reopens immediately to approximate real qb-radialmenu's "wheel stays open
-- for chained selections" behaviour. QB.nui.openRadialMenu has no concept of
-- staying open across a selection (it's one-shot), so this is a best-effort
-- emulation via a fresh request rather than a truly persistent NUI state.
local function openRegisteredRadial()
    if isOpen then return end
    if #order == 0 then return end

    local items = translateItems()
    if #items == 0 then return end

    isOpen = true
    local result = Citizen.Await(QB.nui.openRadialMenu(items))
    isOpen = false

    if not result or result.cancelled then return end

    local option = byId[result.selectedId]
    dispatch(option)

    if option and option.shouldClose == false then
        openRegisteredRadial()
    end
end

provideExport("qb-radialmenu", "AddOption", AddOption)
provideExport("qb-radialmenu", "RemoveOption", RemoveOption)

RegisterNetEvent("qb-radialmenu:client:AddOption", AddOption)
RegisterNetEvent("qb-radialmenu:client:RemoveOption", RemoveOption)

AddEventHandler("onClientResourceStop", function(resource)
    local owned = {}
    for id, option in pairs(byId) do
        if option.__qblibOwner == resource then owned[#owned + 1] = id end
    end
    for i = 1, #owned do RemoveOption(owned[i]) end
end)

-- Real qb-radialmenu opens on a fixed keybind rather than a script-triggered
-- call -- there's no QB.nui hook for "open whatever's registered", so this
-- defines its own command + default keybind, same pattern
-- modules/zones/client.lua's registerCreatorKeybind uses. The default key
-- ("F2") is a GUESS: real qb-radialmenu forks differ on their default (and
-- it's always rebindable by the player from FiveM's own Settings > Key
-- Bindings regardless of what's set here), so don't treat this as a faithful
-- default -- it only exists so the wheel is reachable at all without every
-- consumer resource having to bind its own key.
RegisterCommand("qblib_radialmenu_open", openRegisteredRadial, false)
RegisterKeyMapping("qblib_radialmenu_open", "Open Radial Menu", "keyboard", "F2")
