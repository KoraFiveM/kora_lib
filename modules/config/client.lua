-- qblib's own client-side configuration consumer. The server-side catalog
-- bridge lives in server.lua; this counterpart receives only the shared and
-- client-scoped portion of qblib's configuration.

if type(Config) == 'table' and type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() == 'qblib' then
    local source = assert(LoadResourceFile('qblib', 'modules/config/consumer.lua'))
    local factory = assert(load(source, '@@qblib/modules/config/consumer.lua', 't', _ENV))()
    local bridge = factory(exports.qblib)
    if type(Config.notify) == 'table' then
        Config.notify.defaultType = bridge.enum(Config.notify.defaultType, {
            live = true,
            label = 'Default notification type',
            description = 'Selects the semantic style used when a notification caller does not provide a type. The choice controls its icon, status colour, and accessibility wording without changing explicitly typed notifications.',
            options = { 'info', 'success', 'warning', 'error' },
        })
        Config.notify.defaultPosition = bridge.enum(Config.notify.defaultPosition, {
            live = true,
            label = 'Default notification position',
            description = 'Selects where notifications appear when a caller does not request a position. Choose an area that does not overlap the server HUD, inventory, phone, or dispatch feed.',
            options = { 'top-left', 'top-center', 'top-right', 'bottom-left', 'bottom-center', 'bottom-right' },
        })
    end
    Config = bridge.adopt(Config)
end
