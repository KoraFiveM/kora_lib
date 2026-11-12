---
title: "Status effects module"
sidebar_position: 47
---

# Status effects module

Status definitions are shared; applications are rendered client-side and may
also be tracked and authorized server-side.

## Definitions (shared)

`Kora.status.registerEffect(name, def) -> boolean, error?` registers duration, stacking
(`replace`, `extend`, or `stack`), severity levels, screen/particle effects,
animation, and movement multiplier. `Kora.status.getEffectDef(name)` returns the
definition or `nil`. Register definitions from a shared script so both realms
see them.

### `Kora.status.assertName(name)`

Validates an effect name as a non-empty string of at most 128 bytes. This is
also called by every status operation before it reads or changes state.

### `Kora.status.registerEffect(name, def)`

`name` is a non-empty string of at most 128 bytes. Every public operation that
accepts an effect name validates this contract before reading or changing state.
`def` may contain:

- `duration`: finite, non-negative integer milliseconds; omitted means the effect stays
  active until removed.
- `stacking`: `replace` (default), `extend`, or `stack`.
- `severityLevels`: finite, positive integer number of available severity tiers.
- `fx`, `anim`, and `movement`: client presentation settings. `movement`
  requires a finite numeric `speedMultiplier`; concurrent multipliers compose.

Invalid definition-level fields fail at registration, before an effect can be
applied. Nested particle transforms and other native-specific visual options
are checked when rendering; if one fails after an earlier visual started,
kora_lib rolls that earlier visual back before returning the error. A definition
name belongs to the resource that first registers it; another
resource receives `false, error` rather than silently replacing it. Definitions
are removed when their owning resource stops, so restartable resources do not
leave stale effects behind.

### `Kora.status.getEffectDef(name) -> def|nil`

Returns a deep copy of the registered definition. Registration also stores a
deep copy, so neither later mutations to the caller's table nor mutations to a
returned definition can change the live effect configuration.

## Application (client/server)

### `Kora.status.apply`

| Realm | Signature | Result |
| --- | --- | --- |
| client | `Kora.status.apply(name, opts?)` | `true` after local state and presentation are applied. |
| server | `Kora.status.apply(target, name, opts?)` | `true`, or `false, reason` for an unknown effect. `target` must be a positive integer server ID. |

Apply options are `duration` (a finite, non-negative integer milliseconds) and
`severity` (a finite, positive integer). Both realms validate the options before
changing state. A severity supplied for an effect without `severityLevels` is
ignored. The server pushes the accepted effect to the client, including the
authoritative remaining duration after an `extend`, so server tracking and
client rendering expire together. Client-only calls are valid for local
cosmetic state and use the same stacking rules.

### Query and removal

| Realm | Remove | Query one | Query all |
| --- | --- | --- | --- |
| client | `Kora.status.remove(name) -> boolean` | `Kora.status.isActive(name) -> boolean` | `Kora.status.getActive() -> entries` |
| server | `Kora.status.remove(target, name) -> boolean` | `Kora.status.isActive(target, name) -> boolean` | `Kora.status.getActive(target) -> entries` |

Each active entry contains `name`, optional `severity`, and optional
`expiresAt` (the game-timer deadline in milliseconds). Removing an absent
effect returns `false`. On the client, a resource cannot replace or remove an
active effect owned by another resource; server-pushed effects run inside kora_lib
and can supersede local presentation. Every server operation requires a
positive integer target server ID. Server entries are also cleared when a player drops.
Client and server queries remove an effect once its deadline has passed, so
`isActive` and `getActive` never report stale state or retain an expired entry
while coarse timer cleanup is waiting. A client query that clears several
expired effects reconciles movement once after the batch.

Movement multipliers are composed and applied every frame as required by the
game native. The frame loop starts lazily and stops when the final movement
effect is removed.

## Client changes

`Kora.status.onChange(handler)` returns a listener ID and calls
`handler(name, applied)` on every local apply/remove. Remove it with
`Kora.status.offChange(listenerId) -> boolean`; another resource cannot remove
the listener. Listeners and active render state also clean up with their owning
resource.

## Server authority

An effect rendered on the client is presentation, not permission. Apply a
valuable status (for example, treatment, incapacitation, or a reward gate)
from a server handler after validating the player, current state, inventory,
distance, cooldown, and any required role. Do not accept a client event as
proof that the client applied or completed an effect.

```lua
-- server.lua
local ok, reason = Kora.status.apply(source, 'bleeding', {
    duration = 30000,
    severity = 2,
})

if not ok then
    print(('Could not apply bleeding: %s'):format(reason))
end
```
