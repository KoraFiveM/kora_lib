# kora_lib

Lightweight, typed building blocks for FiveM resources in the qbcore2 ecosystem.

kora_lib exposes interface components, callbacks, events, configuration, permissions, world queries, entities, zones, streaming, and other shared utilities through a single `Kora.<module>.<function>` API.

## Install

Start `kora_theme` before kora_lib:

```cfg
ensure kora_theme
ensure kora_lib
```

New kora_lib resources do not need `ox_lib` or `PolyZone`. Do not ensure either
compatibility resource by default; install and start one only when an unchanged
legacy manifest imports `@ox_lib/...` or `@PolyZone/...`.

Load the proxy from each consumer resource:

```lua
dependency 'kora_lib'
shared_script '@kora_lib/init.lua'
```

## Documentation

Read the complete documentation at **[qbcore2.github.io/kora_lib](https://qbcore2.github.io/kora_lib/)**.

- [Installation](https://qbcore2.github.io/kora_lib/getting-started/)
- [Using the API](https://qbcore2.github.io/kora_lib/using-the-api/)
- [API reference](https://qbcore2.github.io/kora_lib/reference/)
- [Performance and lifecycle](https://qbcore2.github.io/kora_lib/performance/)
- [Legacy compatibility](https://qbcore2.github.io/kora_lib/legacy-compat/)
- [ox_lib migration](https://qbcore2.github.io/kora_lib/migration/ox-lib/)

The resource also ships LuaLS declarations in `types.lua`. Module guides live beside their implementations and are checked against the public API by the test suite.

## Development

Run all Lua smoke and contract tests with:

```sh
test/run.sh
```

Prepare the GitHub Pages source locally with:

```sh
docs/build.sh
```
