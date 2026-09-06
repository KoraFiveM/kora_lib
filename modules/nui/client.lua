local pendingRequests = {}
local nextRequestId = 0
local registeredApps = {}
local activeApp
local appOwnership

local function nextId()
    nextRequestId = nextRequestId + 1
    return nextRequestId
end

-- Per-request secret the NUI must echo back in its response. FiveM's NUI
-- callback routing (the `https://<resource>/<callback>` fetch every NUI page
-- uses) isn't scoped to the frame that issued a given request -- any other
-- installed resource's own NUI page could in principle POST a response to
-- "qblib:nui:response" for a guessable sequential requestId. A random token,
-- known only to this client and echoed back only by the legitimate response,
-- closes that gap the same way local/callback's per-player token does for the
-- client<->server boundary.
--
local generateToken = QB.compat.generateToken

-- FXServer represents a function passed through an exports boundary as a
-- callable table rather than a plain Lua function. App action handlers are
-- registered by consumer resources, so accept both shapes.
local isCallable = QB.compat.isCallable

local function assertAppId(id)
    assert(type(id) == "string" and id ~= "" and id:match("^[%w_:%.%-]+$"),
        "App id must be a non-empty namespaced string without whitespace.")
end

-- Handlers belong in Lua and cannot be JSON-encoded into SendNUIMessage. Keep
-- the callable in the private registry and copy only the browser definition.
local function browserApp(definition)
    local result = {}
    for key, value in pairs(definition) do
        if key ~= "onAction" then result[key] = value end
    end
    return result
end

local function assertAppAction(action, location)
    assert(type(action) == "table", ("%s must contain action tables."):format(location))
    assert(type(action.id) == "string" and action.id ~= "", ("%s action id must be a non-empty string."):format(location))
    assert(type(action.label) == "string" and action.label ~= "", ("%s action label must be a non-empty string."):format(location))
    if action.fields ~= nil then
        assert(type(action.fields) == "table", ("%s action fields must be a table."):format(location))
        for index, field in ipairs(action.fields) do
            assert(type(field) == "table" and type(field.id) == "string" and field.id ~= ""
                and type(field.label) == "string" and field.label ~= ""
                and type(field.type) == "string", ("%s action field %d is invalid."):format(location, index))
            assert(field.dependsOn == nil or type(field.dependsOn) == "string", ("%s action field %d dependsOn must be a string."):format(location, index))
            assert(field.optionsByValue == nil or type(field.optionsByValue) == "table", ("%s action field %d optionsByValue must be a table."):format(location, index))
        end
    end
    assert(action.confirm == nil or type(action.confirm) == "string", ("%s action confirm must be a string."):format(location))
end

local function assertAppContent(content, location)
    if content == nil then return end
    assert(type(content) == "table", ("%s content must be a table."):format(location))

    if content.actions ~= nil then
        assert(type(content.actions) == "table", ("%s actions must be a table."):format(location))
        for _, action in ipairs(content.actions) do assertAppAction(action, location) end
    end

    if content.blocks == nil then return end
    assert(type(content.blocks) == "table", ("%s blocks must be a table."):format(location))
    local blockTypes = { text = true, stats = true, table = true, list = true, actions = true, empty = true }

    for index, block in ipairs(content.blocks) do
        local blockLocation = ("%s block %d"):format(location, index)
        assert(type(block) == "table" and blockTypes[block.type], blockLocation .. " has an invalid type.")
        if block.type == "text" then
            assert(type(block.text) == "string", blockLocation .. " requires text.")
        elseif block.type == "stats" or block.type == "list" then
            assert(type(block.items) == "table", blockLocation .. " requires an items table.")
        elseif block.type == "table" then
            assert(type(block.columns) == "table" and type(block.rows) == "table",
                blockLocation .. " requires columns and rows tables.")
        elseif block.type == "actions" then
            assert(type(block.actions) == "table", blockLocation .. " requires an actions table.")
            for _, action in ipairs(block.actions) do assertAppAction(action, blockLocation) end
        elseif block.type == "empty" then
            assert(type(block.title) == "string" and block.title ~= "", blockLocation .. " requires a title.")
        end
    end
