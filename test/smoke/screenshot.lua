local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
local mocks = require('mocks')

local net = mocks.install()
local registeredExports = {}
local nuiMessages = {}
_G.exports = function(name, callback) registeredExports[name] = callback end

dofile(repoRoot .. 'config.lua')
dofile(repoRoot .. 'build/initiate.lua')

-- Client module fixtures: NUI requests resolve immediately so this plain Lua
-- test can verify the capture wrapper without a browser or native texture.
QB.nui = {
    request = function(action, payload)
        local p = promise.new()
        if action == 'screenshot:capture' then
            p:resolve({ data = 'data:image/jpeg;base64,/9j/c21va2U=' })
        elseif action == 'screenshot:upload' then
            p:resolve('uploaded')
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
dofile(repoRoot .. 'compat/client/exports.lua')
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

harness.test('legacy requestScreenshot keeps callback semantics', function()
    local export
    net.fire('__cfx_export_screenshot-basic_requestScreenshot', function(callback) export = callback end)
    harness.assertTrue(type(export) == 'function', 'the screenshot-basic compatibility export should be registered')

    local result
    export(function(data) result = data end)
    harness.assertEqual(result, 'data:image/jpeg;base64,/9j/c21va2U=', 'legacy callback should receive the data URI')
end)

harness.test('qblib registers its direct screenshot exports', function()
    harness.assertTrue(type(registeredExports.requestScreenshot) == 'function',
        'qblib should expose requestScreenshot directly')
    harness.assertTrue(type(registeredExports.requestScreenshotUpload) == 'function',
        'qblib should expose requestScreenshotUpload directly')
end)

_G.SetHttpHandler = function() end
_G.GetPlayerName = function(player) return player == mocks.SOURCE and 'Smoke Tester' or nil end

dofile(repoRoot .. 'modules/screenshot/server.lua')

harness.test('qblib registers requestClientScreenshot directly', function()
    harness.assertTrue(type(registeredExports.requestClientScreenshot) == 'function',
        'qblib should expose requestClientScreenshot for server callers')
end)

harness.test('server capture returns one tokenized latent client upload', function()
    local callbackErr, callbackResult
    local token = QB.screenshot.requestClient(mocks.SOURCE, { encoding = 'jpg' }, function(err, result)
        callbackErr, callbackResult = err, result
    end)
    harness.assertTrue(type(token) == 'string' and #token == 48, 'server capture should return a long opaque token')

    local sent = mocks.lastEntry(net.triggeredClientEvents, 'qblib:client:screenshotRequested')
    harness.assertTrue(sent ~= nil, 'the server should ask the selected player to capture')
    harness.assertEqual(sent[1].token, token, 'the player should receive the one-time capture token')
    local upload = mocks.lastEntry(net.triggeredServerEvents, 'qblib:server:screenshotCaptured')
    harness.assertTrue(upload ~= nil and upload[1] == token,
        'the client should return the image through the tokenized latent event')
    harness.assertEqual(callbackErr, false, 'success callback should receive false for err')
    harness.assertTrue(type(callbackResult) == 'string' and callbackResult:find('data:image/jpeg;base64,', 1, true) == 1,
        'a capture without a fileName should return a JPEG data URI')
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

harness.test('server capture writes a caller-controlled server path when requested', function()
    -- requestClient's fileName is a server API value, never data supplied by
    -- the player/browser. Use the OS temporary directory here so this smoke
    -- path proves qblib-playground's PDF attachment flow receives real bytes.
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
