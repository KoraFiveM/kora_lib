local koraLocaleFiles = {}
local koraLocalePhrases = {}
local koraLocaleResource = GetCurrentResourceName()

local function validKoraLanguage(language)
    return type(language) == 'string' and language:match('^[%w][%w%-_]*$') ~= nil
end

local function loadKoraLocale(language)
    if koraLocaleFiles[language] ~= nil then return koraLocaleFiles[language] or nil end

    local path = ('locales/%s.lua'):format(language)
    local source = LoadResourceFile(koraLocaleResource, path)
    if not source then
        koraLocaleFiles[language] = false
        return nil
    end

    local noopLocale = { new = function() return { addLocale = function() end } end }
    local chunk = load(source, ('@@%s/%s'):format(koraLocaleResource, path), 't', {
        Locale = noopLocale,
        GetConvar = function(_, fallback) return fallback end,
    })
    if not chunk then
        koraLocaleFiles[language] = false
        return nil
    end

    local ok, locales = pcall(chunk)
    if not ok or type(locales) ~= 'table' then
        koraLocaleFiles[language] = false
        return nil
    end

    koraLocaleFiles[language] = locales
    return locales
end

local function koraLocalePhrase(locales, key)
    local value = locales
    for part in key:gmatch('([^%.]+)') do
        if type(value) ~= 'table' then return nil end
        value = value[part]
    end
    return value
end

local function koraLocaleInterpolate(value, ...)
    if type(value) ~= 'string' then return value end

    local substitutions = select(1, ...)
    if type(substitutions) == 'table' then
        for key, replacement in pairs(substitutions) do
            local escapedKey = tostring(key):gsub('([^%w])', '%%%1')
            value = value:gsub('%%{' .. escapedKey .. '}', function() return tostring(replacement) end)
        end
        return value
    end

    if select('#', ...) > 0 then
        local ok, formatted = pcall(string.format, value, ...)
        if ok then return formatted end
    end
    return value
end

---Looks up a kora_lib-owned locale key using the kora_locale convar.
---@param key string
---@param ... any
---@return any
function KoraLang(key, ...)
    assert(type(key) == 'string' and key ~= '', 'locale key must be a non-empty string.')

    local language = GetConvar('kora_locale', 'en')
    if not validKoraLanguage(language) then language = 'en' end

    local phrases = koraLocalePhrases[language]
    if not phrases then
        phrases = {}
        koraLocalePhrases[language] = phrases
    end
    local translated = phrases[key]
    if translated == nil then
        translated = koraLocalePhrase(loadKoraLocale(language), key)
            or koraLocalePhrase(loadKoraLocale('en'), key)
            or key
        phrases[key] = translated
    end
    if select('#', ...) == 0 then return translated end
    return koraLocaleInterpolate(translated, ...)
end
