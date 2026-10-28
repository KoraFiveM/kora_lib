-- Legacy callback retained for callers that integrated with kora_lib before the
-- shared kora_theme browser loader existed.
QB.nui.registerCallback("qblib:nui:theme", function()
    return { accentColor = QB.theme.accentColor() }
end)

---Reapplies kora_theme to kora_lib's own NUI frame.
---@return table<string, string> tokens
function QB.theme.push()
    return QBTheme.refresh()
end
