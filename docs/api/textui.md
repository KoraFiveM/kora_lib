---
title: "Text UI"
sidebar_position: 18
---


# Text UI

Shows a focus-free prompt overlay, such as “E — Open vehicle”. Entries are stacked by handle: the newest live entry is shown, and hiding it restores the previous prompt. This lets separate resources display prompts without hiding each other’s state.

Namespace: `Kora.textui` · Source: `modules/textui/client.lua`

## show/update options

Omitted fields use their defaults. Text is rendered as safe Markdown, not raw HTML. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `key?` | string | Short control label such as E or F6. |
| `icon?` | string | Supported Lucide icon name, such as Car or Key. |
| `iconColor?` | string | CSS color for the icon. |
| `iconAnimation?` | string | spin, spinPulse, spinReverse, pulse, beat, fade, beatFade, bounce, or shake. |
| `alignIcon?` | 'top' \| 'center' | Vertical alignment for the icon. |
| `position?` | string | left-center, right-center (default), top-center, or bottom-center. |
| `style?` | table \| string | Inline CSS declarations or scalar CSS properties. Selectors cannot escape into the page; pointer-events settings are ignored. |

## Prompt stacking

Only the newest live handle is visible. A hidden handle can still be updated; it becomes visible if newer prompts are removed. Each handle belongs to its creator and is automatically removed when that resource stops.

## No focus or interaction

The browser surface is pointer-transparent and the module never requests NUI focus. Text UI is display-only; use an interaction selector when the player needs to choose an option.

## Functions

Show a prompt and retain its ID to update, inspect, or hide it later.

### `Kora.textui.show(text, opts?)`

Adds a prompt to the stack and returns a handle owned by the calling resource.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `text` | string | Prompt text. Newlines are supported for a compact read-only status view. |
| `opts?` | table | Optional key label, icon, style, and placement listed above. |

**Returns**

- **id** — integer handle for update, hide, and visibility checks.

**Example**

```lua
local prompt = Kora.textui.show('Open the vehicle', { key = 'E', icon = 'Car', position = 'right-center' })
```

**Representative console output**

```text
The prompt appears and its ID is saved for later cleanup.
```

### `Kora.textui.update(id, text, opts?)`

Replaces the text and/or options for a live prompt without changing its place in the stack.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | integer | Handle returned by show. |
| `text` | string | New prompt text. |
| `opts?` | table | Optional replacement settings. |

**Returns**

- **updated** — true if the handle is live and owned by the caller; otherwise false.

**Example**

```lua
Kora.textui.update(prompt, 'Enter the vehicle', { key = 'E', icon = 'Key' })
```

**Representative console output**

```text
The prompt text and icon change while retaining its original stack position.
```

### `Kora.textui.hide(id)`

Removes one prompt owned by the calling resource. If it was visible, the previous live prompt is shown.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | integer | Prompt handle from show. |

**Returns**

- **hidden** — true when removed; false if expired or owned by another resource.

**Example**

```lua
Kora.textui.hide(prompt)
```

**Representative console output**

```text
The prompt is removed and any prior prompt becomes visible.
```

### `Kora.textui.isOpen(id?)`

Checks whether a specific handle is still live, or whether any prompt exists when no ID is supplied.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id?` | integer | Optional prompt handle. |

**Returns**

- **open** — boolean.

**Example**

```lua
if Kora.textui.isOpen(prompt) then print('Prompt is still registered') end
```

**Representative console output**

```text
Prints while that prompt handle remains in the stack.
```

### `Kora.textui.isVisible(id)`

Checks whether the handle is the newest live prompt currently rendered.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | integer | Prompt handle from show. |

**Returns**

- **visible** — boolean.

**Example**

```lua
if Kora.textui.isVisible(prompt) then print('This prompt is on screen') end
```

**Representative console output**

```text
Prints only if no newer prompt is covering it.
```

## Limits and related APIs

Explicit invalid option values are rejected instead of silently replaced. Unsafe HTML and URL protocols are not rendered.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/textui/docs.md` or `local/textui/docs.md`) that the reference above does not state.

A client-side, focus-free prompt overlay. Entries are handle-stacked: only the
newest live handle is rendered, and removing it restores the previous entry.
This lets independent resources show temporary prompts without overwriting or
prematurely hiding one another.

### `Kora.textui.show(text, opts?) -> id`

Adds an entry and returns its integer handle. `text` may include newlines for
a compact read-only status view. Options:

- `key`: short control text such as `E` or `F6`.
- `icon`: a supported Lucide icon name such as `Car` or `Key`.
- `iconColor`: CSS colour applied to the icon.
- `iconAnimation`: `spin`, `spinPulse`, `spinReverse`, `pulse`, `beat`, `fade`,
  `beatFade`, `bounce`, or `shake`.
- `alignIcon`: `top` or `center` (default).
- `style`: either flat CSS property values or a CSS declaration string such as
  `"background-color: #111; color: white"`, applied only to the prompt's inline
  style. Selectors and stylesheet rules cannot escape onto the page. The
  browser deliberately ignores `pointerEvents`/`pointer-events` so Text UI
  remains display-only.
- `position`: `left-center`, `right-center` (default), `top-center`, or
  `bottom-center`.

Options default only when omitted; an explicit invalid value (including
`position = false`) is rejected instead of being silently replaced.

Text is rendered as safe GitHub-flavoured Markdown. Raw HTML is ignored and
unsafe link protocols are rejected by the renderer.

### `Kora.textui.update(id, text, opts?) -> boolean`

Replaces a live entry without changing its stack position. Updating a hidden
entry takes effect if it later becomes visible. Returns `false` for an expired
handle or one owned by another resource.

### `Kora.textui.hide(id) -> boolean`

Removes one entry owned by the calling resource. If it was visible, the
previous live entry is rendered; another resource's handle returns `false`.

### `Kora.textui.isOpen(id?) -> boolean`

With an ID, reports whether that handle is live. With no ID, reports whether
the stack contains any entries.

### `Kora.textui.isVisible(id) -> boolean`

Reports whether an entry is currently the newest live handle being rendered.

Every handle is owned by the invoking resource and removed automatically when
that resource stops. The browser component is pointer-transparent and the Lua
module never requests NUI focus.

```lua
local prompt = Kora.textui.show('Open the vehicle', {
    key = 'E',
    icon = 'Car',
    position = 'right-center',
})

Kora.textui.update(prompt, 'Enter the vehicle', { key = 'E', icon = 'Key' })
Kora.textui.hide(prompt)
```
