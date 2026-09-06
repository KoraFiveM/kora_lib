# Theme compatibility module

`qbtheme` is the single owner of the shared palette, colour validation, derived
CSS variables, browser loader, and live refresh behavior. This qblib module is a
permanent compatibility surface for resources already using `QB.theme`.

## API

### `QB.theme.accentColor()`

Returns `exports.qbtheme:getPrimaryColor()`.

### `QB.theme.tokens(overrides?)`

Returns `exports.qbtheme:getTokens(overrides)`. A six-digit hex string overrides
the primary colour. A table may override qbtheme's approved semantic roles.
The returned table is complete, including surfaces, text, controls, status
colours, contrast foregrounds, focus, hover, pressed, and translucent variants.

### `QB.theme.push()`

Client-only. Calls the imported `QBTheme.refresh()` bridge to reapply qbtheme to
qblib's own NUI frame.

New UI resources should depend directly on `qbtheme`, import
`@qbtheme/client/bridge.lua`, and link `theme.css` plus `theme.js`. They do not
need qblib merely to obtain styling.
