package.path = (debug.getinfo(1, "S").source:match("^@(.*/)") or "./") .. "?.lua;" .. package.path
local common = require("common")

local M = {}

local IGNORED_TOP = { meta = true, summary = true }

---Flattens a decoded snapshot into a set of "path:name" strings.
function M.flatten(value)
    local out = {}
    local function walk(v, path)
        if type(v) == "table" then
            if #v > 0 or next(v) == nil then
                for _, item in ipairs(v) do out[path .. ":" .. tostring(item)] = true end
            else
                local first = next(v)
                local leaf = type(v[first]) == "number"
                for k, child in pairs(v) do
                    if leaf then
                        out[path .. ":" .. k] = true
                    else
                        walk(child, path == "" and k or (path .. "." .. k))
                    end
                end
            end
        end
    end
    for k, v in pairs(value) do
        if not IGNORED_TOP[k] then walk(v, k) end
    end
    return out
end

local function isSoft(entry, soft)
    for _, prefix in ipairs(soft) do
        if entry:sub(1, #prefix) == prefix then return true end
    end
    return false
end

---@param golden table decoded golden
---@param actual table decoded actual
---@param opts? { failOn?: string, soft?: string[] }
---@return table result { missing, extra, softMissing, softExtra, failed }
function M.compare(golden, actual, opts)
    opts = opts or {}
    local failOn = opts.failOn or "missing"
    local soft = opts.soft or {}
    local g, a = M.flatten(golden), M.flatten(actual)
    local r = { missing = {}, extra = {}, softMissing = {}, softExtra = {} }
    for entry in pairs(g) do
        if not a[entry] then
            table.insert(isSoft(entry, soft) and r.softMissing or r.missing, entry)
        end
    end
    for entry in pairs(a) do
        if not g[entry] then
            table.insert(isSoft(entry, soft) and r.softExtra or r.extra, entry)
        end
    end
    for _, list in pairs(r) do table.sort(list) end
    r.failed = ((failOn == "missing" or failOn == "both") and #r.missing > 0)
        or ((failOn == "extra" or failOn == "both") and #r.extra > 0)
    return r
end

function M.format(result)
    local lines = {}
    local function section(title, list)
        lines[#lines + 1] = ("%s: %d"):format(title, #list)
        for _, e in ipairs(list) do lines[#lines + 1] = "  " .. e end
    end
    section("missing", result.missing)
    section("extra", result.extra)
    section("missing (soft)", result.softMissing)
    section("extra (soft)", result.softExtra)
    lines[#lines + 1] = result.failed and "RESULT: FAIL" or "RESULT: ok"
    return table.concat(lines, "\n")
end

if not pcall(debug.getlocal, 4, 1) then
    local files, opts = {}, { failOn = "missing", soft = {} }
    local i = 1
    while i <= #arg do
        if arg[i] == "--fail-on" then
            opts.failOn = arg[i + 1]
            i = i + 2
        elseif arg[i] == "--soft" then
            for prefix in (arg[i + 1] or ""):gmatch("[^,]+") do opts.soft[#opts.soft + 1] = prefix end
            i = i + 2
        else
            files[#files + 1] = arg[i]
            i = i + 1
        end
    end
    if #files ~= 2 then
        io.stderr:write("usage: diff.lua <golden.json> <actual.json> [--fail-on missing|extra|both] [--soft prefixes]\n")
        os.exit(2)
    end
    local golden = common.decode(assert(common.readFile(files[1]), "cannot read " .. files[1]))
    local actual = common.decode(assert(common.readFile(files[2]), "cannot read " .. files[2]))
    local result = M.compare(golden, actual, opts)
    print(M.format(result))
    os.exit(result.failed and 1 or 0)
end

return M
