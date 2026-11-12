---
title: "Status"
sidebar_position: 47
---


# Status

## Shared

Defines named status effects and their duration, stacking, severity, and client presentation. Register definitions from shared code so both client and server know the same effect names. Applying an effect changes tracked status; visual effects are presentation and do not grant gameplay permission.

Namespace: `Kora.status` · Source: `modules/status/shared.lua`

### Effect definition fields

Pass these fields inside def when calling registerEffect. Presentation fields are rendered on the client. A `?` after a name means the option is optional.

#### def table

| Option | Type | Description |
| --- | --- | --- |
| `duration?` | integer | Non-negative milliseconds before automatic expiry. Omit it for an effect that remains until removed. |
| `stacking?` | 'replace' \| 'extend' \| 'stack' | How a repeated application combines with an existing one. Defaults to replace. |
| `severityLevels?` | integer | Positive number of severity tiers. Supplying severity when this is absent has no effect. |
| `fx?` | table | Optional client particle or screen effect settings. |
| `anim?` | table | Optional client animation settings. |
| `movement?` | table | Optional movement modifier. Requires finite speedMultiplier; concurrent effects compose. |

### Definition ownership

The first resource to register a name owns it. Definitions are deep-copied at registration, returned as deep copies, and removed automatically when their owner resource stops.

### Functions

Validate effect names, register a definition, or read a safe copy of a registered definition.

#### `Kora.status.assertName(name)`

Validates an effect name using the same rules used by every public status operation.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Non-empty name up to 128 bytes. |

**Returns**

- **return** — no value; invalid names raise an assertion error.

**Example**

```lua
Kora.status.assertName('bleeding')
```

**Representative console output**

```text
The name passes validation.
```

#### `Kora.status.registerEffect(name, def)`

Registers an effect definition owned by the calling resource. Another resource cannot replace an existing owner’s definition.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Unique non-empty effect name up to 128 bytes. |
| `def` | table | Duration, stacking, optional severity levels, and optional presentation settings. |

**Returns**

- **registered** — true on success; false, error when another resource already owns the name.

**Example**

```lua
local ok, err = Kora.status.registerEffect('bleeding', {
    duration = 30000, stacking = 'replace', severityLevels = 3,
    movement = { speedMultiplier = 0.8 },
})
if not ok then print(err) end
```

**Representative console output**

```text
Registers a 30-second effect with three severity levels and a movement modifier.
```

#### `Kora.status.getEffectDef(name)`

Reads the registered definition. Returns a deep copy, so editing the returned table cannot change the live registration.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Registered effect name. |

**Returns**

- **definition** — copied definition table, or nil if the name is not registered.

**Example**

```lua
local definition = Kora.status.getEffectDef('bleeding')
if definition then print(definition.stacking) end
```

**Representative console output**

```text
Prints the configured stacking rule when the effect exists.
```

## Client

Applies and tracks local effects and renders their configured presentation. Client-only effects are useful for cosmetic state; a valuable status should be applied by the server after it checks the action.

Namespace: `Kora.status` · Source: `modules/status/client.lua`

### Apply options

Both client and server apply functions accept the same option fields. A `?` after a name means the option is optional.

| Option | Type | Description |
| --- | --- | --- |
| `duration?` | integer | Non-negative duration in milliseconds. |
| `severity?` | integer | Positive severity tier; ignored when the definition has no severityLevels. |

### Ownership and expiry

A client resource cannot replace or remove another resource’s active effect. Queries remove expired entries instead of reporting stale state. Movement multipliers are reconciled as active effects begin and end.

### Functions

Apply, inspect, or remove an effect for this client, and subscribe to local changes.

#### `Kora.status.apply(name, opts?)`

Applies a registered effect locally and starts its client presentation.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Registered effect name. |
| `opts?` | table | Optional duration and severity overrides. |

**Returns**

- **applied** — true when the effect is accepted.
- **false, reason** — if the effect is unknown or cannot be applied.

**Example**

```lua
Kora.status.apply('bleeding', { duration = 30000, severity = 2 })
```

**Representative console output**

```text
The bleeding status is tracked locally for 30 seconds at severity 2.
```

#### `Kora.status.remove(name)`

Removes a local effect owned by the calling resource.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Effect name. |

**Returns**

- **removed** — true if an active effect was removed; otherwise false.

**Example**

```lua
if Kora.status.remove('bleeding') then print('Bleeding effect cleared') end
```

**Representative console output**

```text
Prints only when an active effect was removed.
```

#### `Kora.status.isActive(name)`

Checks whether one effect is currently active. Expired entries are cleared before the answer is returned.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `name` | string | Effect name. |

**Returns**

- **active** — boolean.

**Example**

```lua
if Kora.status.isActive('bleeding') then print('Treatment still needed') end
```

**Representative console output**

```text
Prints while the effect remains active.
```

#### `Kora.status.getActive()`

