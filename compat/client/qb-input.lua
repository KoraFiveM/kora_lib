-- Compat bridge: translates exports['qb-input']:ShowInput onto Kora.nui.openInputDialog.
-- Field mapping and caveats: see modules/nui/docs.md "Legacy compat".

-- Kora.compat.provideExport registers the hidden CFX export event under the
-- legacy `qb-input` identity; `provide 'qb-input'` alone only satisfies
-- dependency checks.

-- Warned once per resource run: qb-input's Font Awesome `icon` class has no InputField equivalent, so it is dropped.
local warnedIcon = false
local function warnIconOnce()
    if warnedIcon then return end
    warnedIcon = true
    print("[qb-input-bridge] WARNING: input 'icon' fields (Font Awesome classes) have no equivalent on "
        .. "Kora.nui.openInputDialog's fields -- icons are dropped. Only shown once per session.")
end

-- Warned once per unrecognized type name, so the porter knows which type to check.
local warnedTypes = {}
local inputOpen = false
local function warnUnknownTypeOnce(inputType)
    if warnedTypes[inputType] then return end
    warnedTypes[inputType] = true
    print(("[qb-input-bridge] WARNING: input type %q is not recognized -- falling back to a plain text field. "
        .. "Only shown once per type per session."):format(tostring(inputType)))
end

-- radio/select options carry {value, text} in real qb-input (some forks use
-- `label` instead of `text`); Kora.nui's field expects {value, label} with
-- both stringified -- Select's value plumbing (web/src/components/ui/select.tsx)
-- is string-keyed throughout.
local function translateOptions(options)
    local translated = {}

    options = options or {}
    for i = 1, #options do
        local option = options[i]
        translated[i] = {
            value = tostring(option.value),
            label = option.text or option.label or tostring(option.value),
        }
    end

    return translated
end

-- qb-input's "checkbox" type is a GROUP: the entry carries `options[]` and the result is keyed by each
-- option's own `value`, never by `name` (see upstream html/script.js renderCheckboxInput).
-- Kora.nui has only a single-boolean checkbox, so each option expands into its own boolean field keyed by
-- that option's `value`, with the group's `text` prefixed to the label. A checkbox with no `options`
-- (simplified forks) falls through to the single-boolean field keyed by `name`.
local function translateCheckboxOptions(input, fields)
    local prefix = (input.text and input.text ~= "") and (input.text .. ": ") or ""
    for optionIndex = 1, #input.options do
        local option = input.options[optionIndex]
        fields[#fields + 1] = {
            id = tostring(option.value),
            label = prefix .. (option.text or option.label or tostring(option.value)),
            type = "checkbox",
            default = option.checked == true,
        }
    end
end

-- Maps one qb-input `inputs[]` entry onto an InputField. id == name so the legacy `result[name]` lookup works unchanged.
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
        -- Kora.nui.openInputDialog has no dedicated radio-group widget --
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
-- caller has to unwrap. Kora.nui.openInputDialog already performs that wait when
-- this compatibility export was invoked by another resource. A direct kora_lib
-- invocation still returns a promise, so retain the await for that path.
local function showInput(data)
    -- Upstream returns nil for an empty request or while its one dialog is
    -- already active. Preserve that non-reentrant contract instead of opening
    -- overlapping request promises that neither caller can safely own.
    if type(data) ~= "table" or type(data.inputs) ~= "table" or inputOpen then return nil end

    local fields = {}
    for inputIndex = 1, #data.inputs do
        local input = data.inputs[inputIndex]
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
        local response = Kora.nui.openInputDialog(fields, data.header)
        if not calledFromExport then return Citizen.Await(response) end
        return response
    end)
    inputOpen = false
    if not ok then error(result, 0) end
    if not result or result.cancelled then return false end

    return result.values
end

Kora.compat.provideExport("qb-input", "ShowInput", showInput)
