# NUI module

## Overview
The NUI module is the bridge between Lua and the React app in `web/`. Every other module that needs to show something in the browser (a menu, an input dialog) or reach a browser-only capability (the clipboard) goes through `QB.nui.*` rather than calling `SendNUIMessage`/`RegisterNUICallback` directly.

Per the root [docs](../../AGENTS.md), the NUI is **headless**: it renders nothing and holds no focus until a message from Lua tells it to, and gives focus back up the moment that interaction ends.

## UI branding configuration

Set the shared colours in `qbtheme/config.lua`. qblib imports qbtheme's browser
loader and bridge, while the permanent `QB.theme` functions forward to qbtheme
for older Lua consumers. See [modules/theme/docs.md](../theme/docs.md).

## API

### `QB.nui.send(action, data)`
Sends `{ action, data }` to the NUI. Fire-and-forget — use `QB.nui.request` when you need a response back.

### `QB.nui.setFocus(mouse, keyboard)`
Sets NUI focus directly.

#### Parameters
- `mouse: boolean`
- `keyboard: boolean`

### `QB.nui.withFocus(mouse, keyboard, fn)`
Sets focus, runs `fn`, and always clears focus afterward — including when `fn` raises an error or the calling resource stops (the error is re-raised once cleanup runs). Prefer this over `setFocus` whenever the interaction is scoped to one call. Note the built-in `openMenu`/`openContextMenu`/`openInputDialog` wrappers below already manage focus themselves — `withFocus` is for custom interactive requests of your own.

#### Example
```lua
local result = QB.nui.withFocus(true, true, function()
    return QB.nui.request("myCustomDialog", { foo = "bar" })
end)
```

### `QB.nui.registerCallback(name, handler)`
Registers an NUI callback. `handler(data)` returns a plain value (or nil); the raw `RegisterNUICallback` `(data, cb)` plumbing is handled for you, including catching and logging errors so a broken handler can't leave the NUI's fetch hanging.

### `QB.nui.request(action, data, timeout)`
Sends `action` to the NUI and returns its response, once available. Requests are owned by the calling resource: stopping that resource rejects its outstanding requests, removes only its focus leases, and dismisses the matching browser surfaces without posting stale responses.

`QB.nui.requestAsync`, `QB.nui.cancelRequest`, and `QB.nui.updateRequest` are lower-level composition
primitives used by qblib's compatibility modules. They retain a tokenized
request handle so an API such as ox_lib's programmatic dialog close can both
update or dismiss the browser surface while retaining one promise and focus
lease. Gameplay
resources should continue to use `request` and the `open*` helpers.

`QB.nui.acquireFocus` / `QB.nui.releaseFocus` are the matching owner-tracked focus
lease primitives for compatibility APIs whose focus lifetime spans several
calls. They are internal building blocks; normal callers should prefer
`withFocus` or an `open*` helper.

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

### `QB.nui.openAlert(opts)`
Opens a confirmation or acknowledgement dialog. It manages mouse and keyboard focus for its lifetime.

#### Parameters
- `opts: table`
  - `message: string` — required dialog copy.
  - `title?: string`
  - `image?: string` — trusted artwork URL, including `nui://` paths. Artwork is contained in a fixed-height frame and hidden if it cannot load.
  - `confirmLabel?: string`, `cancelLabel?: string`
  - `cancellable?: boolean` — defaults to `true`; when `false`, hides Cancel and prevents Escape/backdrop dismissal.
  - `showCancel?: boolean`, `showClose?: boolean` — independently control the
    two optional dismissal controls while leaving Escape behavior unchanged.
  - `dismissOnBackdrop?: boolean` — defaults to `true`.
  - `centered?: boolean`, `size?: "xs" | "sm" | "md" | "lg" | "xl"`,
    `overflow?: boolean` — responsive placement, width, and long-copy scrolling.
  - `destructive?: boolean` — styles the confirm button as destructive.

The title and message support safe GitHub-flavoured Markdown. Raw HTML is
ignored and alert Markdown images are constrained to the dialog.

#### Returns
- `{ confirmed: boolean }`; `nil` on timeout/error.

#### Example
```lua
local result = QB.nui.openAlert({
    title = "Replace artwork?",
    message = "This change cannot be undone.",
    image = "nui://my-resource/web/images/preview.png",
    confirmLabel = "Replace",
})

if result and result.confirmed then
    -- continue
end
```

