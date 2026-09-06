-- Compatibility surface: qbtheme owns validation and token derivation, while
-- existing consumers can keep using QB.theme without a breaking migration.

---@return string hex `#RRGGBB`
function QB.theme.accentColor()
    return exports.qbtheme:getPrimaryColor()
end

---@param overrides? string|table A primary hex shorthand or semantic override table.
---@return table<string, string> tokens
function QB.theme.tokens(overrides)
    return exports.qbtheme:getTokens(overrides)
end