end

local function assertBrowserApp(definition)
    assertAppId(definition.id)
    assert(type(definition.title) == "string" and definition.title ~= "", "App title must be a non-empty string.")
    assert(definition.accent == nil or (type(definition.accent) == "string"
        and definition.accent:match("^#%x%x%x%x%x%x$") ~= nil),
        "App accent must be a #RRGGBB hex colour.")
    assert(type(definition.navigation) == "table" and #definition.navigation > 0,
        "App navigation must contain at least one view.")
    assert(definition.width == nil or (type(definition.width) == "number" and definition.width > 0),
        "App width must be a positive number.")
    assert(definition.height == nil or (type(definition.height) == "number" and definition.height > 0),
        "App height must be a positive number.")

    local viewIds = {}
    local hasEnabledView = false
    for viewIndex, view in ipairs(definition.navigation) do
        local location = ("App navigation item %d"):format(viewIndex)
        assert(type(view) == "table", location .. " must be a table.")
        assert(type(view.id) == "string" and view.id ~= "", location .. " requires an id.")
        assert(not viewIds[view.id], ("App navigation id '%s' is duplicated."):format(view.id))
        assert(type(view.label) == "string" and view.label ~= "", location .. " requires a label.")
        viewIds[view.id] = true
        if not view.disabled then hasEnabledView = true end
        assertAppContent(view.content, ("App view '%s'"):format(view.id))

        if view.tabs ~= nil then
            assert(type(view.tabs) == "table" and #view.tabs > 0,
                ("App view '%s' tabs must contain at least one tab."):format(view.id))
            local tabIds = {}
            for tabIndex, tab in ipairs(view.tabs) do
                local tabLocation = ("App view '%s' tab %d"):format(view.id, tabIndex)
                assert(type(tab) == "table", tabLocation .. " must be a table.")
                assert(type(tab.id) == "string" and tab.id ~= "", tabLocation .. " requires an id.")
                assert(not tabIds[tab.id], ("App view '%s' tab id '%s' is duplicated."):format(view.id, tab.id))
                assert(type(tab.label) == "string" and tab.label ~= "", tabLocation .. " requires a label.")
                tabIds[tab.id] = true
                assertAppContent(tab.content, ("App view '%s' tab '%s'"):format(view.id, tab.id))
            end
        end
    end
    assert(hasEnabledView, "App navigation must contain at least one enabled view.")
end

local function mergeAppUpdate(registration, update)
    assert(type(update) == "table", "App update must be a table.")

    local candidate = {}
    for key, value in pairs(registration.browser) do candidate[key] = value end
    for key, value in pairs(update) do
        assert(key ~= "id", "App id cannot be changed by updateApp.")
        assert(key ~= "onAction", "Use registerApp to replace an app action handler.")
        candidate[key] = value
    end
    assertBrowserApp(candidate)
    registration.browser = candidate
end

---Sends a message to the NUI. Every module should go through this (and the
---request/response helpers below) instead of talking to the NUI natives
---directly, so the message contract stays in one place.
---@param action string
---@param data any
function QB.nui.send(action, data)
    -- SendNUIMessage (capital NUI) is the runtime wrapper that takes a table
    -- and json-encodes it; the similarly-named SendNuiMessage native takes a
    -- pre-encoded JSON *string* and would stringify a table into garbage.

    SendNUIMessage({ action = action, data = data })
end

---Sets NUI focus directly. Prefer `QB.nui.withFocus` when the caller can scope
---focus to a single operation -- this exists for the rarer case (e.g. a HUD
---that needs to hold focus across several unrelated calls) where that doesn't fit.
---@param mouse boolean
---@param keyboard boolean
function QB.nui.setFocus(mouse, keyboard)
    SetNuiFocus(mouse, keyboard)
end

