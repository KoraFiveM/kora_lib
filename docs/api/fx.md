---
title: "FX"
sidebar_position: 28
---


# FX

Starts tracked client-side particle effects and native screen effects. Handles let the resource that started an effect stop it later. Ownership tracking also cleans up effects when that resource stops, which prevents abandoned looped effects from continuing indefinitely.

Namespace: `Kora.fx` · Source: `modules/fx/client.lua`

## Particle definition fields

Pass one definition table to playPtfx. Supply dict and name, then choose exactly one placement: coords or entity. A `?` after a name means the option is optional.

### playPtfx definition

| Option | Type | Description |
| --- | --- | --- |
| `dict` | string | Required particle asset dictionary to stream, such as core. |
| `name` | string | Required particle effect name inside that dictionary, such as ent_sht_steam. |
| `coords?` | vector3 | World position to play the effect at. Use this placement for an effect not attached to an entity. |
| `entity?` | integer | Positive entity handle to attach the effect to. Use this instead of coords. |
| `bone?` | string | Optional bone name used when the effect is attached to entity. |
| `offset?` | vector3 | Optional finite local offset for an entity-attached effect. Defaults to the origin. |
| `rot?` | vector3 | Optional finite rotation for the effect. Defaults to zero rotation. |
| `scale?` | number | Optional finite effect scale. Defaults to the module setting. |
| `looped?` | boolean | Whether to create a looped effect that can be stopped by its returned handle. |
| `duration?` | integer | Optional non-negative duration in milliseconds for a looped effect. |

## Effect ownership and cleanup

The handle is tied to the resource that called the function. A resource cannot stop another resource’s tracked handle. When a resource stops, its active particle and screen-effect handles are released automatically.

## Functions

Use playPtfx for a particle effect at a world point or attached to an entity, and screenEffect for a full-screen native effect.

### `Kora.fx.playPtfx(def)`

Loads a particle dictionary and starts one particle effect. The returned handle can stop a looped effect later.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `def` | table | Particle effect description; see the fields listed above. |

**Returns**

- **handle** — serializable effect handle when started.
- **false, error** — when the asset could not load or the effect could not start.

**Example**

```lua
local effect, err = Kora.fx.playPtfx({
    dict = 'core',
    name = 'ent_sht_steam',
    coords = vector3(100.0, 200.0, 30.0),
    scale = 1.0,
})
if not effect then print('Effect failed:', err) end
```

**Representative console output**

```text
A steam particle begins at the given position, or the reason is printed if startup fails.
```

### `Kora.fx.stop(handle)`

Stops a looped particle effect created by the calling resource. Non-looped effects finish naturally.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `handle` | table | Handle returned by playPtfx. It must belong to the calling resource. |

**Returns**

- **return** — no value.

**Example**

```lua
if effect then Kora.fx.stop(effect) end
```

**Representative console output**

```text
The owned looped particle effect stops.
```

### `Kora.fx.screenEffect(name, duration?, looped?)`

Starts a native screen effect and returns a handle. The module reference-counts handles with the same effect name so one resource cannot stop an effect another resource still owns.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Native screen-effect name. |
| `duration?` | integer | Optional non-negative duration in milliseconds. Omit it or pass 0 to use the game native’s default. |
| `looped?` | boolean | Optional loop setting. Must be a boolean when supplied. |

**Returns**

- **handle** — opaque handle for this individual start call.

**Example**

```lua
local effect = Kora.fx.screenEffect('FocusIn', 5000, false)
-- Release early if the player cancels the action.
Kora.fx.stopScreenEffect(effect)
```

**Representative console output**

```text
The screen effect starts, then its handle is released early.
```

### `Kora.fx.stopScreenEffect(handle)`

Releases a screen-effect handle owned by the calling resource. The native effect stops after the final live handle for that effect name is released.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `handle` | table | Opaque handle returned by screenEffect. Legacy &#123; name = "..." &#125; values are accepted but release only one matching handle owned by this resource. |

**Returns**

- **return** — no value.

**Example**

```lua
local effect = Kora.fx.screenEffect('FocusIn', 5000, true)
-- Later, when the screen should return to normal:
Kora.fx.stopScreenEffect(effect)
```

**Representative console output**

```text
The effect remains active while another owner still has a live handle; otherwise it stops.
```

## Limits and related APIs

Malformed explicit transforms, scales, entity handles, or duration values are rejected before a native effect is started.

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/fx/docs.md` or `local/fx/docs.md`) that the reference above does not state.

Client-side, owner-tracked particle and screen effects.

### `Kora.fx.playPtfx(def)`

Streams `def.dict` and starts `def.name` at `def.entity` or `def.coords`.
Options include `bone`, finite `offset`/`rot` components and `scale`, `looped`, and a looped-effect
`duration` (a finite non-negative integer in milliseconds). Returns a serializable handle, or `false, error` when streaming or
startup fails.

When supplied, `entity` is a positive finite integer, `bone` is a string, and `looped`
is boolean. `offset`, `rot`, and `scale` default only when omitted; malformed
explicit values are rejected before kora_lib streams an asset or calls a native.

### `Kora.fx.stop(handle)`

Stops a tracked looped particle handle created by the calling resource.
Non-looped effects finish naturally.

### `Kora.fx.screenEffect(name, duration?, looped?)`

Starts a native screen effect and returns an opaque per-call handle. Calls that
use the same native effect name are reference-counted so one caller cannot stop
another caller's still-live effect. `duration` is a finite non-negative integer
in milliseconds; omit it or pass `0` for the native default. `looped`, when
supplied, must be boolean.

### `Kora.fx.stopScreenEffect(handle)`

Releases a tracked screen-effect handle created by the calling resource and
stops the native effect after its final same-name handle is released. Each
invoking resource's handles are released automatically when that resource
stops. Retain the returned handle; legacy `{ name = "..." }` handles remain
accepted, but can release only one matching handle owned by the calling
resource.
