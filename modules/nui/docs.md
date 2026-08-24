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
Opens a radial menu, always centred on screen. It uses the same recursive item tree and result shape as `openMenu`, so a caller can reuse its item-building logic. It manages NUI focus for its entire lifetime.

#### Parameters
- `items: table[]` — same `MenuItem` shape as `openMenu`, including `submenu = { title?, items }`.
- `opts?: table` — optional geometry: `radius?: positive number` (defaults to the NUI's safe radial size).

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

## Legacy compat: `qb-menu` / `qb-input` / `qb-radialmenu`

`qb-menu`, `qb-input` and `qb-radialmenu` are being deprecated in favour of `QB.nui.openMenu`/`openContextMenu`/`openRadialMenu`/`openInputDialog` above. Until every consumer has migrated, `compat/client/qb-menu.lua`, `compat/client/qb-input.lua` and `compat/client/qb-radialmenu.lua` translate the real, public APIs of those standalone resources onto the same `QB.nui.*` calls, and register themselves under the `qb-menu`/`qb-input`/`qb-radialmenu` export identities (`provide 'qb-menu'` / `provide 'qb-input'` / `provide 'qb-radialmenu'` in `fxmanifest.lua`, plus the `__cfx_export_` hijack every compat file in this codebase uses — see `qbtarget/client/compat/ox-target.lua` for the canonical version of the same trick). A script written against `exports['qb-menu']:openMenu(...)`, `exports['qb-input']:ShowInput(...)` or `exports['qb-radialmenu']:AddOption(...)` keeps working unmodified with qb-menu/qb-input/qb-radialmenu never actually installed.

### `exports['qb-menu']:openMenu(menu)`
Translates each `menu` entry onto one `QB.nui.openMenu` item and, on selection, fires the item's legacy `params.event` the same way real qb-menu does.

| qb-menu field | Mapped to | Notes |
|---|---|---|
| `header` | `label` | |
| `txt` | `description` | |
| `disabled` / `isMenuHeader` | `disabled` | Real qb-menu's `isMenuHeader` rows are unselectable section labels; the new menu has no dedicated header row type, so this is the closest equivalent. |
| `icon` | `image` / `icon` | Item artwork URLs and known shared-item images render directly; qblib-native icon names retain their curated lucide rendering. |
| *(none)* | `id` | Real qb-menu items have no stable id; the 1-based position in the array is used. |
| `params.event` / `params.isServer` / `params.args` | — | Fired via `TriggerEvent`/`TriggerServerEvent` on selection, exactly as real qb-menu's own `selectMenuItem` NUI callback does. |

`openMenu(menu, sort, skipFirst)` also honours hidden rows and upstream sorting. `action`, command, QB-command and function-action rows follow qb-menu dispatch precedence, and `showHeader`/`playerfocus`/`qb-menu:client:menuClosed` are supplied alongside the two original exports.

`exports['qb-menu']:closeMenu()` and the `qb-menu:client:openMenu`/`qb-menu:client:closeMenu` net events are also registered. `closeMenu` dismisses the active list menu through its normal cancellation response, which also releases focus and settles the awaiting request.

### `exports['qb-input']:ShowInput(data)`
Translates `data.inputs[]` onto `QB.nui.openInputDialog` fields and blocks the calling coroutine until the player answers, returning either a `{ [name]: value }` table (submit) or `false` (cancel) — exactly real qb-input's own return shape, never a promise.

| qb-input `inputs[]` field | Mapped to | Notes |
|---|---|---|
| `name` | `id` | Kept identical so the legacy `result[name]` lookup needs zero reshaping. |
| `text` | `label` | Falls back to `name` if absent. |
| `isRequired` | `required` | |
| `default` / `checked` | `default` | `checked` (some forks' checkbox convention) wins over `default` when both are set. |
| `min` / `max` | `min` / `max` | `number`, `slider` only. |
| `type = "text" \| "password" \| "textarea"` | same | |
| `type = "number"` | `number` | |
| `type = "checkbox"` | `checkbox` | |
| `type = "radio" \| "select"` | `select` | No dedicated radio-group widget exists on the new dialog — `radio` collapses onto `select`, the closest equivalent (single value from a fixed list). |
| `type = "slider"` | `range` | Newer qb-input forks only; `step` passes through. |
| `options[].value` / `.text`/`.label` | `options[].value` / `.label` | Both stringified — the new `select` field is string-keyed throughout. |
| `icon` | *(dropped)* | Same reasoning as qb-menu's `icon` above — no equivalent field exists at all on `InputField`. One warning per resource run. |
| any other `type` | `text` | One warning per unrecognized type name per resource run, naming the type, rather than silently misrendering it. |

### `exports['qb-radialmenu']:AddOption(option, shouldClose)` / `RemoveOption(id)`

**Biggest caveat of the three compat shims**: real qb-radialmenu is a **global, persistent** menu — other resources register/unregister options into one shared wheel over time via `AddOption`/`RemoveOption`, and the player opens it whenever they like via a fixed keybind. `QB.nui.openRadialMenu` is a **one-shot, per-call** menu — build an items list, await one result. There is no QB.nui primitive for "a menu that's already open, built from whatever's currently registered", so `compat/client/qb-radialmenu.lua` keeps its own in-memory registry of currently-registered options and only calls `QB.nui.openRadialMenu` when its own keybind (`qblib_radialmenu_open`, default `F2` — a guess, see the file's header comment; always rebindable from FiveM's own Settings > Key Bindings) fires, translating the registry into an items list at that moment. This means:
- There is no script-triggered "open now" call — matching real qb-radialmenu's own keybind-driven UX, but unlike every other `QB.nui.open*` wrapper, which is always caller-initiated.
- `option.shouldClose == false` is approximated by immediately re-issuing a fresh `QB.nui.openRadialMenu` request after dispatch, rather than a truly persistent NUI state staying open across the selection.

| qb-radialmenu `option` field | Mapped to | Notes |
|---|---|---|
| `id` | `id` | Kept if supplied; auto-generated (`radial_<n>`) and returned from `AddOption` otherwise, same as most real forks. |
| `title` / `label` | `label` | `title` wins if both are set. |
| `top` | *(ordering)* | `top` options are moved to the front of the translated items list, stable within each group — the closest flat-list equivalent of "pin near the top of the wheel"; there's no ring-position concept to replicate against QB.nui's own radial layout. |
| `icon` | *(dropped)* | Same reasoning as qb-menu/qb-input's `icon` above — Font Awesome vs. lucide vocabularies don't overlap. One warning per resource run. |
| `iconAnimation` | *(dropped)* | Purely decorative on top of the already-dropped icon; no equivalent field exists at all, and it doesn't get its own warning on top of the icon one. |
| `type` (`"client"` / `"server"`) + `event` | — | Fired via `TriggerEvent`/`TriggerServerEvent(event)` on selection when `onSelect` isn't set — `type == "server"` triggers server-side, anything else client-side, mirroring qb-menu's `params.isServer`. |
| `onSelect` (function) | — | Called directly (`pcall`-wrapped) instead of firing `event`, when present. |
| `shouldClose` (field, or `AddOption`'s 2nd positional arg) | — | The field wins when both are set. Defaults to `true`. `false` triggers the reopen-after-select approximation described above. |

`exports['qb-radialmenu']:RemoveOption(id)` and the `qb-radialmenu:client:AddOption`/`qb-radialmenu:client:RemoveOption` net events are also registered, mirroring `AddOption`/`RemoveOption` 1:1.

## Notes
- `QB.nui.request` tags every call with a `requestId` **and a random per-request token** and resolves it through one shared response callback (`qblib:nui:response`) rather than registering a new callback per call — see `modules/nui/AGENTS.md` for why the token exists and why one shared callback is used.
- A request that never gets a response (NUI never loaded, player alt-F4'd, etc.) times out after `timeout` instead of hanging forever — you get `nil` back rather than a hang.
- `openMenu`/`openContextMenu`/`openRadialMenu`/`openInputDialog` are thin wrappers over `QB.nui.request` — they don't unwrap the result any further than the NUI's own raw response, so check for `.cancelled` before reading `.selectedId`/`.path`/`.values`, and for `nil` before that (timeout/error).
- These functions still run inside a coroutine and `Citizen.Await` a real promise internally — that part isn't gone, it just no longer needs to be in your own code. If you're calling `QB.nui.*` from **within qblib itself** (another module in this same resource) rather than as a consumer, you still get the raw promise back and still need your own `Citizen.Await` — the auto-await above only kicks in for a genuine cross-resource caller (see `settleForExport` in `modules/nui/client.lua`), which is what every consumer resource always is.
