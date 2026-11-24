if type(Config) == 'table' and type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() == 'kora_lib' then
    local source = assert(LoadResourceFile('kora_lib', 'modules/config/consumer.lua'))
    local factory = assert(load(source, '@@kora_lib/modules/config/consumer.lua', 't', _ENV))()
    local bridge = factory(exports.kora_lib)
    if type(Config.bridge) == 'table' then
        for _, area in ipairs({ 'banking', 'bossmenu', 'clothing', 'dispatch', 'doorlock', 'fuel', 'helptext', 'notify', 'vehiclekeys' }) do
            local provider = Config.bridge[area]
            if type(provider) == 'string' then
                Config.bridge[area] = bridge.string(provider, {
                    live = true,
                    minLength = 1,
                    maxLength = 128,
                    pattern = '^[%w_.%-]+$',
                })
            end
        end
    end
    if type(Config.notify) == 'table' then
        Config.notify.defaultType = bridge.enum(Config.notify.defaultType, {
            live = true,
            label = KoraLang('Modules.Config.editor.schema_notify_type'),
            description = KoraLang('Modules.Config.editor.schema_notify_type_description'),
            options = { 'info', 'success', 'warning', 'error' },
        })
        Config.notify.defaultPosition = bridge.enum(Config.notify.defaultPosition, {
            live = true,
            label = KoraLang('Modules.Config.editor.schema_notify_position'),
            description = KoraLang('Modules.Config.editor.schema_notify_position_description'),
            options = { 'top-left', 'top-center', 'top-right', 'bottom-left', 'bottom-center', 'bottom-right' },
        })
    end
    Config = bridge.adopt(Config)
end
