local realm = IsDuplicityVersion() and 'server' or 'client'

for area, provider in pairs(Config.Bridge) do
    assert(type(area) == 'string' and type(provider) == 'string', 'Bridge config entries must map names to provider folders.')

    local moduleRoot = ('modules/bridge/modules/%s/%s/'):format(area, provider)
    for _, fileName in ipairs({ 'shared.lua', realm .. '.lua' }) do
        local path = moduleRoot .. fileName
        local source = LoadResourceFile('kora_lib', path)
        if source then
            local chunk, err = load(source, ('@@kora_lib/%s'):format(path), 't', _ENV)
            assert(chunk, ('Unable to compile bridge module %s: %s'):format(path, tostring(err)))
            chunk()
        end
    end
end
