-- Shared helpers for the ox_lib parity tools: file walking, comment stripping,
-- and a small deterministic JSON encoder/decoder (no external dependencies).
local M = {}

---Directory containing the calling script, with trailing slash.
function M.scriptDir(level)
    local src = debug.getinfo(level or 2, "S").source
    return src:match("^@(.*/)") or "./"
end

local function shellQuote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

---Lists files under `root` (relative paths, sorted) whose name matches `ext`.
---@param root string
---@param ext string e.g. "lua"
---@param skipDirs? string[] directory names to skip anywhere in the tree
function M.listFiles(root, ext, skipDirs)
    local prune = {}
    for _, d in ipairs(skipDirs or {}) do
        prune[#prune + 1] = ("-name %s"):format(shellQuote(d))
    end
    local cmd = ("cd %s && find . %s -type f -name %s -print | sort"):format(
        shellQuote(root),
        #prune > 0 and ("\\( " .. table.concat(prune, " -o ") .. " \\) -prune -o") or "",
        shellQuote("*." .. ext)
    )
    local p = assert(io.popen(cmd))
    local files = {}
    for line in p:lines() do
        files[#files + 1] = line:gsub("^%./", "")
    end
    p:close()
    return files
end

function M.readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("a")
    f:close()
    return data
end

---Blanks Lua `--` comments (line and long form), keeping string contents.
function M.stripComments(text)
    text = text:gsub("%-%-%[(=*)%[.-%]%1%]", "")
    local out = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local quote, cut = nil, nil
        local i = 1
        while i <= #line do
            local c = line:sub(i, i)
            if quote then
                if c == "\\" then i = i + 1 elseif c == quote then quote = nil end
            elseif c == "'" or c == '"' then
                quote = c
            elseif c == "-" and line:sub(i + 1, i + 1) == "-" then
                cut = i
                break
            end
            i = i + 1
        end
        out[#out + 1] = cut and line:sub(1, cut - 1) or line
    end
    return table.concat(out, "\n")
end

---Set helper: add `value` to the set `t` (a table of value -> true).
function M.add(t, value)
    t[value] = true
end

---Sorted array from a set (keys of `t`).
function M.keys(t)
    local list = {}
    for k in pairs(t) do list[#list + 1] = k end
    table.sort(list)
    return list
end

-- JSON ---------------------------------------------------------------------

local escapes = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function encodeString(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        return escapes[c] or ("\\u%04x"):format(c:byte())
    end) .. '"'
end

local function isArray(t)
    if next(t) == nil then return true end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return #t == n
end

---Pretty, deterministic (sorted object keys) JSON. Arrays of scalars stay on
---one line when short enough to keep golden files reviewable.
function M.encode(value, indent)
    indent = indent or ""
    local t = type(value)
    if t == "string" then return encodeString(value) end
    if t == "number" then return math.type(value) == "integer" and tostring(value) or ("%.14g"):format(value) end
    if t == "boolean" or t == "nil" then return tostring(value) end
    assert(t == "table", "cannot encode " .. t)
    local inner = indent .. "  "
    local parts = {}
    if isArray(value) then
        if #value == 0 then return "[]" end
        for i, v in ipairs(value) do parts[i] = inner .. M.encode(v, inner) end
        return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
    end
    for _, k in ipairs(M.keys(value)) do
        parts[#parts + 1] = inner .. encodeString(tostring(k)) .. ": " .. M.encode(value[k], inner)
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

---Minimal JSON decoder (objects, arrays, strings, numbers, booleans, null).
function M.decode(text)
    local pos = 1
    local function skip() pos = text:find("[^ \t\r\n]", pos) or #text + 1 end
    local value
    local function str()
        local out = {}
        pos = pos + 1
        while true do
            local c = text:sub(pos, pos)
            assert(c ~= "", "unterminated string")
            if c == '"' then pos = pos + 1 break end
            if c == "\\" then
                local n = text:sub(pos + 1, pos + 1)
                local map = { n = "\n", r = "\r", t = "\t", b = "\b", f = "\f" }
                if n == "u" then
                    out[#out + 1] = utf8.char(tonumber(text:sub(pos + 2, pos + 5), 16))
                    pos = pos + 6
                else
                    out[#out + 1] = map[n] or n
                    pos = pos + 2
                end
            else
                out[#out + 1] = c
                pos = pos + 1
            end
        end
        return table.concat(out)
    end
    function value()
        skip()
        local c = text:sub(pos, pos)
        if c == "{" then
            local obj = {}
            pos = pos + 1
            skip()
            if text:sub(pos, pos) == "}" then pos = pos + 1 return obj end
            while true do
                skip()
                local k = str()
                skip()
                assert(text:sub(pos, pos) == ":", "expected ':' at " .. pos)
                pos = pos + 1
                obj[k] = value()
                skip()
                local d = text:sub(pos, pos)
                pos = pos + 1
                if d == "}" then return obj end
                assert(d == ",", "expected ',' at " .. pos)
            end
        elseif c == "[" then
            local arr = {}
            pos = pos + 1
            skip()
            if text:sub(pos, pos) == "]" then pos = pos + 1 return arr end
            while true do
                arr[#arr + 1] = value()
                skip()
                local d = text:sub(pos, pos)
                pos = pos + 1
                if d == "]" then return arr end
                assert(d == ",", "expected ',' at " .. pos)
            end
        elseif c == '"' then
            return str()
        end
        local lit = text:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
        if lit and lit ~= "" then
            pos = pos + #lit
            return math.tointeger(tonumber(lit)) or tonumber(lit)
        end
        for word, v in pairs({ ["true"] = true, ["false"] = false }) do
            if text:sub(pos, pos + #word - 1) == word then pos = pos + #word return v end
        end
        error("bad JSON at " .. pos)
    end
    local v = value()
    skip()
    assert(pos > #text, "trailing JSON data")
    return v
end

return M
