---
title: "Locales"
sidebar_position: 6
---


# Locales

## Shared

Looks up translated text from a resource’s locales folder. Client calls use the player’s selected language, fall back to English, interpolate named or positional placeholders, and return the key itself when no translation is available.

Namespace: `Kora.locale` · Source: `modules/locales/shared.lua`

### Functions

Read the active language list or translate a key from an explicitly named resource.

#### `Kora.locale.getLanguage()`

Returns the active locale. On the client this is the player’s selected language; server-side it returns the configured fallback language.

**Parameters**



**Returns**

- **language** — locale code string.

**Example**

```lua
print('Language:', Kora.locale.getLanguage())
```

**Representative console output**

```text
Prints the active locale code, such as en.
```

#### `Kora.locale.getLanguages()`

Returns the language codes enabled by the server configuration.

**Parameters**



**Returns**

- **languages** — array of enabled locale code strings.

**Example**

```lua
for _, code in ipairs(Kora.locale.getLanguages()) do
    print(code)
end
```

**Representative console output**

```text
Prints each locale code the server offers.
```

#### `Kora.locale.translate(resource, key, ...values)`

Translates a key from a specific resource. Extra arguments fill placeholders in the translated string.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `resource` | string | Resource name containing locales/. Use only letters, numbers, underscore, or hyphen. |
| `key` | string | Translation key to look up. |
| `...values` | any | Optional replacements for positional placeholders such as %s. |

**Returns**

- **text** — translated string, or the key itself if no translation exists.

**Example**

```lua
local message = Kora.locale.translate('kora_shop', 'purchase.success', itemLabel)
print(message)
```

**Representative console output**

```text
Prints the translated message with itemLabel inserted where its placeholder appears.
```

## Client

Stores the player’s language preference locally and exposes Kora.lang as a shorthand translator for the calling resource. Preferences use a client KVP and are not written to character or database records.

Namespace: `Kora.locale` · Source: `modules/locales/client.lua`

### Functions

Change the saved locale or translate a key in the current resource without naming it every time.

#### `Kora.locale.setLanguage(language)`

Sets and persists the player’s preferred locale code on this client.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `language` | string | Enabled locale code. Invalid values are rejected or resolved to the configured fallback. |

**Returns**

- **return** — no value.

**Example**

```lua
Kora.locale.setLanguage('de')
print(Kora.locale.getLanguage())
```

**Representative console output**

```text
The selected locale is saved on this client and then printed.
```

#### `Kora.lang(key, ...values)`

Convenience function that translates key from the resource calling Kora Lib.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `key` | string | Translation key in the calling resource’s locale files. |
| `...values` | any | Optional replacement values for placeholders. |

**Returns**

- **text** — translated string, or key if missing.

**Example**

```lua
print(Kora.lang('welcome', GetPlayerName(PlayerId())))
```

**Representative console output**

```text
Prints the calling resource’s welcome translation with the player name inserted.
```

## Server

Server-side locale helpers read the configured fallback language and can translate text for a named resource. Client language preferences are local to each player; use a server-to-client message when text must be translated using the recipient’s chosen locale.

Namespace: `Kora.locale` · Source: `modules/locales/shared.lua`

### Functions

Use getLanguage/getLanguages and translate in server code; getLanguage returns the server fallback.

#### `Kora.locale.getLanguage()`

Returns the server fallback locale configured for the resource environment.

**Parameters**



**Returns**

- **language** — locale code string.

**Example**

```lua
print('Server locale:', Kora.locale.getLanguage())
```

**Representative console output**

```text
Prints the server fallback language code.
```

#### `Kora.locale.getLanguages()`

Returns the locale codes enabled in server configuration.

**Parameters**



**Returns**

- **languages** — array of locale code strings.

**Example**

```lua
local languages = Kora.locale.getLanguages()
print('Available locales:', #languages)
```

**Representative console output**

```text
Prints how many locales the server offers.
```

#### `Kora.locale.translate(resource, key, ...values)`

Translates a key using the server-side locale context and a named resource.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `resource` | string | Resource name with a locales folder. |
| `key` | string | Translation key. |
| `...values` | any | Optional positional replacement values. |

**Returns**

- **text** — translated string, or original key if not found.

**Example**

```lua
local text = Kora.locale.translate('kora_core', 'server.restart_notice')
print(text)
```

**Representative console output**

```text
Prints the server-context translation.
```

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/locales/docs.md` or `local/locales/docs.md`) that the reference above does not state.

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