### `QB.nui.openMenu(items, title, opts)`
Opens a searchable list menu. Grants mouse+keyboard NUI focus while open and releases it as soon as the menu closes (selection, cancel, or timeout) — no `withFocus` wrap needed.

#### Parameters
- `items: table[]` — `{ id, label, description?, icon?, disabled?, readOnly?,
  progress?, colorScheme?, metadata?, arrow?, iconColor?, iconAnimation?,
  iconWidth?, iconHeight?, values?, checked?, close?, submenu? }[]`. Labels and
  descriptions support safe Markdown; metadata may carry labeled values and
  per-value progress.
- `title?: string`
- `opts?: table` — optional geometry. `position.horizontal` is `left`, `center`, or `right`; `position.vertical` is `top`, `center`, or `bottom`. `offsetX`/`offsetY`, `maxWidth`, and `maxHeight` are positive pixel values. `presentation = "panel"` uses a compact non-modal, non-searchable surface while retaining keyboard navigation; the default is the existing searchable dialog.

#### Returns
- `{ selectedId: string }` or `{ cancelled: true }`; `nil` on timeout/error.

`icon` resolves qblib's curated Lucide names immediately, ox-compatible Font
Awesome names through lazy prefix chunks, and safe HTTP/NUI image URLs.

```lua
-- A compact menu, vertically centred on the right with a comfortable inset.
QB.nui.openMenu(items, "Admin Menu", {
    position = { horizontal = "right", vertical = "center", offsetX = 48 },
    maxWidth = 400,
    maxHeight = 680,
})
```

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
  - `type: "text" | "password" | "textarea" | "number" | "checkbox" | "select" | "multiselect" | "range" | "combobox" | "date" | "date-range" | "time" | "color"`
  - `description?: string` — help text shared by standalone dialogs and AppShell forms.
  - `options?: { value, label, disabled? }[]` — `select`, `multiselect`, and `combobox`. Numeric values are accepted for Lua compatibility and normalized to strings in browser results. `select` restricts the result to one option; `multiselect` returns a string array; `combobox` is free text with filtered suggestions (matched against label and value, capped at 8).
  - `rows?: integer` — `textarea` only (default 3).
  - `default?`, `placeholder?` — a `number` without a default starts blank. A required blank blocks submission; an optional blank is omitted from the returned `values` table rather than being coerced to zero.
  - `required?: boolean`, `min?: number`, `max?: number` (`number`/`range`), `minLength?: integer`, `maxLength?: integer`, `pattern?: string` (text-like types) — optional client-side validation that gates submission. This is convenience only; validate authoritative values again in Lua/server code.
  - `dependsOn?: string`, `optionsByValue?: table<string, option[]>` — select an option set using another field's current value. Invalid dependent selections reset atomically to the first available option.
  - `visibleWhen?: { fieldId, equals }` — render and validate the field only when another field equals the given scalar value.
  - `numericOnly?: boolean`, `keypad?: boolean` — restrict textual entry to digits and optionally render the compact keypad.
  - `presets?: { value: number, label?: string }[]` — quick choices below a number field.
  - `step?: number` — increment for number and range controls.
  - `searchable?: boolean` — adds a fixed-choice filter to select/multiselect;
    unlike `combobox`, typed search text can never become the submitted value.
  - `dateMin?`, `dateMax?` — ISO strings or numeric timestamps, normalized in
    the browser's local timezone. Numeric date/time defaults are normalized the
    same way. `dateFormat` supports common Day.js tokens including month/day
    names, ordinals, quarters, and escaped `[text]`.
- `title?: string`, `description?: string`

#### Returns
- `{ values: table<string, any> }` or `{ cancelled: true }`; `nil` on an NUI/export error. Optional blank number fields have no key in `values`.

#### Example
```lua
local result = QB.nui.openInputDialog({
    { id = "amount", label = "Amount", type = "number", default = 1, min = 1 },
}, "Withdraw")

if result and not result.cancelled then
    print("amount:", result.values.amount)
end
```

### Registered applications (`AppShell`)

`registerApp` defines a full application once; `openApp` opens it later by id,
with the same automatic focus and dismissal lifecycle as menus and inputs.
qblib renders the shared application frame, navigation, tables, lists, forms,
records, timelines, maps, summary cards, empty states, and buttons. The
registering resource remains the owner of its data, permissions, validation,
and every action handler in Lua.

