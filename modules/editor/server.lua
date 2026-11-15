local C = Config.editor or {}

local function notify(src, message)
    Kora.notify.send(src, {
        title = KoraLang('Modules.Editor.title'),
        message = message,
        type = 'error',
    })
end

local function allowed(src)
    if C.enabled ~= true then return false end
    local permission = C.permission or 'editor'
    local prefix = C.permissionPrefix or 'kora_lib'
    return Kora.permissions.hasPermission(src, permission, prefix)
end

local suggestions = {}

local publicSuggestions = {
    { name = 'kora_zonedebug', help = KoraLang('Modules.Editor.zone_toggle_help'), params = { { name = 'on|off', help = KoraLang('Modules.Editor.optional_toggle_help') } } },
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
        if src <= 0 then return print(KoraLang('Modules.Editor.player_command'):format(name)) end
        if not allowed(src) then return notify(src, KoraLang('Modules.Editor.no_access')) end

        local value, err = resolve(args or {})
        if value == nil then return notify(src, err) end
        TriggerClientEvent(eventName, src, value)
    end, false)
end

register(C.zoneCommand or 'kora_zonecreator', 'kora_lib:editor:startZoneCreator', function(args)
    local zoneType = type(args[1]) == 'string' and args[1]:lower() or 'box'
    if zoneType ~= 'box' and zoneType ~= 'sphere' and zoneType ~= 'poly' then
        return nil, KoraLang('Modules.Editor.zone_usage')
    end
    return zoneType
end, KoraLang('Modules.Editor.zone_help'), { { name = 'type', help = KoraLang('Modules.Editor.zone_param_help') } })

register(C.placementCommand or 'kora_place', 'kora_lib:editor:startPlacement', function(args)
    local model = args[1]
    if type(model) ~= 'string' or model == '' or #model > 64 or not model:match('^[%w_%-]+$') then
        return nil, KoraLang('Modules.Editor.placement_usage')
    end
    return model
end, KoraLang('Modules.Editor.placement_help'), { { name = 'model', help = KoraLang('Modules.Editor.model_param_help') } })

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, playerId in ipairs(GetPlayers()) do suggest(tonumber(playerId)) end
end)

AddEventHandler('playerJoining', function()
    local src = source
    SetTimeout(10000, function()
        if GetPlayerName(src) then suggest(src) end
    end)
end)

AddEventHandler('chat:init', function()
    local src = source
    if src and src > 0 then suggest(src) end
end)
