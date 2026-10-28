return function()
    local compat = {}

    -- Consumer-local QB.util uses the same callable rules as kora_lib's own VM.
    -- Keep this here to avoid routing callback validation back through an
    -- export when the surrounding module is deliberately local.
    local function isCallable(value, seen)
        if type(value) == 'function' then return true end
        if type(value) ~= 'table' then return false end
        if type(rawget(value, '__cfx_functionReference')) == 'string' then return true end

        seen = seen or {}
        if seen[value] then return false end
        seen[value] = true
        local mt = getmetatable(value)
        return type(mt) == 'table' and isCallable(mt.__call, seen)
    end

    compat.isCallable = isCallable

    ---@param providedResource string
    ---@param exportName string
    ---@param func function|table
    function compat.provideExport(providedResource, exportName, func)
        assert(type(providedResource) == 'string' and providedResource ~= '',
            'QB.compat.provideExport requires a resource name.')
        assert(type(exportName) == 'string' and exportName ~= '',
            'QB.compat.provideExport requires an export name.')
        assert(isCallable(func), 'QB.compat.provideExport requires a callable value.')

        AddEventHandler(('__cfx_export_%s_%s'):format(providedResource, exportName), function(setCallback)
            setCallback(func)
        end)
    end

    return compat
end
