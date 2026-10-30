---
title: kora_lib documentation
permalink: /
---

<div class="hero" markdown="1">

# Build FiveM resources without rebuilding the basics

{: .tagline }
kora_lib is the shared utility layer for the qbcore2 resource set. It provides a typed `QB` API for interface components, world interaction, entities, streaming, callbacks, permissions, configuration, and the other foundations most resources need.

[Install kora_lib]({{ site.baseurl }}/getting-started/){: .button }
[Browse the API]({{ site.baseurl }}/reference/){: .button .secondary }

</div>

## What you get

- **One consistent API.** Consumer resources load `@kora_lib/init.lua` and call namespaced helpers such as `QB.notify.send`, `QB.zones.sphere`, and `QB.callback.trigger`.
- **Client, server, and shared modules.** Every reference page labels the realm where an operation is available.
- **Resource ownership.** Long-lived registrations are associated with the resource that created them and cleaned up when it stops.
- **Typed contracts.** [`types.lua`](https://github.com/qbcore2/kora_lib/blob/main/types.lua) describes functions, options, handles, callbacks, and return values for Lua language servers.
- **Headless interface components.** Menus, prompts, notifications, progress bars, apps, and minigames use kora_lib's shared NUI without holding focus while idle.
- **Migration bridges.** kora_lib can satisfy legacy `qb-menu`, `qb-input`, `qb-radialmenu`, `qb-minigames`, and `screenshot-basic` consumers, and documents its ox_lib compatibility boundary.

## Start with the job

| If you need to… | Start here |
| --- | --- |
| Let a player interact with a location or entity | [Interactions]({{ site.baseurl }}/reference/interact/), [zones]({{ site.baseurl }}/reference/zones/), and [text UI]({{ site.baseurl }}/reference/textui/) |
| Show feedback or collect input | [Notifications]({{ site.baseurl }}/reference/notify/), [progress bars]({{ site.baseurl }}/reference/progressbar/), [NUI]({{ site.baseurl }}/reference/nui/), and [minigames]({{ site.baseurl }}/reference/minigames/) |
| Find, spawn, modify, or move something in the world | [World queries]({{ site.baseurl }}/reference/world/), [entities]({{ site.baseurl }}/reference/entities/), [vehicles]({{ site.baseurl }}/reference/vehicle/), and [teleporting]({{ site.baseurl }}/reference/teleport/) |
| Exchange client and server data safely | [Callbacks]({{ site.baseurl }}/reference/callback/), [events]({{ site.baseurl }}/reference/events/), [state bags]({{ site.baseurl }}/reference/state/), and [permissions]({{ site.baseurl }}/reference/permissions/) |
| Give resource owners safe editable settings | [Configuration]({{ site.baseurl }}/reference/config/) |
| Build a server-authoritative gameplay flow | [Actions]({{ site.baseurl }}/reference/actions/), [rewards]({{ site.baseurl }}/reference/rewards/), [skills]({{ site.baseurl }}/reference/skills/), and [status effects]({{ site.baseurl }}/reference/status/) |
| Replace an existing qb or ox_lib dependency | [Legacy compatibility]({{ site.baseurl }}/legacy-compat/) and the [ox_lib migration guide]({{ site.baseurl }}/migration/ox-lib/) |

The [API index]({{ site.baseurl }}/reference/) remains the complete alphabetical-by-domain reference. Each module page states its available realms, parameters, return values, lifecycle behavior, and examples.

## Quick example

Add kora_lib to a consumer resource:

```lua
dependency 'kora_lib'
shared_script '@kora_lib/init.lua'
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

The proxy lazily loads stateless helpers and client streaming functions inside
the consumer; stateful modules resolve to kora_lib's generated exports. You
normally use the `QB` form either way. Direct exports remain available when a
language cannot load the Lua proxy.

## Where to go next

1. Follow [Installation]({{ site.baseurl }}/getting-started/) to add kora_lib and its required `kora_theme` dependency.
2. Read [Using the API]({{ site.baseurl }}/using-the-api/) for realms, return values, asynchronous calls, ownership, and direct exports.
3. Read [Performance and lifecycle]({{ site.baseurl }}/performance/) before building a hot-path feature or adding a compatibility wrapper.
4. Open the [API index]({{ site.baseurl }}/reference/) and choose the module for the task at hand.

If you are migrating an existing resource, check [legacy compatibility]({{ site.baseurl }}/legacy-compat/) or the [ox_lib migration notes]({{ site.baseurl }}/migration/ox-lib/) before changing calls.
