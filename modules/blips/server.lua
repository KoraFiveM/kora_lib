-- The settings app is client-local, but resource ownership is operational
-- information. Resolve the viewer's permission server-side and let the UI
-- fail closed when this callback is unavailable.
QB.callback.register('qblib:blips:isAdmin', function(src)
    if type(src) ~= 'number' or src <= 0 then return false end
    return QB.permissions.hasPermission(src, 'admin') == true
end, { rateLimit = { max = 10, window = 10000 } })
