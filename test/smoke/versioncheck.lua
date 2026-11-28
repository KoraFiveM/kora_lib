local h = dofile('test/harness.lua')

_G.Kora = setmetatable({}, { __index = function(t, k) local m = {}; rawset(t, k, m); return m end })

local invokingResource = 'kora_phone'
local installedVersion
local httpRequest -- { url, callback } captured from the last check() call
local manifestUrl = 'https://raw.githubusercontent.com/KoraFiveM/kora_phone/dev/fxmanifest.lua'
local patchNotesUrl = 'https://raw.githubusercontent.com/KoraFiveM/kora_phone/dev/patchnotes.md'

_G.GetInvokingResource = function() return invokingResource end
_G.GetResourceMetadata = function(resource, key, index)
    if resource == invokingResource and key == 'version' and index == 0 then return installedVersion end
    return nil
end
_G.PerformHttpRequest = function(url, callback, method)
    httpRequest = { url = url, callback = callback, method = method }
    return true
end

dofile('modules/versioncheck/server.lua')

local printed = {} -- console capture for assertions; realPrint restored before h.report
local realPrint = print
_G.print = function(...)
    local parts = {}
    for i = 1, select('#', ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    printed[#printed + 1] = table.concat(parts, ' ')
end

-- Runs one check() against a remote manifest reporting remoteVersion; returns its console output.
local function checkPrints(remoteVersion)
    local manifest = ([[
fx_version 'cerulean'
game 'gta5'

version '%s'
]]):format(remoteVersion)
    local start = #printed + 1
    httpRequest = nil
    local ok, err = pcall(Kora.versioncheck.check, manifestUrl, patchNotesUrl)
    h.assertTrue(ok, 'check() failed: ' .. tostring(err))
    local callbackOk, callbackErr = pcall(httpRequest.callback, 200, manifest, {}, '')
    h.assertTrue(callbackOk, 'remote callback failed: ' .. tostring(callbackErr))
    return table.concat(printed, '\n', start)
end

h.test('equal or newer than remote prints nothing (issue #58)', function()
    installedVersion = '1.2.3'
    h.assertEqual(checkPrints('1.2.3'), '')
    installedVersion = '0.0.1-dev.4'
    h.assertEqual(checkPrints('0.0.1-dev.3'), '')
end)

h.test('an older version still warns with both versions named', function()
    installedVersion = '0.0.1-dev.3'
    local out = checkPrints('0.0.1-dev.4')
    h.assertTrue(out:find('out of date', 1, true) ~= nil, 'output reports out of date')
    h.assertTrue(out:find('0.0.1%-dev%.3', 1, false) ~= nil, 'output names the installed version')
    h.assertTrue(out:find('0.0.1%-dev%.4', 1, false) ~= nil, 'output names the remote version')
    installedVersion = '0.0.9'
    h.assertTrue(checkPrints('0.0.10'):find('out of date', 1, true) ~= nil)
end)

h.test('a release outranks a pre-release of the same core', function()
    installedVersion = '1.2.3-dev.1'
    h.assertTrue(checkPrints('1.2.3'):find('out of date', 1, true) ~= nil)
    installedVersion = '1.2.3'
    h.assertEqual(checkPrints('1.2.3-dev.1'), '')
end)

_G.print = realPrint
h.report('versioncheck')
