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
        repoRoot, '^function Kora\\.', '*.lua'
    )) or discover(('cd %q && grep -rlE %q --include=%q local modules 2>/dev/null'):format(
        repoRoot, '^function Kora\\.', '*.lua'
    ))

    if not files then error('failed to discover public Kora functions', 2) end

    table.sort(files)
    return files
end

local function guideDirectories(root)
    local directories = discover(('cd %q && find %q -mindepth 1 -maxdepth 1 -type d -exec basename {} \\; 2>/dev/null')
        :format(repoRoot, root))
    if not directories then error(('failed to discover %s guides'):format(root), 2) end
    table.sort(directories)
    return directories
end

local types = readFile(repoRoot .. 'types.lua')
local referenceIndex = readFile(repoRoot .. 'docs/reference.md')
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
            if currentClass == 'kora_lib' and fieldType ~= 'fun' then
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

    for moduleName, functionName in source:gmatch('function%s+Kora%.([%w_]+)%.([%w_]+)%s*%(') do
        if moduleName ~= 'compat' then
            local symbol = ('Kora.%s.%s'):format(moduleName, functionName)
            local key = symbol .. '\0' .. docsPath
            if not symbols[key] then
                symbols[key] = true
                harness.test(symbol .. ' is typed and documented', function()
                    local className = moduleClasses[moduleName]
                    harness.assertTrue(className ~= nil, moduleName .. ' is missing from the kora_lib type')
                    harness.assertTrue(classFields[className] and classFields[className][functionName],
                        symbol .. ' is missing from ' .. tostring(className))
                    harness.assertTrue(docs:find(symbol, 1, true) ~= nil,
                        symbol .. ' is missing from ' .. docsPath)
                end)
            end
        end
    end

    if source:find('function Kora.lang(', 1, true) then
        harness.test('Kora.lang is typed and documented', function()
            harness.assertTrue(classFields.kora_lib and classFields.kora_lib.lang, 'Kora.lang is missing from kora_lib')
            harness.assertTrue(docs:find('Kora.lang', 1, true) ~= nil, 'Kora.lang is missing from ' .. docsPath)
        end)
    end
end

harness.test('the public contract discovered exports', function()
    harness.assertTrue(next(symbols) ~= nil, 'no public functions were discovered')
end)

harness.test('every module and local core has a reference guide', function()
    for _, root in ipairs({ 'modules', 'local' }) do
        for _, directory in ipairs(guideDirectories(root)) do
            local docsPath = ('%s%s/%s/docs.md'):format(repoRoot, root, directory)
            local file = io.open(docsPath, 'r')
            harness.assertTrue(file ~= nil, ('%s/%s is missing docs.md'):format(root, directory))
            if file then file:close() end
        end
    end
end)

harness.test('the API index links every module and local core reference page', function()
    for _, root in ipairs({ 'modules', 'local' }) do
        for _, directory in ipairs(guideDirectories(root)) do
            local referencePath = ('/reference/%s/'):format(directory)
            harness.assertTrue(referenceIndex:find(referencePath, 1, true) ~= nil,
                ('API index is missing %s'):format(referencePath))
        end
    end
end)

harness.report('api contract')
