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

## `Kora.state.globalMap(name)` — shared

Replicates a keyed table (plants, coral spots, jewellery cases, showroom
slots, ...) through `GlobalState` **one entry at a time**. Writing a whole table
to one GlobalState key re-sends every entry to every client on every change;
a global map only sends the entry that changed.

Each entry is stored as `GlobalState['<name>:<key>']`. A key index,
`GlobalState['<name>:__keys']` (a sorted array of keys), is rewritten only when
a key is added or removed, never on an update. `name` is 1–64 bytes without
`:`; keys are integers or 1–128 byte strings (`'__keys'` is reserved; `5` and
`5.0` are the same key).

Server handle (writes):
- `map.set(key, value)` — writes one entry; `nil` removes it.
- `map.remove(key)` — same as `set(key, nil)`.
- `map.get(key)`, `map.all()` — read back.

Creating the server handle publishes an empty index if there is none yet, so
clients can tell the map exists. Handles with the same name share one key set,
seeded from the existing index, so re-creating a map after a kora_lib restart
(inside `Kora.onReady`) continues where it left off.

Client handle (reads):
- `map.get(key)` — one entry.
- `map.all()` — every entry, read through the index.
- `map.ready(timeoutMs?)` → `boolean` — waits (default 5000 ms) until the
  server has created the map. Use it instead of `repeat Wait() until GlobalState.X`.
- `map.onChange(fn(key, value, old))` → listener id — one global state-bag
  handler filtered by the map's prefix; index updates and other maps are
  ignored. Remove it with `Kora.state.offChange(id)`; it is also removed when
  your resource stops.

```lua
-- server
local plants = Kora.state.globalMap('drugs_plants')
plants.set(plantId, { coords = coords, stage = 1 })
plants.set(plantId, { coords = coords, stage = 2 }) -- only this entry is sent

-- client
local plants = Kora.state.globalMap('drugs_plants')
if plants.ready(10000) then
    for id, plant in pairs(plants.all()) do spawnPlant(id, plant) end
end
plants.onChange(function(id, plant)
    if plant then updatePlant(id, plant) else removePlant(id) end
end)
```

## `Kora.state.offChange(listenerId)` — client/server

Removes the native handler for a positive finite integer listener ID and
returns whether it was live. A listener ID does not transfer mutation
authority: another resource cannot remove it. Listeners are also removed
automatically when their owning resource stops.
