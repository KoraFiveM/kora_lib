local isCallable = QB.compat.isCallable
local generateToken = QB.compat.generateToken
local pendingUploads = {}
local playerUploads = {}

local function screenshotMilliseconds()
    if type(GetGameTimer) == 'function' then return GetGameTimer() end
    return math.floor(os.clock() * 1000)
end

local function screenshotDebug(session, stage, detail)
    local config = (Config and Config.screenshot) or {}
    if GetConvarInt(config.debugConvar or 'qblib_screenshot_debug', 0) ~= 1 then return end

    local elapsed = screenshotMilliseconds() - (session.startedAt or screenshotMilliseconds())
    local suffix = detail and detail ~= '' and ('; %s'):format(detail) or ''
    print(('[qblib:screenshot][debug][%s] %s (+%d ms%s)'):format(session.token:sub(1, 8), stage, elapsed, suffix))
end

local validEncodings = {
    jpg = { mime = 'image/jpeg', extension = 'jpg' },
    png = { mime = 'image/png', extension = 'png' },
    webp = { mime = 'image/webp', extension = 'webp' },
}

local function screenshotConfig()
    return (Config and Config.screenshot) or {}
end

local function imageMatchesEncoding(data, encoding)
    if encoding == 'jpg' then return data:sub(1, 3) == '\255\216\255' end
    if encoding == 'png' then return data:sub(1, 8) == '\137PNG\r\n\26\n' end
    return data:sub(1, 4) == 'RIFF' and data:sub(9, 12) == 'WEBP'
end

local BASE64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

