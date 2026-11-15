---Returns the locale selected by kora_lib for the ox_lib compatibility surface.
---@param owner? string Private originating-resource metadata from ox_lib.
---@return string locale
function Kora.ox.getLocaleKey(owner)
    assert(owner == nil or (type(owner) == 'string' and owner ~= ''), KoraLang('Modules.Ox.locale_owner_invalid'))
    return Kora.locale.getLanguage()
end
