# NUI module

## Overview
The NUI module is the bridge between Lua and the React app in `web/`. Every other module that needs to show something in the browser (a menu, an input dialog) or reach a browser-only capability (the clipboard) goes through `QB.nui.*` rather than calling `SendNUIMessage`/`RegisterNUICallback` directly.

Per the root [docs](../../AGENTS.md), the NUI is **headless**: it renders nothing and holds no focus until a message from Lua tells it to, and gives focus back up the moment that interaction ends.

## UI branding configuration

Set `Config.ui.accentColor` in `config.lua` to any six-digit hex colour (for example `"#7C3AED"`). The NUI requests it on startup through the private `qblib:nui:theme` callback, backed by `modules/theme`. See [modules/theme/docs.md](../theme/docs.md) for how the accent colour is validated and turned into the full token set — including `QB.theme.tokens()`, which any other resource's own NUI can call to match this look.

## API

### `QB.nui.send(action, data)`
Sends `{ action, data }` to the NUI. Fire-and-forget — use `QB.nui.request` when you need a response back.

### `QB.nui.setFocus(mouse, keyboard)`
Sets NUI focus directly.

#### Parameters
- `mouse: boolean`
- `keyboard: boolean`

### `QB.nui.withFocus(mouse, keyboard, fn)`
Sets focus, runs `fn`, and always clears focus afterward — including when `fn` raises an error (the error is re-raised once cleanup runs). Prefer this over `setFocus` whenever the interaction is scoped to one call. Note the built-in `openMenu`/`openContextMenu`/`openInputDialog` wrappers below already manage focus themselves — `withFocus` is for custom interactive requests of your own.

#### Example
```lua
local result = QB.nui.withFocus(true, true, function()
    return QB.nui.request("myCustomDialog", { foo = "bar" })
end)
```

### `QB.nui.registerCallback(name, handler)`
Registers an NUI callback. `handler(data)` returns a plain value (or nil); the raw `RegisterNUICallback` `(data, cb)` plumbing is handled for you, including catching and logging errors so a broken handler can't leave the NUI's fetch hanging.

### `QB.nui.request(action, data, timeout)`
Sends `action` to the NUI and returns its response, once available.

#### Parameters
- `action: string`
- `data: any`
- `timeout: integer | false | nil` — milliseconds before the request times out. Defaults to `30000`. Pass `false` to disable.

#### Returns
- The NUI's result value, or (from your own resource, calling this like any other `QB.*` export) `nil` on timeout/error — check qblib's own console for why. Must run inside a coroutine (`CreateThread`, a command handler, an NUI callback — anywhere `Citizen.Await` is legal), since it suspends until the NUI responds.

#### Example
```lua
local result = QB.nui.request("someAction", { foo = "bar" })
if result ~= nil then
    print("NUI responded:", json.encode(result))
end
```

### `QB.nui.copyToClipboard(text)`
Copies `text` to the system clipboard via the NUI — the browser is the only part of this stack with real clipboard access.

#### Parameters
- `text: string`

#### Returns
- `true` once the browser confirms the write, or `nil` on timeout/error.

#### Example
```lua
QB.nui.copyToClipboard("QB.zones.box({ ... })")
```

### `QB.nui.openMenu(items, title)`
Opens a searchable list menu. Grants mouse+keyboard NUI focus while open and releases it as soon as the menu closes (selection, cancel, or timeout) — no `withFocus` wrap needed.

#### Parameters
- `items: table[]` — `{ id: string, label: string, description?: string, icon?: string, disabled?: boolean }[]`
- `title?: string`

#### Returns
- `{ selectedId: string }` or `{ cancelled: true }`; `nil` on timeout/error.

`icon` resolves against a small curated set of lucide icon names (`web/src/lib/icon.ts`) — a name outside that set just renders with no icon rather than erroring; extend that file's list if you need one that isn't there yet.

### `QB.nui.openContextMenu(items, x, y)`
Opens a context menu anchored at `(x, y)`, or centered if omitted. Manages focus the same way `openMenu` does.

