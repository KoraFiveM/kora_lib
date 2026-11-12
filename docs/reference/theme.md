---
title: "Theme compatibility module"
sidebar_position: 19
---

# Theme compatibility module

`kora_theme` is the single owner of the shared palette, colour validation, derived
CSS variables, browser loader, and live refresh behavior. This kora_lib module is a
permanent compatibility surface for resources already using `Kora.theme`.

## API

### `Kora.theme.accentColor()`

Returns `exports.kora_theme:getPrimaryColor()`.

### `Kora.theme.tokens(overrides?)`

Returns `exports.kora_theme:getTokens(overrides)`. A six-digit hex string overrides
the primary colour. A table may override kora_theme's approved semantic roles.
The returned table is complete, including surfaces, text, controls, status
colours, contrast foregrounds, focus, hover, pressed, and translucent variants.

The map includes the resolved `font-sans`, `font-heading` and `font-mono`
stacks.

### `Kora.theme.getFonts()`

Returns `exports.kora_theme:getFonts()`: `{ body, heading, mono }`, each
`{ id, label, stack, source }`. `id` is a kora_theme catalog id such as
`poppins`, `default` or `custom`; `stack` is the CSS font-family list;
`source` is `config` (kora_theme's `/config` font settings), `theme.json` or
`default`. A default heading uses the body font.

### `Kora.theme.onFontsChanged(handler)`

Client-only. Calls `handler(fonts)` with the new `getFonts()` result whenever an
admin changes the server fonts in `/config` → kora_theme → fonts. Returns an
unsubscribe function. Browser UIs that link kora_theme's `theme.css`/`theme.js`
and import its bridge need no handler: their `--font-sans`, `--font-heading`
and `--font-mono` variables update automatically. Use this hook for Lua-side
work such as fonts drawn by natives or sent in custom NUI messages.

### `Kora.theme.push()`

Client-only. Calls the imported `KoraTheme.refresh()` bridge to reapply kora_theme to
kora_lib's own NUI frame.

New UI resources should depend directly on `kora_theme`, import
`@kora_theme/client/bridge.lua`, and link `theme.css` plus `theme.js`. They do not
need kora_lib merely to obtain styling. Use `var(--font-sans)`,
`var(--font-heading)` and `var(--font-mono)` instead of hardcoded font
families so the configured fonts apply.
