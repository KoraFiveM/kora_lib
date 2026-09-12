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

## Migration order

1. Start qblib in a test environment while the consumer still uses its legacy calls.
2. Exercise every menu, input, radial action, minigame, or screenshot path the resource owns.
3. Check the relevant mapping caveats above.
4. Replace legacy calls with native `QB.nui`, `QB.minigames`, or `QB.screenshot` calls when you need a qblib-only capability.
5. Remove the standalone legacy resource only after all consumers work through qblib's provided identity.
