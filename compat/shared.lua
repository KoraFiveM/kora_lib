---Registers an export under another provided resource identity. `provide` in
---the manifest only satisfies dependency resolution; this handler makes
---`exports[providedResource]:name()` resolve to `func` in either realm.
---@param providedResource string
---@param exportName string
---@param func function|table Callable function or FiveM funcref.
function Kora.compat.provideExport(providedResource, exportName, func)
    assert(type(providedResource) == "string" and providedResource ~= "",
        "Kora.compat.provideExport requires a resource name.")
    assert(type(exportName) == "string" and exportName ~= "",
        "Kora.compat.provideExport requires an export name.")
    assert(Kora.compat.isCallable(func), "Kora.compat.provideExport requires a callable value.")

    AddEventHandler(("__cfx_export_%s_%s"):format(providedResource, exportName), function(setCallback)
        setCallback(func)
    end)
end
