package.path = (debug.getinfo(1, "S").source:match("^@(.*/)") or "./") .. "?.lua;" .. package.path
-- extract_ox_surface: regex-based public-surface snapshot of an ox_lib tree
-- (upstream checkout or the shim). Emits names only, never source text.
--
--   lua5.4 tools/parity/extract_ox_surface.lua <ox_lib dir> > surface.json
local common = require("common")

local M = {}

local SKIP_DIRS = { "web", "node_modules", ".git", "test", "package" }

---Realm of a file under resource/ or imports/ from its path.
local function realmOf(path)
    local base = path:match("([^/]+)$")
    if base == "client.lua" or path:find("/client/", 1, true) then return "client" end
    if base == "server.lua" or path:find("/server/", 1, true) then return "server" end
    return "shared"
end

local function addAll(set, text, pattern)
    for name in text:gmatch(pattern) do set[name] = true end
end

---@param root string path to an ox_lib-shaped resource
---@return table surface
function M.extract(root)
    local files = common.listFiles(root, "lua", SKIP_DIRS)

    local imports, resourceLib, subkeys = {}, {}, {}
    local exportsByRealm = { shared = {}, client = {}, server = {} }
    local dynamicExports = {}
    local events, convars = {}, {}
    local nuiActions, nuiCallbacks = {}, {}

    -- imports/ directories are the lazily loadable `lib.<name>` modules.
    local p = io.popen(("cd '%s' && ls -1 imports 2>/dev/null"):format(root))
    for line in p:lines() do imports[line] = true end
    p:close()

    for _, path in ipairs(files) do
        local text = common.readFile(root .. "/" .. path)
        local code = common.stripComments(text)
        local realm = realmOf(path)
        local inResource = path:find("^resource/") or path == "init.lua"
        local inImports = path:find("^imports/")

        -- Top-level lib.X definitions under resource/ and init.lua are
        -- auto-exported by the __newindex rule in resource/init.lua.
        if inResource then
            for name in code:gmatch("function%s+lib%.([%w_]+)%s*%(") do
                resourceLib[name] = true
                if path:find("^resource/") then exportsByRealm[realm][name] = true end
            end
            for name in code:gmatch("\n%s*lib%.([%w_]+)%s*=[^=]") do
                resourceLib[name] = true
                if path:find("^resource/") then exportsByRealm[realm][name] = true end
            end
        end

        -- Explicit exports('name', fn) calls; a %s template is a dynamic family.
        for name in code:gmatch("exports%s*%(%s*%(?%s*[\"']([^\"']+)[\"']") do
            if name:find("%%s") then
                dynamicExports[name] = true
            else
                exportsByRealm[realm][name] = true
            end
        end

        -- Sub-keys: lib.<mod>.<fn> / lib.<mod>:<method>, plus class-file locals.
        if inImports or path == "init.lua" then
            local mod = inImports and path:match("^imports/([^/]+)/") or "init"
            subkeys[mod] = subkeys[mod] or {}
            for owner, sep, name in code:gmatch("function%s+([%w_]+)([%.:])([%w_]+)%s*%(") do
                if owner ~= "lib" then subkeys[mod][owner .. sep .. name] = true end
            end
            for a, sep, name in code:gmatch("function%s+lib%.([%w_]+)([%.:])([%w_]+)%s*%(") do
                subkeys[mod][a .. sep .. name] = true
            end
            for a, name in code:gmatch("\n%s*lib%.([%w_]+)%.([%w_]+)%s*=[^=]") do
                subkeys[mod][a .. "." .. name] = true
            end
            if not next(subkeys[mod]) then subkeys[mod] = nil end
        end

        addAll(events, code, "[\"'](ox_lib:[^\"']*)[\"']")
        addAll(events, code, "[\"'](__ox_[^\"']*)[\"']")

        for name in code:gmatch("GetConvar[%w]*%s*%(%s*[\"']([^\"']+)[\"']") do convars[name] = true end

        if code:find("SendNUIMessage", 1, true) or code:find("SendNuiMessage", 1, true) then
            addAll(nuiActions, code, "action%s*=%s*[\"']([^\"']+)[\"']")
        end
        addAll(nuiCallbacks, code, "RegisterNUICallback%s*%(%s*[\"']([^\"']+)[\"']")
    end

    -- fxmanifest metadata
    local manifestText = common.readFile(root .. "/fxmanifest.lua")
    local manifestKeys, oxLibValues, version = {}, {}, nil
    if manifestText then
        local mcode = common.stripComments(manifestText)
        local lines = "\n" .. mcode
        for key in lines:gmatch("\n([%a_][%w_]*)[ \t]*[%({'\"]") do manifestKeys[key] = true end
        for key in lines:gmatch("\n([%a_][%w_]*)[ \t]*\n") do manifestKeys[key] = true end
        version = mcode:match("\nversion%s*[%(]?%s*[\"']([^\"']+)[\"']")
        -- ox_lib 'x' / ox_libs { 'x', ... }
        for value in mcode:gmatch("\nox_lib%s+[\"']([^\"']+)[\"']") do oxLibValues[value] = true end
        for block in mcode:gmatch("\nox_libs%s*(%b{})") do addAll(oxLibValues, block, "[\"']([^\"']+)[\"']") end
    end

    local locales = {}
    local lp = io.popen(("cd '%s' && ls -1 locales 2>/dev/null"):format(root))
    for line in lp:lines() do
        local code = line:match("^(.+)%.json$")
        if code then locales[code] = true end
    end
    lp:close()

    local surface = {
        meta = { tool = "extract_ox_surface", version = version },
        lib = {
            imports = common.keys(imports),
            resource = common.keys(resourceLib),
            subkeys = {},
        },
        exports = {
            shared = common.keys(exportsByRealm.shared),
            client = common.keys(exportsByRealm.client),
            server = common.keys(exportsByRealm.server),
            dynamic = common.keys(dynamicExports),
        },
        events = common.keys(events),
        convars = common.keys(convars),
        nui = { actions = common.keys(nuiActions), callbacks = common.keys(nuiCallbacks) },
        manifest = { keys = common.keys(manifestKeys), oxLib = common.keys(oxLibValues) },
        locales = common.keys(locales),
    }
    for mod, set in pairs(subkeys) do surface.lib.subkeys[mod] = common.keys(set) end

    local exportTotal = #surface.exports.shared + #surface.exports.client + #surface.exports.server
    surface.summary = {
        importModules = #surface.lib.imports,
        resourceLibKeys = #surface.lib.resource,
        exportsTotal = exportTotal,
        exportsDynamicFamilies = #surface.exports.dynamic,
        events = #surface.events,
        convars = #surface.convars,
        nuiActions = #surface.nui.actions,
        nuiCallbacks = #surface.nui.callbacks,
        locales = #surface.locales,
    }
    return surface
end

if not pcall(debug.getlocal, 4, 1) then
    local root = arg and arg[1]
    if not root then
        io.stderr:write("usage: extract_ox_surface.lua <ox_lib dir>\n")
        os.exit(2)
    end
    print(common.encode(M.extract(root)))
end

return M
