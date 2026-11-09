local isCallable = Kora.compat.isCallable
local isInteger = Kora.util.isInteger

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
    if options == nil then options = {} end
    assert(type(options) == 'table', 'Screenshot options must be a table.')

    local config = screenshotConfig()
    local encoding = options.encoding
    if encoding == nil then encoding = config.defaultEncoding or 'jpg' end
    assert(type(encoding) == 'string' and validEncodings[encoding], 'Screenshot encoding must be jpg, png, or webp.')

    local quality = options.quality
    if quality == nil then quality = config.defaultQuality or 0.92 end
    assert(type(quality) == 'number' and quality >= 0 and quality <= 1,
        'Screenshot quality must be a number from 0 to 1.')

    local maxWidth = options.maxWidth
    if maxWidth == nil then maxWidth = config.maxWidth end
    local maxHeight = options.maxHeight
    if maxHeight == nil then maxHeight = config.maxHeight end
    assert(maxWidth == false or (isInteger(maxWidth) and maxWidth >= 1),
        'Screenshot maxWidth must be a positive integer or false.')
    assert(maxHeight == false or (isInteger(maxHeight) and maxHeight >= 1),
        'Screenshot maxHeight must be a positive integer or false.')

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
    if timeout == nil then timeout = screenshotConfig().requestTimeout or 30000 end
    assert(isInteger(timeout) and timeout > 0,
        'Screenshot timeout must be a positive integer.')

    CreateThread(function()
        local ok, result = pcall(function()
            return Citizen.Await(Kora.nui.request('screenshot:capture', normalized, timeout))
        end)

        if ok then
            p:resolve(result and result.data or nil)
        else
            p:reject(result)
        end
    end)

    return p
end

local function settleForExport(p)
    if GetInvokingResource() then return Citizen.Await(p) end
    return p
end

---Captures the game render target and resolves to a data URI.
---@param options? table `{ encoding?: 'jpg'|'png'|'webp', quality?: number, maxWidth?: integer|false, maxHeight?: integer|false, includeNui?: boolean }`
---@param timeout? integer
---@return promise|any dataUri
function Kora.screenshot.capture(options, timeout)
    return settleForExport(beginCapture(options, timeout))
end

local function normalizeUploadOptions(options)
    if options == nil then options = {} end
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
    if timeout == nil then timeout = screenshotConfig().requestTimeout or 30000 end
    assert(isInteger(timeout) and timeout > 0,
        'Screenshot timeout must be a positive integer.')

    CreateThread(function()
        local ok, result = pcall(function()
            return Citizen.Await(Kora.nui.request('screenshot:upload', {
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
function Kora.screenshot.upload(url, field, options, timeout)
    return settleForExport(beginUpload(url, field, options, timeout))
end

function Kora.screenshot.requestScreenshot(options, callback)
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

function Kora.screenshot.requestScreenshotUpload(url, field, options, callback)
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

if exports then
    exports('requestScreenshot', Kora.screenshot.requestScreenshot)
    exports('requestScreenshotUpload', Kora.screenshot.requestScreenshotUpload)
end

local function sendLatentScreenshot(token, options, timeout)
    beginCapture(options, timeout):next(function(dataUri)
        if type(dataUri) ~= 'string' or dataUri == '' then
            TriggerServerEvent('kora_lib:server:screenshotFailed', token, 'The NUI returned an empty screenshot.')
            return
        end

        TriggerServerEvent('kora_lib:server:screenshotProgressed', token, 'captured', #dataUri)
        local bytesPerSecond = tonumber(screenshotConfig().uploadBytesPerSecond) or (2 * 1024 * 1024)
        TriggerServerEvent('kora_lib:server:screenshotProgressed', token, 'sending', #dataUri)
        local ok, err = pcall(TriggerLatentServerEvent,
            'kora_lib:server:screenshotCaptured', bytesPerSecond, token, dataUri)
        if not ok then TriggerServerEvent('kora_lib:server:screenshotFailed', token, tostring(err)) end
    end, function(err)
        TriggerServerEvent('kora_lib:server:screenshotFailed', token, tostring(err))
    end)
end

RegisterNetEvent('kora_lib:client:screenshotRequested', function(payload)
    if type(payload) ~= 'table' or type(payload.token) ~= 'string' then return end

    local token = payload.token
    local options = {}
    for key, value in pairs(payload) do if key ~= 'token' and key ~= 'timeout' then options[key] = value end end
    local timeout = tonumber(payload.timeout) or screenshotConfig().requestTimeout or 30000
    local captureTimeout = math.max(1000, timeout - 1000)
    TriggerServerEvent('kora_lib:server:screenshotProgressed', token, 'received')

    if payload.rawBody then
        local endpoint = GetCurrentServerEndpoint()
        if type(endpoint) ~= 'string' or endpoint == '' then
            sendLatentScreenshot(token, options, captureTimeout)
            return
        end

        endpoint = endpoint:gsub('/+$', '')
        if not endpoint:match('^https?://') then endpoint = 'http://' .. endpoint end
        if endpoint:match('^http://') then
            sendLatentScreenshot(token, options, captureTimeout)
            return
        end
        options.url = ('%s/%s/screenshot/upload/%s'):format(endpoint, GetCurrentResourceName(), token)
        options.headers = {}

        TriggerServerEvent('kora_lib:server:screenshotProgressed', token, 'sending')
        Kora.nui.request('screenshot:upload', options, captureTimeout):next(function()
        end, function()
            sendLatentScreenshot(token, options, captureTimeout)
        end)
        return
    end

    sendLatentScreenshot(token, options, captureTimeout)
end)
