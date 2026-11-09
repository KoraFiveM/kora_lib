local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")

local EVENT_CALLS = { "AddEventHandler", "RegisterNetEvent", "RegisterServerEvent", "AddStateBagChangeHandler" }
local EVENT_PREFIXES = { "ox_lib:", "__ox_cb_", "__ox_notify_" }

---Blanks `--` comments (line and block) while leaving string contents intact.
local function stripComments(text)
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

local function hasOxLibString(s)
    return s:find("[\"']ox_lib[\"']") ~= nil
end

---@return string[] violations found in a fxmanifest.lua body
local function scanManifest(text)
    local found = {}
    local code = stripComments(text)
    local pos = 1
    while true do
        local s, e = code:find("%f[%w_]provides?%f[^%w_]", pos)
        if not s then break end
        local rest = code:sub(e + 1)
        local body = rest:match("^%s*%(?%s*(%b{})") or rest:match("^[^\n]*")
        if hasOxLibString(body) then
            found[#found + 1] = "manifest provides ox_lib"
        end
        pos = e + 1
    end
    return found
end

---@return string[] violations found in a Lua file body
local function scanLua(text)
    local found = {}
    local code = stripComments(text)
    if code:find("provideExport%s*%(%s*[\"']ox_lib[\"']") then
        found[#found + 1] = "provideExport('ox_lib', ...)"
    end
    if code:find("[\"']__cfx_export_ox_lib_") then
        found[#found + 1] = "__cfx_export_ox_lib_* registration"
    end
    for _, call in ipairs(EVENT_CALLS) do
        for _, prefix in ipairs(EVENT_PREFIXES) do
            local pat = call .. "%s*%(%s*[\"']" .. prefix:gsub("%p", "%%%0")
            if code:find(pat) then
                found[#found + 1] = ("%s('%s...')"):format(call, prefix)
            end
        end
    end
    return found
end

local function readFile(path)
    local f = assert(io.open(path, "rb"))
    local data = f:read("a")
    f:close()
    return data
end

---Lists tracked-looking Lua files, skipping tests, vendored deps and VCS data.
local function listLuaFiles()
    local p = assert(io.popen(("cd %q && find . -name '*.lua' -not -path './test/*' -not -path './.git/*' -not -path '*/node_modules/*' | sort"):format(repoRoot)))
    local files = {}
    for line in p:lines() do files[#files + 1] = line:gsub("^%./", "") end
    p:close()
    return files
end

harness.test("scanner flags every bad manifest form", function()
    local bad = {
        "provide 'ox_lib'",
        'provide "ox_lib"',
        "provide('ox_lib')",
        "provide   (  \"ox_lib\"  )",
        "provides { 'qblib', 'ox_lib' }",
        "provides {\n  'a',\n  \"ox_lib\",\n}",
    }
    for _, sample in ipairs(bad) do
        harness.assertEqual(#scanManifest(sample), 1, "missed: " .. sample)
    end
end)

harness.test("scanner accepts good manifests and ignores comments", function()
    local good = {
        "provide 'qblib'\nprovide 'qb-menu'",
        "-- provide 'ox_lib' would be wrong\nprovide 'qblib'",
        "provides { 'qblib', 'qb-input' }",
        "dependency 'ox_lib'",
        "shared_script '@ox_lib/init.lua'",
        "provide 'ox_lib_extras'",
    }
    for _, sample in ipairs(good) do
        harness.assertEqual(#scanManifest(sample), 0, "false positive: " .. sample)
    end
end)

harness.test("scanner flags every bad Lua registration form", function()
    local bad = {
        "Kora.compat.provideExport('ox_lib', 'notify', fn)",
        'compat.provideExport( "ox_lib" , "x", fn)',
        "AddEventHandler('ox_lib:notify', fn)",
        'RegisterNetEvent("ox_lib:defaultNotify", fn)',
        "RegisterNetEvent('ox_lib:alertDialog')",
        "AddEventHandler('__ox_cb_thing', fn)",
        "RegisterNetEvent('__ox_notify_res', fn)",
        "AddEventHandler('__cfx_export_ox_lib_notify', fn)",
        "AddEventHandler(\"__cfx_export_ox_lib_hasLoaded\", fn)",
    }
    for _, sample in ipairs(bad) do
        harness.assertTrue(#scanLua(sample) >= 1, "missed: " .. sample)
    end
end)

harness.test("scanner accepts forwarding exports and unrelated code", function()
    local good = {
        "exports.kora_lib:ox_notify(data, owner)",
        "exports['kora_lib']:ox_showContext(id)",
        "AddEventHandler('kora:notify', fn)",
        "Kora.compat.provideExport('qb-menu', 'openMenu', fn)",
        "-- AddEventHandler('ox_lib:notify', fn)",
        "--[[ RegisterNetEvent('ox_lib:notify') ]] local x = 1",
        "TriggerEvent('ox_lib:notify', data)",
        "RegisterCommand('ox_lib-radial', fn)",
    }
    for _, sample in ipairs(good) do
        local v = scanLua(sample)
        harness.assertEqual(#v, 0, "false positive: " .. sample .. " -> " .. table.concat(v, ","))
    end
end)

harness.test("fxmanifest.lua does not provide ox_lib", function()
    local v = scanManifest(readFile(repoRoot .. "fxmanifest.lua"))
    harness.assertEqual(#v, 0, table.concat(v, "; "))
end)

harness.test("no kora_lib Lua file registers an ox_lib identity", function()
    local files = listLuaFiles()
    harness.assertTrue(#files > 50, "file listing looks wrong (" .. #files .. " files)")
    local problems = {}
    for _, path in ipairs(files) do
        for _, v in ipairs(scanLua(readFile(repoRoot .. path))) do
            problems[#problems + 1] = path .. ": " .. v
        end
    end
    harness.assertEqual(#problems, 0, table.concat(problems, "; "))
end)

harness.report("ox identity guard")
