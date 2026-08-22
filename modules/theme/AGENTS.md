# theme module guide

## Purpose
Centralizes `Config.ui.accentColor` validation and the HSL token-derivation math, previously duplicated/only-in-TS, so both qblib's own NUI and any external consuming resource read the brand colour from one place.

## Public API
- `QB.theme.accentColor()` — validated `Config.ui.accentColor`, or the default `#DC143C` (with a warning) if missing/malformed.
- `QB.theme.tokens(accentColor?)` — the full accent-derived HSL token table (`primary`, `ring`, `brand-hover`, `brand-pressed`, `brand-soft`, `brand-border`, `primary-foreground`), as ready-to-apply CSS custom-property strings.
- `QB.theme.push()` (client-only) — resends the current accent colour to qblib's own NUI via the `qblib:theme` action, for a live resync. Not useful to an external resource, which never talks to qblib's NUI frame directly.

## Implementation notes
- **File layout**: `shared.lua` holds `accentColor()`/`tokens()` — pure Lua, no natives, just `Config` table access, so both realms can compute identical tokens. `client.lua` holds only the `qblib:nui:theme` `QB.nui.registerCallback` registration and `push()`, since those need `QB.nui.*`, a client-only API. This mirrors `modules/notify`'s shared+client split rather than inventing a new layout.
- **Keep `QB.theme.tokens()`'s math in sync with `web/src/components/theme/ThemeSynchronizer.tsx`'s `applyAccentColor`/`hslFromHex`/`relativeLuminance`** — it's a deliberate line-for-line port (same magic numbers: `5.1`/`10.6` lightness deltas, `0.14`/`0.45` alphas, the two literal foreground HSL strings). If one implementation changes, change both, and re-check `test/smoke/theme.lua`'s parity assertions.
- **`DARK_SURFACE_LUMINANCE`** is `relativeLuminance(16, 16, 16)` — the `#101010` overlay background's luminance — computed once at module load (a local, not per-call), matching the TS module-scope `const`. It's the dark-surface half of the white-vs-dark-foreground contrast comparison `primary-foreground` is chosen from.
- **No `Math.round` in Lua**: `round1(value) = math.floor(value * 10 + 0.5) / 10` matches JS's half-up rounding for the non-negative hue/saturation/lightness values this module ever rounds — it would round incorrectly for negative input, but none of the three ever go negative (hue is normalized into `[0, 360)`, saturation/lightness are always non-negative fractions).
- **String formatting matters for parity**: Lua's default `tostring` on a whole-number float prints a trailing `.0` (`348.0`), which JS's number-to-string coercion never does (`348`). `hslToken`'s internal `numToStr` special-cases whole numbers to avoid this — necessary for the token strings to byte-for-byte match what `ThemeSynchronizer.tsx` produces (and what `globals.css`'s static defaults already look like). The alpha argument (`0.14`/`0.45`) bypasses `numToStr` entirely — it's a fixed literal interpolated as-is, not a rounded value, matching the TS template literal's own handling.
- **`web/src/styles/globals.css`'s static `--brand-hover`/`--brand-pressed` values (83.2%) don't quite match this module's/the TS formula's actual output (83.3%)** — a pre-existing ~0.1% drift in that hand-authored static fallback (every other token there, including `--primary` itself, matches the formula exactly). That CSS block is only ever a pre-JS default anyway (overwritten by `ThemeSynchronizer`/`QB.theme.tokens()` at runtime), so don't "fix" this module to reproduce the drift — `test/smoke/theme.lua`'s parity assertions intentionally assert the correct formula output, not the CSS file's literal text, for those two tokens.

## Best practices
- A resource with its own NUI should call `QB.theme.tokens()` directly (Lua-to-Lua, via the `QB` proxy) and forward the result to its own frame — there's no need to reach qblib's `qblib:nui:theme` NUI callback at all, that's scoped to qblib's own frame.
- Don't hardcode `#DC143C` (or any other accent) in a consuming resource's components; read it through `QB.theme.accentColor()`/`tokens()` so a server's `Config.ui.accentColor` change actually propagates.
- Ship your own resource's static base palette (non-accent tokens) as CSS defaults, same as qblib does — `QB.theme.tokens()` deliberately doesn't cover them.
