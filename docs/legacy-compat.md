---
title: Legacy resource compatibility
permalink: /legacy-compat/
---

# Legacy resource compatibility

qblib can replace several older standalone resources while consumers migrate to the native `QB` APIs. Its manifest uses `provide` so dependency checks succeed, and its compatibility bridge registers exports under each legacy resource identity.

Compatibility providers can use
`QB.compat.provideExport(resourceName, exportName, callable)` in either realm.
It registers the hidden CFX export event that `provide` alone does not create;
the callable may be a Lua function or a FiveM funcref. Registration executes
inside the consuming resource, so the alias handler stops with its provider
instead of surviving as a stale qblib-owned reference.

These bridges preserve the documented call shape, but they cannot reproduce behavior for which qblib has no equivalent. Review the caveats below before removing the original resource.

## qb-menu

Provided client exports:

```lua
exports['qb-menu']:openMenu(items)
exports['qb-menu']:closeMenu()
exports['qb-menu']:showHeader(items)
```

The legacy `qb-menu:client:openMenu` and `qb-menu:client:closeMenu` events are also handled. Menus render through `QB.nui.openMenu`. Legacy Font Awesome class names are not qblib's Lucide icon names, so unsupported icons are dropped. See the [NUI reference]({{ site.baseurl }}/reference/nui/) for the field mapping and dispatch rules.

## qb-input

Provided client export:

```lua
local values = exports['qb-input']:ShowInput(definition)
```

The bridge maps supported text, number, password, radio, select, and checkbox fields to `QB.nui.openInputDialog`. Radio groups become selects, a checkbox group becomes individual booleans, and Font Awesome icons are dropped. Cancellation returns `nil`.

## qb-radialmenu

Provided client exports:

```lua
exports['qb-radialmenu']:AddOption(option, id)
exports['qb-radialmenu']:RemoveOption(id)
```

The bridge keeps a registry and opens a qblib radial menu from its F1 keybind. qblib's radial menu is a one-shot interaction rather than a permanently open global menu, and it does not use screen coordinates. Unsupported icon names are dropped. Nested items and standard client/server command or event actions are translated at selection time.

## qb-minigames

Provided client exports:

```lua
exports['qb-minigames']:Hacking(...)
exports['qb-minigames']:KeyMinigame(...)
exports['qb-minigames']:Lockpick(...)
exports['qb-minigames']:StartPinpad(...)
exports['qb-minigames']:Quiz(...)
exports['qb-minigames']:Skillbar(...)
exports['qb-minigames']:WordGuess(...)
exports['qb-minigames']:WordScramble(...)
```

Calls render through `QB.minigames.play`. These legacy client-only calls do not mint a server-consumable proof; use qblib's authorization flow when success gates a valuable server action. Lockpick and Skillbar have documented mechanic differences. See [Minigames]({{ site.baseurl }}/reference/minigames/) for signatures and result mapping.

## screenshot-basic

Provided client exports:

```lua
exports['screenshot-basic']:requestScreenshot(options, callback)
exports['screenshot-basic']:requestScreenshotUpload(url, field, options, callback)
```

The bridge uses qblib's on-demand capture path. It captures the FiveM game render target; separate CEF/NUI layers cannot be included. See [Screenshots]({{ site.baseurl }}/reference/screenshot/) for encodings, size limits, upload behavior, and the security boundary around server filenames.

## Optional named-import resources

qblib itself does not require `ox_lib` or `PolyZone`. Keep both stopped unless
an installed resource explicitly imports one of their files in its manifest:

```lua
shared_script '@ox_lib/init.lua'
-- or
client_script '@PolyZone/client.lua'
```

`provide` cannot satisfy either import: FiveM resolves `@resource/file` by the
actual started resource name. In that case, start the matching qblib-backed
compatibility resource after `qblib` and before the importing resource. The
installed folder must therefore retain the exact `ox_lib` or `PolyZone` resource
name from the importing manifest; do not rename it to a project-specific name.
The optional `ox_lib` resource provides the complete pinned
[ox_lib 3.39.0 surface]({{ site.baseurl }}/migration/ox-lib/); `PolyZone`
targets PolyZone 2.6.2 and provides `client.lua`, BoxZone, CircleZone,
EntityZone, and ComboZone over qblib's zone engine. Static shapes use
`QB.zones`; EntityZone uses model-local containment so it follows a moving or
rotating entity without rebuilding grid entries. `destroy()`/`remove()` stops
any transition or custom-point polling owned by that wrapper. Native qblib
resources should use `QB.nui` and `QB.zones` directly; `QB.ox` is private to
the optional `ox_lib` bridge.

