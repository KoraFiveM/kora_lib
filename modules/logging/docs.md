# Logging module

## Overview
A lightweight event log: an in-memory ring buffer plus per-category counters, with an optional Discord webhook mirror for anything logged. Any resource can call it -- there's nothing framework-specific baked in.

## API

### `QB.logging.event(category, src, data)` -- server
Records an event and, if a webhook is configured, forwards it there too.

#### Parameters
- `category: string` -- non-empty grouping label of at most 64 bytes, e.g. `"money"`, `"job"`, `"admin"`.
- `src: integer` -- the acting player's positive server id, or `0` for a system-initiated event.
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
- `table` -- `{ counts = { [category] = integer, ... }, ringSize = integer }`.
  `counts` is a snapshot and can be safely changed by the caller. `ringSize` is
  the number of entries currently held (capped at 500).

## Notes
- The ring buffer holds the most recent 500 events; older entries are overwritten, not persisted anywhere.
- Set the `qblib_log_webhook` convar to a Discord webhook URL to mirror every `event()` call there. The legacy `qbcore_log_webhook` convar still works as a fallback.
- Webhook delivery is fire-and-forget -- a failing or slow endpoint never blocks or throws into the caller.
- Webhook content is capped at Discord's 2,000-character message limit; this
  affects only the outbound mirror, never the complete local ring entry.
- If a webhook payload cannot be JSON-encoded, the event remains in the local
  ring/counters and qblib logs one diagnostic instead of interrupting the caller.
- The webhook message's `username` is whichever resource called `event()` (via `GetInvokingResource()`), so events from different resources are distinguishable in the Discord channel.
