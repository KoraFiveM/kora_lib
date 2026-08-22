

local function handleException(reason, value)
    if type(value) == 'function' then return tostring(value) end
    return reason
end

local function formatArgs(...)
    local args = { ... }
    local argCount = select('#', ...)
    local formatted = {}
    local jsonOptions = { sort_keys = true, indent = true, exception = handleException }

    for k = 1, argCount do
        local v = args[k]
        if type(v) == "table" then
            table.insert(formatted, json.encode(v, jsonOptions))
        elseif type(v) == "boolean" then
            table.insert(formatted, tostring(v))
        elseif v == nil then
            table.insert(formatted, 'nil')
        else
            table.insert(formatted, tostring(v))
        end
    end

    return table.concat(formatted, ' ')
end

function QB.print.debug(...)
    print('^6[DEBUG]^0 ' .. formatArgs(...))
end

function QB.print.info(...)
    print('^4[INFO]^0 ' .. formatArgs(...))
end

function QB.print.error(...)
    print('^1[ERROR]^0 ' .. formatArgs(...))
end

function QB.print.warn(...)
    print('^3[WARNING]^0 ' .. formatArgs(...))
end

function QB.print.success(...)
    print('^2[SUCCESS]^0 ' .. formatArgs(...))
end