Returns the local player’s active status entries, removing expired entries before returning.

**Parameters**



**Returns**

- **entries** — array of &#123; name, severity?, expiresAt? &#125; records.

**Example**

```lua
for _, effect in ipairs(Kora.status.getActive()) do
    print(effect.name, effect.severity)
end
```

**Representative console output**

```text
Prints each active status and its severity.
```

#### `Kora.status.onChange(handler)`

Subscribes to local effect apply/remove events.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `handler` | function | Called with (name, applied), where applied is true or false. |

**Returns**

- **listenerId** — ID for offChange.

**Example**

```lua
local listener = Kora.status.onChange(function(name, applied)
    print(name, applied and 'applied' or 'removed')
end)
```

**Representative console output**

```text
Prints whenever a local status is applied or removed.
```

#### `Kora.status.offChange(listenerId)`

Removes a change subscription owned by the calling resource.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `listenerId` | integer | Listener ID from onChange. |

**Returns**

- **removed** — boolean.

**Example**

```lua
Kora.status.offChange(listener)
```

**Representative console output**

```text
The listener stops receiving local status changes.
```

## Server

Tracks and applies effects for a target player and pushes accepted changes to that client. Use this realm for a status that represents a server-authorized gameplay condition.

Namespace: `Kora.status` · Source: `modules/status/server.lua`

### Stacking and expiry

Definitions choose replace, extend, or stack behavior. The server sends the authoritative remaining duration so a client display stays aligned. Expired values are removed during reads, even if the coarse cleanup timer has not run yet. Player entries are also cleared when that player disconnects.

### Authorization

A client-rendered effect is not proof that a player earned it. Check identity, distance, inventory, cooldown, and action state before calling apply for a valuable status.

### Functions

Apply, inspect, and remove effects for a player by server ID.

#### `Kora.status.apply(target, name, opts?)`

Applies a registered status to a player and synchronizes its accepted duration with that player’s client.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `target` | integer | Positive player server ID. |
| `name` | string | Registered effect name. |
| `opts?` | table | Optional duration and severity. |

**Returns**

- **applied** — true on success.
- **false, reason** — for an unknown effect or rejected application.

**Example**

```lua
local ok, reason = Kora.status.apply(source, 'bleeding', { duration = 30000, severity = 2 })
if not ok then print(reason) end
```

**Representative console output**

```text
Applies the server-tracked status or prints the reason it was rejected.
```

#### `Kora.status.remove(target, name)`

Removes a tracked effect from a player.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `target` | integer | Positive player server ID. |
| `name` | string | Effect name. |

**Returns**

- **removed** — boolean.

**Example**

```lua
Kora.status.remove(source, 'bleeding')
```

**Representative console output**

```text
The status is removed from server tracking and the client is updated.
```

#### `Kora.status.isActive(target, name)`

Checks whether a player has an unexpired effect.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `target` | integer | Positive player server ID. |
| `name` | string | Effect name. |

**Returns**

- **active** — boolean.

**Example**

```lua
if Kora.status.isActive(source, 'bleeding') then print('Player is bleeding') end
```

**Representative console output**

```text
Prints while the server tracks an active bleeding effect.
```

#### `Kora.status.getActive(target)`

Returns all unexpired statuses for a player.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `target` | integer | Positive player server ID. |

**Returns**

- **entries** — array of &#123; name, severity?, expiresAt? &#125; records.

**Example**

```lua
local effects = Kora.status.getActive(source)
print('Active status count:', #effects)
```

**Representative console output**

```text
Prints the count of current statuses.
```

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/status/docs.md` or `local/status/docs.md`) that the reference above does not state.

Status definitions are shared; applications are rendered client-side and may
also be tracked and authorized server-side.

### Definitions (shared)

`Kora.status.registerEffect(name, def) -> boolean, error?` registers duration, stacking
(`replace`, `extend`, or `stack`), severity levels, screen/particle effects,
animation, and movement multiplier. `Kora.status.getEffectDef(name)` returns the
definition or `nil`. Register definitions from a shared script so both realms
see them.

#### `Kora.status.assertName(name)`

Validates an effect name as a non-empty string of at most 128 bytes. This is
also called by every status operation before it reads or changes state.

#### `Kora.status.registerEffect(name, def)`

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

#### `Kora.status.getEffectDef(name) -> def|nil`

Returns a deep copy of the registered definition. Registration also stores a
deep copy, so neither later mutations to the caller's table nor mutations to a
returned definition can change the live effect configuration.

### Application (client/server)

#### `Kora.status.apply`

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

#### Query and removal

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

### Client changes

`Kora.status.onChange(handler)` returns a listener ID and calls
`handler(name, applied)` on every local apply/remove. Remove it with
`Kora.status.offChange(listenerId) -> boolean`; another resource cannot remove
the listener. Listeners and active render state also clean up with their owning
resource.

### Server authority

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
