# theme module guide

## Purpose

This module permanently preserves qblib's `QB.theme` API while the standalone
`qbtheme` resource owns the implementation.

## Rules

- `shared.lua` remains a thin forward to `qbtheme:getPrimaryColor()` and
  `qbtheme:getTokens(overrides?)`. Do not duplicate validation or colour math.
- `client.lua` retains the legacy `qblib:nui:theme` callback and forwards
  `QB.theme.push()` to the imported `QBTheme.refresh()` bridge.
- New browser UIs depend on qbtheme directly and import its bridge, stylesheet,
  and loader. Do not add local copies of the reserved global tokens.
- Keep the compatibility surface documented and covered by the smoke test.
