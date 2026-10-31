-- Admin-facing entry commands for kora_lib's client-side zone and entity
-- editors. This is a convenience/UX gate only: a modified client can invoke
-- its own local library code, so consuming resources must separately
-- authorize every persistent or gameplay-affecting change on the server.

local C = Config.editor or {}

local function notify(src, message)
    Kora.notify.send(src, {
        title = 'kora_lib editor',
        message = message,
        type = 'error',
    })
end

local function allowed(src)
    if C.enabled ~= true then return false end
    local permission = C.permission or 'editor'
    local prefix = C.permissionPrefix or 'kora_lib'
    -- Servers that granted the deprecated qblib.editor ACE keep working.
    return Kora.permissions.hasPermission(src, permission, prefix)
        or (prefix == 'kora_lib' and Kora.permissions.hasPermission(src, permission, 'qblib'))
end

local function register(name, eventName, resolve)
    if type(name) ~= 'string' or name == '' then return end
    RegisterCommand(name, function(src, args)
        if src <= 0 then return print(('%s is an in-game player command.'):format(name)) end
        if not allowed(src) then return notify(src, 'You do not have access to the developer editors.') end

        local value, err = resolve(args or {})
        if value == nil then return notify(src, err) end
        TriggerClientEvent(eventName, src, value)
    end, false)
end

register(C.zoneCommand or 'qb_zonecreator', 'kora_lib:editor:startZoneCreator', function(args)
    local zoneType = type(args[1]) == 'string' and args[1]:lower() or 'box'
    if zoneType ~= 'box' and zoneType ~= 'sphere' and zoneType ~= 'poly' then
        return nil, 'Usage: /qb_zonecreator [box|sphere|poly]'
    end
    return zoneType
end)

register(C.placementCommand or 'qb_place', 'kora_lib:editor:startPlacement', function(args)
    local model = args[1]
    if type(model) ~= 'string' or model == '' or #model > 64 or not model:match('^[%w_%-]+$') then
        return nil, 'Usage: /qb_place <model>'
    end
    return model
end)
