# Locales

`QB.lang(key, ...)` resolves a key from the calling resource's `locales/`
folder. Clients use their own saved language, fall back to English, interpolate
both legacy `%{name}` and positional `%s` placeholders, and return the key when
no translation exists.

Set the client-readable defaults with `setr qb_locale "en"` and the languages
a server offers with `setr qb_locales "en,de"`. Players choose with qbcore's `/language`
command; the preference is stored in qblib's client KVP, never in character or
database data.

- `QB.locale.getLanguage()` returns the current client language (or server
  fallback when called server-side).
- `QB.locale.getLanguages()` returns enabled language codes.
- `QB.locale.setLanguage(code)` is client-only and persists the preference.
- `QB.locale.translate(resource, key, ...)` resolves an explicit resource;
  qbcore uses it to localize server-originated legacy notifications at the
  recipient.
