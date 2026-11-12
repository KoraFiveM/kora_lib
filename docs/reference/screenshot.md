---
title: "Screenshot"
sidebar_position: 45
---

# Screenshot

`Kora.screenshot` keeps the game-view texture current while captures are pending,
serialises NUI captures, and releases their resources when the queue drains.
Output is capped at 1920×1080 by default (`Config.screenshot`) to keep diagnostic
captures cheap on high-DPI or ultrawide clients.

## API

`Kora.screenshot.capture(options, timeout)` returns a data URI. Its callback
compatibility equivalent is `Kora.screenshot.requestScreenshot(options, callback)`.

```lua
-- Client: returns an awaitable promise in kora_lib and a settled data URI through
-- exports.kora_lib:screenshot_capture(...) for another resource.
local image = Citizen.Await(Kora.screenshot.capture({
    encoding = 'jpg', -- jpg | png | webp
    quality = 0.9,    -- 0 to 1
    maxWidth = 1920,  -- false leaves a dimension unbounded
    maxHeight = 1080,
}))

-- Server: sends a one-time upload request to the player. The callback receives
-- false + the saved path/data URI on success, or an error string on failure.
Kora.screenshot.requestClient(source, {
    fileName = ('%s/reports/feedback.jpg'):format(GetResourcePath(GetCurrentResourceName())),
    encoding = 'jpg',
    quality = 0.86,
    timeout = 15000,
}, function(err, result)
    if err then return print(err) end
    print(('Saved screenshot to %s'):format(result))
end)
```

`Kora.screenshot.upload(url, field, options)` captures then uploads from the
client. A supplied `field` sends multipart form data; no field uses the legacy
JSON data-URI body. `Kora.screenshot.requestScreenshotUpload(url, field, options,
callback)` retains screenshot-basic's callback API.

`maxWidth`, `maxHeight`, and every timeout must be finite integers. Dimensions
are positive (or `false` to leave one unbounded); server request timeouts must
be greater than 1000 ms.
For `Kora.screenshot.requestClient`, put the timeout in `options.timeout`.
Client `capture` and `upload` use their separate positional `timeout` argument.
When supplied, an options value must be a table; `encoding` must be `jpg`,
`png`, or `webp`, and a timeout is never silently replaced when explicitly
invalid. `Kora.screenshot.requestClient(source)` is valid and uses the configured
server defaults.

For server-initiated captures, the browser posts the encoded image bytes
directly to kora_lib's one-time HTTP upload endpoint. The multi-megabyte image does
not become a base64 Lua string or cross a network event; only small progress or
failure messages do in the normal path. If a secure NUI page cannot reach a
plain-HTTP server endpoint, the client automatically retries through the
bounded tokenized latent-event receiver. Capture failures reach the callback
instead of waiting silently, so callers can continue their workflow without a
screenshot.

## `screenshot-basic` compatibility

kora_lib provides `screenshot-basic` and exposes its public client exports
`requestScreenshot` / `requestScreenshotUpload` plus server export
`requestClientScreenshot`. Existing callers can keep using
`exports['screenshot-basic']` while migrating to `Kora.screenshot`.

The `includeNui` option is accepted for source compatibility but cannot include
other resources' CEF/NUI surfaces: FiveM's CfxTexture exposes the game render
target, not a composited browser desktop. HUD/game rendering is captured; use a
purpose-built in-game evidence camera if a report must show a separate web UI.

## Upload safety

Server-initiated capture uploads use a one-time 48-character token, expire
after `Config.screenshot.requestTimeout`, permit one active capture per player,
and reject empty, oversized, or type-mismatched images before invoking the
server callback. The HTTP path checks `Content-Length` when supplied and always
checks the received body size. `Config.screenshot.maxBytes` must be a positive
integer; an invalid value safely falls back to the 12 MiB default.
`fileName` is intentionally server-controlled; never pass it from an untrusted
client event. The token associates an upload with the requested player; it is
not proof that the resulting image is genuine. A modified client can submit an
arbitrary image for its own live request, so treat a capture as client-supplied
evidence and make any moderation or gameplay decision from independently
validated server state.
