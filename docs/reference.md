---
title: API index
permalink: /reference/
---

# API index

Every public qblib namespace has a reference page. Each page is generated from the `docs.md` file beside its implementation, and every normal exported function is checked against both that guide and `types.lua` by the test suite.

## Core

- [Cache]({{ site.baseurl }}/reference/cache/) — fast local-player state and consumer-owned cached values
- [Configuration]({{ site.baseurl }}/reference/config/) — typed, owner-editable resource settings
- [Callbacks]({{ site.baseurl }}/reference/callback/) — promise-based client/server request and response
- [Events]({{ site.baseurl }}/reference/events/) — client/server messages with session correlation and optional rate limits
- [Hash lookup]({{ site.baseurl }}/reference/lookup/) — GTA model, weapon, component, object, ped, and pickup names
- [Locales]({{ site.baseurl }}/reference/locales/) — language selection, lookup, and interpolation
- [Resources]({{ site.baseurl }}/reference/resources/) — owner tracking and automatic cleanup registries
- [State bags]({{ site.baseurl }}/reference/state/) — normalized state-bag subscriptions
- [Streaming]({{ site.baseurl }}/reference/stream/) — models, animation data, effects, textures, audio, and collision

## Interface and player input

[Controls]({{ site.baseurl }}/reference/controls/), [instructional buttons]({{ site.baseurl }}/reference/instructional/), [interactions]({{ site.baseurl }}/reference/interact/), [keybinds]({{ site.baseurl }}/reference/keybind/), [minigames]({{ site.baseurl }}/reference/minigames/), [NUI]({{ site.baseurl }}/reference/nui/), [notifications]({{ site.baseurl }}/reference/notify/), [progress bars]({{ site.baseurl }}/reference/progressbar/), [text UI]({{ site.baseurl }}/reference/textui/), and [theme]({{ site.baseurl }}/reference/theme/).

## World and entities

[Animations]({{ site.baseurl }}/reference/anim/), [blips]({{ site.baseurl }}/reference/blips/), [camera overlays]({{ site.baseurl }}/reference/camera/), [closest-entity helpers]({{ site.baseurl }}/reference/closest/), [distance checks]({{ site.baseurl }}/reference/distancecheck/), [drawing]({{ site.baseurl }}/reference/drawing/), [developer editors]({{ site.baseurl }}/reference/editor/), [entities]({{ site.baseurl }}/reference/entities/), [effects]({{ site.baseurl }}/reference/fx/), [freecam]({{ site.baseurl }}/reference/freecam/), [placement]({{ site.baseurl }}/reference/placement/), [raycasts]({{ site.baseurl }}/reference/raycast/), [sound]({{ site.baseurl }}/reference/sound/), [teleporting]({{ site.baseurl }}/reference/teleport/), [vehicles]({{ site.baseurl }}/reference/vehicle/), [visual effects]({{ site.baseurl }}/reference/visuals/), [world queries]({{ site.baseurl }}/reference/world/), and [zones]({{ site.baseurl }}/reference/zones/).

## Gameplay and server systems

[Actions]({{ site.baseurl }}/reference/actions/), [commands]({{ site.baseurl }}/reference/commands/), [Discord]({{ site.baseurl }}/reference/discord/), [logging]({{ site.baseurl }}/reference/logging/), [permissions]({{ site.baseurl }}/reference/permissions/), [rewards]({{ site.baseurl }}/reference/rewards/), [screenshots]({{ site.baseurl }}/reference/screenshot/), [skills]({{ site.baseurl }}/reference/skills/), and [status effects]({{ site.baseurl }}/reference/status/).

## Utilities and compatibility

[Loops]({{ site.baseurl }}/reference/loops/), [print helpers]({{ site.baseurl }}/reference/prints/), [random selection]({{ site.baseurl }}/reference/random/), [require]({{ site.baseurl }}/reference/require/), [timers]({{ site.baseurl }}/reference/timers/), and [general utilities]({{ site.baseurl }}/reference/util/).

The [ox_lib provider]({{ site.baseurl }}/reference/ox/) is primarily an implementation contract for the separate compatibility resource. Most consumers should start with the [ox_lib migration guide]({{ site.baseurl }}/migration/ox-lib/) instead.
