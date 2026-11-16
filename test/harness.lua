local M = {}

-- Smoke tests load individual modules without the manifest. Give them the real
-- English translator in an isolated environment so their native mocks stay intact.
local directory = debug.getinfo(1, 'S').source:match('^@(.*/)') or 'test/'
local function readLocaleFile(path)
    local file = assert(io.open(directory .. '../' .. path, 'rb'))
    local contents = file:read('*a')
    file:close()
    return contents
end
local localeEnvironment = setmetatable({
    GetCurrentResourceName = function() return 'kora_lib' end,
    GetConvar = function(_, fallback) return fallback end,
    LoadResourceFile = function(resource, path)
        if resource == 'kora_lib' and path == 'locales/en.lua' then return readLocaleFile(path) end
    end,
}, { __index = _G })
assert(load(readLocaleFile('local/locales/shared.lua'), '@local/locales/shared.lua', 't', localeEnvironment))()
_G.KoraLang = localeEnvironment.KoraLang

local results = {}

---Runs `fn` immediately, recording whether it raised an error.
---@param name string
---@param fn fun()
function M.test(name, fn)
    local ok, err = pcall(fn)
    table.insert(results, { name = name, ok = ok, err = err })
end

local function formatValue(v)
    return type(v) == "string" and v or tostring(v)
end

function M.assertEqual(actual, expected, message)
    if actual ~= expected then
        error(("%s (expected %s, got %s)"):format(message or "values differ", formatValue(expected), formatValue(actual)), 2)
    end
end

function M.assertTrue(value, message)
    if not value then
        error(message or "expected value to be truthy", 2)
    end
end

function M.assertFalse(value, message)
    if value then
        error(message or "expected value to be falsy", 2)
    end
end

function M.assertThrows(fn, message)
    if pcall(fn) then
        error(message or "expected function to raise an error", 2)
    end
end

---Prints a pass/fail summary for the current file and exits non-zero if anything failed.
---@param moduleName string
function M.report(moduleName)
    local passed, failed = 0, 0

    for _, r in ipairs(results) do
        if r.ok then
            passed = passed + 1
            print(("  [PASS] %s"):format(r.name))
        else
            failed = failed + 1
            print(("  [FAIL] %s -- %s"):format(r.name, tostring(r.err)))
        end
    end

    print(("%s: %d passed, %d failed"):format(moduleName, passed, failed))
    os.exit(failed > 0 and 1 or 0, true)
end

return M
