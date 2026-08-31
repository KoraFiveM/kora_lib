# Text UI module

A client-side, focus-free prompt overlay. Entries are handle-stacked: only the
newest live handle is rendered, and removing it restores the previous entry.
This lets independent resources show temporary prompts without overwriting or
prematurely hiding one another.

## `QB.textui.show(text, opts?) -> id`

Adds an entry and returns its integer handle. Options:

- `key`: short control text such as `E` or `F6`.
- `icon`: a supported Lucide icon name such as `Car` or `Key`.
- `position`: `left-center`, `right-center` (default), `top-center`, or
  `bottom-center`.

## `QB.textui.update(id, text, opts?) -> boolean`

Replaces a live entry without changing its stack position. Updating a hidden
entry takes effect if it later becomes visible. Returns `false` for an expired
handle.

## `QB.textui.hide(id) -> boolean`

Removes one entry. If it was visible, the previous live entry is rendered.

## `QB.textui.isOpen(id?) -> boolean`

With an ID, reports whether that handle is live. With no ID, reports whether
the stack contains any entries.

## `QB.textui.isVisible(id) -> boolean`

Reports whether an entry is currently the newest live handle being rendered.

Every handle is owned by the invoking resource and removed automatically when
that resource stops. The browser component is pointer-transparent and the Lua
module never requests NUI focus.

```lua
local prompt = QB.textui.show('Open the vehicle', {
    key = 'E',
    icon = 'Car',
    position = 'right-center',
})

QB.textui.update(prompt, 'Enter the vehicle', { key = 'E', icon = 'Key' })
QB.textui.hide(prompt)
```
