return function()
    local compat = {}

    ---@param providedResource string
    ---@param exportName string
    ---@param func function|table
    function compat.provideExport(providedResource, exportName, func)
        assert(type(providedResource) == 'string' and providedResource ~= '',
            'QB.compat.provideExport requires a resource name.')
        assert(type(exportName) == 'string' and exportName ~= '',
            'QB.compat.provideExport requires an export name.')
        assert(QB.util.isCallable(func), 'QB.compat.provideExport requires a callable value.')

        AddEventHandler(('__cfx_export_%s_%s'):format(providedResource, exportName), function(setCallback)
            setCallback(func)
        end)
    end

    return compat
end
