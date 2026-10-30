local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
local mocks = require('mocks')

local net = mocks.install()
local registeredExports = {}
local nuiMessages = {}
local nuiRequests = {}
local httpHandler
local rejectRawUpload = false
_G.exports = function(name, callback) registeredExports[name] = callback end

dofile(repoRoot .. 'config.lua')
dofile(repoRoot .. 'build/initiate.lua')
dofile(repoRoot .. 'modules/util/shared.lua')

-- Client module fixtures: NUI requests resolve immediately so this plain Lua
-- test can verify the capture wrapper without a browser or native texture.
QB.nui = {
    request = function(action, payload)
        nuiRequests[#nuiRequests + 1] = { action = action, payload = payload }
        local p = promise.new()
        if action == 'screenshot:capture' then
            p:resolve({ data = 'data:image/jpeg;base64,/9j/c21va2U=' })
        elseif action == 'screenshot:upload' then
            if rejectRawUpload then
                p:reject('TypeError: Failed to fetch')
                return p
            end
            if payload.rawBody and httpHandler then
                local status
                httpHandler({
                    method = 'POST',
                    path = payload.url:match('^https?://[^/]+(.+)$'),
                    headers = { ['Content-Length'] = '8' },
                    setDataHandler = function(handler) handler('\255\216\255smoke') end,
                }, {
                    writeHead = function(code) status = code end,
                    send = function() end,
                })
                if status and status >= 200 and status < 300 then p:resolve('ok') else p:reject(('HTTP %s'):format(tostring(status))) end
            else
                p:resolve('uploaded')
            end
        else
            p:reject('unexpected NUI action')
        end
        return p
    end,
    send = function(action, payload)
        nuiMessages[#nuiMessages + 1] = { action = action, payload = payload }
    end,
}

dofile(repoRoot .. 'modules/screenshot/client.lua')
dofile(repoRoot .. 'compat/shared.lua')
dofile(repoRoot .. 'compat/client/screenshot-basic.lua')

harness.test('client capture resolves the NUI data URI', function()
    local result = Citizen.Await(QB.screenshot.capture({ encoding = 'jpg', maxWidth = 1280 }))
    harness.assertEqual(result, 'data:image/jpeg;base64,/9j/c21va2U=', 'capture should pass the browser data URI through')
end)

harness.test('client capture rejects an unsupported image format', function()
    harness.assertThrows(function()
        QB.screenshot.capture({ encoding = 'gif' })
    end, 'invalid encodings must not reach the NUI')
end)

harness.test('client capture and upload reject non-finite dimensions and timeouts', function()
    harness.assertThrows(function()
        QB.screenshot.capture({ maxWidth = math.huge })
    end, 'infinite dimensions must not reach the NUI')
    harness.assertThrows(function()
        QB.screenshot.capture({}, math.huge)
    end, 'infinite capture timeouts must not reach the NUI')
    harness.assertThrows(function()
        QB.screenshot.upload('https://example.invalid', nil, {}, math.huge)
    end, 'infinite upload timeouts must not reach the NUI')
    harness.assertThrows(function()
        QB.screenshot.capture(false)
    end, 'false capture options must not silently default')
    harness.assertThrows(function()
        QB.screenshot.capture({ encoding = false })
    end, 'false encoding must not silently default')
    harness.assertThrows(function()
        QB.screenshot.capture({}, false)
    end, 'false capture timeout must not silently default')
end)

harness.test('legacy requestScreenshot keeps callback semantics', function()
    local export
    net.fire('__cfx_export_screenshot-basic_requestScreenshot', function(callback) export = callback end)
    harness.assertTrue(type(export) == 'function', 'the screenshot-basic compatibility export should be registered')

    local result
    export(function(data) result = data end)
    harness.assertEqual(result, 'data:image/jpeg;base64,/9j/c21va2U=', 'legacy callback should receive the data URI')
end)

harness.test('kora_lib registers its direct screenshot exports', function()
    harness.assertTrue(type(registeredExports.requestScreenshot) == 'function',
        'kora_lib should expose requestScreenshot directly')
    harness.assertTrue(type(registeredExports.requestScreenshotUpload) == 'function',
        'kora_lib should expose requestScreenshotUpload directly')
end)

_G.SetHttpHandler = function(handler) httpHandler = handler end
_G.GetPlayerName = function(player) return player == mocks.SOURCE and 'Smoke Tester' or nil end
_G.GetCurrentServerEndpoint = function() return 'https://127.0.0.1:30120' end

dofile(repoRoot .. 'modules/screenshot/server.lua')

harness.test('kora_lib registers requestClientScreenshot directly', function()
    harness.assertTrue(type(registeredExports.requestClientScreenshot) == 'function',
        'kora_lib should expose requestClientScreenshot for server callers')
end)

harness.test('invalid request values do not reserve the player capture slot', function()
    for _, timeout in ipairs({ 0, 1000, 1500.5, math.huge, 'invalid' }) do
        harness.assertThrows(function()
            QB.screenshot.requestClient(mocks.SOURCE, { timeout = timeout })
        end)
    end
    harness.assertThrows(function()
        QB.screenshot.requestClient(math.huge, { timeout = 30000 })
    end, 'infinite player IDs should fail before session allocation')
    harness.assertThrows(function()
        QB.screenshot.requestClient(mocks.SOURCE, { maxHeight = math.huge, timeout = 30000 })
    end, 'infinite dimensions should fail before session allocation')
    harness.assertThrows(function()
        QB.screenshot.requestClient(mocks.SOURCE, false)
    end, 'false server options should fail before session allocation')
    harness.assertThrows(function()
        QB.screenshot.requestClient(mocks.SOURCE, { encoding = false, timeout = 30000 })
    end, 'false server encoding should fail before session allocation')
    local completed = false
    QB.screenshot.requestClient(mocks.SOURCE, { timeout = 30000 }, function(err)
        harness.assertEqual(err, false)
        completed = true
    end)
    harness.assertTrue(completed, 'a valid request must complete after rejected timeout options')
end)

harness.test('server capture accepts omitted options and uses its defaults', function()
    local callbackErr
    local token = QB.screenshot.requestClient(mocks.SOURCE, nil, function(err)
        callbackErr = err
    end)

    harness.assertTrue(type(token) == 'string' and #token == 48)
    harness.assertEqual(callbackErr, false)
end)

harness.test('server capture uses one tokenized raw browser upload', function()
    local callbackErr, callbackResult
    local token = QB.screenshot.requestClient(mocks.SOURCE, { encoding = 'jpg' }, function(err, result)
        callbackErr, callbackResult = err, result
    end)
    harness.assertTrue(type(token) == 'string' and #token == 48, 'server capture should return a long opaque token')

    local sent = mocks.lastEntry(net.triggeredClientEvents, 'kora_lib:client:screenshotRequested')
    harness.assertTrue(sent ~= nil, 'the server should ask the selected player to capture')
    harness.assertEqual(sent[1].token, token, 'the player should receive the one-time capture token')
    local upload = nuiRequests[#nuiRequests]
    harness.assertEqual(upload.action, 'screenshot:upload')
    harness.assertTrue(upload.payload.rawBody, 'server captures should upload a binary Blob without creating a data URI')
    harness.assertTrue(upload.payload.url:find('/kora_lib_test/screenshot/upload/' .. token, 1, true) ~= nil,
        'the browser upload should carry the one-time server token')
    harness.assertEqual(mocks.lastEntry(net.triggeredServerEvents, 'kora_lib:server:screenshotCaptured'), nil,
        'new clients must not send multi-megabyte screenshot data through a Lua event')
    harness.assertEqual(callbackErr, false, 'success callback should receive false for err')
    harness.assertTrue(type(callbackResult) == 'string' and callbackResult:find('data:image/jpeg;base64,', 1, true) == 1,
        'a capture without a fileName should return a JPEG data URI')
end)

harness.test('server capture falls back when the browser cannot reach the HTTP upload route', function()
    local destination = os.tmpname()
    local callbackErr, callbackResult
    rejectRawUpload = true
    QB.screenshot.requestClient(mocks.SOURCE, { fileName = destination, encoding = 'jpg' }, function(err, result)
        callbackErr, callbackResult = err, result
    end)
    rejectRawUpload = false

    local file = io.open(destination, 'rb')
    harness.assertTrue(file ~= nil, 'the latent fallback should save the screenshot')
    local bytes = file:read('*a')
    file:close()
    os.remove(destination)

    harness.assertEqual(callbackErr, false, 'the fallback should complete the original request')
    harness.assertEqual(callbackResult, destination, 'the fallback should retain the requested destination')
    harness.assertEqual(bytes, '\255\216\255smoke', 'the fallback should preserve the captured JPEG')
    harness.assertTrue(mocks.lastEntry(net.triggeredServerEvents, 'kora_lib:server:screenshotCaptured') ~= nil,
        'a failed browser upload should use the bounded latent receiver')
end)

harness.test('server capture avoids mixed-content fetches for a plain HTTP endpoint', function()
    local destination = os.tmpname()
    local callbackErr
    _G.GetCurrentServerEndpoint = function() return 'zap.ssite.co.uk:30121' end
    QB.screenshot.requestClient(mocks.SOURCE, { fileName = destination, encoding = 'jpg' }, function(err)
        callbackErr = err
    end)
    _G.GetCurrentServerEndpoint = function() return 'https://127.0.0.1:30120' end

    local file = io.open(destination, 'rb')
    harness.assertTrue(file ~= nil, 'the plain-HTTP fallback should save the screenshot')
    file:close()
    os.remove(destination)
    harness.assertEqual(callbackErr, false, 'the plain-HTTP fallback should complete successfully')
    harness.assertEqual(nuiRequests[#nuiRequests].action, 'screenshot:capture',
        'plain HTTP should use latent capture without attempting a browser upload')
end)

harness.test('server capture fails promptly when the client NUI rejects capture', function()
    local request = QB.nui.request
    QB.nui.request = function()
        local p = promise.new()
        p:reject('simulated NUI capture failure')
        return p
    end
    local callbackErr
    local token = QB.screenshot.requestClient(mocks.SOURCE, { encoding = 'jpg' }, function(err)
        callbackErr = err
    end)
    QB.nui.request = request

    harness.assertTrue(type(token) == 'string', 'the server should still create a one-time capture token')
    harness.assertEqual(callbackErr, 'The client could not capture or return the screenshot.',
        'the owning player should end a rejected capture immediately')

    local nextToken = QB.screenshot.requestClient(mocks.SOURCE, { encoding = 'jpg' }, function() end)
    harness.assertTrue(type(nextToken) == 'string', 'a rejected capture must release the player capture slot')
end)

harness.test('server progress ignores malformed byte counts even when debug logging is enabled', function()
    local request, triggerClientEvent, getConvarInt = QB.nui.request, TriggerClientEvent, GetConvarInt
    QB.nui.request = function() return promise.new() end
    _G.TriggerClientEvent = function() end
    local token = QB.screenshot.requestClient(mocks.SOURCE, { encoding = 'jpg' }, function() end)
    QB.nui.request, _G.TriggerClientEvent = request, triggerClientEvent

    _G.GetConvarInt = function() return 1 end
    _G.source = mocks.SOURCE
    local ok = pcall(net.fire, 'kora_lib:server:screenshotProgressed', token, 'received', math.huge)
    _G.GetConvarInt, _G.source = getConvarInt, nil
    harness.assertTrue(ok, 'untrusted progress values must not make debug logging throw')

    _G.source = mocks.SOURCE
    net.fire('kora_lib:server:screenshotFailed', token)
    _G.source = nil
end)

harness.test('server capture rejects a mismatched image type and releases the player slot', function()
    local callbackErr
    local token = QB.screenshot.requestClient(mocks.SOURCE, { encoding = 'png' }, function(err)
        callbackErr = err
    end)

    harness.assertTrue(type(token) == 'string', 'the mismatched request should still issue a token')
    harness.assertTrue(type(callbackErr) == 'string', 'the callback should receive a useful error')

    local nextToken = QB.screenshot.requestClient(mocks.SOURCE, { encoding = 'jpg' }, function() end)
    harness.assertTrue(type(nextToken) == 'string', 'a rejected upload must release the per-player capture slot')
end)

harness.test('server capture retains its safe upload limit when maxBytes is malformed', function()
    local maxBytes = Config.screenshot.maxBytes
    Config.screenshot.maxBytes = false

    local ok = pcall(QB.screenshot.requestClient, mocks.SOURCE, { encoding = 'jpg' }, function() end)
    Config.screenshot.maxBytes = maxBytes

    harness.assertTrue(ok, 'an invalid server cap must not turn an upload into a request-time error')
end)

harness.test('server capture writes a caller-controlled server path when requested', function()
    -- requestClient's fileName is a server API value, never data supplied by
    -- the player/browser. Use the OS temporary directory here so this smoke
    -- path proves kora_lib-playground's PDF attachment flow receives real bytes.
    local destination = os.tmpname()
    local callbackErr, callbackResult
    QB.screenshot.requestClient(mocks.SOURCE, { fileName = destination, encoding = 'jpg' }, function(err, result)
        callbackErr, callbackResult = err, result
    end)

    local file = io.open(destination, 'rb')
    harness.assertTrue(file ~= nil, 'the supplied server path should receive the capture')
    local bytes = file:read('*a')
    file:close()
    os.remove(destination)

    harness.assertEqual(callbackErr, false, 'the file-save callback should report success')
    harness.assertEqual(callbackResult, destination, 'the callback should receive the saved path')
    harness.assertEqual(bytes, '\255\216\255smoke', 'saved image bytes should remain binary-safe')
end)

harness.report('screenshot')