#### Parameters
- `items: table[]` — same shape as `openMenu`'s `items`.
- `x?: number`, `y?: number`

#### Returns
- Same as `openMenu`: `{ selectedId: string }` or `{ cancelled: true }`; `nil` on timeout/error.

### `QB.nui.openRadialMenu(items, opts)`
Opens an anchored radial menu. It uses the same recursive item tree and result shape as `openMenu`, so a caller can reuse its item-building logic. It manages NUI focus for its entire lifetime.

#### Parameters
- `items: table[]` — same `MenuItem` shape as `openMenu`, including `submenu = { title?, items }`.
- `opts?: table` — optional geometry: `x?: number`, `y?: number` (screen pixels; defaults to centre), `radius?: positive number` (defaults to the NUI's safe radial size).

#### Returns
- `{ selectedId: string, path: string[] }` or `{ cancelled: true }`; `nil` on timeout/error. `path` is root-first, so a `vehicle -> repair` selection returns `{ selectedId = "repair", path = { "vehicle", "repair" } }`.

Items sit clockwise from the top. A submenu replaces the ring locally and adds a centre Back control; Escape/backdrop/centre Close cancel the whole request. Long item lists page through a More wedge rather than silently dropping items. Disabled items stay visible but cannot be chosen.

#### Example
```lua
local result = QB.nui.openRadialMenu({
    { id = "engine", label = "Engine", icon = "Wrench" },
    {
        id = "doors",
        label = "Doors",
        icon = "Car",
        submenu = {
            items = {
                { id = "lock", label = "Lock", icon = "Lock" },
                { id = "unlock", label = "Unlock", icon = "Unlock" },
            },
        },
    },
}, { radius = 160 })

if result and not result.cancelled then
    print(table.concat(result.path, " -> "))
end
```

### `QB.nui.openInputDialog(fields, title, description)`
Opens a schema-driven input form. Manages focus the same way `openMenu` does.

#### Parameters
- `fields: table[]` — one per input:
  - `id: string`, `label: string`
  - `type: "text" | "password" | "textarea" | "number" | "checkbox" | "select"`
  - `options?: { value, label }[]` — `select` only.
  - `rows?: integer` — `textarea` only (default 3).
  - `default?`, `placeholder?`
  - `required?: boolean`, `min?: number`, `max?: number` (`number` only), `pattern?: string` (text-like types only) — optional client-side validation that gates the Confirm button. Convenience only: still validate anything that matters once you have the result.
- `title?: string`, `description?: string`

#### Returns
- `{ values: table<string, any> }` or `{ cancelled: true }`; `nil` on timeout/error.

#### Example
```lua
local result = QB.nui.openInputDialog({
    { id = "amount", label = "Amount", type = "number", default = 1, min = 1 },
}, "Withdraw")

if result and not result.cancelled then
    print("amount:", result.values.amount)
end
```

## Notes
- `QB.nui.request` tags every call with a `requestId` **and a random per-request token** and resolves it through one shared response callback (`qblib:nui:response`) rather than registering a new callback per call — see `modules/nui/AGENTS.md` for why the token exists and why one shared callback is used.
- A request that never gets a response (NUI never loaded, player alt-F4'd, etc.) times out after `timeout` instead of hanging forever — you get `nil` back rather than a hang.
- `openMenu`/`openContextMenu`/`openRadialMenu`/`openInputDialog` are thin wrappers over `QB.nui.request` — they don't unwrap the result any further than the NUI's own raw response, so check for `.cancelled` before reading `.selectedId`/`.path`/`.values`, and for `nil` before that (timeout/error).
- These functions still run inside a coroutine and `Citizen.Await` a real promise internally — that part isn't gone, it just no longer needs to be in your own code. If you're calling `QB.nui.*` from **within qblib itself** (another module in this same resource) rather than as a consumer, you still get the raw promise back and still need your own `Citizen.Await` — the auto-await above only kicks in for a genuine cross-resource caller (see `settleForExport` in `modules/nui/client.lua`), which is what every consumer resource always is.
