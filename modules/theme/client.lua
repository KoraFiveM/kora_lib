-- Legacy callback retained for callers that integrated with qblib before the
-- shared qbtheme browser loader existed.
QB.nui.registerCallback("qblib:nui:theme", function()
    return { accentColor = QB.theme.accentColor() }
end)

---Reapplies qbtheme to qblib's own NUI frame.
function QB.theme.push()
    return QBTheme.refresh()
end
