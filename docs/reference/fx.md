---
title: "Effects module"
sidebar_position: 28
---

# Effects module

Client-side, owner-tracked particle and screen effects.

## `Kora.fx.playPtfx(def)`

Streams `def.dict` and starts `def.name` at `def.entity` or `def.coords`.
Options include `bone`, finite `offset`/`rot` components and `scale`, `looped`, and a looped-effect
`duration` (a finite non-negative integer in milliseconds). Returns a serializable handle, or `false, error` when streaming or
startup fails.

When supplied, `entity` is a positive finite integer, `bone` is a string, and `looped`
is boolean. `offset`, `rot`, and `scale` default only when omitted; malformed
explicit values are rejected before kora_lib streams an asset or calls a native.

## `Kora.fx.stop(handle)`

Stops a tracked looped particle handle created by the calling resource.
Non-looped effects finish naturally.

## `Kora.fx.screenEffect(name, duration?, looped?)`

Starts a native screen effect and returns an opaque per-call handle. Calls that
use the same native effect name are reference-counted so one caller cannot stop
another caller's still-live effect. `duration` is a finite non-negative integer
in milliseconds; omit it or pass `0` for the native default. `looped`, when
supplied, must be boolean.

## `Kora.fx.stopScreenEffect(handle)`

Releases a tracked screen-effect handle created by the calling resource and
stops the native effect after its final same-name handle is released. Each
invoking resource's handles are released automatically when that resource
stops. Retain the returned handle; legacy `{ name = "..." }` handles remain
accepted, but can release only one matching handle owned by the calling
resource.
