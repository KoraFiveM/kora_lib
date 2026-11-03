-- Legacy callback retained for callers that integrated with kora_lib before the
-- shared kora_theme browser loader existed.
Kora.nui.registerCallback("kora_lib:nui:theme", function()
    return { accentColor = Kora.theme.accentColor() }
end)

---Reapplies kora_theme to kora_lib's own NUI frame.
---@return table<string, string> tokens
function Kora.theme.push()
    return QBTheme.refresh()
end

---Runs a handler whenever an admin changes the server fonts in /config. The
---imported bridge already updates kora_lib's own NUI frame.
---@param handler fun(fonts: table)
---@return fun() unsubscribe
function Kora.theme.onFontsChanged(handler)
    assert(type(handler) == "function", "Kora.theme.onFontsChanged expects a function.")
    local event = AddEventHandler("qbtheme:fontsChanged", function()
        handler(Kora.theme.getFonts())
    end)
    return function() RemoveEventHandler(event) end
end
