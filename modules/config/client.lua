-- qblib's own client-side configuration consumer. The server-side catalog
-- bridge lives in server.lua; this counterpart receives only the shared and
-- client-scoped portion of qblib's configuration.

if type(Config) == 'table' and type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() == 'qblib' then
    local source = assert(LoadResourceFile('qblib', 'modules/config/consumer.lua'))
    local factory = assert(load(source, '@@qblib/modules/config/consumer.lua', 't', _ENV))()
    Config = factory(exports.qblib).adopt(Config)
end
