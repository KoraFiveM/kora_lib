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

### `Kora.theme.push()`

Client-only. Calls the imported `QBTheme.refresh()` bridge to reapply kora_theme to
kora_lib's own NUI frame.

New UI resources should depend directly on `kora_theme`, import
`@kora_theme/client/bridge.lua`, and link `theme.css` plus `theme.js`. They do not
need kora_lib merely to obtain styling.
