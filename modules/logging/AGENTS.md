# logging module guide

## Purpose
A small ring-buffered event log (`QB.logging.event`) plus aggregate counters (`QB.logging.getStats`), with an optional Discord webhook mirror. Moved out of qbcore: the mechanics never touched anything framework-specific (no player/job/identity knowledge), so any resource can log through one shared ring buffer and one shared webhook convar instead of every framework/resource hand-rolling its own.

## Implementation notes
- **Server-only** -- there's no client-side equivalent; a client wanting to log something does it via its own server-side handler, same as any other server-authoritative write.
- **Ring buffer, not unbounded**: `RING = 500` entries, overwritten oldest-first once full (`head` wraps via `% RING`). This is an in-memory debugging aid, not a persistence layer -- nothing here survives a restart.
- **Webhook is opt-in and fire-and-forget**: `PerformHttpRequest(url, function() end, ...)` -- a slow or dead webhook endpoint never blocks or fails the caller. Checked via `GetConvar('qblib_log_webhook', ...)`, falling back to the legacy `qbcore_log_webhook` convar name so a server that already set that before this module moved into qblib doesn't silently stop logging.
- **Webhook messages are attributed by `GetInvokingResource()`**, not a hardcoded name -- this is what makes the module framework-agnostic: qbcore calling through `Core.logging.event` still shows up as `qbcore` (it's the direct caller into qblib), while another resource calling `QB.logging.event` directly is attributed to itself.
- **`category`/`data` are opaque to this module** -- it never inspects or validates them beyond passing `data` through `json.encode` for the webhook body. Callers own their own event vocabulary (e.g. qbcore's `Core.logging` callers use categories like `'money'`/`'job'`/`'admin'`).

## Testing
`test/smoke/logging.lua` mocks `GetConvar`, `PerformHttpRequest`, `GetInvokingResource`, and `json.encode`/`os.time`. Covers: ring buffer growth and wraparound, `counts` aggregation, the webhook firing only when the convar is set, the legacy `qbcore_log_webhook` fallback, and webhook `username` following `GetInvokingResource()`.
