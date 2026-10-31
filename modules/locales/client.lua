local KVP_KEY = 'locale'

local function validLanguage(language)
    return type(language) == 'string' and language:match('^[%w][%w%-_]*$') ~= nil
end

local savedLanguage = GetResourceKvpString(KVP_KEY)
if validLanguage(savedLanguage) then Kora.locale._language = savedLanguage end

---Persists a language preference for this FiveM player. This is deliberately
---client KVP storage, so it is neither a character field nor sent to the DB.
---@param language string
---@return boolean, string|nil
function Kora.locale.setLanguage(language)
    if not validLanguage(language) then return false, 'Language codes may only contain letters, numbers, hyphens, and underscores.' end

    local allowed = false
    local languages = Kora.locale.getLanguages()
    for candidateIndex = 1, #languages do
        local candidate = languages[candidateIndex]
        if candidate == language then
            allowed = true
            break
        end
    end
    if not allowed then return false, ('%s is not enabled by qb_locales.'):format(language) end

    local oldLanguage = Kora.locale.getLanguage()
    if oldLanguage == language then return true end

    SetResourceKvp(KVP_KEY, language)
    Kora.locale._language = language
    TriggerEvent('kora_lib:client:localeChanged', language, oldLanguage)
    -- Deprecated alias for listeners that predate the kora_lib rename.
    TriggerEvent('qblib:client:localeChanged', language, oldLanguage)
    return true
end
