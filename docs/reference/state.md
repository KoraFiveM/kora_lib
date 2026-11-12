---
title: "State module"
sidebar_position: 8
---

# State module

## `Kora.state.awaitGlobal(key, timeoutMs?, pollIntervalMs?)` — shared

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

## `Kora.state.onChange(keyFilter?, bagFilter?, handler)` — client/server

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

## `Kora.state.offChange(listenerId)` — client/server

Removes the native handler for a positive finite integer listener ID and
returns whether it was live. A listener ID does not transfer mutation
authority: another resource cannot remove it. Listeners are also removed
automatically when their owning resource stops.
