# Status effects module

Status definitions are shared; applications are rendered client-side and may
also be tracked and authorized server-side.

## Definitions (shared)

`QB.status.registerEffect(name, def)` registers duration, stacking
(`replace`, `extend`, or `stack`), severity levels, screen/particle effects,
animation, and movement multiplier. `QB.status.getEffectDef(name)` returns the
definition or `nil`. Register definitions from a shared script so both realms
see them.

## Application (client/server)

- Client: `QB.status.apply(name, opts?)`, `QB.status.remove(name)`,
  `QB.status.isActive(name)`, `QB.status.getActive()`.
- Server: `QB.status.apply(target, name, opts?)`,
  `QB.status.remove(target, name)`, `QB.status.isActive(target, name)`, and
  `QB.status.getActive(target)`.

Apply options are `duration` and `severity`. The server pushes the accepted
effect to the client, including the authoritative remaining duration after an
`extend`, so server tracking and client rendering expire together. Client-only
calls are valid for local cosmetic state and use the same stacking rules.

Movement multipliers are composed and applied every frame as required by the
game native. The frame loop starts lazily and stops when the final movement
effect is removed.

## Client changes

`QB.status.onChange(handler)` returns a listener ID and calls
`handler(name, applied)` on every local apply/remove. Remove it with
`QB.status.offChange(listenerId)`; listeners and active render state also clean
up with their owning resource.
