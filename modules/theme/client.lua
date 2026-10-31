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
