---
title: "Screenshot"
sidebar_position: 45
---


# Screenshot

## Client

Captures the game render target and can upload the result. The module bounds image dimensions, serializes NUI captures, and provides callback-style compatibility with screenshot-basic. A screenshot is client-submitted evidence, not proof that the image is genuine.

Namespace: `Kora.screenshot` · Source: `modules/screenshot/client.lua`

### Capture options

Pass an options table to capture or upload. Output is limited to 1920×1080 by default. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `encoding?` | 'jpg' \| 'png' \| 'webp' | Image encoding format. |
| `quality?` | number | Encoding quality from 0 to 1 for lossy formats. |
| `maxWidth?` | integer \| false | Positive maximum width; false leaves width unbounded. |
| `maxHeight?` | integer \| false | Positive maximum height; false leaves height unbounded. |

### Compatibility

kora_lib provides the screenshot-basic client exports requestScreenshot and requestScreenshotUpload. includeNui is accepted for compatibility, but FiveM captures the game render target rather than a composited browser surface.

### Capture safety

Server-initiated captures use a one-time token, expire after the configured timeout, allow one active request per player, and reject empty or oversized images. The client can submit arbitrary image bytes for its request, so validate any moderation decision against independent server state.

### Functions

Capture a data URI, upload it, or use callback forms compatible with screenshot-basic.

#### `Kora.screenshot.capture(options?, timeout?)`

Captures the game screen and returns an awaitable data URI.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `options?` | table | Optional encoding, quality, and maximum image dimensions. |
| `timeout?` | integer | Optional finite integer timeout in milliseconds. |

**Returns**

- **promise result** — data URI string on success; rejects on capture or timeout failure.

**Example**

```lua
local image = Citizen.Await(Kora.screenshot.capture({ encoding = 'jpg', quality = 0.9, maxWidth = 1920, maxHeight = 1080 }))
print(image:sub(1, 30))
```

**Representative console output**

```text
Prints the beginning of the returned encoded image data.
```

#### `Kora.screenshot.upload(url, field?, options?, timeout?)`

Captures and sends the image to a URL. With field, the request uses multipart form data; without it, a legacy JSON data-URI body is sent.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `url` | string | Destination URL. |
| `field?` | string | Optional multipart form field name. |
| `options?` | table | Optional encoding, quality, and dimension limits. |
| `timeout?` | integer | Optional finite integer timeout. |

**Returns**

- **promise result** — response value or upload error.

**Example**

```lua
local response = Citizen.Await(Kora.screenshot.upload('https://example.invalid/upload', 'file', { encoding = 'jpg', quality = 0.86 }))
print(response)
```

**Representative console output**

```text
Uploads the captured JPEG using a multipart field named file.
```

#### `Kora.screenshot.requestScreenshot(options, callback)`

Callback-style capture equivalent for existing screenshot-basic callers.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `options` | table | Capture encoding, quality, and dimension options. |
| `callback` | function | Called with the resulting screenshot data or failure value. |

**Returns**

- **callback** — receives screenshot result.

**Example**

```lua
Kora.screenshot.requestScreenshot({ encoding = 'jpg', quality = 0.9 }, function(data)
    if data then print('Capture received') end
end)
```

**Representative console output**

```text
The callback runs when the image is captured or the request fails.
```

#### `Kora.screenshot.requestScreenshotUpload(url, field, options, callback)`

Callback-style capture-and-upload function compatible with screenshot-basic.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `url` | string | Upload endpoint. |
| `field` | string? | Optional multipart form field. |
| `options` | table | Capture and upload options. |
| `callback` | function | Called with the upload response or failure. |

**Returns**

- **callback** — receives upload result.

**Example**

```lua
Kora.screenshot.requestScreenshotUpload(url, 'file', { encoding = 'jpg' }, function(data)
    print(data and 'Uploaded' or 'Upload failed')
end)
```

**Representative console output**

```text
Prints whether the callback received an upload result.
```

### Limits and related APIs

Dimensions and timeouts must be finite integers. Dimensions are positive or false. Server request timeout must exceed 1000 ms.

## Server

Requests a screenshot from one client and receives the saved path or data URI through a callback. The upload path uses a one-time token and bounded image size; the file destination is selected on the server.

Namespace: `Kora.screenshot` · Source: `modules/screenshot/server.lua`

### Server request options

The options table controls the client capture and server upload. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `fileName?` | string | Server-selected output destination. Never accept this value from an untrusted client event. |
| `encoding?` | 'jpg' \| 'png' \| 'webp' | Requested image format. |
| `quality?` | number | Image encoding quality. |
| `timeout?` | integer | Request timeout in milliseconds, greater than 1000. Defaults from Config.screenshot. |
| `maxWidth / maxHeight?` | integer \| false | Optional image bounds; dimensions must be positive integers unless false. |

### What the callback proves

The callback associates the upload with the player who received the one-time request, but it does not prove that the submitted image is authentic. The image bytes come from that client. Recheck all gameplay and moderation facts on the server.

### Functions

Use requestClient to ask one player for a capture and handle success or failure asynchronously.

#### `Kora.screenshot.requestClient(player, options?, callback)`

Starts a one-time client screenshot request and calls the callback with an error or result.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `player` | integer | Positive server ID of the requested player. |
| `options?` | table | Optional fileName, encoding, quality, timeout, and capture dimension settings. |
| `callback` | function | Receives (error, result). On success error is nil and result is the saved path or data URI. |

**Returns**

- **callback** — error string and result; success returns nil, result.

**Example**

```lua
Kora.screenshot.requestClient(source, {
    fileName = GetResourcePath(GetCurrentResourceName()) .. '/reports/feedback.jpg',
    encoding = 'jpg', quality = 0.86, timeout = 15000,
}, function(err, result)
    if err then return print(err) end
    print('Saved screenshot to:', result)
end)
```

**Representative console output**

```text
Prints an error or the path where the server-side request saved the image. The same function is also exported as `exports.kora_lib:requestClientScreenshot(player, options, callback)`, and is served to resources written against screenshot-basic's `requestClientScreenshot` export.
```

### Limits and related APIs

Only one capture can be active per player. The request token expires and can be used once. Image size is capped by Config.screenshot.maxBytes.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/screenshot/docs.md` or `local/screenshot/docs.md`) that the reference above does not state.

`Kora.screenshot` keeps the game-view texture current while captures are pending,
serialises NUI captures, and releases their resources when the queue drains.
Output is capped at 1920×1080 by default (`Config.screenshot`) to keep diagnostic
captures cheap on high-DPI or ultrawide clients.

### API

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

### `screenshot-basic` compatibility

kora_lib provides `screenshot-basic` and exposes its public client exports
`requestScreenshot` / `requestScreenshotUpload` plus server export
`requestClientScreenshot`. Existing callers can keep using
`exports['screenshot-basic']` while migrating to `Kora.screenshot`.

The `includeNui` option is accepted for source compatibility but cannot include
other resources' CEF/NUI surfaces: FiveM's CfxTexture exposes the game render
target, not a composited browser desktop. HUD/game rendering is captured; use a
purpose-built in-game evidence camera if a report must show a separate web UI.

### Upload safety

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