---Runs `fn` with NUI focus set, guaranteeing focus is released afterward even
---if `fn` errors -- the headless-UI rule (AGENTS.md) is that focus never
---outlives the interaction that requested it, and this is the one place that
---guarantee is enforced instead of every caller hand-rolling it.
---@param mouse boolean
---@param keyboard boolean
---@param fn fun(): any
---@return any
function QB.nui.withFocus(mouse, keyboard, fn)
    SetNuiFocus(mouse, keyboard)

    local ok, result = pcall(fn)

    SetNuiFocus(false, false)

    if not ok then error(result, 0) end

    return result
end

---Registers an NUI callback, wrapping RegisterNUICallback's raw `(data, cb)`
---signature so handlers just return a value (or nil) like a normal function.
---A handler that errors is logged and responds with an empty table rather than
---leaving the NUI's fetch promise hanging.
---@param name string
---@param handler fun(data: any): any
function QB.nui.registerCallback(name, handler)
    RegisterNUICallback(name, function(data, cb)
        local ok, result = pcall(handler, data)

        if not ok then
            print(("[qblib:nui] callback '%s' errored: %s"):format(name, tostring(result)))
            cb({})
            return
        end

        cb(result or {})
    end)
end

---The single shared response channel every `QB.nui.request` call resolves
---through, keyed by requestId -- one registered callback rather than a
---dynamically-named one per request. `data.token` must match the token this
---request was issued with (see generateToken above); a mismatched or missing
---token is silently ignored rather than resolving/rejecting anything.
QB.nui.registerCallback("qblib:nui:response", function(data)
    local pending = pendingRequests[data.requestId]
    if not pending then return {} end
    if type(data.token) ~= "string" or data.token ~= pending.token then return {} end

    pendingRequests[data.requestId] = nil

    if data.ok then
        pending.promise:resolve(data.result)
    else
        pending.promise:reject(data.error or "NUI request failed.")
    end

    return {}
end)

