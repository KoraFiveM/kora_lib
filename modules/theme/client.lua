-- The frontend fetches this once on mount, which is more reliable than a
-- startup SendNUIMessage: the page may not have attached its event listener
-- at the moment client scripts begin loading. QB.theme.push() (below) covers
-- the matching live-resync path the frontend's ThemeSynchronizer also
-- understands. Callback name and response shape are unchanged from before
-- this module existed -- qblib's own NUI depends on both exactly as-is.
QB.nui.registerCallback("qblib:nui:theme", function()
    return { accentColor = QB.theme.accentColor() }
end)

---Pushes the current accent colour to qblib's own NUI as a live resync,
---via the same "qblib:theme" action ThemeSynchronizer already listens for.
---Consuming resources with their own NUI don't use this -- they call
---QB.theme.tokens() directly and forward the result to their own frame (see
---modules/theme/docs.md).
function QB.theme.push()
    QB.nui.send("qblib:theme", { accentColor = QB.theme.accentColor() })
end
