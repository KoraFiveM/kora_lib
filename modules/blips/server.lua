-- Registers the callback under its kora_lib: name and under the deprecated
-- qblib: alias, so callers that predate the rename keep working.
local function registerWithLegacyAlias(name, handler, options)
    Kora.callback.register(name, handler, options)
    Kora.callback.register((name:gsub('^kora_lib:', 'qblib:')), handler, options)
end

-- The settings app is client-local, but resource ownership is operational
-- information. Resolve the viewer's permission server-side and let the UI
-- fail closed when this callback is unavailable.
registerWithLegacyAlias('kora_lib:blips:isAdmin', function(src)
    if type(src) ~= 'number' or src < 1 or src % 1 ~= 0 or src ~= src
        or src == math.huge or src == -math.huge then
        return false
    end
    return Kora.permissions.hasPermission(src, 'admin') == true
end, { rateLimit = { max = 10, window = 10000 } })
