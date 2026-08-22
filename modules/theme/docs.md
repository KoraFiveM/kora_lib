# Theme module

## Overview
The single source of truth for qblib's brand colour and the design-token set derived from it. `Config.ui.accentColor` is validated here, and the same HSL math qblib's own NUI uses (`web/src/components/theme/ThemeSynchronizer.tsx`) is ported to Lua so any consuming resource — not just qblib's own frontend — can pull ready-made tokens and match its look without re-deriving them.

## API

### `QB.theme.accentColor()`
Returns the configured accent colour (`Config.ui.accentColor`) if it's a valid `#RRGGBB` hex string, otherwise falls back to the default `#DC143C` (and logs a warning if a value was configured but invalid).

#### Returns
- `string` — a `#RRGGBB` hex colour.

### `QB.theme.tokens(accentColor)`
Derives the full semantic HSL token set from an accent colour — ready to apply directly as CSS custom properties (`--primary`, `--brand-hover`, etc.) in any consuming resource's own NUI.

#### Parameters
- `accentColor?: string` — a `#RRGGBB` hex colour. Defaults to `QB.theme.accentColor()`. An invalid value falls back to the default accent, same as `accentColor()`.

#### Returns
- `table<string, string>` — keys `primary`, `ring`, `brand-hover`, `brand-pressed`, `brand-soft`, `brand-border`, `primary-foreground`. Each value is an HSL-triplet string (`"H S% L%"`, or `"H S% L% / A"` for the two alpha tokens) in the exact format `web/src/styles/globals.css` already uses — apply it with `document.documentElement.style.setProperty("--" .. key, value)` on the NUI side with no reshaping.

#### Example
```lua
-- From another resource's client.lua, having pulled in @qblib/init.lua:
local tokens = QB.theme.tokens()
QB.nui.send("myresource:theme", tokens) -- forward to your own NUI frame
```
```ts
// In your own NUI, on receiving the "myresource:theme" message:
for (const [key, value] of Object.entries(tokens)) {
    document.documentElement.style.setProperty(`--${key}`, value)
}
```

## Notes
- `QB.theme.tokens()` only covers the accent-derived subset of qblib's palette (the tokens `ThemeSynchronizer.tsx` actually computes). It does not return the static base palette (`--background`, `--card`, `--popover`, etc.) — ship those as sane CSS defaults in your own resource, the same way qblib's own `globals.css` does, and let `QB.theme.tokens()` override just the accent-derived subset at runtime.
- qblib's own NUI still fetches this via the `qblib:nui:theme` NUI callback and the `qblib:theme` push event (both unchanged, now backed by this module) — a resource with its *own* NUI should call `QB.theme.tokens()` directly from Lua instead, since it never needs a round trip through qblib's NUI frame at all.
