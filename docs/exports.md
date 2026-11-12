---
title: Exports
sidebar_position: 10
---

# Exports

`build/finalise.lua` loops over the `Kora` table after every module has loaded and registers one export per function:

| `Kora` form | Export name |
| --- | --- |
| `Kora.foo(...)` (a top-level function) | `exports.kora_lib:foo(...)` |
| `Kora.stream.loadModel(...)` | `exports.kora_lib:stream_loadModel(...)` |

The `compat` table is skipped, so it is not exported. Which functions exist in which realm is stated on each page of the [API index](./reference.md). In Lua, prefer the `Kora.<module>.<function>` proxy loaded by `@kora_lib/init.lua` (see [Using the API](./using-the-api.md)); direct exports are for non-Lua callers.

Some modules run inside the consuming resource instead of being exported (`Kora.require`, `Kora.config`, `Kora.compat`, `Kora.util`, `Kora.loops`, and client-side `Kora.stream`); `init.lua` loads them from the files listed in `fxmanifest.lua`.

## Configuration bridge exports

The configuration editor calls `kora_lib_configRead`, `kora_lib_configCommit` and `kora_lib_configReset` on resources that use `Kora.config`. See [Configuration module](./api/config.md).

## Provided legacy exports

Under other resource identities (through `provide` and `Kora.compat.provideExport`), kora_lib serves exports for `qb-menu`, `qb-input`, `progressbar`, `qb-radialmenu`, `qb-minigames` and `screenshot-basic`. They are listed in [Legacy compatibility](./legacy-compat.md).
