-- Registers an export under a provided legacy resource identity. `provide` in
-- fxmanifest.lua only satisfies dependency checks; it does not make an
-- exports['legacy-resource']:function() lookup resolve to qblib.
function QB.compat.provideExport(providedResource, exportName, func)
    AddEventHandler(('__cfx_export_%s_%s'):format(providedResource, exportName), function(setCB)
        setCB(func)
    end)
end
