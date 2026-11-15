-- Guards the hard-coded shared_scripts list in fxmanifest.lua: every
-- modules/<name>/shared.lua on disk must be listed, and every listed one must exist.
-- A module added without a manifest entry would silently never load.
local root = (debug.getinfo(1, 'S').source:match('@?(.*/)') or './') .. '../../'
package.path = root .. 'test/?.lua;' .. package.path
local harness = require('harness')

local function read(path)
    local f = assert(io.open(path, 'r'), 'cannot open ' .. path)
    local s = f:read('a')
    f:close()
    return s
end

local function sharedBlock(manifest)
    local block = manifest:match('shared_scripts%s*{(.-)\n}')
    assert(block, 'shared_scripts block not found in fxmanifest.lua')
    return block
end

local function listed(block)
    local set = {}
    for path in block:gmatch("'(modules/[^']-/shared%.lua)'") do
        set[path] = true
    end
    return set
end

local function onDisk()
    local set = {}
    local p = assert(io.popen('cd "' .. root .. '" && ls modules/*/shared.lua'))
    for line in p:lines() do
        set[line] = true
    end
    p:close()
    return set
end

harness.test('every modules/*/shared.lua on disk is listed in shared_scripts', function()
    local manifest = read(root .. 'fxmanifest.lua')
    local set = listed(sharedBlock(manifest))
    local missing = {}
    for path in pairs(onDisk()) do
        if not set[path] then missing[#missing + 1] = path end
    end
    table.sort(missing)
    harness.assertEqual(#missing, 0, 'modules missing from fxmanifest shared_scripts: ' .. table.concat(missing, ', '))
end)

harness.test('every shared_scripts module entry exists on disk', function()
    local manifest = read(root .. 'fxmanifest.lua')
    local disk = onDisk()
    local stale = {}
    for path in pairs(listed(sharedBlock(manifest))) do
        if not disk[path] then stale[#stale + 1] = path end
    end
    table.sort(stale)
    harness.assertEqual(#stale, 0, 'shared_scripts lists missing files: ' .. table.concat(stale, ', '))
end)
harness.report("manifest_shared")
