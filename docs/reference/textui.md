---
title: "Text UI module"
sidebar_position: 18
---

# Text UI module

A client-side, focus-free prompt overlay. Entries are handle-stacked: only the
newest live handle is rendered, and removing it restores the previous entry.
This lets independent resources show temporary prompts without overwriting or
prematurely hiding one another.

## `Kora.textui.show(text, opts?) -> id`

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

## `Kora.textui.update(id, text, opts?) -> boolean`

Replaces a live entry without changing its stack position. Updating a hidden
entry takes effect if it later becomes visible. Returns `false` for an expired
handle or one owned by another resource.

## `Kora.textui.hide(id) -> boolean`

Removes one entry owned by the calling resource. If it was visible, the
previous live entry is rendered; another resource's handle returns `false`.

## `Kora.textui.isOpen(id?) -> boolean`

With an ID, reports whether that handle is live. With no ID, reports whether
the stack contains any entries.

## `Kora.textui.isVisible(id) -> boolean`

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
