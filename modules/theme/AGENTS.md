# theme module guide

## Purpose

This module permanently preserves kora_lib's `Kora.theme` API while the standalone
`kora_theme` resource owns the implementation.

## Rules

- `shared.lua` remains a thin forward to `qbtheme:getPrimaryColor()` and
  `qbtheme:getTokens(overrides?)`. Do not duplicate validation or colour math.
- `shared.lua` forwards `Kora.theme.getFonts()` to `qbtheme:getFonts()`. Fonts
  are resolved only by kora_theme (theme.json, fonts/catalog.json and its
  `/config` settings); do not keep a font list here.
- `client.lua` exposes `Kora.theme.onFontsChanged(handler)` on kora_theme's
  local `qbtheme:fontsChanged` event.
- `client.lua` retains the legacy `kora_lib:nui:theme` callback and forwards
  `Kora.theme.push()` to the imported `QBTheme.refresh()` bridge.
- New browser UIs depend on kora_theme directly and import its bridge, stylesheet,
  and loader. Do not add local copies of the reserved global tokens, and use
  `var(--font-sans|--font-heading|--font-mono)` rather than hardcoded fonts.
- Keep the compatibility surface documented and covered by the smoke test.
