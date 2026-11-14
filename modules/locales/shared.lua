local storedLocales = {}

local function validLanguage(language)
    return type(language) == 'string' and language:match('^[%w][%w%-_]*$') ~= nil
end

local function validResource(resource)
    return type(resource) == 'string' and resource:match('^[%w_%-]+$') ~= nil
end

local function defaultLanguage()
    local language = GetConvar('kora_locale', 'en')
    return validLanguage(language) and language or 'en'
end

local function currentLanguage()
    return Kora.locale._language or defaultLanguage()
end

local function configuredLanguages()
    local configured = GetConvar('kora_locales', '')
    local seen, languages = {}, {}

    local function add(language)
        if validLanguage(language) and not seen[language] then
            seen[language] = true
            languages[#languages + 1] = language
        end
    end

    for language in configured:gmatch('[^,%s]+') do add(language) end
    add(defaultLanguage())
    add('en')
    table.sort(languages)
    return languages
end

local function loadLocaleFile(resource, language)
    local jsonPath = ('locales/%s.json'):format(language)
    local jsonRaw = LoadResourceFile(resource, jsonPath)
    if jsonRaw then
        local ok, decoded = pcall(json.decode, jsonRaw)
        if ok and type(decoded) == 'table' then return decoded end
    end

    local luaPath = ('locales/%s.lua'):format(language)
    local luaRaw = LoadResourceFile(resource, luaPath)
    if not luaRaw then return nil end

    local noopLocale = { new = function() return { addLocale = function() end } end }
    local chunk = load(luaRaw, ('@@%s/%s'):format(resource, luaPath), 't', {
        Locale = noopLocale,
        GetConvar = function(_, fallback) return fallback end,
    })
    if not chunk then return nil end

    local ok, result = pcall(chunk)
    return ok and type(result) == 'table' and result or nil
end

local function resourceLocales(resource, language)
    local cached = storedLocales[resource]
    if not cached then
        cached = {}
        storedLocales[resource] = cached
    end
    if cached[language] == nil then cached[language] = loadLocaleFile(resource, language) or false end
    return cached[language] or nil
end

local function phrase(locales, key)
    local current = locales
    for part in key:gmatch('([^%.]+)') do
        if type(current) ~= 'table' then return nil end
        current = current[part]
        if current == nil then return nil end
    end
    return current
end

local function interpolate(value, ...)
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

local function translate(resource, key, ...)
    local translated = phrase(resourceLocales(resource, currentLanguage()), key)
        or phrase(resourceLocales(resource, 'en'), key)
    return translated == nil and key or interpolate(translated, ...)
end

---Returns the language selected for this FiveM client. On the server this is
---the configured fallback language because client KVP storage is local only.
---@return string
function Kora.locale.getLanguage()
    return currentLanguage()
end

---Returns the server's selectable language codes. Configure them with
---`setr kora_locales "en,de"`; English and `kora_locale` are always included.
---@return string[]
function Kora.locale.getLanguages()
    return configuredLanguages()
end

---Resolves a locale key for an explicit resource. This is primarily used by
---the qb-core compatibility layer to resolve server-originated notifications
---on the receiving client.
---@param resource string
---@param key string
---@param ... any
---@return any
function Kora.locale.translate(resource, key, ...)
    assert(validResource(resource), 'locale resource must be a valid resource name.')
    assert(type(key) == 'string' and key ~= '', 'locale key must be a non-empty string.')
    return translate(resource, key, ...)
end

function Kora.lang(key, ...)
    local resource = GetInvokingResource() or GetCurrentResourceName()
    assert(type(key) == 'string' and key ~= '', 'locale key must be a non-empty string.')
    return translate(resource, key, ...)
end

function Kora.locale.getResourceLocale(resource)
    if not resource then
        resource = GetInvokingResource() or GetCurrentResourceName()
    end
    return resourceLocales(resource, currentLanguage())
end
