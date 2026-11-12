---
title: "Locales"
sidebar_position: 6
---

# Locales

`Kora.lang(key, ...)` resolves a key from the calling resource's `locales/`
folder. Clients use their own saved language, fall back to English, interpolate
both legacy `%{name}` and positional `%s` placeholders, and return the key when
no translation exists.

Named placeholder keys and replacement values are treated literally, so values
such as `50%` and keys such as `%{item.id}` are safe to use.

Set the client-readable defaults with `setr kora_locale "en"` and the languages
a server offers with `setr kora_locales "en,de"`. Players choose with kora_core's `/language`
command; the preference is stored in kora_lib's client KVP, never in character or
database data. Invalid `kora_locale` values fall back to English. Explicit
resource names passed to `Kora.locale.translate` must use the normal FiveM
resource-name characters: letters, numbers, `_`, and `-`.

- `Kora.locale.getLanguage()` returns the current client language (or server
  fallback when called server-side).
- `Kora.locale.getLanguages()` returns enabled language codes.
- `Kora.locale.setLanguage(code)` is client-only and persists the preference.
- `Kora.locale.translate(resource, key, ...)` resolves an explicit resource;
  kora_core uses it to localize server-originated legacy notifications at the
  recipient.