```lua
QB.nui.registerApp({
    id = 'qbmdt:police',
    title = 'Mobile Data Terminal',
    description = 'Los Santos Police Department',
    icon = 'Shield',
    layout = 'standard',
    defaultView = 'dashboard',
    footer = 'LSPD secure network',
    navigation = {
        {
            id = 'dashboard',
            label = 'Dashboard',
            icon = 'Home',
            content = {
                title = 'Shift overview',
                description = 'Current operational picture.',
                actions = {
                    { id = 'new-report', label = 'New report', icon = 'Plus', variant = 'primary' },
                },
                blocks = {
                    {
                        type = 'stats',
                        items = {
                            { label = 'Active units', value = 12, icon = 'Users', tone = 'success' },
                            { label = 'Open reports', value = 4, icon = 'FileText', tone = 'warning' },
                        },
                    },
                },
            },
        },
        {
            id = 'records',
            label = 'Records',
            icon = 'Database',
            tabs = {
                { id = 'people', label = 'People', content = { blocks = { { type = 'empty', title = 'Search people' } } } },
                { id = 'vehicles', label = 'Vehicles', content = { blocks = { { type = 'empty', title = 'Search vehicles' } } } },
            },
        },
    },
    onAction = function(actionId, context)
        if actionId == 'new-report' then
            TriggerEvent('qbmdt:client:newReport', context)
        end
    end,
})

local result = QB.nui.openApp('qbmdt:police', {
    viewId = 'dashboard',
    data = { characterId = citizenid }, -- private; returned only to onAction
})
```

#### Lifecycle API

- `QB.nui.registerApp(definition)` registers or replaces an owner-tracked app.
  The id should be namespaced (`resource:app`). A registration is removed
  automatically if its resource stops. An optional `accent = '#RRGGBB'`
  applies that primary colour only for the app's open lifetime; closing or
  superseding the app restores the player's `/theme` colour (or qbtheme's
  configured palette when the player has not selected one). Apps without an
  `accent` use that effective player/server theme throughout.
- `layout = 'standard'` (the default) uses the sidebar at normal resolutions
  and switches to horizontal navigation on smaller viewports. `layout =
  'compact'` always uses horizontal navigation, permits a 420px minimum width,
  and is intended for ATMs and focused single-workspace tools.
- `QB.nui.openApp(id, opts?)` opens it and returns after X/Escape, an action
  requests closure, the owner calls `closeApp`, the app is superseded, or its
  resource stops. The result is
  `{ closed = true, reason, viewId?, tabId? }`.
- `QB.nui.updateApp(id, update)` shallow-merges definition fields. Supplying
  `navigation` replaces the navigation tree as a whole. An open instance
  refreshes immediately and keeps its view/tab if they still exist.
- `QB.nui.closeApp(id?)` closes the matching app, or the currently open app
  when id is omitted. `QB.nui.isAppOpen(id?)` reports its state.
- `QB.nui.unregisterApp(id)` closes an open instance and removes its
  registration.

App actions can appear in `content.actions`, an `actions` or `form` block,
list/timeline items, table rows, and map markers. They all call
`onAction(actionId, context)`. `context` includes `viewId`, `tabId`, optional
`itemId`/`value`, and the private `opts.data` passed to `openApp`. Definitions
are validated recursively, and the browser cannot invoke an action id that is
not declared in the active definition. Still treat action values as client
input and validate them authoritatively in the owning resource/server.

An action may declare `fields`, using exactly the same renderer and validator
as `openInputDialog`. Header forms render once below the content header;
action-block and item forms render only under the block/item that launched
them. Drafts survive unrelated `updateApp` refreshes. The submitted
`{ [field.id] = value }` becomes `context.value`. Set `confirm = '…'` to add an
explicit acknowledgement, including for actions with no fields.

Set `closeBeforeAction = true` when the handler launches another focused UI or
world editor. qblib closes AppShell and releases its focus lease before calling
the owner handler; handler/result failures are reported as notifications
because the shell is no longer visible. Ordinary nested qblib dialogs instead
take their own focus lease, so closing the child restores the still-open app.

For dependent selects or multiselects, set `dependsOn` to the controlling field
id and provide `optionsByValue`, keyed by that field's values. Changing the
controller updates it and all dependent choices in one state transition.

```lua
{ id = 'warn', label = 'Warn player', fields = {
    { id = 'target', label = 'Player', type = 'select', options = players, required = true },
    { id = 'reason', label = 'Reason', type = 'textarea', required = true },
} }
```

An action handler may combine these result fields:

- `update = { ... }` — shallow definition patch. It is validated and applied
  before other result fields, so the same result may navigate to a newly added
  view or tab. For asynchronous pushes, call `updateApp` directly.
- `navigate = { viewId, tabId?, replace? }` — navigate without rebuilding the
  definition. Unless `replace` is true, AppShell exposes Back to return to the
  prior view/tab.
- `notice = { tone, message }` — persistent in-shell feedback. If the action
  also closes the shell, qblib routes the notice through notifications.
- `close = true` — close AppShell after the action.

Shell-owned copy (Cancel, Confirm, Working, paging, search/empty defaults, map
controls, and accessibility labels) comes from `qblib/locales/*.json` through
the normal locale fallback system. Consumer titles, action labels, field
labels, and content remain the consumer's responsibility.

#### Content blocks

- `text`: `title?`, `text`
- `stats`: `title?`, `items = { { label, value, description?, icon?, tone? } }`
- `progress`: `title?`, `items = { { label, value, max, description?, detail?, icon?, tone? } }`. Renders an accessible bounded-value graph; `value` must be between zero and `max`.
- `table`: `id?`, `title?`, `columns = { { key, label, align?, sortable? } }`,
  `rows`, `empty?`, row `action?` / `idKey?`, plus `searchable?`,
  `searchPlaceholder?`, and `pageSize?`. A cell may be a scalar or
  `{ value?, label?, description?, icon?, tone?, badge? }`.
- `list`: `id?`, `title?`, `layout = 'list'|'grid'|'cards'`, `searchable?`,
  `searchPlaceholder?`, `pageSize?`, `scrollable?`, and recursive items. Set
  content-level `scrollable = false` with a list-level `scrollable = true` when
  the surrounding header and blocks should remain fixed while only the list
  owns vertical overflow. Items support
  `description`, `image`, `icon`, `badge`, `tone`, `metadata`, `children`, a
  primary `action`, and multiple `actions`.
- `actions`: `title?`, `actions`
- `form`: `id`, `title?`, `description?`, `fields`, `action`, `submitLabel?` —
  an always-visible shared form.
- `details`: `id?`, `title?`, `columns?` (1-3), and labelled value items.
- `timeline`: `id?`, `title?`, timestamped items with metadata and actions.
- `map`: `id?`, `title?`, tile URL/projection definition, markers, selection,
  pan/zoom/follow/recentre settings, and optional expiry/fade metadata. Tile
  URLs use `{z}`, `{x}`, `{y}` placeholders and may point at another resource
  through `https://cfx-nui-<resource>/...`; that resource keeps and exposes its
  own tile assets. A marker's `fadeDuration` overrides the block default when
  different marker classes have different lifetimes.
- `empty`: `title`, `description?`, `icon?`

Tones are `neutral`, `primary`, `success`, `warning`, and `destructive`.
Button variants are `primary`, `secondary`, `outline`, `ghost`, and
`destructive`. Set an action's boolean `state` for a toggle: AppShell exposes
an accessible pressed state and an explicit `On` or `Off` indicator beside the
action label. Keep the label action-oriented (for example, `Turn Admin Duty
Off`) so both the present state and the result of clicking are clear. Icon
strings use the same curated Lucide resolver as menus.

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

