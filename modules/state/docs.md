# State module

## `QB.state.onChange(keyFilter?, bagFilter?, handler)` — client/server

Registers a state-bag subscription. Either filter may be `nil` to match every
key or bag. The handler receives one normalized context table:

```lua
local listener = QB.state.onChange('locked', nil, function(change)
    print(change.bagName, change.entity, change.value, change.replicated)
end)
```

The context contains `entity`, `bagName`, `key`, `value`, `reserved`, and
`replicated`. `entity` is resolved through `GetEntityFromStateBagName` and is
`0` for global/player bags or when the entity is unavailable. Handler errors are
contained and logged. Registration does not replay an existing value.

## `QB.state.offChange(listenerId)` — client/server

Removes the native handler and returns whether it was live. Listeners are also
removed automatically when their owning resource stops.
