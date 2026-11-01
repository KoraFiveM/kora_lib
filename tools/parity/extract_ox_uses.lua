package.path = (debug.getinfo(1, "S").source:match("^@(.*/)") or "./") .. "?.lua;" .. package.path
-- extract_ox_uses: which ox_lib / oxmysql / ox_target APIs a consumer resource
-- calls. Emits names and occurrence counts only, never source text.
--
--   lua5.4 tools/parity/extract_ox_uses.lua <consumer dir> > uses.json
local common = require("common")

local M = {}

local SKIP_DIRS = { "web", "node_modules", ".git", "locales" }

local function bump(map, key)
    map[key] = (map[key] or 0) + 1
end

---Iterates `prefix.a.b` chains (up to `depth` segments) that are not the tail
---of a longer access such as `self.lib.x` or `obj:cache.y`.
local function eachChain(code, prefix, depth, fn)
    local pat = "()%f[%w_]" .. prefix .. "([%.%w_]*)"
    for pos, rest in code:gmatch(pat) do
        local before = pos > 1 and code:sub(pos - 1, pos - 1) or ""
        if before ~= "." and before ~= ":" and rest:sub(1, 1) == "." then
            local parts, n = {}, 0
            for seg in rest:gmatch("%.([%w_]+)") do
                n = n + 1
                parts[n] = seg
                if n == depth then break end
            end
            if n > 0 then fn(parts) end
        end
    end
end

---@param root string
---@return table uses
function M.extract(root)
    local lib, cache, mysql, oxTarget, oxmysqlExports, globals = {}, {}, {}, {}, {}, {}
    local counts = { files = 0, require = 0, libLoad = 0 }
    local libModules = {}

    for _, path in ipairs(common.listFiles(root, "lua", SKIP_DIRS)) do
        local text = common.readFile(root .. "/" .. path)
        local code = common.stripComments(text)
        counts.files = counts.files + 1

        eachChain(code, "lib", 2, function(parts)
            bump(lib, table.concat(parts, "."))
            libModules[parts[1]] = true
        end)
        eachChain(code, "cache", 1, function(parts) bump(cache, parts[1]) end)
        eachChain(code, "MySQL", 3, function(parts)
            -- `MySQL.lua` is the "@oxmysql/lib/MySQL.lua" manifest path, not an API.
            if parts[1] ~= "lua" then bump(mysql, "MySQL." .. table.concat(parts, ".")) end
        end)
        for _, name in ipairs({ "locale", "SetInterval", "ClearInterval" }) do
            for _ in code:gmatch("%f[%w_.:]" .. name .. "%s*%(") do bump(globals, name) end
        end

        for _ in code:gmatch("%f[%w_.:]require%s*%(?%s*[\"']") do counts.require = counts.require + 1 end
        for _ in code:gmatch("lib%.load%s*%(") do counts.libLoad = counts.libLoad + 1 end

        for name in code:gmatch("exports[%.%[]['\"]?ox_target['\"]?%]?[:%.]([%w_]+)") do bump(oxTarget, name) end
        for name in code:gmatch("exports[%.%[]['\"]?oxmysql['\"]?%]?[:%.]([%w_]+)") do bump(oxmysqlExports, name) end
    end

    return {
        meta = { tool = "extract_ox_uses" },
        lib = lib,
        cache = cache,
        mysql = mysql,
        globals = globals,
        oxTarget = oxTarget,
        oxmysqlExports = oxmysqlExports,
        summary = {
            luaFiles = counts.files,
            requireCalls = counts.require,
            libLoadCalls = counts.libLoad,
            libNames = #common.keys(lib),
            libModules = #common.keys(libModules),
            cacheKeys = #common.keys(cache),
            mysqlForms = #common.keys(mysql),
            oxTargetFunctions = #common.keys(oxTarget),
        },
    }
end

if not pcall(debug.getlocal, 4, 1) then
    local root = arg and arg[1]
    if not root then
        io.stderr:write("usage: extract_ox_uses.lua <consumer dir>\n")
        os.exit(2)
    end
    print(common.encode(M.extract(root)))
end

return M
