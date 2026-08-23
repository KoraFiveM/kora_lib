local storedLang = {}
local language = GetConvar('qb_locale', 'en')

local function loadLocaleFile(resource)
    local jsonPath = ('locales/%s.json'):format(language)
    local jsonRaw = LoadResourceFile(resource, jsonPath)

    if jsonRaw then
        local ok, decoded = pcall(json.decode, jsonRaw)
        if ok and type(decoded) == 'table' then
            return decoded
        end
    end

    local luaPath = ('locales/%s.lua'):format(language)
    local luaRaw = LoadResourceFile(resource, luaPath)

    if not luaRaw then
        return nil
    end

    local chunk, err = load(luaRaw, ('@@%s/%s'):format(resource, luaPath))
    if not chunk then
        return nil
    end

    local ok, result = pcall(chunk)
    if not ok then
        return nil
    end

    if type(result) ~= 'table' then
        return nil
    end

    return result
end

function QB.lang(key, ...)
    local resource = GetInvokingResource() or GetCurrentResourceName()
    assert(resource, 'Resource name not found')

    local locales = storedLang[resource]
    if not locales then
        locales = loadLocaleFile(resource) or {}
        storedLang[resource] = locales
    end

    local current = locales
    for part in key:gmatch('([^%.]+)') do
        if type(current) ~= 'table' then
            return key
        end
        current = current[part]
        if current == nil then
            return key
        end
    end

    if type(current) == 'string' and select('#', ...) > 0 then
        local ok, formatted = pcall(string.format, current, ...)
        if ok then return formatted end
        return current
    end

    return current
end
QB.locale = QB.lang