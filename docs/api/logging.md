---
title: "Logging"
sidebar_position: 41
---

# Kora Framework logging

One diagnostic API for server Lua, client Lua, server JavaScript and NUI. This
module owns filtering, redaction, bounded records and FiveM console rendering.
Diagnostic delivery is best effort, not a durable audit trail. Domain-owned
administrator, financial and inventory audit tables remain authoritative.

## Public API

Both realms expose `Kora.logging.trace`, `Kora.logging.debug`, `Kora.logging.info`,
`Kora.logging.warn`, `Kora.logging.error`, and `Kora.logging.fatal`:

```lua
Kora.logging.warn('inventory.save_failed', 'Inventory save failed', {
    playerId = src,
    operationId = operationId,
    reason = 'database_unavailable',
})
if Kora.logging.isEnabled('debug') then
    Kora.logging.debug('inventory.capacity', 'Capacity checked', { weight = weight })
end
```

Signature: `(eventName: string, message: string, fields?: table): boolean`.
Calls do not yield. `true` means accepted locally, not persisted or delivered.
Filtered, invalid, full-queue and failed-sink calls return `false`; failures do
not escape into gameplay. `fatal` never stops a resource. Event names are stable
1–128-byte identifiers; put variable values in fields, not in the event name.
`Kora.logging.isEnabled(level)` includes an active capture's threshold on clients.
Use it before constructing expensive diagnostics; Lua evaluates arguments first.

| Level | Use |
| --- | --- |
| trace | Very detailed, temporary investigation |
| debug | Normal internal decisions useful during debugging |
| info | Meaningful lifecycle milestones and completed operations |
| warn | Rejected input, degraded operation, recoverable failure |
| error | Operation failed; intervention/investigation may be needed |
| fatal | Resource cannot perform its primary role |

Keep messages concise. Pass only approved scalar context or small tables. Never
pass credentials, full player data, SQL parameters, raw queries, authorization
headers or entire network payloads. Recursive key redaction is defense in depth;
it cannot identify secrets interpolated into prose. Use safe error codes for
SQL/HTTP failures. Pass an existing `operationId` across related calls; this
logger does not invent distributed trace IDs.

`Kora.print.*` remains a variadic compatibility adapter; `success` maps to info.
New code uses the diagnostic API above.

### Legacy events and statistics

`Kora.logging.event(category, src, data)` remains server-only. Category is a
nonempty string of at most 64 bytes, source a nonnegative integer (0 = system),
and data a table or nil. Invalid programmer arguments still assert as before.
It retains category/source/data semantics and category counts, now with sanitized
snapshots, and emits an info record through the common renderer. The ring holds
500 entries across events and diagnostics; it is overwritten and lost on restart.

`Kora.logging.getStats()` returns a fresh table. Server fields: `counts`,
`ringSize`, `emitted`, `dropped`, `failures`. Client fields: `queuedBytes`,
`emitted`, `dropped`, `failures`. Counters are process/realm-local. They are not
exposed through an unrestricted network query.

Only legacy `event` calls mirror to Discord. Configure a **server-only**
`kora_lib_log_webhook`; `kora_core_log_webhook`, `qblib_log_webhook`, then `qbcore_log_webhook`, remain
fallbacks. Delivery is asynchronous, best effort, capped at 2,000 bytes and has
mention parsing disabled. Never use `setr` for a webhook or credential.
`Core.logging.logEvent`, core exports and the local `qb-log` compatibility event
retain their existing contracts.

## Console and export configuration

```cfg
setr kora_logging_level info
setr kora_logging_level_kora_inventory debug
set kora_logging_format pretty
```

Use server `set` for server-only settings and `setr` only for non-secret client
settings. Thresholds are read at call time. `kora_logging_format` supports
`pretty` (default), `json`, and `dual`. Invalid levels fall back to info; invalid
formats fall back to pretty. Resource overrides use the exact resource name.

Pretty output contains time (UTC on the server), level, resource/realm, event,
message and compact fields. Client forwarding adds player and capture identity.
Colors belong only to the renderer; caller colors and control characters are
removed, and line breaks escaped. Client-local timestamps use the client clock,
not a fabricated wall-clock time.