-- A promise object doesn't survive crossing a real cross-resource exports()
-- call back to the caller: only METHOD CALLS on it (:next(), used below)
-- reach the real promise inside qblib, while plain field reads (.state,
-- .value -- what Citizen.Await itself checks) on the crossed reference never
-- reflect the real remote promise's settlement, so the caller's own
-- Citizen.Await silently resolves nil regardless of the real outcome.
-- GetInvokingResource() is nil for a same-VM call (qblib's own modules,
-- every dofile()'d smoke test) and the real calling resource's name for a
-- genuine cross-resource exports() call (same signal modules/zones already
-- relies on for ownership tracking -- see its AGENTS.md's "Resource
-- ownership" note) -- exactly the distinction that matters here. Same-VM
-- callers get the real promise back unchanged, so `Citizen.Await(QB.nui.X(...))`
-- keeps working exactly as before for internal callers and every smoke test.
-- A genuine cross-resource caller gets the already-awaited plain value (or a
-- raised error on rejection/timeout, which -- like every other qblib error --
-- surfaces to that caller as a printed export-call error and a nil return,
-- not a catchable Lua error) instead of a promise it can't usefully await.
-- Deliberately duplicated per-file -- see local/callback/{client,server}.lua
-- and modules/zones/client.lua for the other copies.
local function settleForExport(p)
    if GetInvokingResource() then
        return Citizen.Await(p)
    end
    return p
end

---Sends `action` to the NUI and returns a promise that resolves with whatever
---the NUI eventually posts back to the shared `qblib:nui:response` callback
---for this request's id (carrying the matching token). This is the core
---primitive menus, input dialogs, and `QB.nui.copyToClipboard` are all built on.
---@param action string
---@param data any
---@param timeout? integer | false Milliseconds before the promise rejects. Defaults to 30000; pass false to disable.
---@return promise promise
local function requestPromise(action, data, timeout)
    local requestId = nextId()
    local token = generateToken()
    local p = promise.new()
    -- Private metadata used by the long-lived app shell callbacks. Keeping it
    -- on the local promise avoids changing the public wire envelope or return
    -- value of QB.nui.request.
    p.qblibNuiRequestId = requestId
    p.qblibNuiToken = token
    pendingRequests[requestId] = { promise = p, token = token }

    QB.nui.send(action, { requestId = requestId, token = token, payload = data })

    if timeout ~= false then
        timeout = timeout or 30000

        -- A one-shot native timer rather than a CreateThread+Wait coroutine --
        -- this timeout almost never actually fires (the response callback
        -- above settles it first), so it shouldn't cost a whole thread per
        -- request. Same idiom local/callback/server.lua already uses for the
        -- same "cheap deadline that's usually beaten by a real response" shape.
        SetTimeout(timeout, function()
            if pendingRequests[requestId] then
                pendingRequests[requestId] = nil
                p:reject("NUI request timed out.")
            end
        end)
    end

    return p
end

-- Settles one known local request without waiting for a browser round trip.
-- App-owner shutdown and app supersession use this after telling the browser
-- to hide: focus must be released immediately even if the frame disappears
-- before it gets a chance to answer normally.
local function settlePendingRequest(p, ok, value)
    local requestId = p and p.qblibNuiRequestId
    local pending = requestId and pendingRequests[requestId]
    if not pending or pending.promise ~= p then return false end

    pendingRequests[requestId] = nil
    if ok then p:resolve(value) else p:reject(value) end
    return true
end

---Public wrapper over the same primitive above, for callers sending a custom
---NUI action qblib doesn't have a dedicated wrapper for.
---@param action string
---@param data any
---@param timeout? integer | false
---@return promise|any result A promise for a same-VM caller (unchanged, awaitable as before); the
---already-settled result value directly for a genuine cross-resource caller (see settleForExport above).
function QB.nui.request(action, data, timeout)
    return settleForExport(requestPromise(action, data, timeout))
end

-- Grants mouse+keyboard focus for the lifetime of an interactive request and
-- releases it the moment the promise settles -- answered, cancelled, or timed
-- out (the request timeout doubles as the guarantee focus can't get stuck).
-- This is what makes the open* wrappers below actually clickable/typable
-- in-game; without focus the NUI renders but can never receive input.
local function focusUntilSettled(p)
    SetNuiFocus(true, true)

    local function release() SetNuiFocus(false, false) end
    p:next(release, release)

    return p
end

---Copies `text` to the system clipboard via the NUI (the only place with
---access to a real clipboard API). Never takes focus -- the operation is
---invisible.
---@param text string
---@return promise|any result See QB.nui.request's return doc.
function QB.nui.copyToClipboard(text)
    assert(type(text) == "string", "copyToClipboard requires a string.")
    return settleForExport(requestPromise("copyToClipboard", { text = text }))
end

---Opens a searchable list menu. Grants NUI focus while open and releases it
---when the menu closes (selection, cancel, or timeout).
---@param items table[] `{ id: string, label: string, description?: string, icon?: string, disabled?: boolean, submenu?: { title?: string, items: table[] } }[]`
---@param title? string
---@param opts? table `{ position?: { horizontal?: 'left'|'center'|'right', vertical?: 'top'|'center'|'bottom', offsetX?: positive number, offsetY?: positive number }, maxWidth?: positive number, maxHeight?: positive number }` Geometry in screen pixels; defaults to the existing centred menu.
---@return promise|any result Resolves/returns `{ selectedId: string, path: string[] }` or `{ cancelled: true }`. See QB.nui.request's return doc.
function QB.nui.openMenu(items, title, opts)
    assert(type(items) == "table", "openMenu requires an items table.")
    -- timeout = false: these three wait on a HUMAN, and there's no sensible
    -- deadline for "how long until they pick something" -- a player can open a
    -- dialog, get shot at, and come back to it. A timeout here doesn't fail
    -- safe either: it rejects a dialog that's still on screen, so the player
    -- goes on to answer a request nothing is listening for any more. They're
    -- all dismissable (Escape/backdrop/Cancel), so cancelling is always
    -- available as the way out -- see modules/nui/docs.md.
    return settleForExport(focusUntilSettled(requestPromise("openMenu", {
        title = title,
        items = items,
        position = opts and opts.position,
        maxWidth = opts and opts.maxWidth,
        maxHeight = opts and opts.maxHeight,
    }, false)))
end

---Opens a context menu anchored at (x, y) -- or centered, if omitted. Grants
---NUI focus while open and releases it when the menu closes.
---@param items table[] Same shape as openMenu's `items`; submenus are ignored because a context menu is one level only.
---@param x? number
---@param y? number
---@return promise|any result Resolves/returns `{ selectedId: string, path: string[] }` or `{ cancelled: true }`. See QB.nui.request's return doc.
function QB.nui.openContextMenu(items, x, y)
    assert(type(items) == "table", "openContextMenu requires an items table.")
    -- No timeout, same reasoning as openMenu above.
    return settleForExport(focusUntilSettled(requestPromise("openContextMenu", { items = items, x = x, y = y }, false)))
end

---Opens a radial menu, always centred on screen. Items share openMenu's
---schema, including nested submenus; the NUI handles navigation and returns
---one MenuResult.
---@param items table[] Same shape as openMenu's `items`.
---@param opts? table `{ radius?: number }`
---@return promise|any result Resolves/returns `{ selectedId: string, path: string[] }` or `{ cancelled: true }`. See QB.nui.request's return doc.
function QB.nui.openRadialMenu(items, opts)
    assert(type(items) == "table", "openRadialMenu requires an items table.")
    assert(opts == nil or type(opts) == "table", "openRadialMenu options must be a table.")

    opts = opts or {}
    assert(opts.radius == nil or (type(opts.radius) == "number" and opts.radius > 0),
        "openRadialMenu radius must be a positive number.")

    -- No timeout, same reasoning as openMenu: a human owns dismissal, and
    -- timing out would leave a still-visible radial with no awaiting caller.
    return settleForExport(focusUntilSettled(requestPromise("openRadialMenu", {
        items = items,
        radius = opts.radius,
    }, false)))
end

---Opens a confirmation dialog. Grants NUI focus while open and releases it
---when the dialog closes.
---@param opts table `{ message: string, title?: string, image?: string, confirmLabel?: string, cancelLabel?: string, cancellable?: boolean, destructive?: boolean }`
---@return promise|any result Resolves/returns `{ confirmed: boolean }` -- `confirmed = false` covers
---the cancel button, Escape and the backdrop alike. With `cancellable = false` there is no cancel
---button and neither Escape nor the backdrop dismisses it, so it can only resolve `true`.
---See QB.nui.request's return doc for the promise-vs-value distinction.
function QB.nui.openAlert(opts)
    assert(type(opts) == "table", "openAlert requires an options table.")
    assert(type(opts.message) == "string" and #opts.message > 0, "openAlert requires a message string.")

    -- No timeout, same reasoning as openMenu -- and a non-cancellable alert
    -- MUST NOT have one: timing it out would resolve a dialog that's still on
    -- screen demanding an answer, which is what it was set up to prevent.
    return settleForExport(focusUntilSettled(requestPromise("openAlert", opts, false)))
end

---Opens a schema-driven input form. Grants NUI focus while open and releases
---it when the dialog closes (submit, cancel, or timeout).
---@param fields table[] `{ id: string, label: string, type: "text"|"password"|"textarea"|"number"|"checkbox"|"select"|"range"|"combobox", options?, rows?, default?, placeholder?, required?, min?, max?, pattern? }[]` -- see modules/nui/docs.md for what applies to which type.
---@param title? string
---@param description? string
---@return promise|any result Resolves/returns `{ values: table<string, any> }` or `{ cancelled: true }`. See QB.nui.request's return doc.
function QB.nui.openInputDialog(fields, title, description)
    assert(type(fields) == "table", "openInputDialog requires a fields table.")
    -- No timeout, same reasoning as openMenu above -- and most acute here,
    -- since filling in a multi-field form is the slowest thing the NUI asks
    -- anyone to do.
    return settleForExport(focusUntilSettled(requestPromise("openInputDialog", { title = title, description = description, fields = fields }, false)))
end

-- App registrations are owner-tracked like callbacks, zones, and keybinds.
-- If a consumer stops while its app is open, ask the browser to settle the
-- request first (which releases focus) and then remove the definition.
local function applyAppAccent(registration)
    QB.nui.send("qbtheme:override", registration and registration.browser.accent or nil)
end

appOwnership = QB.resources.registry(function(id)
    local current = activeApp
    if current and current.id == id then
        QB.nui.send("closeApp", {
            appId = id,
            token = current.token,
            reason = "resourceStop",
        })
        settlePendingRequest(current.promise, true, { closed = true, reason = "resourceStop" })
    end
    registeredApps[id] = nil
end)

---Registers a declarative full-screen application shell. The definition owns
---navigation, tabs, standard content blocks, and an optional Lua action
---handler. Registrations are automatically removed when their owner stops.
---@param definition table QBAppDefinition
---@return string id
function QB.nui.registerApp(definition)
    assert(type(definition) == "table", "registerApp requires a definition table.")
    assert(definition.onAction == nil or isCallable(definition.onAction), "App onAction must be callable.")

    local publicDefinition = browserApp(definition)
    assertBrowserApp(publicDefinition)

    local owner = GetInvokingResource() or GetCurrentResourceName()
    local previousOwner = appOwnership.owner(definition.id)
    if previousOwner and previousOwner ~= owner then
        print(("^3[qblib:nui]^7 app '%s' was registered by '%s' and is being overwritten by '%s' -- namespace app ids.")
            :format(definition.id, previousOwner, owner))
    end

    registeredApps[definition.id] = {
        browser = publicDefinition,
        onAction = definition.onAction,
        owner = owner,
    }
    appOwnership.track(owner, definition.id)

    local current = activeApp
    if current and current.id == definition.id then
        applyAppAccent(registeredApps[definition.id])
        QB.nui.send("updateApp", {
            appId = definition.id,
            token = current.token,
            app = publicDefinition,
        })
    end
    return definition.id
end

---Unregisters an application. An open instance is closed before its
---definition is removed so the awaiting openApp call and NUI focus settle.
---@param id string
---@return boolean removed
function QB.nui.unregisterApp(id)
    assertAppId(id)
    local registration = registeredApps[id]
    if not registration then return false end

    local invoker = GetInvokingResource()
    assert(not invoker or invoker == registration.owner,
        ("App '%s' is owned by resource '%s'."):format(id, registration.owner))

    local current = activeApp
    if current and current.id == id then
        QB.nui.send("closeApp", { appId = id, token = current.token, reason = "unregister" })
        settlePendingRequest(current.promise, true, { closed = true, reason = "unregister" })
    end

    registeredApps[id] = nil
    appOwnership.untrack(id)
    return true
end

---Opens a registered application and holds mouse/keyboard focus until the
---player closes it. Only one registered app shell can be active at a time;
---opening another supersedes the current one through useNuiRequest.
---@param id string
---@param opts? table `{ data?: any, viewId?: string, tabId?: string }`
---@return promise|any result `{ closed: true, reason: string, viewId?: string, tabId?: string }`
function QB.nui.openApp(id, opts)
    assertAppId(id)
    assert(opts == nil or type(opts) == "table", "openApp options must be a table.")

    local registration = registeredApps[id]
    assert(registration, ("App '%s' is not registered."):format(id))

    -- Settle an old app before granting the new one focus. If this were left
    -- to the browser's asynchronous supersede response, the old promise's
    -- focus-release callback could run after the new request granted focus,
    -- leaving the newly visible app unable to receive input.
    if activeApp then
        local previous = activeApp
        -- Reopening/replacing an app is normal control flow (notably when an
        -- admin runs /admin again). Resolve the old caller as closed instead
        -- of rejecting its cross-resource export call, which would otherwise
        -- print a misleading SCRIPT ERROR in the resource that opened it.
        settlePendingRequest(previous.promise, true, { closed = true, reason = "superseded" })
    end

    opts = opts or {}
    applyAppAccent(registration)
    local p = requestPromise("openApp", {
        app = registration.browser,
        data = opts.data,
        viewId = opts.viewId,
        tabId = opts.tabId,
    }, false)

    local instance = {
        id = id,
        token = p.qblibNuiToken,
        promise = p,
        data = opts.data,
    }
    activeApp = instance

    local function clear()
        if activeApp ~= instance then return end
        activeApp = nil
        applyAppAccent(nil)
    end
    p:next(clear, clear)

    return settleForExport(focusUntilSettled(p))
end

---Replaces fields on a registered app definition. Navigation is replaced as
---a whole when supplied; active instances receive the updated definition
---immediately without losing their selected view/tab when those still exist.
---@param id string
---@param update table Partial QBAppDefinition (id/onAction excluded).
---@return boolean updated
function QB.nui.updateApp(id, update)
    assertAppId(id)
    local registration = registeredApps[id]
    if not registration then return false end

    local invoker = GetInvokingResource()
    assert(not invoker or invoker == registration.owner,
        ("App '%s' is owned by resource '%s'."):format(id, registration.owner))

    mergeAppUpdate(registration, update)

    local current = activeApp
    if current and current.id == id then
        applyAppAccent(registration)
        QB.nui.send("updateApp", {
            appId = id,
            token = current.token,
            app = registration.browser,
        })
    end

    return true
end

---Closes the active app shell. The browser response settles openApp and the
---normal focus-until-settled path releases NUI focus.
---@param id? string Omit to close whichever registered app is active.
---@return boolean closing
function QB.nui.closeApp(id)
    if id ~= nil then assertAppId(id) end
    local current = activeApp
    if not current or (id and current.id ~= id) then return false end

    QB.nui.send("closeApp", {
        appId = current.id,
        token = current.token,
        reason = "api",
    })
    return true
end

---@param id? string
---@return boolean open
function QB.nui.isAppOpen(id)
    if id ~= nil then assertAppId(id) end
    return activeApp ~= nil and (id == nil or activeApp.id == id)
end

-- One authenticated route for every button/list/table action emitted by the
-- AppShell. The per-open token prevents another NUI page from invoking a
-- registered application's privileged action handler by guessing its id.
QB.nui.registerCallback("qblib:app:action", function(data)
    local current = activeApp
    if not current or type(data) ~= "table" then
        return { ok = false, error = "No app is open." }
    end
    if data.appId ~= current.id or type(data.token) ~= "string" or data.token ~= current.token then
        return { ok = false, error = "Invalid app session." }
    end
    if type(data.actionId) ~= "string" or data.actionId == "" then
        return { ok = false, error = "Invalid app action." }
    end

    local registration = registeredApps[current.id]
    if not registration or not registration.onAction then
        return { ok = false, error = "This app has no action handler." }
    end

    local ok, result = pcall(registration.onAction, data.actionId, {
        appId = current.id,
        viewId = data.viewId,
        tabId = data.tabId,
        itemId = data.itemId,
        value = data.value,
        data = current.data,
    })
    if not ok then
        print(("[qblib:nui] app '%s' action '%s' errored: %s")
            :format(current.id, data.actionId, tostring(result)))
        return { ok = false, error = "The app action failed." }
    end

    if type(result) == "table" and result.update ~= nil then
        local updateOk, updateError = pcall(mergeAppUpdate, registration, result.update)
        if not updateOk then
            print(("[qblib:nui] app '%s' action '%s' returned an invalid update: %s")
                :format(current.id, data.actionId, tostring(updateError)))
            return { ok = false, error = "The app returned an invalid update." }
        end
        applyAppAccent(registration)
        result.app = registration.browser
        result.update = nil
    end

    return { ok = true, result = result or {} }
end)
