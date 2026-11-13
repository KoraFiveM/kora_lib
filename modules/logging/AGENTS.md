# Kora logging module guide

Read docs.md for the contract, limits and operational examples. Generic logging
belongs here; domain audit persistence remains with its owning resource.

The unified logging change explicitly supersedes the former server-only module
restriction. Shared helpers own record sanitization, filtering and formatting.
Server code owns the ring, legacy events, Discord mirror and capture authority;
client code owns local output and a bounded, capture-scoped queue. NUI callbacks
must execute in the consuming resource, so nui.lua is an explicit consumer-local
transport exception to the library's normal Kora.nui-only rule.

- Never trust client player IDs, severity filters, resource claims or clocks.
  Use event source and a live server-issued capture generation on every batch.
- Disabled forwarding installs no timers or log queues and sends no network traffic.
- Bound work before JSON decoding/serialization. No unbounded retries, queues,
  per-frame work, payload dumps or arbitrary object stringification.
- Keep internal helpers under logging._internal (a non-exported table). Only
  documented top-level functions may become auto-generated exports.
- Preserve legacy event validation, category/source/data semantics, counters and
  webhook convar precedence. Snapshot/sanitize inputs; never retain caller tables.
- Diagnostics must not recurse when their sink fails. Use bounded fixed-text
  fallback warnings without serializing the exception or original payload.
- Add contract/lifecycle tests with any API/transport change. Keep docs.md,
  types.lua and JavaScript declarations synchronized.

Copyright © 2026 Kora Framework.