JSON records have the stable prefix `KORA_LOG ` and schema version 1:

```json
{"schemaVersion":1,"observedAt":1794571200,"severity":"warn","severityNumber":13,"resource":"kora_inventory","realm":"server","event":"inventory.save_failed","message":"Inventory save failed","fields":{"playerId":42}}
```

An external collector first removes FiveM/Docker prefixes, selects the
`KORA_LOG ` marker, then JSON-decodes the rest of that single line. Ignore pretty
lines in dual mode so records are not counted twice. Fields are truncated when
necessary to keep the encoded record within 4 KiB. There is no HTTP exporter,
dashboard, file writer or retention daemon in this resource. Configure retention
and rotation in the external collector/container logging system.

OpenTelemetry mapping: `observedAt` (Unix seconds) → ObservedTimestamp,
`severityNumber` → SeverityNumber, `severity` → SeverityText, `message` → Body,
`event` → EventName, `resource` → service/resource attribute, and `fields` →
Attributes. Forwarded records carry `clientReported=true`, server-assigned
`playerId`, `captureId`, `sessionId`, and optional untrusted `clientTime` in
milliseconds since client runtime startup. Resource/realm and client timestamps
are claims, not proof of what ran. No client data is an audit authority.

## Targeted client debugging

Console or staff with ACE `kora.logging.capture` may run:

```text
kora_log_capture start 42 kora_hud debug 600
kora_log_capture start 42 * trace 60
kora_log_capture status
kora_log_capture stop 42
```

The optional arguments default to resource `*`, level `debug`, and 600 seconds.
Duration is 1–3600 seconds. Starting again replaces the previous capture for that
player. Status and control records appear in the server console. Disconnect,
expiry, library restart, or stopping the selected resource invalidates capture.
No backlog is replayed when another capture begins. Local client diagnostics
continue at their configured threshold whether forwarding is enabled or not.

For explicitly enabled development-wide capture, set before starting resources:

```cfg
setr kora_logging_capture_all true
set kora_logging_capture_level debug
```

Clients wait at most ten seconds for their network session, then request one capture
on library startup in that mode; it expires after
one hour. Restart the library or use targeted commands for another session. This
is not an always-on telemetry collector. By default there is no handshake,
forwarding timer, queue allocation for records or client-to-server log traffic.

Limits (server convars, clamped to safe ranges) are sent when a capture starts:

| `kora_logging_` suffix | Default | Allowed |
| --- | ---: | ---: |
| record_bytes | 4096 | 1024–4096 |
| batch_bytes | 16384 | 4096–16384 |
| queue_bytes | 65536 | 4096–65536 |
| flush_ms | 1000 | 100–10000 |
| client_rate | 20 records/sec | 1–200 |
| client_burst | 40 records | 1–200 |
| aggregate_rate | 200 records/sec | 1–2000 |

The server charges malformed active-session requests against the rate budget,
validates the session and record filters again, and ignores claimed player IDs.
Excess records are dropped, never retried indefinitely. Server drop/failure
counts appear in stats; client queue drops also produce an aggregate local
warning. Batches have at most 40 records. Keep event frequencies reasonable.

## JavaScript and NUI

Server JavaScript consumers include this before their own entrypoint:

```lua
server_script '@kora_lib/modules/logging/adapters/server.js'
```

Then call `globalThis.KoraLogger.warn(eventName, message, fields)` or
`KoraLogger.isEnabled(level)`. All six levels share the Lua contract. The adapter
resolves exports on each call, so a library restart does not retain stale handles.
During library unavailability at most three fixed bootstrap warnings are printed.

NUI pages load the shared adapter before their application script:

```html
<script src="https://cfx-nui-kora_lib/modules/logging/adapters/browser.js"></script>
```

The page-owning resource includes, after its Kora proxy:

```lua
client_script '@kora_lib/modules/logging/nui.lua'
```

Use the same `globalThis.KoraLogger` API in the browser. Type declarations ship
beside the adapter; consumer copies must match it. Browser-local output is
sanitized and remains available in previews. A single page-ready callback
receives capture state; subsequent updates are events, not polling. Only enabled
captures forward through the consumer-local callback and normal client queue.
Browser requests are bounded and have at most four in flight.

