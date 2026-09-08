# Effects module

Client-side, owner-tracked particle and screen effects.

## `QB.fx.playPtfx(def)`

Streams `def.dict` and starts `def.name` at `def.entity` or `def.coords`.
Options include `bone`, `offset`, `rot`, `scale`, `looped`, and a looped-effect
`duration`. Returns a serializable handle, or `false, error` when streaming or
startup fails.

## `QB.fx.stop(handle)`

Stops a tracked looped particle handle. Non-looped effects finish naturally.

## `QB.fx.screenEffect(name, duration?, looped?)`

Starts a native screen effect and returns an opaque per-call handle. Calls that
use the same native effect name are reference-counted so one caller cannot stop
another caller's still-live effect.

## `QB.fx.stopScreenEffect(handle)`

Releases a tracked screen-effect handle and stops the native effect after its
final same-name handle is released. Each invoking resource's handles are
released automatically when that resource stops. Retain the returned handle;
legacy `{ name = "..." }` handles remain accepted, but can release only one
matching handle owned by the calling resource.
