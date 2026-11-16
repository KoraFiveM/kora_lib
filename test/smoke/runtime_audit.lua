local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local repoRoot = scriptDir .. '../../'
local harness = dofile(scriptDir .. '../harness.lua')
local function read(path)
    local file = assert(io.open(repoRoot .. path, 'rb'))
    local source = file:read('*a')
    file:close()
    return source
end

local englishSource = read('locales/en.lua')
local function countKeys(node)
    local count = 0
    for _, value in pairs(node) do
        count = count + (type(value) == 'table' and countKeys(value) or 1)
    end
    return count
end
local englishKeyCount = countKeys(assert(load(englishSource))())

local function setup(isServer)
    local commands, output = {}, {}
    local env = setmetatable({
        IsDuplicityVersion = function() return isServer end,
        GetCurrentResourceName = function() return 'kora_lib' end,
        GetInvokingResource = function() return nil end,
        GetConvar = function(_, fallback) return fallback end,
        GetGameTimer = function() return 0 end,
        LoadResourceFile = function(resource, path)
            if resource == 'kora_lib' and path == 'locales/en.lua' then return englishSource end
        end,
        RegisterCommand = function(name, handler, restricted)
            commands[name] = { handler = handler, restricted = restricted }
        end,
        CreateThread = function(fn) fn() end,
        Wait = function() end,
        print = function(line) output[#output + 1] = line end,
        json = { decode = function(source)
            harness.assertEqual(source, '{"value":7}')
            return { value = 7 }
        end },
    }, { __index = _G })
    for _, path in ipairs({
        'local/locales/shared.lua', 'build/initiate.lua', 'modules/util/shared.lua',
        'modules/loops/shared.lua', 'modules/vehicle/shared.lua', 'modules/random/shared.lua',
        'modules/rewards/shared.lua', 'modules/locales/shared.lua', 'modules/qa/audit.lua',
    }) do
        assert(load(read(path), '@' .. path, 't', env))()
    end
    env.Kora.auditFixture.unavailable = function() error('untested fixture must never run') end
    local name = isServer and 'kora_lib_audit_server' or 'kora_lib_audit_client'
    local command = commands[name]
    harness.assertEqual(command.restricted, isServer)
    return command.handler, output, env.Kora
end

harness.test('client audit prints verified functions, English text and untested functions', function()
    local run, output = setup(false)
    run(0, {})
    local transcript = table.concat(output, '\n')
    harness.assertTrue(transcript:find('[PASS] util.fnv1a | Modules.Util.util_fnv1a =>', 1, true))
    harness.assertTrue(transcript:find('[PASS] locale app.cancel | en="Cancel"', 1, true))
    harness.assertTrue(transcript:find('[UNTESTED] auditFixture.unavailable', 1, true))
    harness.assertTrue(output[#output]:find('[INCOMPLETE]', 1, true))
    harness.assertFalse(transcript:find('[FAIL]', 1, true), transcript)
    harness.assertTrue(output[#output]:find(('locale keys: %d passed, 0 failed'):format(englishKeyCount), 1, true))
end)

harness.test('server summary reports a failed assertion and missing locale without hiding either', function()
    local run, output, kora = setup(true)
    kora.util.trim = function() return 'wrong' end
    local translate = kora.locale.translate
    kora.locale.translate = function(resource, key, ...)
        if key == 'app.cancel' then return key end
        return translate(resource, key, ...)
    end
    run(0, { 'summary' })
    local transcript = table.concat(output, '\n')
    harness.assertTrue(transcript:find('[FAIL] util.trim', 1, true))
    harness.assertTrue(transcript:find('[FAIL] locale app.cancel', 1, true))
    harness.assertFalse(transcript:find('[PASS]', 1, true))
    harness.assertTrue(output[#output]:find('1 failed', 1, true))
end)

harness.report('runtime audit')
