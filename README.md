# qblib

Lightweight, typed building blocks for FiveM resources in the qbcore2 ecosystem.

qblib exposes interface components, callbacks, events, configuration, permissions, world queries, entities, zones, streaming, and other shared utilities through a single `QB.<module>.<function>` API.

## Install

Start `qbtheme` before qblib:

```cfg
ensure qbtheme
ensure qblib
```

Load the proxy from each consumer resource:

```lua
dependency 'qblib'
shared_script '@qblib/init.lua'
```

## Documentation

Read the complete documentation at **[qbcore2.github.io/qblib](https://qbcore2.github.io/qblib/)**.

- [Installation](https://qbcore2.github.io/qblib/getting-started/)
- [Using the API](https://qbcore2.github.io/qblib/using-the-api/)
- [API reference](https://qbcore2.github.io/qblib/reference/)
- [Legacy compatibility](https://qbcore2.github.io/qblib/legacy-compat/)
- [ox_lib migration](https://qbcore2.github.io/qblib/migration/ox-lib/)

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
