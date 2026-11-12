---
title: "Theme"
sidebar_position: 19
---


# Theme

## Shared

Provides a compatibility path to the shared kora_theme palette, design tokens, and font settings. New UI resources should depend on kora_theme directly; Kora.theme remains useful to older resources already using the Kora Lib namespace.

Namespace: `Kora.theme` · Source: `modules/theme/shared.lua`

### Prefer the shared theme package for new UIs

A new UI resource should depend directly on kora_theme, import @kora_theme/client/bridge.lua, and load its theme.css and theme.js files. Use the published CSS variables such as --font-sans, --font-heading, and --font-mono so administrator changes apply without duplicating palette data.

### Functions

Read the active accent color, complete token map, or configured font catalog.

#### `Kora.theme.accentColor()`

Returns the currently configured primary accent color from kora_theme.

**Parameters**



**Returns**

- **color** — six-digit hex color string.

**Example**

```lua
local accent = Kora.theme.accentColor()
print('Primary accent:', accent)
```

**Representative console output**

```text
Prints the configured accent color, for example #8CC63E.
```

#### `Kora.theme.tokens(overrides?)`

Returns the complete semantic token map used by kora_theme. An optional hex color or approved role table can customize the result for this call.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `overrides?` | string \| table | Optional six-digit hex primary color, or a table overriding approved semantic color roles. |

**Returns**

- **tokens** — table of resolved CSS-ready semantic colors and font variables.

**Example**

```lua
local tokens = Kora.theme.tokens()
print(tokens['surface'], tokens['text-primary'])
```

**Representative console output**

```text
Prints the resolved surface and primary text tokens.
```

#### `Kora.theme.getFonts()`

Returns the configured body, heading, and monospace font definitions. Each entry includes its catalog id, display label, CSS font stack, and source.

**Parameters**



**Returns**

- **fonts** — table with body, heading, and mono entries. Each entry has id, label, stack, and source.

**Example**

```lua
local fonts = Kora.theme.getFonts()
print(fonts.body.stack)
```

**Representative console output**

```text
Prints the CSS font stack selected for body text.
```

## Client

Provides client-side hooks for kora_theme updates and for refreshing kora_lib’s own NUI frame. The font-change subscription is for Lua-side consumers that need to react to an administrator changing the configured fonts.

Namespace: `Kora.theme` · Source: `modules/theme/client.lua`

### Font updates in Lua and browser pages

Browser pages loading the kora_theme stylesheet and bridge receive CSS variable updates automatically. Use onFontsChanged only for Lua-side work, such as text drawn by game natives or a custom NUI message that carries a font choice.

### Functions

Subscribe to configured font updates or reapply the theme to kora_lib’s own browser frame.

#### `Kora.theme.onFontsChanged(handler)`

Registers a callback that receives the latest font catalog whenever an administrator changes the server fonts in /config → kora_theme → fonts.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `handler` | function | Function called with the updated fonts table (same shape as getFonts()). |

**Returns**

- **unsubscribe** — function that removes this subscription.

**Example**

```lua
local stopListening = Kora.theme.onFontsChanged(function(fonts)
    print('Body font changed to:', fonts.body.label)
end)
-- Call when this listener is no longer needed:
stopListening()
```

**Representative console output**

```text
When fonts change the callback prints the new body font label. Calling stopListening removes the listener.
```

#### `Kora.theme.push()`

Reapplies the active kora_theme styling to kora_lib’s own NUI frame through its imported browser bridge. This does not update a separate resource’s browser page.

**Parameters**



**Returns**

- **return** — no value.

**Example**

```lua
Kora.theme.push()
```

**Representative console output**

```text
kora_lib’s own NUI frame refreshes its theme.
```

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/theme/docs.md` or `local/theme/docs.md`) that the reference above does not state.

`kora_theme` is the single owner of the shared palette, colour validation, derived
CSS variables, browser loader, and live refresh behavior. This kora_lib module is a
permanent compatibility surface for resources already using `Kora.theme`.

### API

#### `Kora.theme.accentColor()`

Returns `exports.kora_theme:getPrimaryColor()`.

#### `Kora.theme.tokens(overrides?)`

Returns `exports.kora_theme:getTokens(overrides)`. A six-digit hex string overrides
the primary colour. A table may override kora_theme's approved semantic roles.
The returned table is complete, including surfaces, text, controls, status
colours, contrast foregrounds, focus, hover, pressed, and translucent variants.

The map includes the resolved `font-sans`, `font-heading` and `font-mono`
stacks.

#### `Kora.theme.getFonts()`

Returns `exports.kora_theme:getFonts()`: `{ body, heading, mono }`, each
`{ id, label, stack, source }`. `id` is a kora_theme catalog id such as
`poppins`, `default` or `custom`; `stack` is the CSS font-family list;
`source` is `config` (kora_theme's `/config` font settings), `theme.json` or
`default`. A default heading uses the body font.

#### `Kora.theme.onFontsChanged(handler)`

Client-only. Calls `handler(fonts)` with the new `getFonts()` result whenever an
admin changes the server fonts in `/config` → kora_theme → fonts. Returns an
unsubscribe function. Browser UIs that link kora_theme's `theme.css`/`theme.js`
and import its bridge need no handler: their `--font-sans`, `--font-heading`
and `--font-mono` variables update automatically. Use this hook for Lua-side
work such as fonts drawn by natives or sent in custom NUI messages.

#### `Kora.theme.push()`

Client-only. Calls the imported `KoraTheme.refresh()` bridge to reapply kora_theme to
kora_lib's own NUI frame.

New UI resources should depend directly on `kora_theme`, import
`@kora_theme/client/bridge.lua`, and link `theme.css` plus `theme.js`. They do not
need kora_lib merely to obtain styling. Use `var(--font-sans)`,
`var(--font-heading)` and `var(--font-mono)` instead of hardcoded font
families so the configured fonts apply.
