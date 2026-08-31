# Locales

`QB.lang(key, ...)` is a shared translation lookup. It reads the configured
locale, falls back to English, interpolates positional `%s` values, and returns
the key itself when no translation exists.
