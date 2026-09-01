local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')

local function readFile(path)
    local file, err = io.open(path, 'r')
    if not file then error(err, 2) end
    local contents = file:read('*a')
    file:close()
    return contents
end

local function discover(command)
    local pipe = io.popen(command, 'r')
    if not pipe then return nil end

    local files = {}
    for path in pipe:lines() do files[#files + 1] = path end

    -- io.popen's close status reflects the shell pipeline, so a missing binary
    -- and a genuine "no matches" both land here -- the emptiness check below is
    -- what actually distinguishes them.
    pipe:close()

    if #files == 0 then return nil end
    return files
end

local function sourceFiles()
    -- ripgrep when available, POSIX grep otherwise. rg is not installed
    -- everywhere this suite runs, and without a fallback this whole contract
    -- check silently stopped executing -- which is exactly the failure mode it
    -- exists to catch elsewhere.
    local files = discover(('cd %q && rg -l %q local modules --glob %q 2>/dev/null'):format(
        repoRoot, '^function QB\\.', '*.lua'
    )) or discover(('cd %q && grep -rlE %q --include=%q local modules 2>/dev/null'):format(
        repoRoot, '^function QB\\.', '*.lua'
    ))

    if not files then error('failed to discover public QB functions', 2) end

    table.sort(files)
    return files
end

local types = readFile(repoRoot .. 'types.lua')
local moduleClasses = {}
local classFields = {}
local currentClass

for line in types:gmatch('[^\r\n]+') do
    local className = line:match('^%-%-%-@class%s+([%w_]+)')
    if className then
        currentClass = className
        classFields[currentClass] = classFields[currentClass] or {}
    else
        local fieldName, fieldType = line:match('^%-%-%-@field%s+([%w_]+)%s+([^%s]+)')
        if fieldName and currentClass then
            classFields[currentClass][fieldName] = true
            if currentClass == 'QBLib' and fieldType ~= 'fun' then
                moduleClasses[fieldName] = fieldType
            end
        end
    end
end

local symbols = {}
for _, sourcePath in ipairs(sourceFiles()) do
    local source = readFile(repoRoot .. sourcePath)
    local docsPath = sourcePath:match('^(.*)/[^/]+$') .. '/docs.md'
    local docs = readFile(repoRoot .. docsPath)

    for moduleName, functionName in source:gmatch('function%s+QB%.([%w_]+)%.([%w_]+)%s*%(') do
        local symbol = ('QB.%s.%s'):format(moduleName, functionName)
        local key = symbol .. '\0' .. docsPath
        if not symbols[key] then
            symbols[key] = true
            harness.test(symbol .. ' is typed and documented', function()
                local className = moduleClasses[moduleName]
                harness.assertTrue(className ~= nil, moduleName .. ' is missing from the QBLib type')
                harness.assertTrue(classFields[className] and classFields[className][functionName],
                    symbol .. ' is missing from ' .. tostring(className))
                harness.assertTrue(docs:find(symbol, 1, true) ~= nil,
                    symbol .. ' is missing from ' .. docsPath)
            end)
        end
    end

    if source:find('function QB.lang(', 1, true) then
        harness.test('QB.lang is typed and documented', function()
            harness.assertTrue(classFields.QBLib and classFields.QBLib.lang, 'QB.lang is missing from QBLib')
            harness.assertTrue(docs:find('QB.lang', 1, true) ~= nil, 'QB.lang is missing from ' .. docsPath)
        end)
    end
end

harness.test('the public contract discovered exports', function()
    harness.assertTrue(next(symbols) ~= nil, 'no public functions were discovered')
end)

harness.report('api contract')
