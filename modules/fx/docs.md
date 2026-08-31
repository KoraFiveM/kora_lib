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

Starts a native screen effect and returns its name-based handle.

## `QB.fx.stopScreenEffect(handle)`

Stops a tracked screen-effect handle. All tracked effects are stopped when the
invoking resource stops.
