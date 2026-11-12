---
title: "Logging"
sidebar_position: 41
---


# Logging

Records compact server events in a shared in-memory ring buffer and optionally mirrors them to a Discord webhook. Categories and data are caller-defined, so any resource can use one logging API without a framework-specific event schema.

Namespace: `Kora.logging` · Source: `modules/logging/server.lua`

## Event data

data is caller-defined and is not interpreted by this module. The webhook mirror JSON-encodes it.

## Memory and webhook behavior

The ring buffer holds at most 500 recent events and overwrites the oldest entries. It is an in-memory debugging aid, not permanent storage. Set the kora_lib_log_webhook convar to mirror events; legacy kora_lib_log_webhook and kora_core_log_webhook values are fallbacks. Webhook delivery never blocks the caller.

## Choose useful event details

Include enough context to investigate an action, such as action type, amount, account, target ID, and a reason. Avoid placing secrets or unnecessary personal data in logs.

## Functions

Record an event with event, then inspect aggregate category counts with getStats.

### `Kora.logging.event(category, src, data)`

Adds an event to the local log and starts a non-blocking webhook request when a webhook is configured.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `category` | string | Non-empty category up to 64 bytes, such as money, job, or admin. |
| `src` | integer | Positive acting player server ID, or 0 for a system event. |
| `data` | table? | Optional event details. Keep values JSON encodable if the webhook should include them. |

**Returns**

- **return** — no value.

**Example**

```lua
Kora.logging.event('money', source, { type = 'add', amount = 500, account = 'bank' })
```

**Representative console output**

```text
The event is added to the local buffer and optionally sent to the configured webhook.
```

### `Kora.logging.getStats()`

Returns a safe snapshot of event counts and current ring-buffer size. Changing the returned counts table does not alter internal counters.

**Parameters**



**Returns**

- **stats** — table with counts and ringSize.

**Example**

```lua
local stats = Kora.logging.getStats()
print('Events in memory:', stats.ringSize)
print('Money events:', stats.counts.money or 0)
```

**Representative console output**

```text
Prints the current buffer size and count for the money category.
```

## Limits and related APIs

A system event may use src = 0; otherwise src must be a positive integer player ID. Webhook messages are truncated to Discord’s message limit; local entries keep their full data.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/logging/docs.md` or `local/logging/docs.md`) that the reference above does not state.

### API

#### `Kora.logging.event(category, src, data)` -- server
Records an event and, if a webhook is configured, forwards it there too.

##### Example
```lua
Kora.logging.event('money', source, { type = 'add', amount = 500, account = 'bank' })
```

Called cross-resource via export:
```lua
exports.kora_lib:logging_event('admin', source, { action = 'kick', target = 12 })
```