`Kora.logging.nui(level, eventName, message, fields)` is the client bridge's
entrypoint; `Kora.logging.getCapture()` returns its current non-secret state.
These are integration APIs, not gameplay authorization. The consumer-local
callback is intentional: exporting `Kora.nui.registerCallback` would register in
the library's frame instead of the consuming page. Raw callback/message natives
are limited to this transport adapter. No focus or UI is created.

## Validation and migration boundaries

Run `test/run.sh` for Lua coverage and `node --test test/logging_adapters.test.cjs`
for browser/server adapter tests. Mocked checks cover format/filtering, redaction,
legacy contracts, authorization, forged identities, expiry, queue limits and
restart cleanup. Verify console/F8 styling, NUI transport and extraction from real
FiveM/Docker output in a separately authorized manual session.

This resource uses the logger for diagnostics. Other resources can adopt it independently. Explicit console reports (SQL inspection,
permission reports, creator command replies), pure development tools, upstream
queue implementation and pre-library theme/loading bootstrap messages retain
local output. Do not indiscriminately replace prints in third-party code or
redirect durable audit rows into this best-effort stream. Engine-generated
errors and arbitrary browser console calls are not intercepted.

## Independent rollout and compatibility

Deploy this library without changing dependent resources. Existing
`Kora.logging.event(category, src, data)`, `getStats()`, core forwarding exports,
and variadic `Kora.print.debug/info/warn/error/success(...)` remain supported.
Existing raw `print` and browser console calls continue unchanged and are not
captured automatically. No database migration or coordinated resource release
is required; durable domain audits remain independent.

Compatibility covers API calls, not byte-for-byte output: `Kora.print.debug`
is filtered at the default info threshold, success maps to info, output styling
changes, and fields are sanitized, redacted and bounded. Existing event counters
and webhook settings remain supported. The 500-entry debugging ring is shared
with new diagnostic records, so ringSize no longer counts only domain events.

Adopt the new severity API resource by resource after this library is installed.
NUI adoption additionally needs the browser script and consumer-local Lua bridge.
A resource using those new APIs/assets requires this logger version; rolling the
library back first would remove that capability. No dependent-resource migration
is part of this library-only rollout. Leave capture disabled unless debugging.

## Manual FiveM acceptance (not run by offline tests)

1. In a development instance, configure `setr kora_logging_format dual` and
   `setr kora_logging_level info`. Trigger a known diagnostic on server and client.
   Confirm readable level colors in FXServer/F8 and one compact `KORA_LOG` JSON
   line per enabled call; debug stays filtered by default.
2. Run `kora_log_capture start 42 kora_hud debug 60` for a connected tester.
   Trigger HUD Lua and browser diagnostics. Confirm only that player/resource is
   received, with `realm=client`/`nui`, server-assigned player/capture identity,
   and debug records accepted even when the local threshold is info.
3. Run `kora_log_capture status`, then `kora_log_capture stop 42`. Repeat using
   expiry, disconnect/reconnect, selected-resource restart and library restart.
   Confirm old queued records never appear in a new capture. Check an unauthorized
   player cannot start or stop capture.
4. With capture disabled, use the client profiler/network monitor to confirm no
   logging flush timer or client-to-server batch traffic. With capture enabled,
   generate a bounded diagnostic burst and inspect drop counters and local
   overflow warnings; gameplay must remain responsive. Confirm the browser bridge
   recovers after a library restart without reloading its page.
5. Save actual console output externally, strip the transport prefix through
   `KORA_LOG `, and parse the remaining line as JSON. Check server and forwarded
   records, escaped multiline messages, redacted fields, byte bounds and absence
   of color escapes. Ignore pretty lines to avoid double-counting in dual mode.

This checklist requires a separately authorized live development session; no
server start, deployment, database migration or collector installation is needed
for the offline checks.

References: [OpenTelemetry log model](https://opentelemetry.io/docs/specs/otel/logs/data-model/),
[OWASP logging guidance](https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html).

Copyright © 2026 Kora Framework.
