-- Compatibility surface: kora_theme owns validation and token derivation, while
-- existing consumers can keep using Kora.theme without a breaking migration.

---@return string hex `#RRGGBB`
function Kora.theme.accentColor()
    return exports.kora_theme:getPrimaryColor()
end

---@param overrides? string|table A primary hex shorthand or semantic override table.
---@return table<string, string> tokens
function Kora.theme.tokens(overrides)
    return exports.kora_theme:getTokens(overrides)
end
