local isCallable = QB.compat.isCallable

local validEncodings = {
    jpg = true,
    png = true,
    webp = true,
}

local function screenshotConfig()
    return (Config and Config.screenshot) or {}
end

local function copyHeaders(headers)
    if headers == nil then return {} end
    assert(type(headers) == 'table', 'Screenshot headers must be a table.')

    local result = {}
    for key, value in pairs(headers) do
        assert(type(key) == 'string' and key ~= '', 'Screenshot header names must be non-empty strings.')
        assert(type(value) == 'string' or type(value) == 'number', 'Screenshot header values must be strings or numbers.')
        result[key] = tostring(value)
    end
    return result
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

    -- screenshot-basic accepted this option but its CfxTexture capture never
    -- contained CEF layers. Retain it on the wire for source compatibility;
    -- see modules/screenshot/docs.md for the rendering boundary.
    assert(options.includeNui == nil or type(options.includeNui) == 'boolean',
        'Screenshot includeNui must be a boolean.')

    return {
        encoding = encoding,
        quality = quality,
        maxWidth = maxWidth,
        maxHeight = maxHeight,
        includeNui = options.includeNui == true,
    }
end

local function beginCapture(options, timeout)
    local p = promise.new()
    local normalized = normalizeOptions(options)
    timeout = timeout or screenshotConfig().requestTimeout or 30000
    assert(type(timeout) == 'number' and timeout > 0 and timeout % 1 == 0,
        'Screenshot timeout must be a positive integer.')

    CreateThread(function()
        local ok, result = pcall(function()
            return Citizen.Await(QB.nui.request('screenshot:capture', normalized, timeout))
        end)

        if ok then
            p:resolve(result and result.data or nil)
        else
            p:reject(result)
        end
    end)

    return p
end

-- A promise object does not survive a real cross-resource exports call, so
-- match QB.nui's public convention: internal callers receive an awaitable
-- promise and external callers receive its settled value.
local function settleForExport(p)
    if GetInvokingResource() then return Citizen.Await(p) end
    return p
end

---Captures the game render target and resolves to a data URI.
---@param options? table `{ encoding?: 'jpg'|'png'|'webp', quality?: number, maxWidth?: integer|false, maxHeight?: integer|false, includeNui?: boolean }`
---@param timeout? integer
---@return promise|any dataUri
function QB.screenshot.capture(options, timeout)
    return settleForExport(beginCapture(options, timeout))
end

local function normalizeUploadOptions(options)
    options = options or {}
    assert(type(options) == 'table', 'Screenshot upload options must be a table.')

    local capture = normalizeOptions(options)
    capture.headers = copyHeaders(options.headers)
    return capture
end

local function beginUpload(url, field, options, timeout)
    assert(type(url) == 'string' and url:match('^https?://'), 'Screenshot upload URL must be an absolute HTTP(S) URL.')
    assert(field == nil or type(field) == 'string', 'Screenshot upload field must be a string or nil.')

    local p = promise.new()
    local normalized = normalizeUploadOptions(options)
    timeout = timeout or screenshotConfig().requestTimeout or 30000

    CreateThread(function()
        local ok, result = pcall(function()
            return Citizen.Await(QB.nui.request('screenshot:upload', {
                url = url,
                field = field,
                encoding = normalized.encoding,
                quality = normalized.quality,
                maxWidth = normalized.maxWidth,
                maxHeight = normalized.maxHeight,
                includeNui = normalized.includeNui,
                headers = normalized.headers,
            }, timeout))
        end)

        if ok then p:resolve(result) else p:reject(result) end
    end)

    return p
end

---Captures and uploads an image. A non-empty field sends multipart form data;
---an omitted field matches screenshot-basic's legacy JSON data-URI mode.
---@param url string
---@param field? string
---@param options? table
---@param timeout? integer
---@return promise|any responseBody
function QB.screenshot.upload(url, field, options, timeout)
    return settleForExport(beginUpload(url, field, options, timeout))
end

function QB.screenshot.requestScreenshot(options, callback)
    if callback == nil then
        callback = options
        options = { encoding = 'jpg' }
    end
    assert(isCallable(callback), 'requestScreenshot requires a callback.')

    local p = beginCapture(options)
    p:next(function(data)
        callback(data)
    end, function()
        callback(nil)
    end)
end

function QB.screenshot.requestScreenshotUpload(url, field, options, callback)
    if callback == nil then
        callback = options
        options = { headers = {}, encoding = 'jpg' }
    end
    assert(isCallable(callback), 'requestScreenshotUpload requires a callback.')

    local p = beginUpload(url, field, options)
    p:next(function(response)
        callback(response)
    end, function()
        callback(nil)
    end)
end

-- qblib's direct aliases are useful for a resource that has already made
-- qblib a dependency, while the provided-resource hooks preserve the normal
-- exports['screenshot-basic']:requestScreenshot(...) call shape.
if exports then
    exports('requestScreenshot', QB.screenshot.requestScreenshot)
    exports('requestScreenshotUpload', QB.screenshot.requestScreenshotUpload)
end

RegisterNetEvent('qblib:client:screenshotRequested', function(payload)
    if type(payload) ~= 'table' or type(payload.token) ~= 'string' then return end

    local token = payload.token
    local options = {}
    for key, value in pairs(payload) do
        if key ~= 'token' and key ~= 'timeout' and key ~= 'rawBody' then options[key] = value end
    end
    local timeout = tonumber(payload.timeout) or screenshotConfig().requestTimeout or 30000
    local captureTimeout = math.max(1000, timeout - 1000)
    TriggerServerEvent('qblib:server:screenshotProgressed', token, 'received')

    beginCapture(options, captureTimeout):next(function(dataUri)
        if type(dataUri) ~= 'string' or dataUri == '' then
            TriggerServerEvent('qblib:server:screenshotFailed', token, 'The NUI returned an empty screenshot.')
            return
        end

        TriggerServerEvent('qblib:server:screenshotProgressed', token, 'captured', #dataUri)
        local bytesPerSecond = tonumber(screenshotConfig().uploadBytesPerSecond) or (2 * 1024 * 1024)
        TriggerServerEvent('qblib:server:screenshotProgressed', token, 'sending', #dataUri)
        local ok, err = pcall(TriggerLatentServerEvent, 'qblib:server:screenshotCaptured', bytesPerSecond, token, dataUri)
        if not ok then TriggerServerEvent('qblib:server:screenshotFailed', token, tostring(err)) end
    end, function(err)
        TriggerServerEvent('qblib:server:screenshotFailed', token, tostring(err))
    end)
end)
