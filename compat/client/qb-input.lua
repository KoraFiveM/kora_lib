local warnedIcon = false
local function warnIconOnce()
    if warnedIcon then return end
    warnedIcon = true
    print("[qb-input-bridge] WARNING: input 'icon' fields (Font Awesome classes) have no equivalent on "
        .. "Kora.nui.openInputDialog's fields -- icons are dropped. Only shown once per session.")
end

local warnedTypes = {}
local inputOpen = false
local function warnUnknownTypeOnce(inputType)
    if warnedTypes[inputType] then return end
    warnedTypes[inputType] = true
    print(("[qb-input-bridge] WARNING: input type %q is not recognized -- falling back to a plain text field. "
        .. "Only shown once per type per session."):format(tostring(inputType)))
end

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
        if input.checked ~= nil then field.default = input.checked end
    elseif inputType == "radio" or inputType == "select" then
        field.type = "select"
        field.options = translateOptions(input.options)
    elseif inputType == "slider" then
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

local function showInput(data)
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

    local calledFromExport = GetInvokingResource() ~= nil

    inputOpen = true
    local ok, result = pcall(function()
        local response = Kora.nui.openInputDialog(fields, data.header)
        if not calledFromExport then return Citizen.Await(response) end
        return response
    end)
    inputOpen = false
    if not ok then error(result, 0) end
    if not result or result.cancelled then return nil end

    return result.values
end

Kora.compat.provideExport("qb-input", "ShowInput", showInput)