local function base64Encode(data)
    local output = {}
    for index = 1, #data, 3 do
        local first, second, third = data:byte(index, index + 2)
        local value = first * 65536 + (second or 0) * 256 + (third or 0)
        output[#output + 1] = BASE64:sub(math.floor(value / 262144) % 64 + 1, math.floor(value / 262144) % 64 + 1)
        output[#output + 1] = BASE64:sub(math.floor(value / 4096) % 64 + 1, math.floor(value / 4096) % 64 + 1)
        output[#output + 1] = second and BASE64:sub(math.floor(value / 64) % 64 + 1, math.floor(value / 64) % 64 + 1) or '='
        output[#output + 1] = third and BASE64:sub(value % 64 + 1, value % 64 + 1) or '='
    end
    return table.concat(output)
end

local base64Values = {}
for index = 1, #BASE64 do base64Values[BASE64:byte(index)] = index - 1 end

local function base64Decode(data)
    if type(data) ~= 'string' or #data == 0 or #data % 4 ~= 0 then return nil end

    local output = {}
    for index = 1, #data, 4 do
        local firstByte, secondByte, thirdByte, fourthByte = data:byte(index, index + 3)
        local first, second = base64Values[firstByte], base64Values[secondByte]
        if first == nil or second == nil then return nil end

        local thirdPadding = thirdByte == 61
        local fourthPadding = fourthByte == 61
        if thirdPadding then
            if not fourthPadding or index + 3 ~= #data then return nil end
            output[#output + 1] = string.char((first * 4) + math.floor(second / 16))
        else
            local third = base64Values[thirdByte]
            if third == nil then return nil end
            output[#output + 1] = string.char((first * 4) + math.floor(second / 16))
            output[#output + 1] = string.char(((second % 16) * 16) + math.floor(third / 4))
            if fourthPadding then
                if index + 3 ~= #data then return nil end
            else
                local fourth = base64Values[fourthByte]
                if fourth == nil then return nil end
                output[#output + 1] = string.char(((third % 4) * 64) + fourth)
            end
        end
    end
    return table.concat(output)
end

local function finish(session, err, result)
    if pendingUploads[session.token] ~= session then return end
    screenshotDebug(session, err and 'capture failed' or 'capture completed',
        err and tostring(err) or (session.bytes and ('%d bytes'):format(session.bytes) or nil))
    pendingUploads[session.token] = nil
    if playerUploads[session.player] == session.token then playerUploads[session.player] = nil end

    if not isCallable(session.callback) then return end
    local ok, callbackErr = pcall(session.callback, err or false, result)
    if not ok then
        print(('[qblib:screenshot] capture callback failed: %s'):format(tostring(callbackErr)))
    end
end

local function normalizeOptions(options)
    options = options or {}
    assert(type(options) == 'table', 'Screenshot options must be a table.')

    local config = screenshotConfig()
    local encoding = options.encoding or config.defaultEncoding or 'jpg'
    assert(type(encoding) == 'string' and validEncodings[encoding], 'Screenshot encoding must be jpg, png, or webp.')

    local quality = options.quality
    if quality == nil then quality = config.defaultQuality or 0.92 end
    assert(type(quality) == 'number' and quality >= 0 and quality <= 1,
        'Screenshot quality must be a number from 0 to 1.')

    local maxWidth = options.maxWidth
    if maxWidth == nil then maxWidth = config.maxWidth end
    local maxHeight = options.maxHeight
    if maxHeight == nil then maxHeight = config.maxHeight end
    assert(maxWidth == false or (type(maxWidth) == 'number' and maxWidth >= 1 and maxWidth % 1 == 0),
        'Screenshot maxWidth must be a positive integer or false.')
    assert(maxHeight == false or (type(maxHeight) == 'number' and maxHeight >= 1 and maxHeight % 1 == 0),
        'Screenshot maxHeight must be a positive integer or false.')
    assert(options.includeNui == nil or type(options.includeNui) == 'boolean',
        'Screenshot includeNui must be a boolean.')
    assert(options.fileName == nil or (type(options.fileName) == 'string' and options.fileName ~= ''),
        'Screenshot fileName must be a non-empty string.')

    return {
        encoding = encoding,
        quality = quality,
        maxWidth = maxWidth,
        maxHeight = maxHeight,
        includeNui = options.includeNui == true,
        fileName = options.fileName,
    }
end

---Requests one game-frame capture from a connected client. The opaque upload
---token is single-use, per-player, and expires automatically.
---@param player integer
---@param options? table `{ fileName?: string, encoding?: 'jpg'|'png'|'webp', quality?: number, maxWidth?: integer|false, maxHeight?: integer|false, includeNui?: boolean, timeout?: integer }`
---@param callback? fun(err: string|false, result?: string)
---@return string token
function QB.screenshot.requestClient(player, options, callback)
    assert(type(player) == 'number' and player >= 1 and player % 1 == 0,
        'Screenshot player must be a positive server ID.')
    assert(callback == nil or isCallable(callback), 'Screenshot callback must be callable.')
    assert(GetPlayerName(player) ~= nil, 'Screenshot player is not connected.')
    assert(not playerUploads[player], 'A screenshot is already pending for this player.')

    local normalized = normalizeOptions(options)
    local token = generateToken(48)
    local session = {
        token = token,
        player = player,
        encoding = normalized.encoding,
        fileName = normalized.fileName,
        callback = callback,
        startedAt = screenshotMilliseconds(),
    }
    pendingUploads[token] = session
    playerUploads[player] = token

    local timeout = options and options.timeout or screenshotConfig().requestTimeout or 30000
    assert(type(timeout) == 'number' and timeout > 1000 and timeout % 1 == 0,
        'Screenshot timeout must be an integer greater than 1000 milliseconds.')
    SetTimeout(timeout, function()
        if pendingUploads[token] == session then
            finish(session, 'Screenshot capture timed out.')
        end
    end)

    TriggerClientEvent('qblib:client:screenshotRequested', player, {
        token = token,
        rawBody = true,
        encoding = normalized.encoding,
        quality = normalized.quality,
        maxWidth = normalized.maxWidth,
        maxHeight = normalized.maxHeight,
        -- Kept for screenshot-basic source compatibility. Game-view capture
        -- cannot access separate resource CEF layers; docs make that explicit.
        includeNui = normalized.includeNui,
        timeout = timeout,
    })
    screenshotDebug(session, 'request sent to client', ('player %d; %s'):format(player, normalized.encoding))

    return token
end

-- GetCurrentServerEndpoint is client-only. The player that received the
-- request builds the upload URL, then reports this specific inability so a
-- report can continue without waiting for the capture timeout.
RegisterNetEvent('qblib:server:screenshotFailed', function(token, clientReason)
    if type(token) ~= 'string' then return end

    local session = pendingUploads[token]
    if not session or session.player ~= source then return end
    screenshotDebug(session, 'client reported failure', type(clientReason) == 'string' and clientReason:sub(1, 240) or nil)
    finish(session, 'The client could not capture or return the screenshot.')
end)

RegisterNetEvent('qblib:server:screenshotProgressed', function(token, stage, value)
    local session = type(token) == 'string' and pendingUploads[token] or nil
    if not session or session.player ~= source then return end

    local stages = {
        received = 'client received request',
        captured = 'client encoded game frame',
        sending = 'client started latent upload',
    }
    local label = type(stage) == 'string' and stages[stage] or nil
    if not label then return end
    screenshotDebug(session, label, type(value) == 'number' and ('%d bytes'):format(value) or nil)
end)

local function persistScreenshot(session, data)
    if type(data) ~= 'string' or #data == 0 then return 'The screenshot was empty.', nil, 400 end

    local maxBytes = screenshotConfig().maxBytes or (12 * 1024 * 1024)
    if #data > maxBytes then return 'The screenshot exceeded qblib\'s upload limit.', nil, 413 end
    if not imageMatchesEncoding(data, session.encoding) then
        return 'The uploaded file did not match the requested image format.', nil, 415
    end

    local result
    if session.fileName then
        local file, err = io.open(session.fileName, 'wb')
        if not file then return ('Unable to save screenshot: %s'):format(tostring(err)), nil, 500 end
        file:write(data)
        file:close()
        result = session.fileName
    else
        result = ('data:%s;base64,%s'):format(validEncodings[session.encoding].mime, base64Encode(data))
    end
    session.bytes = #data
    return false, result, 200
end

RegisterNetEvent('qblib:server:screenshotCaptured', function(token, dataUri)
    local session = type(token) == 'string' and pendingUploads[token] or nil
    if not session or session.player ~= source then return end

    screenshotDebug(session, 'server received latent upload',
        type(dataUri) == 'string' and ('%d encoded bytes'):format(#dataUri) or 'invalid payload')
    local prefix = ('data:%s;base64,'):format(validEncodings[session.encoding].mime)
    if type(dataUri) ~= 'string' or dataUri:sub(1, #prefix) ~= prefix then
        finish(session, 'The returned screenshot data did not match the requested image format.')
        return
    end

    local encoded = dataUri:sub(#prefix + 1)
    local maxBytes = screenshotConfig().maxBytes or (12 * 1024 * 1024)
    if #encoded > math.ceil(maxBytes / 3) * 4 then
        finish(session, 'The screenshot exceeded qblib\'s upload limit.')
        return
    end

    local decodeStartedAt = screenshotMilliseconds()
    local data = base64Decode(encoded)
    screenshotDebug(session, 'server decoded screenshot',
        ('%d ms; %s'):format(screenshotMilliseconds() - decodeStartedAt,
            data and ('%d bytes'):format(#data) or 'invalid base64'))
    local err, result = persistScreenshot(session, data)
    finish(session, err, result)
end)

local responseHeaders = {
    ['Access-Control-Allow-Origin'] = '*',
    ['Access-Control-Allow-Methods'] = 'POST, OPTIONS',
    ['Access-Control-Allow-Headers'] = 'Content-Type',
    ['Cache-Control'] = 'no-store',
    ['X-Content-Type-Options'] = 'nosniff',
    ['Content-Type'] = 'text/plain; charset=utf-8',
}

local function reply(response, status, body)
    response.writeHead(status, responseHeaders)
    response.send(body or '')
end

local function receiveUpload(request, response)
    local path = request.path or ''
    local token = path:match('^/screenshot/upload/([%w]+)$')
        or path:match(('^/%s/screenshot/upload/([%%w]+)$'):format(GetCurrentResourceName()))
    if not token then
        reply(response, 404, 'Not found')
        return
    end

    if request.method == 'OPTIONS' then
        reply(response, 204)
        return
    end
    if request.method ~= 'POST' then
        response.writeHead(405, {
            ['Access-Control-Allow-Origin'] = '*',
            ['Access-Control-Allow-Methods'] = 'POST, OPTIONS',
            ['Access-Control-Allow-Headers'] = 'Content-Type',
            ['Allow'] = 'POST, OPTIONS',
            ['Cache-Control'] = 'no-store',
            ['Content-Type'] = 'text/plain; charset=utf-8',
            ['X-Content-Type-Options'] = 'nosniff',
        })
        response.send('Method not allowed')
        return
    end

    local session = pendingUploads[token]
    if not session then
        reply(response, 404, 'Capture request expired')
        return
    end

    request.setDataHandler(function(data)
        if pendingUploads[token] ~= session then
            reply(response, 409, 'Capture request was already completed')
            return
        end
        local err, result, status = persistScreenshot(session, data)
        finish(session, err, result)
        reply(response, status, err and tostring(err) or 'ok')
    end)
end

if type(SetHttpHandler) == 'function' then SetHttpHandler(receiveUpload) end

AddEventHandler('playerDropped', function()
    local token = playerUploads[source]
    local session = token and pendingUploads[token]
    if session then finish(session, 'The player disconnected before the screenshot was captured.') end
end)

local function legacyRequestClientScreenshot(player, options, callback)
    return QB.screenshot.requestClient(tonumber(player), options, callback)
end

if exports then exports('requestClientScreenshot', legacyRequestClientScreenshot) end

AddEventHandler('__cfx_export_screenshot-basic_requestClientScreenshot', function(setCallback)
    setCallback(legacyRequestClientScreenshot)
end)
