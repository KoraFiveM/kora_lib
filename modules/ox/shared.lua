---Returns the locale selected by qblib for the ox_lib compatibility surface.
---@param owner? string Private originating-resource metadata from ox_lib.
---@return string locale
function QB.ox.getLocaleKey(owner)
    assert(owner == nil or (type(owner) == 'string' and owner ~= ''), 'ox locale owner must be a non-empty string.')
    return QB.locale.getLanguage()
end
