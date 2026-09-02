local pendingRequests = {}
local nextRequestId = 0

local function nextId()
    nextRequestId = nextRequestId + 1
    return nextRequestId
end

-- Seeded ONCE at module load, not per token: reseeding from a time-derived
-- value on every call would hand two same-millisecond requests identical RNG
-- state -- and therefore identical "secrets". GetGameTimer() only (no os.clock()
-- -- the `os` library doesn't exist in FiveM's client-side Lua sandbox, only
-- server-side; local/callback/server.lua and local/events/server.lua can use
-- it because they're server scripts).
math.randomseed(GetGameTimer())

-- Per-request secret the NUI must echo back in its response. FiveM's NUI
-- callback routing (the `https://<resource>/<callback>` fetch every NUI page
-- uses) isn't scoped to the frame that issued a given request -- any other
-- installed resource's own NUI page could in principle POST a response to
-- "qblib:nui:response" for a guessable sequential requestId. A random token,
-- known only to this client and echoed back only by the legitimate response,
-- closes that gap the same way local/callback's per-player token does for the
-- client<->server boundary.
--
-- Deliberately duplicated from local/callback/server.lua and
-- local/events/server.lua (module files are separate Lua chunks; a shared
-- private helper is impossible and QB.* attachments become public exports) --
-- keep the three copies in sync.
local function generateToken()
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    local parts = {}

    for i = 1, 32 do
        local index = math.random(1, #chars)
        parts[i] = chars:sub(index, index)
    end

    return table.concat(parts)
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
