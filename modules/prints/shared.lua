local function handleException(reason, value)
    if type(value) == 'function' then return tostring(value) end
    return reason
end

local function formatArgs(...)
    local args = table.pack(...)
    local formatted = {}
    local jsonOptions = {
        sort_keys = true,
        indent = true,
        exception = handleException
    }

    for i = 1, args.n do
        local value = args[i]

        if type(value) == "table" then
            local ok, encoded = pcall(json.encode, value, jsonOptions)
            formatted[i] = ok and type(encoded) == 'string' and encoded or tostring(value)
        elseif type(value) == "boolean" then
            formatted[i] = tostring(value)
        elseif value == nil then
            formatted[i] = 'nil'
        elseif type(value) == 'number' then
            formatted[i] = '^7' .. tostring(value) .. '^0'
        else
            formatted[i] = tostring(value)
        end
    end

    return table.concat(formatted, ' ')
end

---@param ... any
function Kora.print.debug(...)
    print('^6[DEBUG]^0 ' .. formatArgs(...))
end

---@param ... any
function Kora.print.info(...)
    print('^4[INFO]^0 ' .. formatArgs(...))
end

---@param ... any
function Kora.print.error(...)
    print('^1[ERROR]^0 ' .. formatArgs(...))
end

---@param ... any
function Kora.print.warn(...)
    print('^3[WARNING]^0 ' .. formatArgs(...))
end

---@param ... any
function Kora.print.success(...)
    print('^2[SUCCESS]^0 ' .. formatArgs(...))
end
