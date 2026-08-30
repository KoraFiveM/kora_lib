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

-- Real qb-input's "checkbox" type is a CHECKBOX GROUP, not a single boolean:
-- an `inputs[]` entry of type "checkbox" carries its own `options[]` list
-- (each `{value, text, checked}`, same shape as radio/select), and the
-- submitted result is keyed by EACH OPTION'S OWN `value` -- never by the
-- input's own `name` at all. See qbcore-framework/qb-input's
-- html/script.js: `renderCheckboxInput` sets `formInputs[option.value] =
-- option.checked and "true" or "false"` for every option, and `name` is
-- only used to group the `<input>` elements in the DOM, not as a result key.
-- QB.nui.openInputDialog's `checkbox` field type is a single boolean keyed
-- by its own `id` -- there is no multi-option checkbox-group widget to route
-- to -- so one real checkbox input with options expands into N separate
-- boolean fields here, one per option, each keyed by that option's OWN
-- value exactly like upstream, with the group's own `text` prefixed onto
-- each option's label for context since the flat field list can't show
-- visual grouping. A checkbox input with no `options` (some simplified
-- qb-input forks use a single scalar `checked`/`default` boolean instead of
-- a group) still falls through to the single-boolean field below, keyed by
-- `name` as before.
local function translateCheckboxOptions(input, fields)
    local prefix = (input.text and input.text ~= "") and (input.text .. ": ") or ""
    for _, option in ipairs(input.options) do
        fields[#fields + 1] = {
            id = tostring(option.value),
            label = prefix .. (option.text or option.label or tostring(option.value)),
            type = "checkbox",
            default = option.checked == true,
        }
    end
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
        -- Only reached for a checkbox with no `options` -- see
        -- translateCheckboxOptions above for the (real, upstream) group case,
        -- which ShowInput routes there before this function ever runs.
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
-- caller has to unwrap. QB.nui.openInputDialog already performs that wait when
-- this compatibility export was invoked by another resource. A direct qblib
-- invocation still returns a promise, so retain the await for that path.
local function ShowInput(data)
    -- Upstream returns nil for an empty request or while its one dialog is
    -- already active. Preserve that non-reentrant contract instead of opening
    -- overlapping request promises that neither caller can safely own.
    if type(data) ~= "table" or type(data.inputs) ~= "table" or inputOpen then return nil end

    local fields = {}
    for _, input in ipairs(data.inputs) do
        if input.type == "checkbox" and type(input.options) == "table" and #input.options > 0 then
            translateCheckboxOptions(input, fields)
        else
            fields[#fields + 1] = translateField(input)
        end
    end

    -- Capture before the NUI wrapper can yield; the original export runtime
    -- might not still be present when this coroutine resumes.
    local calledFromExport = GetInvokingResource() ~= nil

    inputOpen = true
    local ok, result = pcall(function()
        local response = QB.nui.openInputDialog(fields, data.header)
        if not calledFromExport then return Citizen.Await(response) end
        return response
    end)
    inputOpen = false
    if not ok then error(result, 0) end
    if not result or result.cancelled then return false end

    return result.values
end

provideExport("qb-input", "ShowInput", ShowInput)
