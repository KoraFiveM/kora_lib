-- This file returns a factory because QB.require has to run inside the
-- consumer resource that loaded @qblib/init.lua. Exporting these functions
-- from qblib would execute required chunks in qblib's environment instead.
return function(currentResource)
    assert(type(currentResource) == 'string' and currentResource ~= '', 'Current resource name not found')

    local LOADING = {}
    local loaded = {}
    local unpack = table.unpack

    local function assertResource(resource)
        if type(resource) ~= 'string' or resource == '' then
            error(('resource must be a non-empty string (received %s)'):format(type(resource)), 3)
        end

        if resource == '.' or resource == '..' or resource:find('[@%c/\\]') then
            error(("invalid resource name '%s'"):format(resource), 3)
        end
    end

    local function moduleCandidates(path)
        if type(path) ~= 'string' or path == '' then
            error(('module path must be a non-empty string (received %s)'):format(type(path)), 3)
        end

        if path:sub(1, 1) == '/' or path:sub(-1) == '/' or path:find('\\', 1, true)
            or path:find('//', 1, true) or path:find('%c') then
            error(("invalid module path '%s'"):format(path), 3)
        end

        for segment in path:gmatch('[^/]+') do
            if segment == '.' or segment == '..' then
                error(("invalid module path '%s'"):format(path), 3)
            end
        end

        if path:sub(-4) == '.lua' then return { path } end
        return { path .. '.lua', path .. '/init.lua' }
    end

    local function requireOne(resource, path)
        assertResource(resource)

        local candidates = moduleCandidates(path)
        local resourceCache = loaded[resource]
        if not resourceCache then
            resourceCache = {}
            loaded[resource] = resourceCache
        end

        local tried = {}

        for i = 1, #candidates do
            local fileName = candidates[i]
            local cached = resourceCache[fileName]

            if cached == LOADING then
                error(("circular dependency while loading '@%s/%s'"):format(resource, fileName), 3)
            end

            if cached ~= nil then return cached end

            local source = LoadResourceFile(resource, fileName)
            if source ~= nil then
                resourceCache[fileName] = LOADING

                local chunk, compileError = load(source, ('@@%s/%s'):format(resource, fileName), 't', _ENV)
                if not chunk then
                    resourceCache[fileName] = nil
                    error(("unable to compile '@%s/%s': %s"):format(resource, fileName, compileError), 3)
                end

                local ok, result = pcall(chunk)
                if not ok then
                    resourceCache[fileName] = nil
                    error(("unable to load '@%s/%s': %s"):format(resource, fileName, result), 3)
                end

                -- Match Lua require: a module with no explicit return value is
                -- considered successfully loaded and resolves to true.
                if result == nil then result = true end
                resourceCache[fileName] = result
                return result
            end

            tried[#tried + 1] = ("no file '@%s/%s'"):format(resource, fileName)
        end

        error(("module '%s' was not found:\n\t%s"):format(path, table.concat(tried, '\n\t')), 3)
    end

    local function loadPaths(resource, paths)
        assertResource(resource)

        if type(paths) == 'string' then return requireOne(resource, paths) end
        if type(paths) ~= 'table' then
            error(('paths must be a string or an array of strings (received %s)'):format(type(paths)), 3)
        end

        local count = 0
        for key in pairs(paths) do
            if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then
                error('paths must be a dense array of strings', 3)
            end
            if key > count then count = key end
        end

        assert(count > 0, 'paths must contain at least one module path')

        local results = {}
        for i = 1, count do
            assert(rawget(paths, i) ~= nil, 'paths must be a dense array of strings')
            results[i] = requireOne(resource, paths[i])
        end

        return unpack(results, 1, count)
    end

    local api = {}

    ---Loads one Lua module or an ordered list of modules from a resource.
    ---@param resource string
    ---@param paths string|string[]
    ---@return any ...
    function api.load(resource, paths)
        return loadPaths(resource, paths)
    end

    ---Loads one Lua module or an ordered list from the current resource.
    ---@param paths string|string[]
    ---@return any ...
    function api.current(paths)
        return loadPaths(currentResource, paths)
    end

    -- `local` is a Lua keyword, so dot syntax cannot express this field. Keep
    -- the requested name available as QB.require["local"](...), with
    -- QB.require.current(...) as the normal dot-syntax spelling.
    api['local'] = api.current

    local function clearResource(resource)
        loaded[resource] = nil
    end

    if type(AddEventHandler) == 'function' then
        AddEventHandler('onResourceStop', clearResource)
        AddEventHandler('onClientResourceStop', clearResource)
    end

    return api
end
