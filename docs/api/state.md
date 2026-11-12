---
title: "State"
sidebar_position: 8
---


# State

## Shared

Waits for a replicated GlobalState value during startup. It provides a bounded alternative to writing an endless loop that waits for server state.

Namespace: `Kora.state` · Source: `modules/state/shared.lua`

### Choose a sensible polling interval

The default checks every 50 milliseconds. A zero interval checks each game frame and is intended only when frame-level responsiveness is necessary. The timeout remains bounded, so a missing key does not leave a permanent startup loop.

### Functions

Use awaitGlobal when a resource needs a global state key before it can initialize.

#### `Kora.state.awaitGlobal(key, timeoutMs?, pollIntervalMs?)`

Waits until GlobalState[key] is not nil or the timeout expires. A value of false is considered present and is returned as-is.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `key` | string | Non-empty GlobalState key. |
| `timeoutMs?` | integer | Maximum wait in milliseconds. Defaults to 5000; must be non-negative. |
| `pollIntervalMs?` | integer | Wait between checks in milliseconds. Defaults to 50; must be non-negative. Zero checks once per game frame. |

**Returns**

- **value** — current GlobalState value, including false, when it appears.
- **reason** — "timeout" when the key stays nil until the time limit.

**Example**

```lua
local config, reason = Kora.state.awaitGlobal('Jewellery', 10000)
if config == nil then
    print(('State unavailable: %s'):format(reason))
else
    print('Jewellery state is ready')
end
```

**Representative console output**

```text
Prints a timeout reason if the key does not appear within ten seconds; otherwise it reports that the state is ready.
```

### Limits and related APIs

Defaults apply only when an argument is omitted. Explicit timeout and polling values must be finite non-negative integers.

## Client

Subscribes to FiveM state-bag changes visible to the client. A subscription can filter by state key, bag name, both, or neither. The callback receives one normalized context object and is not replayed the current value when first registered.

Namespace: `Kora.state` · Source: `modules/state/client.lua`

### Change context

The handler receives a table with entity, bagName, key, value, reserved, and replicated. entity is the entity resolved from the bag name; it is 0 for global/player bags or when the entity is unavailable. Registration does not send an initial snapshot. A callback already queued when the listener is removed is ignored.

### Automatic cleanup

Listeners belong to the resource that registered them and are removed automatically when that resource stops.

### Functions

Register a listener and retain its ID so this resource can remove it before it stops.

#### `Kora.state.onChange(keyFilter?, bagFilter?, handler)`

Subscribes to matching state-bag changes. Either filter may be nil to match any value.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `keyFilter?` | string | Optional exact state key filter. nil matches every key. |
| `bagFilter?` | string | Optional exact bag name filter. nil matches every bag. |
| `handler` | function | Required callback receiving one change context table. |

**Returns**

- **listenerId** — positive integer used by offChange.

**Example**

```lua
local listener = Kora.state.onChange('locked', nil, function(change)
    print(change.bagName, change.entity, change.value, change.replicated)
end)
-- Later:
Kora.state.offChange(listener)
```

**Representative console output**

```text
Prints the bag, resolved entity, new value, and replication flag for locked changes.
```

#### `Kora.state.offChange(listenerId)`

Removes a listener previously registered by this resource. Another resource cannot remove a listener it does not own.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `listenerId` | integer | Positive listener ID returned by onChange. |

**Returns**

- **removed** — true if the listener was active and removed; false if it was unknown or already removed.

**Example**

```lua
local removed = Kora.state.offChange(listener)
print('Listener removed:', removed)
```

**Representative console output**

```text
Prints true when the subscription was still active.
```

## Server

Subscribes to server-observed state-bag changes. Filter and callback behavior matches the client realm, while entity resolution and replication data reflect what the server can observe.

Namespace: `Kora.state` · Source: `modules/state/server.lua`

### Change context

The callback receives entity, bagName, key, value, reserved, and replicated. entity is 0 for global/player bags or when the entity cannot be resolved. The subscription does not replay a value that existed before it was registered.

### Authority and cleanup

A state-bag update is data, not proof that an action is authorized. Validate permissions and game rules in the server handler that owns the state. Listeners are removed when their registering resource stops.

### Functions

Register a state listener and remove it when the server resource no longer needs the subscription.

#### `Kora.state.onChange(keyFilter?, bagFilter?, handler)`

Registers a server-side state-bag listener matching the optional key and bag filters.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `keyFilter?` | string | Optional exact state key; nil matches every key. |
| `bagFilter?` | string | Optional exact bag name; nil matches every bag. |
| `handler` | function | Required callback receiving one normalized change context. |

**Returns**

- **listenerId** — positive integer subscription ID.

**Example**

```lua
local listener = Kora.state.onChange('doorLocked', nil, function(change)
    print(change.bagName, change.value, change.replicated)
end)
```

**Representative console output**

```text
Prints each observed doorLocked update.
```

#### `Kora.state.offChange(listenerId)`

Removes an active listener owned by the calling resource.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `listenerId` | integer | Positive ID returned by onChange. |

**Returns**

- **removed** — boolean indicating whether the listener was removed.

**Example**

```lua
Kora.state.offChange(listener)
```

**Representative console output**

```text
The listener no longer receives future matching changes.
```

## Additional notes from the module guide

Behaviour, validation and ownership details from the guide kept beside the implementation (`modules/state/docs.md` or `local/state/docs.md`) that the reference above does not state.

### `Kora.state.awaitGlobal(key, timeoutMs?, pollIntervalMs?)` — shared

Waits for a `GlobalState` key to become non-nil without allowing an unbounded
startup loop. The timeout defaults to 5000 ms and polling defaults to 50 ms;
both must be finite, non-negative integers. Defaults apply only when omitted;
explicit invalid values are rejected. It returns the value (including `false`)
or `nil, "timeout"`. A `pollIntervalMs` of `0` polls once per game frame; use
the default or another positive interval for ordinary startup state.

```lua
local jewellery, reason = Kora.state.awaitGlobal('Jewellery', 10000)
if not jewellery then
    print(('Jewellery state unavailable: %s'):format(reason))
end
```

### `Kora.state.onChange(keyFilter?, bagFilter?, handler)` — client/server

Registers a state-bag subscription. Either filter may be `nil` to match every
key or bag. The handler receives one normalized context table:

```lua
local listener = Kora.state.onChange('locked', nil, function(change)
    print(change.bagName, change.entity, change.value, change.replicated)
end)
```

The context contains `entity`, `bagName`, `key`, `value`, `reserved`, and
`replicated`. `entity` is resolved through `GetEntityFromStateBagName` and is
`0` for global/player bags or when the entity is unavailable. Handler errors are
contained and logged. Registration does not replay an existing value. A callback
already queued when its listener is removed is ignored.

### `Kora.state.offChange(listenerId)` — client/server

Removes the native handler for a positive finite integer listener ID and
returns whether it was live. A listener ID does not transfer mutation
authority: another resource cannot remove it. Listeners are also removed
automatically when their owning resource stops.
