# tools/parity

Regex-based API-surface tooling for the ox_lib compatibility work. Plain Lua 5.4, no network, no dependencies. Snapshots hold names and counts only.

```sh
lua5.4 tools/parity/extract_ox_surface.lua <ox_lib dir>  > surface.json   # lib keys, exports by realm, events, convars, NUI, manifest
lua5.4 tools/parity/extract_ox_uses.lua    <consumer dir> > uses.json      # lib.*, cache.*, require/lib.load, exports.ox_target, MySQL.* counts
lua5.4 tools/parity/diff.lua golden/ox_lib-3.39.0.json surface.json [--fail-on missing|extra|both] [--soft prefix,prefix]
```

`golden/` holds the committed snapshots (`ox_lib-3.39.0.json`, `ox_inventory-2.48.1-uses.json`). Regenerate a golden only on a reviewed version bump. `test/smoke/ox_surface.lua` self-tests the tools on `test/fixtures/` and, when `OX_LIB_SHIM_PATH` / `OX_INVENTORY_PATH` are set, diffs those trees against the goldens (otherwise it prints "ok - skipped").

## Limits

- Extraction is regex-only. Dynamic assignments that regex cannot see (computed export names, `__newindex` auto-exports outside the `function lib.X` / `lib.X =` forms) are missed.
- No dynamic check: upstream `imports/**` uses CfxLua syntax (`?.`, compound assignment, `<const>`-style extensions) that stock Lua 5.4 cannot parse, so loading them under `test/mocks.lua` would need a CfxLua-to-Lua transpile or stubbing each file (the shim's own `test/compat.lua` stubs `require` for that reason). It stays out of scope here; run an FXServer-backed check instead.
