local function registerWithLegacyAlias(name, handler, options)
    Kora.callback.register(name, handler, options)
    Kora.callback.register((name:gsub('^kora_lib:', 'qblib:')), handler, options)
end

registerWithLegacyAlias('kora_lib:blips:isAdmin', function(src)
    if type(src) ~= 'number' or src < 1 or src % 1 ~= 0 or src ~= src
        or src == math.huge or src == -math.huge then
        return false
    end
    return Kora.permissions.hasPermission(src, 'admin') == true
end, { rateLimit = { max = 10, window = 10000 } })