### PolyZone bridge coverage

Import wrapper files in the same order as upstream PolyZone. A consumer that
uses every shape needs this manifest order:

```lua
client_scripts {
    '@PolyZone/client.lua',
    '@PolyZone/BoxZone.lua',
    '@PolyZone/EntityZone.lua',
    '@PolyZone/CircleZone.lua',
    '@PolyZone/ComboZone.lua',
    'client.lua',
}
```

| Legacy surface | qblib-backed behavior |
| --- | --- |
| `PolyZone`, `BoxZone`, `CircleZone` | Containment, `onPlayerInOut`, `onPointInOut`, pausing, `addEvent`/`removeEvent`, debug blips, manual `draw(forceDraw)`, and destruction. PolyZones and BoxZones without explicit `minZ`/`maxZ` remain XY-only; flat CircleZones use qblib's exact shared-grid 2D circle; `useZ = true` uses a 3D sphere. Both preserve PolyZone's exclusive radius boundary. PolyZones retain bounding-box fields, `drawPoly`, and `ensureMetatable`; BoxZones retain heading, mutable size/center helpers, directional `scale`/`offset`, points/`TransformPoint`, and legacy geometry helpers. |
| `EntityZone` | Moving model-bounds containment, validated player-transition polling, damage callbacks, and on-demand current-bounds drawing. Its debug blip follows the entity. |
| `ComboZone` | Child-backed containment with no duplicate zone registration; dynamic add/remove, exhaustive containment/transition APIs, optional event filtering by child name, child debug blips, `draw(forceDraw)`, and `printInfo()`. |

The bridge keeps expensive work opt-in: normal static zones stay in qblib's
shared spatial grid; ComboZone reuses its children and adds only a lightweight
reference grid for static candidate lookup (moving children remain fallback
candidates); polling only begins when a legacy polling API is explicitly
called; and entity/debug updates only run while those optional features are active. It is
a migration aid, not a reason to add PolyZone to a new qblib resource.
Every shape also accepts PolyZone's `debugBlip = true` creation option (and
rejects non-boolean values). It creates only the requested blip; it does not
enable general zone rendering. Use the shared-grid `onPlayerInOut(callback)`
form for static zones; an explicit finite, non-negative `waitInMS` starts a
per-zone legacy poll and should be reserved for timing compatibility.

For example, add only the wrapper your installed resource needs:

```cfg
ensure qblib
ensure ox_lib  # only for @ox_lib/... imports or ox_lib API callers

# or:
ensure qblib
ensure PolyZone # only for @PolyZone/... imports
```

Do not enable either line pre-emptively. Keep the importing resource after its
wrapper, and remove the wrapper again once the final consumer has migrated to
the native `QB` API. Default configurations must use explicit resource lines,
not broad `ensure [test]` or `ensure [compat]` group starts, because those
groups can also start optional wrappers.

### Verify an optional wrapper

Before enabling a wrapper for a legacy resource, run its contract suite from
the server workspace:

```sh
bash resources/[compat]/PolyZone/test/run.sh
(cd resources/[test]/ox_lib && bash test/run.sh)
```

The PolyZone suite exercises the wrapper's legacy shape/method behavior. The
ox_lib suite compares its vendored upstream files and resource exports against
the declared ox_lib release. These checks validate compatibility coverage; they
do not make either resource a default dependency.

## Migration order

1. Start qblib in a test environment while the consumer still uses its legacy calls.
2. Exercise every menu, input, radial action, minigame, or screenshot path the resource owns.
3. Check the relevant mapping caveats above.
4. Replace legacy calls with native `QB.nui`, `QB.minigames`, or `QB.screenshot` calls when you need a qblib-only capability.
5. Remove the standalone legacy resource only after all consumers work through qblib's provided identity.
