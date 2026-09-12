---
title: qblib documentation
permalink: /
---

<div class="hero" markdown="1">

# Build FiveM resources without rebuilding the basics

{: .tagline }
qblib is the shared utility layer for the qbcore2 resource set. It provides a typed `QB` API for interface components, world interaction, entities, streaming, callbacks, permissions, configuration, and the other foundations most resources need.

[Install qblib]({{ site.baseurl }}/getting-started/){: .button }
[Browse the API]({{ site.baseurl }}/reference/){: .button .secondary }

</div>

## What you get

- **One consistent API.** Consumer resources load `@qblib/init.lua` and call namespaced helpers such as `QB.notify.send`, `QB.zones.sphere`, and `QB.callback.trigger`.
- **Client, server, and shared modules.** Every reference page labels the realm where an operation is available.
- **Resource ownership.** Long-lived registrations are associated with the resource that created them and cleaned up when it stops.
- **Typed contracts.** [`types.lua`](https://github.com/qbcore2/qblib/blob/main/types.lua) describes functions, options, handles, callbacks, and return values for Lua language servers.
- **Headless interface components.** Menus, prompts, notifications, progress bars, apps, and minigames use qblib's shared NUI without holding focus while idle.
- **Migration bridges.** qblib can satisfy legacy `qb-menu`, `qb-input`, `qb-radialmenu`, `qb-minigames`, and `screenshot-basic` consumers, and documents its ox_lib compatibility boundary.

## Quick example

Add qblib to a consumer resource:

```lua
dependency 'qblib'
shared_script '@qblib/init.lua'
```

Then use the global `QB` proxy in the correct realm:

```lua
-- client.lua
QB.notify.send({
    title = 'Vehicle stored',
    message = 'Your vehicle is now in the garage.',
    type = 'success',
})

local prompt
local zone = QB.zones.sphere({
    coords = vector3(215.8, -810.1, 30.7),
    radius = 2.0,
    onEnter = function()
        prompt = QB.textui.show('Open garage', { key = 'E' })
    end,
    onExit = function()
        if prompt then QB.textui.hide(prompt) end
        prompt = nil
    end,
})
```

The proxy resolves `QB.<module>.<function>` to qblib's generated export named `<module>_<function>`. You normally use the `QB` form; direct exports are available when a language cannot load the Lua proxy.

## Where to go next

1. Follow [Installation]({{ site.baseurl }}/getting-started/) to add qblib and its required `qbtheme` dependency.
2. Read [Using the API]({{ site.baseurl }}/using-the-api/) for realms, return values, asynchronous calls, ownership, and direct exports.
3. Open the [API index]({{ site.baseurl }}/reference/) and choose the module for the task at hand.

If you are migrating an existing resource, check [legacy compatibility]({{ site.baseurl }}/legacy-compat/) or the [ox_lib migration notes]({{ site.baseurl }}/migration/ox-lib/) before changing calls.
