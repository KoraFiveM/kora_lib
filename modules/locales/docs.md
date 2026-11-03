# Locales

`Kora.lang(key, ...)` resolves a key from the calling resource's `locales/`
folder. Clients use their own saved language, fall back to English, interpolate
both legacy `%{name}` and positional `%s` placeholders, and return the key when
no translation exists.

Named placeholder keys and replacement values are treated literally, so values
such as `50%` and keys such as `%{item.id}` are safe to use.

Set the client-readable defaults with `setr qb_locale "en"` and the languages
a server offers with `setr qb_locales "en,de"`. Players choose with kora_core's `/language`
command; the preference is stored in kora_lib's client KVP, never in character or
database data. Invalid `qb_locale` values fall back to English. Explicit
resource names passed to `Kora.locale.translate` must use the normal FiveM
resource-name characters: letters, numbers, `_`, and `-`.

## API

### `Kora.lang(key, ...)`
Resolves `key` from the calling resource's locale files. The calling resource is determined by the invoking resource, falling back to the current resource. Translation lookup tries the selected language and then English; if neither contains the key, the key itself is returned.

#### Parameters
- `key: string` — Non-empty dotted key path, such as `menu.open`. Dots traverse nested tables.
- `...: any` — Optional interpolation values. Pass one table for named `%{name}` placeholders, or positional values for Lua-style `%s` formatting.

#### Returns
- `any` — The translated value after interpolation, or the key when no translation exists. Non-string translation values are returned without interpolation.

### `Kora.locale.getLanguage()`
Returns the language selected for this client. Server-side, where client KVP is unavailable, it returns the configured `qb_locale` fallback.

#### Returns
- `string` — The current or configured fallback language code.

### `Kora.locale.getLanguages()`
Returns the selectable language codes derived from `qb_locales`. The configured default and English are always included, duplicates are removed, and the result is sorted.

#### Returns
- `string[]` — Enabled language codes.

### `Kora.locale.setLanguage(code)`
Client-only. Persists a player's selected language in that client's resource KVP and emits `kora_lib:client:localeChanged` with the new and previous language. The deprecated `qblib:client:localeChanged` alias is also emitted for existing listeners. Selecting the current language succeeds without writing or emitting another change event.

#### Parameters
- `code: string` — Must use letters, numbers, hyphens, or underscores and must appear in the enabled language list.

#### Returns
- `true` — The language is already selected or was saved successfully.
- `false, reason` — The code is malformed or is not enabled by `qb_locales`.

### `Kora.locale.translate(resource, key, ...)`
Resolves a key against an explicitly named resource. This is useful when a server-originated message is translated on the receiving client, where the caller's own resource is not the resource that owns the phrase.

#### Parameters
- `resource: string` — Resource name containing the locale files; letters, numbers, underscores, and hyphens only.
- `key: string` — Required non-empty dotted phrase key.
- `...: any` — Same named-table or positional interpolation values accepted by `Kora.lang`.

#### Returns
- `any` — Translation or original key, using the selected language then English.
- Raises an assertion error — The resource name or key is invalid.

## Locale file lookup

For a resource and language code, the loader tries `locales/<code>.json` first, then the legacy `locales/<code>.lua` format. Successfully loaded files are cached by resource and language. Missing or invalid files behave like a missing key and fall back to English; a missing English entry returns the key.

Named substitutions replace `%{name}` literally, including keys containing punctuation. Positional substitutions use protected `string.format`; a formatting mismatch leaves the original translated string intact instead of raising. Configure the fallback and available language list with `setr qb_locale "en"` and `setr qb_locales "en,de"` respectively.
