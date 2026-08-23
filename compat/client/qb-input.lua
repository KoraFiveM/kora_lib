-- Drop-in compatibility bridge: translates the real, public qb-input API
-- (exports['qb-input']:ShowInput) onto QB.nui.openInputDialog, qblib's own
-- native replacement. qb-input itself is being deprecated in favour of
-- QB.nui.openInputDialog -- this file exists so a script written against
-- exports['qb-input']:ShowInput(...) keeps working unmodified while it
-- migrates, exactly the same shape of shim as
-- qbtarget/client/compat/ox-target.lua and qbcore/compat/*.
--
-- See modules/nui/docs.md's "Legacy compat" section for the field-by-field
-- mapping table and the caveats flagged below.

-- See compat/client/qb-menu.lua's identical copy of this helper for why it's
-- needed (`provide` in fxmanifest.lua alone doesn't make
-- exports['qb-input']:Fn() resolve here -- only registering the underlying
-- __cfx_export_qb-input_<name> event does). Duplicated rather than shared --
-- separate Lua chunks can't share a local.
local function provideExport(providedResource, exportName, func)
    AddEventHandler(('__cfx_export_%s_%s'):format(providedResource, exportName), function(setCB)
        setCB(func)
    end)
end

-- Warned once per resource run -- same reasoning as qb-menu compat's
-- warnIconOnce: real qb-input inputs carry a Font Awesome `icon` class that
-- QB.nui.openInputDialog's InputField has no equivalent field for at all, so
-- it's dropped rather than guessed at.
local warnedIcon = false
local function warnIconOnce()
    if warnedIcon then return end
    warnedIcon = true
    print("[qb-input-bridge] WARNING: input 'icon' fields (Font Awesome classes) have no equivalent on "
        .. "QB.nui.openInputDialog's fields -- icons are dropped. Only shown once per session.")
end

-- Warned once per (unrecognized) type name rather than globally -- unlike
-- the icon warning, which fires every time a *field the whole compat layer
-- can never support carries a value*, this is "you're using a type this
-- shim hasn't seen before", which is worth naming exactly which type so
-- whoever's porting the script knows what to check.
local warnedTypes = {}
local inputOpen = false
local function warnUnknownTypeOnce(inputType)
    if warnedTypes[inputType] then return end
    warnedTypes[inputType] = true
    print(("[qb-input-bridge] WARNING: input type %q is not recognized -- falling back to a plain text field. "
        .. "Only shown once per type per session."):format(tostring(inputType)))
end

-- radio/select options carry {value, text} in real qb-input (some forks use
-- `label` instead of `text`); QB.nui's field expects {value, label} with
-- both stringified -- Select's value plumbing (web/src/components/ui/select.tsx)
-- is string-keyed throughout.
local function translateOptions(options)
    local translated = {}

    for i, option in ipairs(options or {}) do
        translated[i] = {
            value = tostring(option.value),
            label = option.text or option.label or tostring(option.value),
        }
    end

    return translated
end

-- Maps one real qb-input `inputs[]` entry onto an InputField. `name` becomes
-- `id` directly -- QB.nui.openInputDialog's result is `{ values = { [id] = value } }`,
-- so keeping id == name means the legacy `result[name]` lookup keeps working
-- with zero reshaping once ShowInput gets the response back.
local function translateField(input)
    assert(type(input.name) == "string" and #input.name > 0, "qb-input compat: every input needs a string 'name'.")

    if input.icon then warnIconOnce() end

    local field = {
        id = input.name,
        label = input.text or input.name,
        required = input.isRequired or false,
        default = input.default,
        placeholder = input.placeholder,
    }

    local inputType = input.type

    if inputType == "text" or inputType == "password" or inputType == "textarea" then
        field.type = inputType
    elseif inputType == "number" then
        field.type = "number"
        field.min = input.min
        field.max = input.max
    elseif inputType == "checkbox" then
        field.type = "checkbox"
        -- Some qb-input forks use `checked`, others `default` -- honour
        -- whichever is actually set.
        if input.checked ~= nil then field.default = input.checked end
    elseif inputType == "radio" or inputType == "select" then
        -- QB.nui.openInputDialog has no dedicated radio-group widget --
        -- `select` is the closest equivalent (single value from a fixed
        -- option list), so `radio` collapses onto it rather than being
        -- refused outright.
        field.type = "select"
        field.options = translateOptions(input.options)
    elseif inputType == "slider" then
        -- Newer qb-input forks; maps directly onto `range`.
        field.type = "range"
        field.min = input.min
        field.max = input.max
        field.step = input.step
    else
        warnUnknownTypeOnce(inputType)
        field.type = "text"
    end

    return field
end

-- Real ShowInput blocks the calling coroutine and returns either a table of
-- `{ [name]: value }` (submit) or `false` (cancel) -- never a promise the
-- caller has to unwrap. Matched here exactly, via an unconditional
-- Citizen.Await: same idiom as compat/client/qb-menu.lua's openMenu and
-- modules/minigames/client.lua's beginPlay (Citizen.Await passes an
-- already-settled value straight through and genuinely awaits a pending
-- promise, so this is correct regardless of whether QB.nui.openInputDialog
-- decided to hand back a promise or an awaited value underneath).
local function ShowInput(data)
    -- Upstream returns nil for an empty request or while its one dialog is
    -- already active. Preserve that non-reentrant contract instead of opening
    -- overlapping request promises that neither caller can safely own.
    if type(data) ~= "table" or type(data.inputs) ~= "table" or inputOpen then return nil end

    local fields = {}
    for i, input in ipairs(data.inputs) do
        fields[i] = translateField(input)
    end

    inputOpen = true
    local ok, result = pcall(function()
        return Citizen.Await(QB.nui.openInputDialog(fields, data.header))
    end)
    inputOpen = false
    if not ok then error(result, 0) end
    if not result or result.cancelled then return false end

    return result.values
end

provideExport("qb-input", "ShowInput", ShowInput)
