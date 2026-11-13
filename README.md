> [!WARNING]
> **Kora Framework is in alpha and actively being developed.**
>
> This resource is a work in progress. Features may be incomplete or unstable,
> and APIs, configuration, and behavior may change. It is not ready for production use.
>
> **Help shape Kora:** try it out, share feedback, report bugs through this
> repository’s Issues, and contribute improvements through pull requests.

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

The documentation source lives in `docs/` (start at `docs/index.md`).

Published on the Kora documentation site, and readable directly in the repository:

- [Installation](docs/installation.md)
- [Using the API](docs/using-the-api.md)
- [API reference](docs/reference.md)
- [Performance and lifecycle](docs/performance.md)
- [Legacy compatibility](docs/legacy-compat.md)
- [ox_lib migration](docs/migration/ox-lib.md)

The resource also ships LuaLS declarations in `types.lua`. Module guides live beside their implementations and are checked against the public API by the test suite.

## Logging

Use [Kora.logging](modules/logging/docs.md) for server/client diagnostics,
optional targeted client capture, JavaScript/NUI adapters and structured console
export. `Kora.print` and legacy event APIs remain compatibility adapters.

## Development

Run all Lua smoke and contract tests with:

```sh
test/run.sh
```
