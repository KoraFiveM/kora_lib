# Internal locale bootstrap

The resource manifest loads this shared script first in both realms. It provides
`KoraLang(key, ...)` for kora_lib's Lua modules and reads the configured language
with an English fallback. Consumer resources use the
[public locale APIs](../../modules/locales/docs.md).
