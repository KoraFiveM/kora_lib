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

local suggestions = {}

-- Client-registered commands open to every player. The client cannot publish these itself: its
-- chat:addSuggestion at resource load runs before the chat UI exists, and chat:init is a server event.
local publicSuggestions = {
    { name = 'qb_zonedebug', help = 'Toggle zone debug drawing', params = { { name = 'on|off', help = 'Optional; omit to toggle' } } },
}

local function suggest(src)
    if src <= 0 then return end
    for _, s in ipairs(publicSuggestions) do
        TriggerClientEvent('chat:addSuggestion', src, '/' .. s.name, s.help, s.params)
    end
    if not allowed(src) then return end
    for _, s in ipairs(suggestions) do
        TriggerClientEvent('chat:addSuggestion', src, '/' .. s.name, s.help, s.params)
    end
end

local function register(name, eventName, resolve, help, params)
    if type(name) ~= 'string' or name == '' then return end
    suggestions[#suggestions + 1] = { name = name, help = help or '', params = params or {} }
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
end, 'Start the in-world zone creator (admin)', { { name = 'type', help = 'box | sphere | poly (default box)' } })

register(C.placementCommand or 'qb_place', 'kora_lib:editor:startPlacement', function(args)
    local model = args[1]
    if type(model) ~= 'string' or model == '' or #model > 64 or not model:match('^[%w_%-]+$') then
        return nil, 'Usage: /qb_place <model>'
    end
    return model
end, 'Start the entity placement tool (admin)', { { name = 'model', help = 'Model name to place' } })

-- Chat suggestions: only players with editor access see these commands.
AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, playerId in ipairs(GetPlayers()) do suggest(tonumber(playerId)) end
end)

AddEventHandler('playerJoining', function()
    local src = source
    -- The chat UI is not ready the instant a player joins.
    SetTimeout(10000, function()
        if GetPlayerName(src) then suggest(src) end
    end)
end)

-- The chat UI triggers this server event once it has loaded, which is the reliable moment to publish.
AddEventHandler('chat:init', function()
    local src = source
    if src and src > 0 then suggest(src) end
end)
