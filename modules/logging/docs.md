# Logging module

## Overview
A lightweight event log: an in-memory ring buffer plus per-category counters, with an optional Discord webhook mirror for anything logged. Any resource can call it -- there's nothing framework-specific baked in.

## API

### `QB.logging.event(category, src, data)` -- server
Records an event and, if a webhook is configured, forwards it there too.

#### Parameters
- `category: string` -- groups events, e.g. `"money"`, `"job"`, `"admin"`. Meaning is entirely up to the caller.
- `src: integer` -- the acting player's server id, or `0` for a system-initiated event.
- `data: table | nil` -- arbitrary event payload, JSON-encoded for the webhook body.

#### Example
```lua
QB.logging.event('money', source, { type = 'add', amount = 500, account = 'bank' })
```

Called cross-resource via export:
```lua
exports.qblib:logging_event('admin', source, { action = 'kick', target = 12 })
```

### `QB.logging.getStats()` -- server
#### Returns
- `table` -- `{ counts = { [category] = integer, ... }, ringSize = integer }`. `ringSize` is the number of entries currently held (capped at 500).

## Notes
- The ring buffer holds the most recent 500 events; older entries are overwritten, not persisted anywhere.
- Set the `qblib_log_webhook` convar to a Discord webhook URL to mirror every `event()` call there. The legacy `qbcore_log_webhook` convar still works as a fallback.
- Webhook delivery is fire-and-forget -- a failing or slow endpoint never blocks or throws into the caller.
- The webhook message's `username` is whichever resource called `event()` (via `GetInvokingResource()`), so events from different resources are distinguishable in the Discord channel.
