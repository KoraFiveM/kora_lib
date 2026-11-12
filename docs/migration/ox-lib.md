---
title: ox_lib compatibility
sidebar_position: 1
---

# ox_lib compatibility

The optional `ox_lib` compatibility resource is a drop-in FiveM surface for
ox_lib 3.39.0, pinned to official Overextended commit
[`b8f5a043`](https://github.com/overextended/ox_lib/tree/b8f5a04351b1d427e0e112150d36094e9889ec7b)
(2026-09-04). Existing resources keep their normal manifest import:

```lua
shared_script '@ox_lib/init.lua'
```

They also keep using `lib`, `cache`, `SetInterval`, `ClearInterval`, and
`exports.ox_lib` without source changes. Start resources in this order:

```text
kora_theme
kora_lib
ox_lib
consumer resources
```

`ox_lib` is optional: kora_lib and native kora_lib resources do not require or start
it. Enable this compatibility resource only when an installed dependency uses
`@ox_lib/...` imports or the ox_lib API.

## Start order and ox_lib identity

Full start order when the compatibility layer and oxmysql shims are in use:

```text
kora_theme
kora_lib
kora_sql
[compat]/oxmysql
ox_lib          (the shim; needs kora_lib started)
consumers       (ox_inventory, ...)
```

kora_lib never provides `ox_lib`: no `provide 'ox_lib'` in `fxmanifest.lua`, no
`compat.provideExport('ox_lib', ...)`, and no `ox_lib:*`, `__ox_cb_*`,
`__ox_notify_*` or `__cfx_export_ox_lib_*` handlers. The `ox_lib` resource owns
that identity; a second registration would run handlers twice and let
`dependency 'ox_lib'` resolve without the shim started. The shim reaches kora_lib
through the allowed `exports.kora_lib:ox_*` forwarding exports.
`test/smoke/ox_identity_guard.lua` enforces this.

## Architecture

FiveM resolves `@ox_lib/init.lua` by the resource's actual name, so kora_lib's
`provide` directive cannot replace it. The separate `ox_lib` resource owns
the import loader and resource-local state. Its consumer modules, collections,
callbacks, cache, zones, points, streaming helpers, vehicle properties,
locale files, settings, ACL, hooks, and other non-UI behavior are the pinned
upstream implementation.

The browser-facing alert, context, input, list menu, notification, progress,
radial, skill-check, TextUI, clipboard, and focus contracts are forwarded to
`Kora.ox` in kora_lib. This preserves a single NUI document, composable focus
leases, and owner-scoped cleanup instead of running a second permanent UI.
The bridge retains the original consuming resource name so stopping one script
only removes that script's registrations and active interactions.

## Compatibility guarantees

- All 50 resource-owned ox_lib 3.39.0 exports are present in their correct
  client/server realms.
- The upstream lazy module names and manifest metadata imports remain valid.
- UI registries, return values, live menu callbacks, cancellation, non-closing
  options, progress circles, temporal fields, nested radial state, and
  per-resource lifecycle cleanup are translated at the provider boundary.
- Existing kora_lib APIs are unchanged; the ox bridge is additive.
- Pinned-file hashes, export inventory, import behavior, provider behavior,
  Lua syntax, TypeScript types, UI tests, and startup order are checked by the
  repository test suites.

The exhaustive frozen contract and audit checklist live in
[the ox_lib 3.39.0 contract inventory](../migration/ox-lib-contract.md). When ox_lib
is upgraded, update that inventory, the pinned hash manifest, compatibility
tests, and this document together.

## Test-server caller audit

The vendored `resources/[test]` workspace had zero executable ox_lib callers
outside kora_lib and the compatibility resource when this bridge was added. A
few `kora_inventory` comments describe the upstream API for its existing adapter;
they do not execute `lib.*`. Repeat the audit with these exact patterns when a
resource is added or migrated:

```sh
rg -n -g '*.lua' -g 'fxmanifest.lua' -g '__resource.lua' \
  -g '!**/kora_lib/**' -g '!**/ox_lib/**' \
  "@ox_lib/init\\.lua|exports(\\[['\"]ox_lib['\"]\\]|\\.ox_lib)|dependency[[:space:]]+['\"]ox_lib['\"]|provide[[:space:]]+['\"]ox_lib['\"]|['\"]ox_lib:" \
  'resources/[test]'

rg -n -P -g '*.lua' -g '!**/kora_lib/**' -g '!**/ox_lib/**' \
  "(?<![.[:alnum:]_])(?:lib\\.(?:alertDialog|inputDialog|registerContext|showContext|registerMenu|showMenu|notify|progressBar|progressCircle|registerRadial|showRadialMenu|skillCheck|showTextUI|callback|zones|points|addKeybind|locale)|cache\\.(?:playerId|serverId|ped|vehicle|seat|weapon|coords|resource|game))" \
  'resources/[test]'
```

## Licensing

The compatibility resource includes its LGPL-3.0-or-later license and notice.
Pinned upstream files retain their original headers and are distributed as
source. kora_lib's provider code is a separately maintained adapter.
