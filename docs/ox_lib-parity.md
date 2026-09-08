---
layout: default
title: ox_lib parity
---

# ox_lib parity

This matrix was reviewed against ox_lib 3.39.0 at commit
[`b8f5a043`](https://github.com/overextended/ox_lib/tree/b8f5a04351b1d427e0e112150d36094e9889ec7b)
(2026-09-04). “Partial” means qblib offers related functionality, not that an
ox_lib call can be renamed and used unchanged.

qblib is not a drop-in ox_lib replacement. qblib exposes cross-resource
`QB.<module>.<function>` calls; ox_lib installs consumer-local `lib` and `cache`
surfaces. Preserve the qblib contracts for existing qbcore2 callers and use a
purpose-built adapter when migrating an ox resource.

| ox_lib area | qblib area | Parity | Important difference |
|---|---|---|---|
| callbacks | `QB.callback` | Partial | Different signatures, throttling, timeout and error model. |
| cache | `QB.cache` | Partial | Different keys and refresh/computed-cache behavior. |
| keybinds / commands | `QB.keybind`, `QB.commands` | Partial | Different handles and command registration model. |
| alert, context, menu, radial | `QB.nui` | Partial | qblib uses one-shot definitions rather than ox registries/show-hide APIs. |
| input dialog | `QB.nui.openInputDialog` | Partial | Different result shape; date, time and color inputs are absent. |
| notifications | `QB.notify` | Partial | Different payload, positions, deduplication, styling and sound features. |
| progress bar / circle | `QB.progressbar` | Partial | No progress circle; option names and interruption rules differ. |
| skill check / games | `QB.minigames` | Partial | Server-proof flow and mechanics differ; see the module's compatibility notes. |
| text UI | `QB.textui` | Partial | Owner-safe handles, but a smaller style/icon surface. |
| clipboard / focus | `QB.nui` | Partial | Clipboard behavior is close; focus is lease-based and intentionally different. |
| raycast | `QB.raycast` | Partial, incompatible | qblib argument order and positional results differ and omit material hash. |
| zones / points | `QB.zones` | Partial, incompatible | qblib point is a small sphere; polygon thickness grows upward from the lowest point. |
| closest / world helpers | `QB.world`, `QB.closest` | Partial | Defaults, filtering and return shapes differ. |
| streaming / animation | `QB.stream`, `QB.anim` | Partial | Different lifetime, timeout and failure behavior. |
| entities / vehicles | `QB.entities`, `QB.vehicle` | Partial | No ox entity classes/server constructors; vehicle property schema differs. |
| timers | `QB.timers` | Partial | Cron is absent. |
| locale | `QB.locale`, `QB.lang` | Partial | Loading, flattening and cross-resource behavior differ. |
| hooks / authorization | `QB.state` | Missing equivalent | qblib subscriptions do not implement ox's hook pipeline. |
| markers, DUI, scaleform helpers | — | Missing | Scaleform loading exists, but not the higher-level ox helpers. |
| collections and data structures | `QB.util` subset | Partial | ox array/map/set/heap/LRU/ringbuffer and related helpers are absent. |
| RedM | — | Out of scope | This resource targets GTA V/FiveM. |

## Migration hazards

- Do not call `QB.raycast.fromCamera` with ox_lib's `(flags, ignore, distance)`
  order. qblib takes `(maxDistance, flags, ignoreEntity)` and returns
  `hit, coords, entity, normal`.
- Do not exchange vehicle-property snapshots without normalization. Extras and
  several named fields have different semantics. qblib's setters deliberately
  preserve the established QBCore schema.
- Do not assume zone thickness is centered around a polygon plane. Use explicit
  `minZ` and `maxZ` when migrating a zone that depends on that geometry.
- qblib's `QB.zones.point` is proximity through a small sphere, not ox_lib's
  full point object with nearby-point enumeration.
- Compatibility providers should translate at their boundary. The bundled
  qbinventory ox provider is an example: it normalizes notification positions,
  progress props/scenarios and multi-select input rows without changing native
  qblib callers.

Full parity would require new modules and compatibility contracts, not a safe
in-place rename. Add those surfaces incrementally with contract tests and
atomic caller migrations.
