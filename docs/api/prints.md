---
title: "Prints"
sidebar_position: 49
---


# Prints

Small structured-console helpers for readable diagnostic messages. They add a severity prefix, format each argument, join arguments with spaces, and pass the completed line to Lua print().

Namespace: `Kora.print` · Source: `modules/prints/shared.lua`

## How it works

These helpers do not persist records, apply filtering, or send messages to Discord. They print immediately in the realm where the call runs: server calls appear in the server console; client calls appear in that client’s F8 console. For retained events, ring-buffer statistics, or optional Discord delivery, use Kora.logging.event instead.

## Functions

The module exposes five severity methods with the same parameter and output contract. The method name selects the severity label and FiveM color code.

**Parameters (all functions):** ...values — zero or more Lua values. Each argument is formatted independently, then the formatted strings are joined with one space. Tables are JSON formatted when possible.

**Returns (all functions):** No value (nil). Each helper writes one line by calling print().

### `Kora.print.debug(...values)`

Use for developer-oriented details that help trace a flow.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `...values` | Lua values | zero or more Lua values. Each argument is formatted independently, then the formatted strings are joined with one space. Tables are JSON formatted when possible. |

**Returns**

No value (nil). Each helper writes one line by calling print().

**Example**

```lua
Kora.print.debug('config loaded', 'development')
```

**Representative console output**

```text
^6[DEBUG]^0 config loaded development
```

### `Kora.print.info(...values)`

Use for a normal milestone or state transition.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `...values` | Lua values | zero or more Lua values. Each argument is formatted independently, then the formatted strings are joined with one space. Tables are JSON formatted when possible. |

**Returns**

No value (nil). Each helper writes one line by calling print().

**Example**

```lua
Kora.print.info('resource started', GetCurrentResourceName())
```

**Representative console output**

```text
^4[INFO]^0 resource started kora_example
```

### `Kora.print.warn(...values)`

Use when execution can continue, but a value or condition needs attention.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `...values` | Lua values | zero or more Lua values. Each argument is formatted independently, then the formatted strings are joined with one space. Tables are JSON formatted when possible. |

**Returns**

No value (nil). Each helper writes one line by calling print().

**Example**

```lua
Kora.print.warn('missing optional setting', 'garage.blip')
```

**Representative console output**

```text
^3[WARNING]^0 missing optional setting garage.blip
```

### `Kora.print.error(...values)`

Use when an operation failed or cannot proceed as expected.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `...values` | Lua values | zero or more Lua values. Each argument is formatted independently, then the formatted strings are joined with one space. Tables are JSON formatted when possible. |

**Returns**

No value (nil). Each helper writes one line by calling print().

**Example**

```lua
Kora.print.error('failed to load account', source)
```

**Representative console output**

```text
^1[ERROR]^0 failed to load account ^742^0
```

### `Kora.print.success(...values)`

Use for a successful action worth calling out during development or administration.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `...values` | Lua values | zero or more Lua values. Each argument is formatted independently, then the formatted strings are joined with one space. Tables are JSON formatted when possible. |

**Returns**

No value (nil). Each helper writes one line by calling print().

**Example**

```lua
Kora.print.success('character saved', characterId)
```

**Representative console output**

```text
^2[SUCCESS]^0 character saved char_104
```

## Structured values

Pass a table as an argument to get readable JSON instead of Lua's default table address. Object keys are sorted before encoding, which makes repeated snapshots easier to compare.

```lua
Kora.print.info('player loaded', {
    source = 42,
    license = 'license:abc',
})
```

**Representative output**

```text
^4[INFO]^0 player loaded {
  "license": "license:abc",
  "source": 42
}
```

> **Note:** The example output is representative: the JSON encoder sorts the keys and formats the table with indentation. Whitespace can vary with the FiveM JSON encoder version.

## Value formatting

| Kind | Description |
| --- | --- |
| String | Printed as-is. |
| Number | A number passed as a direct argument is converted with tostring and wrapped in ^7…^0. Numbers inside a JSON-encoded table remain ordinary JSON numbers. |
| Boolean | Printed as true or false. |
| nil | Printed as the literal text nil. |
| Table | JSON encoded with sorted keys and indentation. If encoding fails (for example, for a cyclic table), tostring(table) is used. |
| Other values | Converted with tostring. Function values inside a table are converted to their tostring representation by the JSON encoder exception handler. |

## Common use cases

- Report that a resource or player lifecycle step completed.
- Inspect a value or structured snapshot while developing a feature.
- Make warnings and errors easy to distinguish in the relevant FiveM console.

## Limits and related APIs

Kora.print is a presentation helper, not a persistent logging system. It writes every call immediately; it does not suppress debug messages or retain a history. Avoid calling it every frame or in a hot loop, because each call formats its arguments and writes to a console. For event records that need ring-buffer statistics or optional Discord delivery, use Kora.logging.event.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/prints/docs.md` or `local/prints/docs.md`) that the reference above does not state.

Shared structured-console helpers. Each function accepts any number of values, formats them on one line, and adds a colored severity prefix:

```lua
Kora.print.debug(...)
Kora.print.info(...)
Kora.print.warn(...)
Kora.print.error(...)
Kora.print.success(...)
```

Tables are encoded as indented JSON with sorted keys. Numbers, booleans, strings, `nil`, and functions are converted to readable text without changing the values passed by the caller.
If a table cannot be JSON-encoded (for example, it contains a cycle), the
helper falls back to its Lua string representation rather than throwing from a
diagnostic call.

```lua
Kora.print.info('player loaded', {
    source = source,
    license = license,
})
```

These are presentation helpers, not persistent logging. Use `Kora.logging.event` when an event needs ring-buffer statistics or optional Discord delivery.
