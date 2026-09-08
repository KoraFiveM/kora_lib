# Screenshot

`QB.screenshot` captures the FiveM game render target on demand. It has no
per-frame loop while idle, serialises NUI captures, and caps output at 1920×1080
by default (`Config.screenshot`) to keep diagnostic captures cheap on high-DPI
or ultrawide clients.

## API

`QB.screenshot.capture(options, timeout)` returns a data URI. Its callback
compatibility equivalent is `QB.screenshot.requestScreenshot(options, callback)`.

```lua
-- Client: returns an awaitable promise in qblib and a settled data URI through
-- exports.qblib:screenshot_capture(...) for another resource.
local image = Citizen.Await(QB.screenshot.capture({
    encoding = 'jpg', -- jpg | png | webp
    quality = 0.9,    -- 0 to 1
    maxWidth = 1920,  -- false leaves a dimension unbounded
    maxHeight = 1080,
}))

-- Server: sends a one-time upload request to the player. The callback receives
-- false + the saved path/data URI on success, or an error string on failure.
QB.screenshot.requestClient(source, {
    fileName = ('%s/reports/feedback.jpg'):format(GetResourcePath(GetCurrentResourceName())),
    encoding = 'jpg',
    quality = 0.86,
    timeout = 15000,
}, function(err, result)
    if err then return print(err) end
    print(('Saved screenshot to %s'):format(result))
end)
```

`QB.screenshot.upload(url, field, options)` captures then uploads from the
client. A supplied `field` sends multipart form data; no field uses the legacy
JSON data-URI body. `QB.screenshot.requestScreenshotUpload(url, field, options,
callback)` retains screenshot-basic's callback API.

For server-initiated captures, the browser posts the encoded image bytes
directly to qblib's one-time HTTP upload endpoint. The multi-megabyte image does
not become a base64 Lua string or cross a network event; only small progress or
failure messages do. Capture or transfer failures reach the callback instead
of waiting silently, so callers can continue their workflow without a
screenshot. The legacy tokenized latent-event receiver remains accepted during
rolling upgrades, but new clients do not use it.

## `screenshot-basic` compatibility

qblib provides `screenshot-basic` and exposes its public client exports
`requestScreenshot` / `requestScreenshotUpload` plus server export
`requestClientScreenshot`. Existing callers can keep using
`exports['screenshot-basic']` while migrating to `QB.screenshot`.

The `includeNui` option is accepted for source compatibility but cannot include
other resources' CEF/NUI surfaces: FiveM's CfxTexture exposes the game render
target, not a composited browser desktop. HUD/game rendering is captured; use a
purpose-built in-game evidence camera if a report must show a separate web UI.

## Upload safety

Server-initiated capture uploads use a one-time 48-character token, expire
after `Config.screenshot.requestTimeout`, permit one active capture per player,
and reject empty, oversized, or type-mismatched images before invoking the
server callback. The HTTP path checks `Content-Length` when supplied and always
checks the received body size.
`fileName` is intentionally server-controlled; never pass it from an untrusted
client event.