`openMenu(menu, sort, skipFirst)` also honours hidden rows and upstream sorting. `action`, command, QB-command and function-action rows follow qb-menu dispatch precedence, and `showHeader`/`playerfocus`/`qb-menu:client:menuClosed` are supplied alongside the two original exports. `showHeader` remains a non-interactive prompt until the `playerfocus` key is pressed; that key replaces it with the normal interactive, focus-lease-managed menu and preserves the original row dispatch. A non-table (including `nil`) `menu` is a silent no-op, matching real qb-menu's own `if not data or not next(data) then return end` — a script that conditionally builds a menu and passes `nil` when there's nothing to show keeps working instead of erroring.

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
| `type = "checkbox"` (no `options`) | `checkbox` | Some simplified qb-input forks use a single scalar boolean this way — kept keyed by `name`, unchanged. |
| `type = "checkbox"` **with** `options[]` | **N `checkbox` fields, one per option** | Real qbcore-framework/qb-input's checkbox type is a **group**, not a single boolean — its `html/script.js` (`renderCheckboxInput`) submits `formInputs[option.value] = ...` for every option, never keyed by the input's own `name`. Each option expands into its own field keyed by `tostring(option.value)` (not the group's `name`), with the group's own `text` prefixed onto each option's label for context since the flat field list has no visual grouping. `result.values[option.value]` matches upstream's own result shape exactly. |
| `type = "radio" \| "select"` | `select` | No dedicated radio-group widget exists on the new dialog — `radio` collapses onto `select`, the closest equivalent (single value from a fixed list). |
| `type = "slider"` | `range` | Newer qb-input forks only; `step` passes through. |
| `type = "color"` | `text` | No equivalent widget exists on `InputField` at all (no color picker) — falls back to the generic unrecognized-type warning and a plain text field; a caller still gets back whatever hex string the player typed, just without a native color picker. |
| `options[].value` / `.text`/`.label` | `options[].value` / `.label` | Both stringified — the new `select` field is string-keyed throughout. |
| `icon` | *(dropped)* | Same reasoning as qb-menu's `icon` above — no equivalent field exists at all on `InputField`. One warning per resource run. |
| any other `type` | `text` | One warning per unrecognized type name per resource run, naming the type, rather than silently misrendering it. |

### `exports['qb-radialmenu']:AddOption(option, id_or_shouldClose)` / `RemoveOption(id)`

**Biggest caveat of the three compat shims**: real qb-radialmenu is a **global, persistent** menu — other resources register/unregister options into one shared wheel over time via `AddOption`/`RemoveOption`, and the player opens it whenever they like via a fixed keybind. `QB.nui.openRadialMenu` is a **one-shot, per-call** menu — build an items list, await one result. There is no QB.nui primitive for "a menu that's already open, built from whatever's currently registered", so `compat/client/qb-radialmenu.lua` keeps its own in-memory registry of currently-registered options and only calls `QB.nui.openRadialMenu` when its own keybind (`qblib_radialmenu_open`, default `F1`, matching qbcore-framework/qb-radialmenu's own `config.lua` default; always rebindable from FiveM's own Settings > Key Bindings) fires, translating the registry into an items list at that moment. This means:
- There is no script-triggered "open now" call — matching real qb-radialmenu's own keybind-driven UX, but unlike every other `QB.nui.open*` wrapper, which is always caller-initiated.
- `option.shouldClose == false` is approximated by immediately re-issuing a fresh `QB.nui.openRadialMenu` request after dispatch, rather than a truly persistent NUI state staying open across the selection.
- **Built-in default content is reproduced**, the same way real qb-radialmenu's own `main.lua` injects it fresh every time the wheel opens: a **Vehicle** submenu (doors, extras, a flip option once the vehicle is off its wheels, and a seats submenu while occupying it — built from live vehicle-native state, ported from upstream's `SetupVehicleMenu`) and a per-job **Work** submenu (`Config.radialmenuCompat.jobInteractions`, ported from upstream's `SetupJobMenu` and `Config.JobInteractions`), both registered through this file's own `AddOption` at a stable slot so repeated opens update the entry instead of duplicating it. A **downed police/EMS player** sees the wheel wholesale replaced with a single emergency-button option, matching upstream's own downed override, and the wheel is blocked outright (matching upstream) for anyone else while downed, or for anyone while handcuffed. `PlayerData`/job-registry lookups go through `exports.qbcore:getPlayerData`/`getShared`, pcall-guarded the same way qb-menu compat's `imageFor` reads item images — without qbcore running, this content simply doesn't appear rather than erroring.
  - **Not reproduced**: most of real qb-radialmenu's *default* `Config.JobInteractions` content (tow/taxi/mechanic/hotdog jobs, and most of the police entries — search/escort/jail/seize-license/the objects submenu) fires events owned by companion job resources this environment doesn't run, or needs an aimed-at/nearby **target** player the wheel's own event payload never carries; only entries with a real, self-contained, verified-working handler in this server's own resources are wired up (see `config.lua`'s `Config.radialmenuCompat` comment for the exact list and reasoning). `stretcher.lua`/`trunk.lua`/`clothing.lua` — features bundled into the real resource, not part of the generic `AddOption`/`RemoveOption` API surface — aren't ported either; this server's `qbambulance`/`qbclothing` already own equivalent functionality through their own mechanisms.

| qb-radialmenu `option` field | Mapped to | Notes |
|---|---|---|
| `id` | `id` | Kept if supplied; auto-generated (`radial_<n>`) and returned from `AddOption` otherwise, same as most real forks. Also assigned recursively to nested `items[]` entries that don't already have one — see `items` below. |
| `title` / `label` | `label` | `title` wins if both are set. |
| `items` (nested array of the same option shape) | `submenu = { title, items }` | Real qb-radialmenu options can carry their own nested `items[]` to form a submenu (upstream's own "Work"/"Vehicle" branches, above). `QB.nui.openRadialMenu` natively supports arbitrary submenu depth via `item.submenu` (`web/src/components/menu/RadialMenu.tsx`), so this translates directly and recursively — a registered option's nested leaves dispatch correctly via their own id regardless of depth, using the NUI result's `selectedId` (its `path` isn't needed since ids are unique across the whole registry). |
| `top` | *(ordering)* | `top` options are moved to the front of the translated items list, stable within each group — the closest flat-list equivalent of "pin near the top of the wheel". **Not a real qb-radialmenu field at all** — upstream has no such concept and would simply ignore it; this is an additive convenience only. |
| `icon` | *(dropped)* | Same reasoning as qb-menu/qb-input's `icon` above — Font Awesome vs. lucide vocabularies don't overlap. One warning per resource run. |
| `iconAnimation` | *(dropped)* | Purely decorative on top of the already-dropped icon; no equivalent field exists at all, and it doesn't get its own warning on top of the icon one. |
| `type` (`"client"` / `"server"` / `"command"` / `"qbcommand"`) + `event` | — | On selection, when `onSelect` isn't set: `"server"` → `TriggerServerEvent(event, option)`; `"command"` → `ExecuteCommand(event)`; `"qbcommand"` → `TriggerServerEvent('QBCore:CallCommand', event, option)`; anything else (including no `type` at all) → `TriggerEvent(event, option)`. The selected option's own table is always passed back as the event's argument, matching real qb-radialmenu's own `TriggerEvent(data.event, data)` / `TriggerServerEvent(data.event, data)` — its own handlers (e.g. the built-in door/extra/seat ones above) depend on reading fields back off that table. |
| `onSelect` (function) | — | Called directly (`pcall`-wrapped) instead of firing `event`, when present. |
| `shouldClose` (field, or `AddOption`'s 2nd positional arg **when it's a boolean**) | — | The field wins when both are set. Defaults to `true`. `false` triggers the reopen-after-select approximation described above. |

`AddOption`'s second positional argument is interpreted two ways depending on its type, since different parts of the ecosystem use it differently: a **boolean** is `shouldClose` (some forks' convention); anything else non-nil (a number or string) is an **explicit id to register/update at**, matching qbcore-framework/qb-radialmenu's own real signature (`AddOption(data, id)`) — used internally by its `SetupJobMenu`/`SetupVehicleMenu` to update an existing wheel entry in place every time the wheel opens, rather than appending a duplicate one. Re-registering at the same explicit id replaces that entry rather than growing the registry.

`exports['qb-radialmenu']:RemoveOption(id)` and the `qb-radialmenu:client:AddOption`/`qb-radialmenu:client:RemoveOption` net events are also registered, mirroring `AddOption`/`RemoveOption` 1:1.

## Notes
- `QB.nui.request` tags every call with a `requestId` **and a random per-request token** and resolves it through one shared response callback (`qblib:nui:response`) rather than registering a new callback per call — see `modules/nui/AGENTS.md` for why the token exists and why one shared callback is used.
- The invoking resource owns its pending requests and focus leases. If it stops, qblib rejects those requests, tells the browser to dismiss the exact tokenized surfaces, and preserves focus held by unrelated resources.
- Releasing the final focus lease restores the keep-input state that existed before qblib acquired focus, so compatibility surfaces do not interfere with another overlay's input policy.
- A request that never gets a response (NUI never loaded, player alt-F4'd, etc.) times out after `timeout` instead of hanging forever — you get `nil` back rather than a hang.
- `openMenu`/`openContextMenu`/`openRadialMenu`/`openInputDialog` are thin wrappers over `QB.nui.request` — they don't unwrap the result any further than the NUI's own raw response, so check for `.cancelled` before reading `.selectedId`/`.path`/`.values`, and for `nil` before that (timeout/error).
- These functions still run inside a coroutine and `Citizen.Await` a real promise internally — that part isn't gone, it just no longer needs to be in your own code. If you're calling `QB.nui.*` from **within qblib itself** (another module in this same resource) rather than as a consumer, you still get the raw promise back and still need your own `Citizen.Await` — the auto-await above only kicks in for a genuine cross-resource caller (see `settleForExport` in `modules/nui/client.lua`), which is what every consumer resource always is.
